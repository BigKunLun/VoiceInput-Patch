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

    /// Return 键的 virtualKey
    private static let returnKeyCode: CGKeyCode = 36

    /// 用于键入操作的串行队列
    private static let typeQueue = DispatchQueue(label: "com.bigkunlun.voiceinput.type", qos: .userInteractive)

    /// 归一化换行符并截断超长文本，作为所有下游处理的统一输入
    static func normalized(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unified.count > maxLength ? String(unified.prefix(maxLength)) : unified
    }

    /// 写回剪贴板用的单行安全版本：换行一律转空格，
    /// 保证用户手动 Cmd+Shift+V 时不会触发 bracket paste 卡住终端
    static func sanitizedForClipboard(_ text: String) -> String {
        normalized(text).replacingOccurrences(of: "\n", with: " ")
    }

    /// 异步键入文本，完成后在主线程回调
    /// - Parameter preserveNewlines: true 时用 Option+Enter 键入软换行保住多行结构，
    ///   false 时换行统一替换为空格
    static func type(_ text: String, preserveNewlines: Bool, completion: @escaping () -> Void) {
        typeQueue.async {
            guard let src = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion() }
                return
            }

            let processed = normalized(text)

            if preserveNewlines {
                // 按换行切段，段与段之间发送软换行键
                let segments = processed.components(separatedBy: "\n")
                for (index, segment) in segments.enumerated() {
                    if index > 0 {
                        postSoftReturn(source: src)
                        usleep(chunkDelayUs)
                    }
                    typeSegment(segment, source: src)
                }
            } else {
                typeSegment(processed.replacingOccurrences(of: "\n", with: " "), source: src)
            }

            DispatchQueue.main.async { completion() }
        }
    }

    /// 分块键入一段无换行文本：每个 CGEvent 最多携带 maxChunkUTF16 个 UTF-16 码元，
    /// 避免逐字符产生海量事件淹没终端
    private static func typeSegment(_ segment: String, source: CGEventSource) {
        guard !segment.isEmpty else { return }

        var chunk: [UniChar] = []
        chunk.reserveCapacity(maxChunkUTF16)

        for char in segment {
            let utf16 = Array(String(char).utf16)
            if chunk.count + utf16.count > maxChunkUTF16 {
                typeChunk(chunk, source: source)
                usleep(chunkDelayUs)
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: utf16)
        }

        if !chunk.isEmpty {
            typeChunk(chunk, source: source)
        }
    }

    /// 发送 Option+Enter：macOS 终端下 Claude Code 等 TUI 将其识别为软换行而非提交
    private static func postSoftReturn(source: CGEventSource) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskAlternate
        keyUp.flags = .maskAlternate

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
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
