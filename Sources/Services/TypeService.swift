//
//  TypeService.swift
//  VoiceInput
//

import Foundation
import CoreGraphics

class TypeService {
    /// 每个分块间的延迟（微秒）
    private static let chunkDelayUs: UInt32 = 800

    /// CGEvent keyboardSetUnicodeString 单次最大 UTF-16 码元数
    private static let maxChunkUTF16 = 20

    /// 单次键入最大字符数
    static let maxLength = 10000

    /// 用于键入操作的串行队列
    private static let typeQueue = DispatchQueue(label: "com.bigkunlun.voiceinput.type", qos: .userInteractive)

    /// 异步键入文本，完成后在主线程回调
    /// 换行替换为空格，超长文本截断至 maxLength，分块键入减少 CGEvent 数量
    static func type(_ text: String, completion: @escaping () -> Void) {
        typeQueue.async {
            guard let src = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion() }
                return
            }

            // 换行替换为空格，避免触发提交（\r\n、\r、\n 统一处理）
            var processedText = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")

            // 超长文本截断保护
            if processedText.count > maxLength {
                processedText = String(processedText.prefix(maxLength))
            }

            // 分块键入：每个 CGEvent 最多携带 maxChunkUTF16 个 UTF-16 码元，
            // 避免逐字符产生海量事件淹没终端
            var chunk: [UniChar] = []
            chunk.reserveCapacity(maxChunkUTF16)

            for char in processedText {
                let utf16 = Array(String(char).utf16)
                if chunk.count + utf16.count > maxChunkUTF16 {
                    typeChunk(chunk, source: src)
                    usleep(chunkDelayUs)
                    chunk.removeAll(keepingCapacity: true)
                }
                chunk.append(contentsOf: utf16)
            }

            if !chunk.isEmpty {
                typeChunk(chunk, source: src)
            }

            DispatchQueue.main.async { completion() }
        }
    }

    private static func typeChunk(_ utf16: [UniChar], source: CGEventSource) {
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
