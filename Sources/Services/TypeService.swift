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

    /// J 键的 virtualKey，配合 Control 发送 LF
    private static let jKeyCode: CGKeyCode = 38

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
    /// - Parameter newlineMode: 换行的键入方式，见 NewlineMode
    static func type(_ text: String, newlineMode: NewlineMode, completion: @escaping () -> Void) {
        typeQueue.async {
            guard let src = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion() }
                return
            }

            let processed = normalized(text)

            if newlineMode == .space {
                // 无需切段，整体替换后一次性分块键入，事件数最少
                typeSegment(processed.replacingOccurrences(of: "\n", with: " "), source: src)
            } else {
                // 按换行切段，段与段之间发送对应的软换行按键
                let segments = processed.components(separatedBy: "\n")
                for (index, segment) in segments.enumerated() {
                    if index > 0 {
                        postNewline(mode: newlineMode, source: src)
                        usleep(chunkDelayUs)
                    }
                    typeSegment(segment, source: src)
                }
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

    /// 按所选方式发送一次换行
    private static func postNewline(mode: NewlineMode, source: CGEventSource) {
        switch mode {
        case .space:
            typeChunk(Array(" ".utf16), source: source)
        case .controlJ:
            postKey(jKeyCode, flags: .maskControl, source: source)
        case .backslashEnter:
            typeChunk(Array("\\".utf16), source: source)
            usleep(chunkDelayUs)
            postKey(returnKeyCode, flags: [], source: source)
        case .optionEnter:
            postKey(returnKeyCode, flags: .maskAlternate, source: source)
        case .shiftEnter:
            postKey(returnKeyCode, flags: .maskShift, source: source)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

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
