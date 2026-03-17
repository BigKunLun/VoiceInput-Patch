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

/// 终端名称 -> 已知 bundleIdentifier 映射
/// key 必须全部小写，enabledBundleIds 通过 lowercased() 查找
let TERMINAL_BUNDLE_IDS: [String: String] = [
    "ghostty": "com.mitchellh.ghostty",
    "terminal": "com.apple.terminal",
    "iterm2": "com.googlecode.iterm2",
    "alacritty": "org.alacritty",
    "wezterm": "org.wezfurlong.wezterm",
    "kitty": "net.kovidgoyal.kitty",
    "warp": "dev.warp.warp-stable",
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

    /// 获取启用终端对应的 bundleId 集合（用于精确匹配）
    var enabledBundleIds: Set<String> {
        var ids = Set<String>()
        for terminal in enabledTerminals {
            if let bundleId = TERMINAL_BUNDLE_IDS[terminal.lowercased()] {
                ids.insert(bundleId)
            }
        }
        return ids
    }
}
