import AppKit
import SwiftUI
import ViewFitCore

@MainActor
struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.externalConnected ? "display" : "laptopcomputer")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ViewFit · 随屏").font(.headline)
                    Text(model.externalConnected ? "正在使用外接屏预设" : "正在使用内置屏预设")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("自动切换", isOn: enabledBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help("自动切换缩放")
            }

            if !model.configuration.enabled {
                Label("自动切换已暂停", systemImage: "pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            ForEach(model.configuration.rules) { rule in
                HStack(alignment: .top, spacing: 10) {
                    ApplicationSymbol(id: rule.id, size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.name).font(.system(size: 12, weight: .medium))
                        Text(rule.enabled ? (model.statuses[rule.id] ?? "等待应用") : "未启用")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    Text(rule.enabled ? (model.externalConnected ? rule.zoomLabel(rule.externalPercent) : rule.defaultLabel) : "—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(rule.enabled ? .primary : .secondary)
                }
            }

            Divider()

            HStack {
                Button("应用当前规则") { model.applyNow() }
                    .disabled(!model.configuration.enabled)
                Spacer()
                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape")
                }.help("设置…")
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }.help("退出 ViewFit · 随屏")
            }.buttonStyle(.borderless)
        }
        .padding(18)
        .frame(width: 310)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.configuration.enabled }, set: {
            model.configuration.enabled = $0
            model.configurationChanged()
        })
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "display.2")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 50, height: 50)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ViewFit · 随屏")
                            .font(.system(size: 19, weight: .semibold))
                        Text("为应用设置外接屏预设。拔掉后，Chrome 和 Codex 恢复 100%，微信恢复基准字号。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: enabledBinding) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("自动切换缩放").font(.system(size: 13, weight: .medium))
                                Text(model.configuration.enabled ? "在显示器连接、断开和应用启动时应用规则。" : "已暂停。应用当前的缩放会保留。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.switch)
                        Toggle("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .font(.caption)
                        Divider()
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: model.externalConnected ? "display" : "laptopcomputer")
                            Text(model.externalConnected ? "外接屏模式" : "内置屏模式")
                            Spacer()
                            Text(model.displayNames.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }.font(.caption)
                    }.padding(8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("应用预设").font(.system(size: 13, weight: .semibold))
                    GroupBox {
                        VStack(spacing: 0) {
                            HStack {
                                Text("应用")
                                Spacer()
                                Text("外接显示器").frame(width: 100)
                                Text("仅内置屏幕").frame(width: 90)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.bottom, 10)

                            ForEach(Array(model.configuration.rules.enumerated()), id: \.element.id) { index, rule in
                                if index > 0 { Divider().padding(.vertical, 12) }
                                ruleRow(rule)
                            }
                        }.padding(10)
                    }
                    Text("规则按应用生效。接入外接屏后，也会影响该应用留在内置屏幕上的窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Codex 和微信会在你切换到应用时调整，不会抢走当前窗口焦点。微信按原生字号档位设置。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("首次使用").font(.system(size: 13, weight: .semibold))
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: model.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                                    .foregroundStyle(model.accessibilityGranted ? Color.green : Color.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("允许辅助功能访问").font(.system(size: 12, weight: .medium))
                                    Text(model.accessibilityGranted ? "已授权，可控制应用的缩放菜单。" : "Codex 和微信需要此权限，才能自动调整缩放。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if !model.accessibilityGranted {
                                    Button("打开设置") { model.requestAccessibility() }
                                }
                            }

                            Divider()

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "puzzlepiece.extension").frame(width: 20)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("连接 Chrome 扩展").font(.system(size: 12, weight: .medium))
                                    Text("Chrome 通过扩展同步所有标签页的缩放。首次需要手动加载一次。")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 8) {
                                        Button("1. 安装连接组件") { model.installChromeBridge() }
                                        Button("2. 显示扩展文件夹") { model.openExtensionFolder() }
                                        Button("3. 打开扩展管理") { model.openChromeExtensions() }
                                    }.controlSize(.small)
                                    Text("在扩展管理中开启“开发者模式”，点击“加载已解压的扩展程序”，选择扩展文件夹。")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !model.bridgeStatus.isEmpty {
                                        Text(model.bridgeStatus).font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }.padding(10)
                    }
                }

                HStack {
                    Text("设置会自动保存")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button("应用当前规则") { model.applyNow() }
                        .disabled(!model.configuration.enabled)
                }
            }.padding(24)
        }
        .frame(minWidth: 600, idealWidth: 620, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        HStack(spacing: 10) {
            ApplicationSymbol(id: rule.id, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(rule.name, isOn: ruleEnabledBinding(rule.id))
                    .toggleStyle(.checkbox).font(.system(size: 12, weight: .medium))
                Text(model.statuses[rule.id] ?? (rule.enabled ? "等待应用" : "未启用"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker("\(rule.name) 外接屏缩放", selection: percentBinding(rule.id)) {
                ForEach(percentOptions(rule), id: \.self) { percent in
                    Text(rule.zoomLabel(percent)).tag(percent)
                }
            }
            .labelsHidden().frame(width: 100)
            .disabled(!rule.enabled)
            Text(rule.defaultLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 90)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.configuration.enabled }, set: {
            model.configuration.enabled = $0
            model.configurationChanged()
        })
    }

    private func ruleEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.configuration.rules.first(where: { $0.id == id })?.enabled ?? false }, set: { enabled in
            guard let index = model.configuration.rules.firstIndex(where: { $0.id == id }) else { return }
            model.configuration.rules[index].enabled = enabled
            model.configurationChanged()
        })
    }

    private func percentBinding(_ id: String) -> Binding<Int> {
        Binding(get: { model.configuration.rules.first(where: { $0.id == id })?.externalPercent ?? 125 }, set: { percent in
            guard let index = model.configuration.rules.firstIndex(where: { $0.id == id }) else { return }
            model.configuration.rules[index].externalPercent = percent
            model.configurationChanged()
        })
    }

    private func percentOptions(_ rule: AppRule) -> [Int] {
        if rule.id == "wechat" { return [100, 110, 120] }
        if rule.id == "codex" { return Array(stride(from: 100, through: 200, by: 10)) }
        return Array(Set([100, 110, 125, 150, 175, 200, rule.externalPercent])).sorted()
    }
}

private extension AppRule {
    var defaultLabel: String { id == "wechat" ? "基准字号" : "100%" }

    func zoomLabel(_ percent: Int) -> String {
        guard id == "wechat" else { return "\(percent)%" }
        switch percent {
        case 110: return "放大1档"
        case 120: return "放大2档"
        default: return "基准"
        }
    }
}

private struct ApplicationSymbol: View {
    let id: String
    let size: CGFloat

    private var symbol: String {
        switch id {
        case "chrome": return "globe"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "wechat": return "bubble.left.and.bubble.right"
        default: return "app"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}
