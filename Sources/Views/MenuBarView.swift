//
//  MenuBarView.swift
//  VoiceInput
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    @State private var showTerminals = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 开关按钮
            Button(action: toggleRunning) {
                HStack {
                    Image(systemName: state.isRunning ? "text.bubble.fill" : "text.bubble")
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

            // 终端选择（整行可点击展开/折叠）
            Button(action: { showTerminals.toggle() }) {
                HStack {
                    Image(systemName: showTerminals ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("监听终端")
                    Spacer()
                    Text("\(state.settings.enabledTerminals.count)/\(PRESET_TERMINALS.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showTerminals {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(PRESET_TERMINALS, id: \.self) { terminal in
                        Toggle(terminal, isOn: Binding(
                            get: { state.settings.enabledTerminals.contains(terminal) },
                            set: { isChecked in
                                if isChecked {
                                    state.settings.enabledTerminals.insert(terminal)
                                } else {
                                    state.settings.enabledTerminals.remove(terminal)
                                }
                                if state.isRunning {
                                    state.stop()
                                    state.start()
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.subheadline)
                    }
                }
                .padding(.leading, 8)
            }

            Divider()

            // 退出按钮
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
        .padding(12)
        .frame(width: 260)
    }

    private func toggleRunning() {
        if state.isRunning {
            state.stop()
        } else {
            state.start()
        }
    }
}
