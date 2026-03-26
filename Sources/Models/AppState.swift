//
//  AppState.swift
//  VoiceInput
//

import Foundation
import Combine
import Cocoa
import ApplicationServices

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning: Bool = false
    @Published var interceptCount: Int = 0
    @Published var lastPreview: String = ""

    let settings = Settings.shared

    private var interceptService: InterceptService?

    private init() {}

    func start() {
        guard !isRunning else { return }

        // 检查辅助功能权限
        guard AXIsProcessTrusted() else {
            showAccessibilityAlert()
            return
        }

        interceptService = InterceptService(
            whitelist: settings.enabledTerminalsLowercased,
            bundleIdWhitelist: settings.enabledBundleIds,
            onIntercept: { [weak self] text, completion in
                DispatchQueue.main.async {
                    self?.interceptCount += 1
                    let truncated = text.count > TypeService.maxLength
                    self?.lastPreview = String(text.prefix(60)) + (truncated ? " [已截断]" : "")
                }
                TypeService.type(text, completion: completion)
            }
        )

        let success = interceptService?.start() ?? false
        isRunning = success
        if !success {
            interceptService = nil
            showStartFailedAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "VoiceInput 需要辅助功能权限才能拦截键盘事件。\n\n请前往 系统设置 → 隐私与安全性 → 辅助功能，添加并勾选 VoiceInput。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func showStartFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "启动失败"
        alert.informativeText = "无法创建事件拦截器，请确认辅助功能权限已授予，然后重试。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    func stop() {
        interceptService?.stop()
        interceptService = nil
        isRunning = false
    }

}
