#!/usr/bin/env swift
// type_unicode.swift
// 通过 CGEvent 直接发送 Unicode 字符，完全绕过输入法
// 无论当前是微信输入法、搜狗、ABC 都能正常输入中英文混合文本
//
// 编译: swiftc -O type_unicode.swift -o type_unicode
// 用法: echo "你好 hello 世界" | ./type_unicode
//       ./type_unicode --text "你好 hello 世界"
//
// 前置: 需要辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能）

import Foundation
import CoreGraphics

// ── 配置 ──────────────────────────────────────────

/// 每个字符间的延迟（微秒）。1000 = 1ms，足够快且稳定
let charDelayUs: UInt32 = 800

/// 每行之间的额外延迟（微秒）
let lineDelayUs: UInt32 = 3000

/// CGEvent 单次可发送的最大 UTF-16 code unit 数
/// Apple 文档建议不超过 20
let maxUTF16PerEvent = 20

// ── 核心函数 ───────────────────────────────────────

func typeUnicode(_ text: String) {
    guard let src = CGEventSource(stateID: .hidSystemState) else {
        fputs("错误: 无法创建 CGEventSource，请检查辅助功能权限\n", stderr)
        exit(1)
    }

    for char in text {
        if char == "\n" {
            // 发送 Return 键 (key code 36)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false) else {
                continue
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(lineDelayUs)
        } else if char == "\t" {
            // 发送 Tab 键 (key code 48)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false) else {
                continue
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(charDelayUs)
        } else {
            let s = String(char)
            let utf16 = Array(s.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else {
                continue
            }

            // 直接设置 Unicode 字符串，绕过输入法
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyDown.flags = []
            keyUp.flags = []

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            usleep(charDelayUs)
        }
    }
}

// ── 入口 ──────────────────────────────────────────

var inputText: String

if CommandLine.arguments.contains("--text"),
   let idx = CommandLine.arguments.firstIndex(of: "--text"),
   idx + 1 < CommandLine.arguments.count {
    // --text "xxx" 模式
    inputText = CommandLine.arguments[(idx + 1)...].joined(separator: " ")
} else if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    type_unicode — 通过 CGEvent 输入 Unicode 文本（绕过输入法）

    用法:
      echo "文本" | ./type_unicode          # 从 stdin 读取
      ./type_unicode --text "你好 world"    # 命令行参数

    注意:
      - 需要辅助功能权限
      - 支持中文、英文、日文、emoji 等任意 Unicode 字符
      - 无论当前输入法是什么都能正常工作
    """)
    exit(0)
} else {
    // 从 stdin 读取
    var lines: [String] = []
    while let line = readLine(strippingNewline: false) {
        lines.append(line)
    }
    inputText = lines.joined()
    // 去掉末尾多余换行
    if inputText.hasSuffix("\n") {
        inputText = String(inputText.dropLast())
    }
}

guard !inputText.isEmpty else {
    fputs("错误: 没有输入文本\n", stderr)
    exit(1)
}

typeUnicode(inputText)
