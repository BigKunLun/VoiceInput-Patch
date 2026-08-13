//
//  MenuBarView.swift
//  VoiceInput
//

import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    /// 必须单独观察：Settings 是独立的 ObservableObject，
    /// 它的变化不会触发 AppState 的 objectWillChange，只观察 state 会导致勾选后界面不刷新
    @ObservedObject var settings = Settings.shared
    @State private var showTerminals = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 开关按钮
            Button(action: toggleRunning) {
                HStack {
                    Image(systemName: state.isRunning ? "waveform.circle.fill" : "waveform")
                        .foregroundColor(state.isRunning ? .green : .secondary)
                    Text(state.isRunning ? "已启动" : "已停止")
                    Spacer()
                    Text(state.isRunning ? "点击停止" : "点击启动")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            Divider()

            // 状态信息
            HStack {
                Text("拦截: \(state.interceptCount)")
                    .font(.subheadline)
                Spacer()
                if !state.lastPreview.isEmpty {
                    Text(state.lastPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Divider()

            terminalSection

            Divider()

            optionSection

            Divider()

            // 版本号 + 退出
            HStack {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - 终端列表

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 整行可点击展开/折叠
            Button(action: { showTerminals.toggle() }) {
                HStack {
                    Image(systemName: showTerminals ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("监听终端")
                    Spacer()
                    Text("\(enabledCount)/\(totalCount)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showTerminals {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(PRESET_TERMINALS, id: \.self) { terminal in
                        Toggle(terminal, isOn: Binding(
                            get: { settings.enabledTerminals.contains(terminal) },
                            set: { isChecked in
                                if isChecked {
                                    settings.enabledTerminals.insert(terminal)
                                } else {
                                    settings.enabledTerminals.remove(terminal)
                                }
                                applyChange()
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.subheadline)
                    }

                    ForEach(settings.customTerminals) { terminal in
                        HStack(spacing: 4) {
                            Toggle(terminal.name, isOn: Binding(
                                get: { terminal.isEnabled },
                                set: { isChecked in
                                    settings.setCustomTerminal(bundleId: terminal.bundleId, enabled: isChecked)
                                    applyChange()
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.subheadline)
                            .help(terminal.bundleId)

                            Spacer()

                            Button(action: {
                                settings.removeCustomTerminal(bundleId: terminal.bundleId)
                                applyChange()
                            }) {
                                Image(systemName: "minus.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移除 \(terminal.name)")
                        }
                    }

                    Button(action: addCustomTerminal) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text("添加应用…")
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - 选项

    private var optionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("换行方式")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.newlineMode },
                    set: { settings.newlineMode = $0 }
                )) {
                    ForEach(NewlineMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .help("终端把某种方式当成提交（内容被发出去）时，换下一个试试。「转为空格」永远安全。")

            Button(action: { state.runNewlineTest() }) {
                HStack(spacing: 4) {
                    Image(systemName: state.testCountdown > 0 ? "timer" : "text.insert")
                        .font(.caption)
                    Text(state.testCountdown > 0
                         ? "\(state.testCountdown) 秒后键入，切到终端窗口"
                         : "测试换行方式")
                        .font(.subheadline)
                }
                .foregroundColor(state.testCountdown > 0 ? .orange : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(state.testCountdown > 0)
            .help("倒计时结束后，用当前换行方式往前台窗口键入「第一行 / 第二行」，一眼看出是换行还是提交")

            Toggle("开机自启", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.subheadline)
            .help("需要 VoiceInput.app 位于「应用程序」文件夹")
        }
    }

    // MARK: - 动作

    private var enabledCount: Int {
        settings.enabledTerminals.count
            + settings.customTerminals.filter { $0.isEnabled }.count
    }

    private var totalCount: Int {
        PRESET_TERMINALS.count + settings.customTerminals.count
    }

    private func toggleRunning() {
        if state.isRunning {
            state.stop()
        } else {
            state.start()
        }
    }

    /// 白名单在 InterceptService 创建时快照，改动后需重建服务才能生效
    private func applyChange() {
        guard state.isRunning else { return }
        state.stop()
        state.start()
    }

    private func addCustomTerminal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"
        panel.message = "选择要监听的终端应用"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundleId = Bundle(url: url)?.bundleIdentifier, !bundleId.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无法读取应用标识"
            alert.informativeText = "选中的应用没有可用的 bundleIdentifier，请换一个应用。"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let name = url.deletingPathExtension().lastPathComponent
        settings.addCustomTerminal(name: name, bundleId: bundleId)
        applyChange()
    }
}
