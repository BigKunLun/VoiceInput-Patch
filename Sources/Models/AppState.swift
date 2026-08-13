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
    /// 换行测试的倒计时秒数，0 表示未在测试中
    @Published var testCountdown: Int = 0

    let settings = Settings.shared

    /// 换行测试用的两行文本
    private static let newlineTestText = "第一行\n第二行"

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
            onIntercept: { [weak self] text, targetPID, completion in
                guard let self = self else {
                    completion()
                    return
                }
                let newlineMode = self.settings.newlineMode
                DispatchQueue.main.async {
                    self.interceptCount += 1
                    let truncated = text.count > TypeService.maxLength
                    self.lastPreview = String(text.prefix(60)) + (truncated ? " [已截断]" : "")
                    self.writeBackSanitizedClipboard(text, newlineMode: newlineMode)
                }
                TypeService.type(text, newlineMode: newlineMode, targetPID: targetPID) { [weak self] aborted in
                    if aborted {
                        self?.lastPreview = "⚠️ 前台应用已切换，键入中止"
                    }
                    completion()
                }
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

    /// 把处理后的单行安全文本写回剪贴板，这样手动 Cmd+Shift+V 粘贴的也是不会卡终端的版本。
    ///
    /// 仅限「转为空格」模式：此时键入内容本就是单行版，写回不损失任何信息。
    /// 其余模式键入的是带换行的原文，若也写回单行版，原文的换行结构就被永久覆盖了——
    /// 用户想把同一段文本粘到编辑器时会发现格式已经没了，这个代价大于收益。
    private func writeBackSanitizedClipboard(_ text: String, newlineMode: NewlineMode) {
        guard newlineMode == .space else { return }
        let sanitized = TypeService.sanitizedForClipboard(text)
        guard sanitized != text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }

    // MARK: - 换行测试

    /// 倒计时结束后用当前换行方式键入两行文本，
    /// 省去「真的语音输入一次」才能验证换行方式是否可用的来回
    func runNewlineTest() {
        guard testCountdown == 0 else { return }
        testCountdown = 3
        scheduleNewlineTestTick()
    }

    private func scheduleNewlineTestTick() {
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.testCountdown -= 1
            if self.testCountdown > 0 {
                self.scheduleNewlineTestTick()
            } else {
                self.performNewlineTest()
            }
        }
        // .common 模式：菜单栏面板打开时定时器不会被 tracking mode 挂起
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performNewlineTest() {
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        TypeService.type(
            Self.newlineTestText,
            newlineMode: settings.newlineMode,
            targetPID: targetPID
        ) { [weak self] aborted in
            self?.lastPreview = aborted ? "⚠️ 测试中止：前台应用已切换" : "换行测试已键入"
        }
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
