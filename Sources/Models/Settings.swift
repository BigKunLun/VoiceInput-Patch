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

/// 换行的键入方式。不同终端 / TUI 对「软换行」的约定不一致，
/// 做成可切换项，终端表现不对时用户自己换一个即可，无需改代码
enum NewlineMode: String, CaseIterable, Codable, Identifiable {
    /// 换行统一替换为空格（最保守，绝不会误提交）
    case space
    /// Ctrl+J：发送 LF (0x0A) 而非 Enter 的 CR (0x0D)，多数 TUI 视为换行
    case controlJ
    /// 反斜杠 + Enter：shell 续行写法，Claude Code / bash / zsh 通用
    case backslashEnter
    /// Option+Enter：需终端开启 option-as-alt，否则退化成普通 Enter 触发提交
    case optionEnter
    /// Shift+Enter：需终端配置过对应 keybind（如 Claude Code 的 /terminal-setup）
    case shiftEnter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .space: return "转为空格"
        case .controlJ: return "Ctrl+J"
        case .backslashEnter: return "反斜杠 + Enter"
        case .optionEnter: return "Option+Enter"
        case .shiftEnter: return "Shift+Enter"
        }
    }
}

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
    private let newlineModeKey = "voiceInput.newlineMode"

    @Published var enabledTerminals: Set<String> {
        didSet { saveEnabledTerminals() }
    }

    @Published var customTerminals: [CustomTerminal] {
        didSet { saveCustomTerminals() }
    }

    /// 换行的键入方式，见 NewlineMode
    @Published var newlineMode: NewlineMode {
        didSet { UserDefaults.standard.set(newlineMode.rawValue, forKey: newlineModeKey) }
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

        if let raw = UserDefaults.standard.string(forKey: newlineModeKey),
           let mode = NewlineMode(rawValue: raw) {
            newlineMode = mode
        } else if let legacy = UserDefaults.standard.object(forKey: preserveNewlinesKey) as? Bool {
            // 迁移 1.3.0 的布尔开关：原「保留换行」走 Ctrl+J，原「不保留」走空格
            newlineMode = legacy ? .controlJ : .space
        } else {
            newlineMode = .controlJ
        }
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
