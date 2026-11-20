import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import ViewFitCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = AppConfiguration()
    @Published var displayNames: [String] = []
    @Published var externalConnected = false
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var statuses: [String: String] = [:]
    @Published var bridgeStatus = "尚未连接 Chrome 扩展"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var generation = Int(Date().timeIntervalSince1970 * 1000)
    private var attempts = AutomationAttemptGate()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var debounce: Task<Void, Never>?
    private var zoomTask: Task<Void, Never>?
    private var activeOperation: String?
    private var settingsWindow: NSWindow?
    private let bundleIDs = ["codex": "com.openai.codex", "wechat": "com.tencent.xinWeChat"]

    init() {
        let firstLaunch = !FileManager.default.fileExists(atPath: Storage.configurationURL.path)
        if let data = try? Data(contentsOf: Storage.configurationURL),
           let saved = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            configuration = saved
        }
        configuration.normalize()
        readDisplays()
        publishChrome()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleDisplayRefresh() }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleDisplayRefresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyForeground() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopBridge() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.accessibilityGranted = AXIsProcessTrusted()
                self.publishChrome()
                self.updateChromeStatus()
                self.applyForeground()
            }
        }
        applyForeground()
        if firstLaunch || CommandLine.arguments.contains("--settings") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.openSettings()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { bridgeStatus = "登录启动设置失败：\(error.localizedDescription)" }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func configurationChanged() {
        configuration.normalize()
        do { try Storage.write(configuration, to: Storage.configurationURL) }
        catch { bridgeStatus = "无法保存设置：\(error.localizedDescription)" }
        applyNow()
    }

    func applyNow() {
        generation += 1
        attempts.reset()
        zoomTask?.cancel(); activeOperation = nil
        publishChrome()
        applyForeground()
    }

    private func scheduleDisplayRefresh() {
        // Docking and waking often emit several events for one transition.
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            let previous = externalConnected
            readDisplays()
            if previous != externalConnected { applyNow() }
            else { publishChrome(); applyForeground() }
        }
    }

    private func readDisplays() {
        displayNames = NSScreen.screens.map(\.localizedName)
        // Check hardware identity, not screen count: clamshell mode has one external screen.
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return }
        externalConnected = displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private func publishChrome() {
        do { try Storage.write(ChromeState(configuration: configuration, external: externalConnected, generation: generation), to: Storage.chromeStateURL) }
        catch { bridgeStatus = "Chrome 状态写入失败：\(error.localizedDescription)" }
    }

    private func stopBridge() {
        var stopped = configuration; stopped.enabled = false
        try? Storage.write(ChromeState(configuration: stopped, external: externalConnected, generation: generation + 1), to: Storage.chromeStateURL)
    }

    private func updateChromeStatus() {
        let heartbeat = (try? String(contentsOf: Storage.heartbeatURL, encoding: .utf8)).flatMap(Double.init) ?? 0
        let connected = Date().timeIntervalSince1970 - heartbeat < 10
        bridgeStatus = connected ? "Chrome 扩展已连接 · 仅在本机传递缩放设置" : "等待 Chrome 扩展连接"
        statuses["chrome"] = !configuration.enabled ? "已暂停" : connected ? "扩展已连接" : "需加载 Chrome 扩展"
    }

    private func applyForeground() {
        for id in ["codex", "wechat"] {
            guard let target = configuration.target(for: id, external: externalConnected) else {
                statuses[id] = "已暂停"; continue
            }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIDs[id]!).first else {
                statuses[id] = "应用未运行"; continue
            }
            let stamp = "\(app.processIdentifier):\(windowIdentity(id, pid: app.processIdentifier)):\(generation):\(target)"
            // Both success and failure finish this request. Polling and activation
            // must never reopen menus or send more keys for a failed transition.
            // A new profile, edited configuration or explicit Apply permits a retry.
            if attempts.hasAttempted(key: stamp) { continue }
            guard accessibilityGranted else { statuses[id] = "需要辅助功能权限"; continue }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                statuses[id] = "切回应用时调整为 \(targetLabel(id, target))"; continue
            }
            guard activeOperation == nil, attempts.begin(key: stamp) else { continue }
            activeOperation = stamp
            statuses[id] = "正在调整…"
            zoomTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await ZoomAdapter.apply(id: id, pid: app.processIdentifier, percent: target)
                    guard !Task.isCancelled, activeOperation == stamp else { return }
                    attempts.finish(key: stamp, succeeded: true)
                    statuses[id] = "已设置\(targetLabel(id, target))"
                } catch {
                    guard !Task.isCancelled, activeOperation == stamp else { return }
                    attempts.finish(key: stamp, succeeded: false)
                    statuses[id] = error.localizedDescription + "；已停止自动重试"
                }
                if activeOperation == stamp { activeOperation = nil }
            }
        }
    }

    private func targetLabel(_ id: String, _ value: Int) -> String {
        if id == "wechat" { return value == 100 ? "基准字号" : "放大 \((value - 100) / 10) 档" }
        return "\(value)%"
    }

    private func windowIdentity(_ id: String, pid: pid_t) -> UInt {
        guard id == "codex", accessibilityGranted else { return 0 }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return 0 }
        return CFHash(window)
    }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func installChromeBridge() {
        do {
            guard let resources = Bundle.main.resourceURL else { return }
            let sourceExtension = resources.appendingPathComponent("ChromeExtension")
            let extensionFolder = Storage.directory.appendingPathComponent("ChromeExtension")
            try FileManager.default.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
            // Copy individual files so a loaded extension keeps a stable directory.
            for file in try FileManager.default.contentsOfDirectory(at: sourceExtension, includingPropertiesForKeys: nil) {
                if file.hasDirectoryPath { continue }
                let destination = extensionFolder.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.createDirectory(at: extensionFolder, withIntermediateDirectories: true)
                try Data(contentsOf: file).write(to: destination, options: .atomic)
            }
            let host = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ViewFitBridge")
            let manifest: [String: Any] = ["name": "com.avenry.screenscale", "description": "ViewFit · 随屏 local zoom settings", "path": host.path, "type": "stdio", "allowed_origins": ["chrome-extension://fgmjjmcpabiopnbpgcjdbgfbcpiajmhl/"]]
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("com.avenry.screenscale.json"), options: .atomic)
            bridgeStatus = "连接组件已安装。请加载扩展；若已加载，请点击扩展的重新加载。"
        } catch { bridgeStatus = "安装失败：\(error.localizedDescription)" }
    }

    func openExtensionFolder() {
        let folder = Storage.directory.appendingPathComponent("ChromeExtension")
        if !FileManager.default.fileExists(atPath: folder.path) { installChromeBridge() }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    func openChromeExtensions() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return }
        NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "ViewFit · 随屏 设置"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false; window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
