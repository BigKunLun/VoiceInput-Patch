//
//  InterceptService.swift
//  VoiceInput
//

import os.log
import Cocoa
import CoreGraphics

private let logger = Logger(subsystem: "com.bigkunlun.voiceinput", category: "intercept")

private func log(_ msg: String) {
    logger.info("\(msg, privacy: .public)")
}

class InterceptService {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var whitelist: Set<String>
    private var bundleIdWhitelist: Set<String>
    private var onIntercept: (String, @escaping () -> Void) -> Void
    /// 所有对 isPaused 的读写都在主线程 RunLoop 中进行（event tap 回调 + DispatchQueue.main）
    private var isPaused = false

    init(whitelist: Set<String>, bundleIdWhitelist: Set<String>, onIntercept: @escaping (String, @escaping () -> Void) -> Void) {
        self.whitelist = whitelist
        self.bundleIdWhitelist = bundleIdWhitelist
        self.onIntercept = onIntercept
    }

    /// 启动事件拦截，返回是否成功
    @discardableResult
    func start() -> Bool {
        assert(Thread.isMainThread, "InterceptService.start() 必须在主线程调用")
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let service = Unmanaged<InterceptService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("❌ 无法创建 CGEvent Tap，请检查辅助功能权限")
            return false
        }

        tap = createdTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        log("✅ InterceptService 已启动，白名单: \(whitelist)，bundleId: \(bundleIdWhitelist)")
        return true
    }

    func stop() {
        assert(Thread.isMainThread, "InterceptService.stop() 必须在主线程调用")
        guard let tap = tap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.tap = nil
        self.runLoopSource = nil
        log("🛑 InterceptService 已停止")
    }

    func pause() {
        assert(Thread.isMainThread, "InterceptService.pause() 必须在主线程调用")
        isPaused = true
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func resume() {
        assert(Thread.isMainThread, "InterceptService.resume() 必须在主线程调用")
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        isPaused = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 处理 tap 被禁用的情况
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap, !isPaused {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // 检查是否是 Cmd+V (keyCode 9)
        let isCmd = flags.contains(.maskCommand)
        let hasOtherMods = flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskAlternate)

        guard keyCode == 9, isCmd, !hasOtherMods else {
            return Unmanaged.passUnretained(event)
        }

        // 检查前台应用
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Unmanaged.passUnretained(event)
        }
        let appName = (app.localizedName ?? "").lowercased()
        let bundleId = (app.bundleIdentifier ?? "").lowercased()

        guard whitelist.contains(appName) || bundleIdWhitelist.contains(bundleId) else {
            log("⚠️ 白名单不匹配: \(appName) / \(bundleId)")
            return Unmanaged.passUnretained(event)
        }

        // 读取剪贴板
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        log("拦截 Cmd+V: \(content.count) 字")

        // 暂停 tap，避免干扰后续键入
        pause()

        // 传递 completion，由调用方在键入完成后调用以恢复 tap
        onIntercept(content) { [weak self] in
            self?.resume()
        }

        // 吞掉 Cmd+V
        return nil
    }
}
