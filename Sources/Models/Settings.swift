//
//  Settings.swift
//  VoiceInput
//

import Foundation
import Combine

/// 预设终端列表
let PRESET_TERMINALS = [
    "Ghostty", "Terminal", "iTerm2",
    "Alacritty", "WezTerm", "kitty", "Warp"
]

class Settings: ObservableObject {
    static let shared = Settings()

    private let enabledTerminalsKey = "voiceInput.enabledTerminals"

    @Published var enabledTerminals: Set<String> {
        didSet {
            save()
        }
    }

    private init() {
        if let saved = UserDefaults.standard.array(forKey: enabledTerminalsKey) as? [String] {
            enabledTerminals = Set(saved)
        } else {
            // 默认只启用 Ghostty
            enabledTerminals = ["Ghostty"]
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(enabledTerminals), forKey: enabledTerminalsKey)
    }

    /// 获取小写的终端名集合（用于匹配）
    var enabledTerminalsLowercased: Set<String> {
        Set(enabledTerminals.map { $0.lowercased() })
    }
}
