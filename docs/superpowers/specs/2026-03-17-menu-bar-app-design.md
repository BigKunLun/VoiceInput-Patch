# VoiceInput-Patch 菜单栏应用设计文档

## 概述

将 VoiceInput-Patch从 Python + Swift 混合架构重构为纯 Swift SwiftUI 菜单栏应用，实现无终端后台运行。

## 目标

- 无需终端窗口即可运行
- 提供图形化开关控制
- 显示运行状态和统计信息
- 支持终端白名单配置

## 非目标

- 开机自启功能（用户自行配置）
- Windows 支持

## 架构

```
┌─────────────────────────────────────────────────────┐
│                VoiceInputApp (SwiftUI)              │
├─────────────────────────────────────────────────────┤
│  MenuBarExtra                                       │
│  ├── 状态图标 (彩色/灰色)│
│  └── 下拉菜单                                        │
│      ├── 开关按钮                                    │
│      ├── 状态信息 (拦截次数、上次预览)                 │
│      └── 设置 (终端多选)                             │
├─────────────────────────────────────────────────────┤
│  Services                                          │
│  ├── InterceptService    ← CGEvent Tap 拦截逻辑     │
│  └── TypeService         ← Unicode 逐字键入逻辑     │
├─────────────────────────────────────────────────────┤
│  Models/ViewModels                                 │
│  ├── AppState            ← 运行状态、统计数据        │
│  └── Settings            ← 终端白名单、持久化        │
└─────────────────────────────────────────────────────┘
```

## 组件设计

### VoiceInputApp.swift
- SwiftUI 应用入口
- 使用 `MenuBarExtra` 创建菜单栏应用
- 管理 AppState 生命周期

### AppState.swift
- `@Published var isRunning: Bool` - 运行状态
- `@Published var interceptCount: Int` - 拦截次数
- `@Published var lastPreview: String` - 上次拦截预览
- `@Published var settings: Settings` - 设置引用
- 方法：`start()`, `stop()`

### Settings.swift
- `var enabledTerminals: Set<String>` - 启用的终端列表
- 持久化：UserDefaults
- 预设终端：Ghostty, Terminal, iTerm2, Alacritty, WezTerm, kitty, Warp

### InterceptService.swift
- 复用现有 `intercept_paste.swift` 核心逻辑
- CGEvent Tap 拦截 Cmd+V
- 白名单过滤（检查前台应用）
- 拦截后调用回调，传递剪贴板内容
- 支持 SIGUSR1/SIGUSR2 暂停/恢复

### TypeService.swift
- 复用现有 `type_unicode.swift` 核心逻辑
- 接收文本，换行替换为空格
- CGEvent Unicode 逐字键入
- post 到 `.cgAnnotatedSessionEventTap` 绕过 tap 干扰
- 清除修饰键 flags

## 数据流

```
用户按 Cmd+V
    ↓
InterceptService (CGEvent Tap)
    → 检查前台应用是否在白名单
    → 是：吞掉事件，读取剪贴板
    → 通知 AppState (计数+1, 更新预览)
    → 调用 TypeService
    ↓
TypeService
    → 换行替换空格
    → CGEvent Unicode 逐字键入
    ↓
终端应用收到逐字输入（非粘贴）
```

## UI 设计

### 菜单栏图标
- 运行中：🎤 彩色/实心样式
- 已停止：🎤 灰色/空心样式

### 下拉菜单布局

```
┌─────────────────────────────┐
│  ● 已启动                    │  ← 点击切换开关
├─────────────────────────────┤
│  拦截次数: 23                │
│  上次: 这是一段语音输入...│
├─────────────────────────────┤
│  监听终端:                   │
│  ☑ Ghostty                  │
│  ☐ Terminal                 │
│  ☐ iTerm2                   │
│  ☐ Alacritty                │
│  ☐ WezTerm                  │
│  ☐ kitty                    │
│  ☐ Warp                     │
├─────────────────────────────┤
│  退出│
└─────────────────────────────┘
```

## 文件结构

```
VoiceInput-Patch/
├── Package.swift
├── Sources/
│   ├── VoiceInputApp.swift      # 入口
│   ├── Models/
│   │   ├── AppState.swift
│   │   └── Settings.swift
│   ├── Services/
│   │   ├── InterceptService.swift
│   │   └── TypeService.swift
│   └── Views/
│       └── MenuBarView.swift    # 菜单内容视图
├── assets/
│   └── AppIcon.icns             # 应用图标
└── build.sh                     # 构建脚本
```

## 技术要点

1. **CGEvent Tap 权限**：需要辅助功能权限，首次启动时检测并提示
2. **线程安全**：CGEvent Tap 回调在 RunLoop 线程，状态更新需切换到主线程
3. **暂停机制**：打字时暂停 tap 避免干扰，复用 SIGUSR1/SIGUSR2 信号机制
4. **持久化**：使用 UserDefaults 存储设置

## 兼容性

- macOS 13.0+
- Apple Silicon / Intel 均可
