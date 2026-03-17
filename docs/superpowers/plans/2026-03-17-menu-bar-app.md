# VoiceInput-Patch 菜单栏应用实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 VoiceInput-Patch 从 Python + Swift 混合架构重构为纯Swift SwiftUI 菜单栏应用

**Architecture:** SwiftUI MenuBarExtra 应用，InterceptService 在独立线程运行 CGEvent Tap，拦截到粘贴后调用 TypeService 逐字键入

**Tech Stack:** Swift 5.9, SwiftUI, CGEvent, CoreGraphics

---

## 文件结构

```
VoiceInput-Patch/
├── Package.swift                    # SPM 配置
├── Sources/
│   ├── VoiceInputApp.swift          # 入口 + MenuBarExtra
│   ├── Models/
│   │   ├── AppState.swift           # 全局状态
│   │   └── Settings.swift           # 设置持久化
│   ├── Services/
│   │   ├── InterceptService.swift   # CGEvent Tap 拦截
│   │   └── TypeService.swift        # Unicode 键入
│   └── Views/
│       └── MenuBarView.swift        # 下拉菜单视图
├── build.sh                         # 构建脚本
└── (保留原有文件作为参考)
```

---

## Chunk 1: 项目骨架与基础模型

### Task 1: 创建 Package.swift

**Files:**
- Create: `Package.swift`

- [ ] **Step 1: 创建 Swift Package 配置**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoiceInput", targets: ["VoiceInput"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources"
        )
    ]
)
```

- [ ] **Step 2: 创建 Sources 目录结构**

```bash
mkdir -p Sources/Models Sources/Services Sources/Views
```

---

### Task 2: 创建 Settings 模型

**Files:**
- Create: `Sources/Models/Settings.swift`

- [ ] **Step 1: 编写 Settings 类**

```swift
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

    private let enabledTerminalsKey = "enabledTerminals"

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
        enabledTerminals.map { $0.lowercased() }.asSet()
    }
}

