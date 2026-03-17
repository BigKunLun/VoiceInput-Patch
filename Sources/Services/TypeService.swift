//
//  TypeService.swift
//  VoiceInput
//

import Foundation
import CoreGraphics

class TypeService {
    /// 每个字符间的延迟（微秒）
    private static let charDelayUs: UInt32 = 800

    /// 单次键入最大字符数
    static let maxLength = 10000

    /// 用于键入操作的串行队列
    private static let typeQueue = DispatchQueue(label: "com.bigkunlun.voiceinput.type", qos: .userInteractive)

    /// 异步键入文本，完成后在主线程回调
    /// 换行替换为空格，超长文本截断至 maxLength
    static func type(_ text: String, completion: @escaping () -> Void) {
        typeQueue.async {
            guard let src = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion() }
                return
            }

            // 换行替换为空格，避免触发提交
            var processedText = text.replacingOccurrences(of: "\n", with: " ")

            // 超长文本截断保护
            if processedText.count > maxLength {
                processedText = String(processedText.prefix(maxLength))
            }

            for char in processedText {
                typeChar(char, source: src)
                usleep(charDelayUs)
            }

            DispatchQueue.main.async { completion() }
        }
    }

    private static func typeChar(_ char: Character, source: CGEventSource) {
        let s = String(char)
        let utf16 = Array(s.utf16)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown.flags = []
        keyUp.flags = []

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
