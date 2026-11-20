import AppKit
import ApplicationServices
import ViewFitCore

/// Only operates on the foreground application. Codex uses its native menu;
/// WeChat uses bounded, targeted shortcuts and never opens a visible menu.
@MainActor
enum ZoomAdapter {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func apply(id: String, pid: pid_t, percent: Int) async throws {
        try ensureForeground(pid)
        guard AXIsProcessTrusted() else { throw Failure(message: "需要辅助功能权限") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        switch id {
        case "codex":
            guard (100...300).contains(percent), percent.isMultiple(of: 10) else {
                throw Failure(message: "Codex 支持 100%–300%，每档 10%")
            }
            try ensureCodexContentFocus(app)
            try await press("0", in: app, pid: pid)
            for _ in 0..<((percent - 100) / 10) {
                try ensureCodexContentFocus(app)
                try await press("+", in: app, pid: pid)
            }
        case "wechat":
            // The numeric storage representation is 100 + 10*n. WeChat itself
            // exposes font-size tiers, not percentages; the UI must label them
            // as native tiers until a percentage has been independently verified.
            guard (100...120).contains(percent), percent.isMultiple(of: 10) else {
                throw Failure(message: "微信仅支持原生字号档位")
            }
            try await WeChatZoomSequence.apply(
                steps: (percent - 100) / 10,
                readState: {
                    try ensureForeground(pid)
                    return .init(
                        canEnlarge: isEnabled(try command("+", in: app)),
                        canShrink: isEnabled(try command("-", in: app))
                    )
                },
                shrink: { try await sendWeChatKey("-", pid: pid) },
                enlarge: { try await sendWeChatKey("+", pid: pid) }
            )
        default:
            throw Failure(message: "不支持的应用")
        }
    }

    private static func ensureForeground(_ pid: pid_t) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw Failure(message: "等待切回应用后调整")
        }
    }

    private static func sendWeChatKey(_ key: String, pid: pid_t) async throws {
        try ensureForeground(pid)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key == "-" ? 27 : 24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key == "-" ? 27 : 24, keyDown: false) else {
            throw Failure(message: "无法创建微信缩放快捷键")
        }
        // '+' is Shift+'=' on the physical keyboard. Both events carry Command,
        // so a shortcut cannot degrade into text inserted in the message composer.
        let flags: CGEventFlags = key == "+" ? [.maskCommand, .maskShift] : [.maskCommand]
        down.flags = flags
        up.flags = flags
        try ensureForeground(pid)
        // Never suspend or check cancellation between a key-down and its key-up.
        // Targeting the PID also avoids delivering either event to another app.
        down.postToPid(pid)
        up.postToPid(pid)
        try await Task.sleep(for: .milliseconds(250))
        try ensureForeground(pid)
    }

    private static func ensureCodexContentFocus(_ app: AXUIElement) throws {
        // Codex's native menu routes +/-/0 to its embedded browser when focused.
        // Inspect only the focused element's ancestors, never conversation text.
        var current = elementAttribute(app, kAXFocusedUIElementAttribute)
        for _ in 0..<24 {
            guard let element = current else { return }
            if let rawURL = attribute(element, kAXURLAttribute) {
                let url: URL?
                if let value = rawURL as? URL { url = value }
                else if let value = rawURL as? String { url = URL(string: value) }
                else { url = nil }
                if let scheme = url?.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    throw Failure(message: "请先点击 Codex 对话区域，避免调整内置浏览器")
                }
            }
            current = elementAttribute(element, kAXParentAttribute)
        }
    }

    private static func press(_ key: String, in app: AXUIElement, pid: pid_t) async throws {
        try ensureForeground(pid)
        // Codex only: open View before selecting its dynamically populated item.
        // WeChat never uses this path; its input is bounded and menu-free.
        let viewMenu = try viewMenu(in: app)
        guard AXUIElementPerformAction(viewMenu, kAXPressAction as CFString) == .success else {
            throw Failure(message: "无法打开应用的显示菜单")
        }
        defer { dismiss(viewMenu) }
        try await Task.sleep(for: .milliseconds(120))
        try ensureForeground(pid)
        let item = try command(key, in: app)
        guard isEnabled(item) else { throw Failure(message: "应用当前不可调整到该档位") }
        try ensureForeground(pid)
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw Failure(message: "应用拒绝缩放操作，请打开主窗口后重试")
        }
        try await Task.sleep(for: .milliseconds(220))
        try ensureForeground(pid)
    }

    private static func command(_ key: String, in app: AXUIElement) throws -> AXUIElement {
        let top = try viewMenu(in: app)
        if let found = findCommand(key, in: top, depth: 0) { return found }
        throw Failure(message: "找不到应用的缩放菜单（⌘\(key)）")
    }

    private static func viewMenu(in app: AXUIElement) throws -> AXUIElement {
        guard let menu = elementAttribute(app, kAXMenuBarAttribute) else {
            throw Failure(message: "无法读取应用菜单，请检查辅助功能权限")
        }
        // Skip Apple, Services, and Window menus to avoid unrelated commands.
        for top in children(menu) {
            let title = attribute(top, kAXTitleAttribute) as? String ?? ""
            if ["View", "显示", "顯示", "视图", "檢視", "表示", "보기", "Darstellung", "Affichage", "Visualización", "Vista", "Beeld"].contains(title) { return top }
        }
        throw Failure(message: "找不到应用的显示菜单")
    }

    private static func dismiss(_ top: AXUIElement) {
        for child in children(top) {
            _ = AXUIElementPerformAction(child, kAXCancelAction as CFString)
        }
    }

    private static func findCommand(_ key: String, in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 4 else { return nil }
        let character = attribute(element, kAXMenuItemCmdCharAttribute) as? String
        let modifiers = (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        // AX's Command modifier is implicit unless NoCommand (8) is present.
        if (character == key || (key == "+" && character == "=")), modifiers & 14 == 0 {
            return element
        }
        for child in children(element) {
            if let found = findCommand(key, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = attribute(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}
