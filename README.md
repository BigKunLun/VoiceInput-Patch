# VoiceInput-Patch — 终端语音输入补丁

## 问题

许多语音输入法（闪电说、讯飞语音等）通过「剪贴板 + Cmd+V」粘贴识别结果。在 Claude Code 等终端应用中，多行粘贴会触发 Bracket Paste Mode 折叠显示，导致语音输入内容无法正常展开。

## 解决方案

macOS 菜单栏应用，通过 CGEvent Tap 拦截指定终端中的 Cmd+V，吞掉粘贴事件，改用 CGEvent Unicode 逐字键入，绕过粘贴检测。

```
语音输入法 -> 写入剪贴板 + Cmd+V
                              |
InterceptService          ->  CGEvent Tap 拦截 Cmd+V -> 吞掉 -> 读取剪贴板
                              |
TypeService               ->  CGEvent keyboardSetUnicodeString 逐字键入
                              -> post 到 .cgAnnotatedSessionEventTap（绕过 tap 干扰）
                              |
终端 / Claude Code         ->  收到逐字键盘输入（非粘贴）-> 不触发折叠
```

## 适用范围

### 语音输入法

兼容所有通过「写入剪贴板 + 模拟 Cmd+V」工作的语音输入法（闪电说、讯飞语音等）。

> 通过输入法框架直接输入的方式（如 macOS 系统听写）本身就是逐字输入，不会触发折叠，无需本工具。

### 终端

预设支持 Ghostty、Terminal、iTerm2、Alacritty、WezTerm、kitty、Warp，可通过菜单栏界面勾选。

## 构建与安装

```bash
# 需要 Xcode Command Line Tools
# 如未安装: xcode-select --install

# 克隆并构建
git clone https://github.com/5Iris5/VoiceInput-Patch.git
cd VoiceInput-Patch
./build.sh

# 运行
open VoiceInput.app
```

### 授予辅助功能权限

系统设置 -> 隐私与安全性 -> 辅助功能 -> 勾选 VoiceInput

## 使用

1. 启动后应用显示在菜单栏（麦克风图标）
2. 点击图标打开菜单，勾选需要监听的终端
3. 点击启动按钮开始拦截
4. 在指定终端中正常使用语音输入即可，非白名单应用中的粘贴不受影响

## 项目结构

```
VoiceInput-Patch/
├── Package.swift                    # SPM 配置
├── Sources/
│   ├── VoiceInputApp.swift          # SwiftUI 应用入口（MenuBarExtra）
│   ├── Models/
│   │   ├── AppState.swift           # 运行状态、统计数据
│   │   └── Settings.swift           # 终端白名单、UserDefaults 持久化
│   ├── Services/
│   │   ├── InterceptService.swift   # CGEvent Tap 拦截 Cmd+V
│   │   └── TypeService.swift        # CGEvent Unicode 逐字键入
│   └── Views/
│       └── MenuBarView.swift        # 菜单栏下拉菜单
├── build.sh                         # 构建脚本（swift build + 打包 .app）
└── docs/
    └── technical-notes.md           # 技术要点与决策记录
```

## 环境要求

- macOS 13.0+（Apple Silicon / Intel 均可）
- Xcode Command Line Tools
- 辅助功能权限
