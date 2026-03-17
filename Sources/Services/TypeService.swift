//
//  TypeService.swift
//  VoiceInput
//

import Foundation
import CoreGraphics

class TypeService {
    /// 每个字符间的延迟（微秒）
    private static let charDelayUs: UInt32 = 800

    /// 键入文本（换行替换为空格）
    static func type(_ text: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        // 换行替换为空格，避免触发提交
        let processedText = text.replacingOccurrences(of: "\n", with: " ")

        for char in processedText {
            typeChar(char, source: src)
            usleep(charDelayUs)
        }
    }

    private static func typeChar(_ char: Character, source: CGEventSource) {
        let s = String(char)
        let utf16 = Array(s.utf16)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        // 直接设置 Unicode 字符串，绕过输入法
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        // 清除修饰键，防止 Cmd 状态泄露
        keyDown.flags = []
        keyUp.flags = []

        // post 到下游，绕过 CGEvent Tap 干扰
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
