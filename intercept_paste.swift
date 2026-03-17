// intercept_paste.swift
// 通过 CGEvent Tap 拦截 Cmd+V，吞掉粘贴事件，并将剪贴板内容输出到 stdout
// 由外部进程（voice_type.py）负责调用 type_unicode 实际输入文本
//
// 编译: swiftc -O intercept_paste.swift -o intercept_paste -framework Cocoa
// 用法: ./intercept_paste --whitelist ghostty
//
// 前置: 需要辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能）

import Cocoa

// ── 配置 ──────────────────────────────────────────

let scriptDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
let logPath = (scriptDir as NSString).appendingPathComponent("voice_type.log")

var whitelistApps: Set<String> = ["ghostty"]
var interceptCount = 0

var tapRef: CFMachPort?
var tapPausedBySignal = false

// ── 日志（只写文件，stdout 留给数据通信） ─────────

func log(_ msg: String, level: String = "INFO") {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(df.string(from: Date())) [\(level)] \(msg)\n"
    // 日志写 stderr，不干扰 stdout 数据通道
    fputs(line, stderr)
    if let fh = FileHandle(forWritingAtPath: logPath) {
        defer { fh.closeFile() }
        fh.seekToEndOfFile()
        if let data = line.data(using: .utf8) { fh.write(data) }
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

// ── CGEvent Tap 回调 ─────────────────────────────

let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if !tapPausedBySignal, let tap = tapRef {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

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
    guard whitelistApps.contains(appName) || whitelistApps.contains(where: { bundleId.contains($0) }) else {
        return Unmanaged.passUnretained(event)
    }

    // 读取剪贴板
    guard let content = NSPasteboard.general.string(forType: .string),
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return Unmanaged.passUnretained(event)
    }

    interceptCount += 1
    let charCount = content.count
    let lineCount = content.components(separatedBy: "\n").count
    let preview = String(content.prefix(60)).replacingOccurrences(of: "\n", with: "↵")

    log("📋 [\(interceptCount)] 拦截 Cmd+V: \(charCount)字 / \(lineCount)行 | \(preview)...")

    // 将内容通过 stdout 发给 Python 进程
    // 协议：BASE64编码的内容 + 换行
    if let data = content.data(using: .utf8) {
        let b64 = data.base64EncodedString()
        print(b64)
        fflush(stdout)
    }

    // 吞掉 Cmd+V
    return nil
}

// ── 解析参数 ─────────────────────────────────────

if let idx = CommandLine.arguments.firstIndex(of: "--whitelist"), idx + 1 < CommandLine.arguments.count {
    whitelistApps = Set(CommandLine.arguments[(idx + 1)...].map { $0.lowercased() })
}

// ── 创建 CGEvent Tap ─────────────────────────────

let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    fputs("❌ 无法创建 CGEvent Tap，请检查辅助功能权限\n", stderr)
    exit(1)
}

tapRef = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

log("🎙️  闪电说 → Claude Code 拦截器 v3 (CGEvent Tap)")
log("  监听终端:   \(whitelistApps.sorted().joined(separator: ", "))")
log("  拦截方式:   Cmd+V 吞掉 → stdout 输出内容 → 外部进程键入")
log("✅ 启动成功")

// SIGUSR1 = 暂停 tap（Python 打字前发送）
// SIGUSR2 = 恢复 tap（Python 打字后发送）
signal(SIGUSR1) { _ in
    tapPausedBySignal = true
    if let tap = tapRef { CGEvent.tapEnable(tap: tap, enable: false) }
}
signal(SIGUSR2) { _ in
    tapPausedBySignal = false
    if let tap = tapRef { CGEvent.tapEnable(tap: tap, enable: true) }
}
signal(SIGINT, { _ in exit(0) })
signal(SIGTERM, { _ in exit(0) })

CFRunLoopRun()
