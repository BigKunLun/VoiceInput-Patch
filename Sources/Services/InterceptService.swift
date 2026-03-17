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
    private var onIntercept: (String) -> Void
    private var isPaused = false

    init(whitelist: Set<String>, bundleIdWhitelist: Set<String>, onIntercept: @escaping (String) -> Void) {
        self.whitelist = whitelist
        self.bundleIdWhitelist = bundleIdWhitelist
        self.onIntercept = onIntercept
    }

    func start() {
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
            return
        }

        tap = createdTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        log("✅ InterceptService 已启动，白名单: \(whitelist)")
    }

    func stop() {
        guard let tap = tap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.tap = nil
        self.runLoopSource = nil
        log("🛑 InterceptService 已停止")
    }

    func pause() {
        isPaused = true
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func resume() {
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

        // 通知主线程（在主线程中会调用 TypeService）
        onIntercept(content)

        // 等待键入完成后恢复 tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.resume()
        }

        // 吞掉 Cmd+V
        return nil
    }
}