extension Array {
    func asSet() -> Set<Element> where Element: Hashable {
        Set(self)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Package.swift Sources/Models/Settings.swift
git commit -m "feat: 添加项目骨架和 Settings 模型"
```

---

### Task 3: 创建 AppState 模型

**Files:**
- Create: `Sources/Models/AppState.swift`

- [ ] **Step 1: 编写 AppState 类**

```swift
//
//  AppState.swift
//  VoiceInput
//

import Foundation
import Combine

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning: Bool = false
    @Published var interceptCount: Int = 0
    @Published var lastPreview: String = ""

    let settings = Settings.shared

    private var interceptService: InterceptService?

    private init() {}

    func start() {
        guard!isRunning else { return }

        interceptService = InterceptService(
            whitelist: settings.enabledTerminalsLowercased,
            onIntercept: { [weak self] text in
                DispatchQueue.main.async {
                    self?.handleIntercept(text)
                }
            }
        )

        interceptService?.start()
        isRunning = true
    }

    func stop() {
        interceptService?.stop()
        interceptService = nil
        isRunning = false
    }

    private func handleIntercept(_ text: String) {
        interceptCount += 1
        lastPreview = String(text.prefix(60))
        TypeService.type(text)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Models/AppState.swift
git commit -m "feat: 添加 AppState 状态管理"
```

---

## Chunk 2: 核心服务

### Task 4: 创建 TypeService

**Files:**
- Create: `Sources/Services/TypeService.swift`

- [ ] **Step 1: 编写 TypeService（复用 type_unicode.swift 核心逻辑）**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Services/TypeService.swift
git commit -m "feat: 添加 TypeService Unicode 键入服务"
```

---

### Task 5: 创建 InterceptService

**Files:**
- Create: `Sources/Services/InterceptService.swift`

- [ ] **Step 1: 编写 InterceptService（复用 intercept_paste.swift 核心逻辑）**

```swift
//
//  InterceptService.swift
//  VoiceInput
//

import Foundation
import Cocoa
import CoreGraphics

class InterceptService {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var whitelist: Set<String>
    private var onIntercept: (String) -> Void

    init(whitelist: Set<String>, onIntercept: @escaping (String) -> Void) {
        self.whitelist = whitelist
        self.onIntercept = onIntercept
    }

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let service = Unmanaged<InterceptService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ 无法创建 CGEvent Tap，请检查辅助功能权限")
            return
        }

        tap = createdTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
    }

    func stop() {
        guard let tap = tap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.tap = nil
        self.runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 处理 tap 被禁用的情况
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // 检查是否是 Cmd+V (keyCode 9)
        let isCmd = flags.contains(.maskCommand)
        let hasOtherMods = flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskAlternate)

        guard keyCode == 9, isCmd, !hasOtherMods else {
            return Unmanaged.passUnretained(event)
        }

        // 检查前台应用
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Unmanaged.passUnretained(event)
        }
        let appName = (app.localizedName ?? "").lowercased()
        let bundleId = (app.bundleIdentifier ?? "").lowercased()

        guard whitelist.contains(appName) || whitelist.contains(where: { bundleId.contains($0) }) else {
            return Unmanaged.passUnretained(event)
        }

        // 读取剪贴板
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        // 通知主线程
        onIntercept(content)

        // 吞掉 Cmd+V
        return nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Services/InterceptService.swift
git commit -m "feat: 添加 InterceptService CGEvent Tap 拦截服务"
```

---

## Chunk 3: UI 与应用入口

### Task 6: 创建 MenuBarView

**Files:**
- Create: `Sources/Views/MenuBarView.swift`

- [ ] **Step 1: 编写菜单视图**

```swift
//
//  MenuBarView.swift
//  VoiceInput
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 开关按钮
            Button(action: toggleRunning) {
                HStack {
                    Image(systemName: state.isRunning ? "mic.circle.fill" : "mic.circle")
                        .foregroundColor(state.isRunning ? .green : .secondary)
                    Text(state.isRunning ? "已启动" : "已停止")
                    Spacer()
                    Text(state.isRunning ? "点击停止" : "点击启动")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            Divider()

            // 状态信息
            VStack(alignment: .leading, spacing: 4) {
                Text("拦截次数: \(state.interceptCount)")
                    .font(.subheadline)
                if !state.lastPreview.isEmpty {
                    Text("上次: \(state.lastPreview)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            // 终端选择
            Text("监听终端:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(PRESET_TERMINALS, id: \.self) { terminal in
                Toggle(terminal, isOn: Binding(
                    get: { state.settings.enabledTerminals.contains(terminal) },
                    set: { isChecked in
                        if isChecked {
                            state.settings.enabledTerminals.insert(terminal)
                        } else {
                            state.settings.enabledTerminals.remove(terminal)
                        }
                        // 如果正在运行，重启以应用新设置
                        if state.isRunning {
                            state.stop()
                            state.start()
                        }
                    }
                ))
                .toggleStyle(.checkbox)
            }

            Divider()

            // 退出按钮
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func toggleRunning() {
        if state.isRunning {
            state.stop()
        } else {
            state.start()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Views/MenuBarView.swift
git commit -m "feat: 添加 MenuBarView 菜单视图"
```

---

### Task 7: 创建应用入口

**Files:**
- Create: `Sources/VoiceInputApp.swift`

- [ ] **Step 1: 编写应用入口**

```swift
//
//  VoiceInputApp.swift
//  VoiceInput
//
//  Created on 2026-03-17.
//

import SwiftUI

@main
struct VoiceInputApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra(systemImage: state.isRunning ? "mic.circle.fill" : "mic.circle") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/VoiceInputApp.swift
git commit -m "feat: 添加应用入口 VoiceInputApp"
```

---

### Task 8: 创建构建脚本

**Files:**
- Create: `build.sh`

- [ ] **Step 1: 编写构建脚本**

```bash
#!/bin/bash
set -e

echo "🔨 构建 VoiceInput..."

# 构建
swift build -c release

# 创建 .app 包
APP_NAME="VoiceInput"
APP_DIR="./${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

# 复制可执行文件
cp .build/release/VoiceInput "${MACOS_DIR}/${APP_NAME}"

# 创建 Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoiceInput</string>
    <key>CFBundleIdentifier</key>
    <string>com.bigkunlun.voiceinput</string>
    <key>CFBundleName</key>
    <string>VoiceInput</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceInput</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 BigKunLun. All rights reserved.</string>
</dict>
</plist>
EOF

chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ 构建完成: ${APP_DIR}"
```

- [ ] **Step 2: 添加执行权限并 Commit**

```bash
chmod +x build.sh
git add build.sh
git commit -m "feat: 添加构建脚本"
```

---

## Chunk 4: 构建与验证

### Task 9: 构建并测试

- [ ] **Step 1: 运行构建脚本**

```bash
cd /Users/shijianing/CodingTime/Personal/VoiceInput-Patch
./build.sh
```

Expected: 构建成功，生成 VoiceInput.app

- [ ] **Step 2: 首次运行检查权限**

```bash
open VoiceInput.app
```

Expected: 系统提示辅助功能权限，授权后应用显示在菜单栏

- [ ] **Step 3: 功能验证**

1. 点击菜单栏图标，确认下拉菜单正常显示
2. 勾选 Ghostty，点击启动
3. 在 Ghostty 中使用语音输入，确认拦截生效
4. 确认拦截次数和预览正常更新

- [ ] **Step 4: Final Commit**

```bash
git add .
git commit -m "feat: 完成 VoiceInput 菜单栏应用"
```

---

## 执行说明

**执行顺序：** 按 Task 1 → Task 9 顺序执行

**依赖关系：**
- Task 2、3 依赖 Task 1（目录结构）
- Task 4、5 可并行
- Task 6、7 依赖 Task 2-5
- Task 8、9 依赖所有前置任务
