//
//  Settings.swift
//  VoiceInput
//

import Foundation
import Combine

/// 预设终端列表
let PRESET_TERMINALS = [
    "Ghostty", "Otty", "Terminal", "iTerm2",
    "Alacritty", "WezTerm", "kitty", "Warp"
]

/// 终端名称 -> 已知 bundleIdentifier 映射
/// key 必须全部小写，enabledBundleIds 通过 lowercased() 查找
let TERMINAL_BUNDLE_IDS: [String: String] = [
    "ghostty": "com.mitchellh.ghostty",
    "otty": "io.appmakes.otty",
    "terminal": "com.apple.terminal",
    "iterm2": "com.googlecode.iterm2",
    "alacritty": "org.alacritty",
    "wezterm": "org.wezfurlong.wezterm",
    "kitty": "net.kovidgoyal.kitty",
    "warp": "dev.warp.warp-stable",
]

/// 用户手动添加的终端，bundleId 从 .app 包内读取，不依赖预设表
struct CustomTerminal: Codable, Hashable, Identifiable {
    var id: String { bundleId }
    let name: String
    let bundleId: String
    var isEnabled: Bool = true
}

class Settings: ObservableObject {
    static let shared = Settings()

    private let enabledTerminalsKey = "voiceInput.enabledTerminals"
    private let customTerminalsKey = "voiceInput.customTerminals"
    private let preserveNewlinesKey = "voiceInput.preserveNewlines"

    @Published var enabledTerminals: Set<String> {
        didSet { saveEnabledTerminals() }
    }

    @Published var customTerminals: [CustomTerminal] {
        didSet { saveCustomTerminals() }
    }

    /// true：换行用 Option+Enter 软换行键入，保住多行结构
    /// false：换行统一替换为空格
    @Published var preserveNewlines: Bool {
        didSet { UserDefaults.standard.set(preserveNewlines, forKey: preserveNewlinesKey) }
    }

    private init() {
        if let saved = UserDefaults.standard.array(forKey: enabledTerminalsKey) as? [String] {
            enabledTerminals = Set(saved)
        } else {
            // 默认只启用 Ghostty
            enabledTerminals = ["Ghostty"]
        }

        if let data = UserDefaults.standard.data(forKey: customTerminalsKey),
           let decoded = try? JSONDecoder().decode([CustomTerminal].self, from: data) {
            customTerminals = decoded
        } else {
            customTerminals = []
        }

        // 未设置过时默认开启（object(forKey:) 为 nil 表示从未写入）
        preserveNewlines = UserDefaults.standard.object(forKey: preserveNewlinesKey) as? Bool ?? true
    }

    private func saveEnabledTerminals() {
        UserDefaults.standard.set(Array(enabledTerminals), forKey: enabledTerminalsKey)
    }

    private func saveCustomTerminals() {
        if let data = try? JSONEncoder().encode(customTerminals) {
            UserDefaults.standard.set(data, forKey: customTerminalsKey)
        }
    }

    /// 添加自定义终端，bundleId 重复时覆盖旧记录
    func addCustomTerminal(name: String, bundleId: String) {
        let normalizedId = bundleId.lowercased()
        // 已在预设表中的应用不重复添加，直接勾选预设项
        if let presetName = PRESET_TERMINALS.first(where: {
            TERMINAL_BUNDLE_IDS[$0.lowercased()] == normalizedId
        }) {
            enabledTerminals.insert(presetName)
            return
        }
        customTerminals.removeAll { $0.bundleId == normalizedId }
        customTerminals.append(CustomTerminal(name: name, bundleId: normalizedId))
    }

    func removeCustomTerminal(bundleId: String) {
        customTerminals.removeAll { $0.bundleId == bundleId }
    }

    func setCustomTerminal(bundleId: String, enabled: Bool) {
        guard let index = customTerminals.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        customTerminals[index].isEnabled = enabled
    }

    /// 小写终端名集合（用于 localizedName 兜底匹配）
    var enabledTerminalsLowercased: Set<String> {
        var names = Set(enabledTerminals.map { $0.lowercased() })
        for terminal in customTerminals where terminal.isEnabled {
            names.insert(terminal.name.lowercased())
        }
        return names
    }

    /// 启用终端对应的 bundleId 集合（用于精确匹配）
    var enabledBundleIds: Set<String> {
        var ids = Set<String>()
        for terminal in enabledTerminals {
            if let bundleId = TERMINAL_BUNDLE_IDS[terminal.lowercased()] {
                ids.insert(bundleId.lowercased())
            }
        }
        for terminal in customTerminals where terminal.isEnabled {
            ids.insert(terminal.bundleId.lowercased())
        }
        return ids
    }
}
