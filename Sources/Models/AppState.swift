//
//  AppState.swift
//  VoiceInput
//

import Foundation
import Combine
import Cocoa
import ApplicationServices
import ServiceManagement

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning: Bool = false
    @Published var interceptCount: Int = 0
    @Published var lastPreview: String = ""
    @Published var launchAtLogin: Bool = false

    let settings = Settings.shared

    private var interceptService: InterceptService?

    private init() {
        refreshLaunchAtLogin()
    }

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
                guard let self = self else {
                    completion()
                    return
                }
                let newlineMode = self.settings.newlineMode
                DispatchQueue.main.async {
                    self.interceptCount += 1
                    let truncated = text.count > TypeService.maxLength
                    self.lastPreview = String(text.prefix(60)) + (truncated ? " [已截断]" : "")
                    self.writeBackSanitizedClipboard(text)
                }
                TypeService.type(text, newlineMode: newlineMode, completion: completion)
            }
        )

        let success = interceptService?.start() ?? false
        isRunning = success
        if !success {
            interceptService = nil
            showStartFailedAlert()
        }
    }

    func stop() {
        interceptService?.stop()
        interceptService = nil
        isRunning = false
    }

    /// 把处理后的单行安全文本写回剪贴板，
    /// 这样即使自动键入被打断，手动 Cmd+Shift+V 粘贴的也是不会卡终端的版本
    private func writeBackSanitizedClipboard(_ text: String) {
        let sanitized = TypeService.sanitizedForClipboard(text)
        guard sanitized != text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }

    // MARK: - 开机自启

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showLaunchAtLoginFailedAlert(error)
        }
        refreshLaunchAtLogin()
    }

    // MARK: - 弹窗

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

    private func showLaunchAtLoginFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "开机自启设置失败"
        alert.informativeText = "\(error.localizedDescription)\n\n请确认 VoiceInput.app 已放入「应用程序」文件夹后重试。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
