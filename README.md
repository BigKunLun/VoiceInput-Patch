# VoiceInput-Patch — 终端语音输入补丁

[English](#english) | [中文](#中文)

---

## English

### Problem

Many voice input tools (e.g. Whisper-based apps, dictation software) work by writing recognized text to the clipboard and simulating Cmd+V. In terminal apps like Claude Code, multi-line pastes trigger **Bracket Paste Mode**, which wraps content in `\e[200~`...`\e[201~` escape sequences. This causes pasted text to be collapsed, garbled, or even **freezes the terminal entirely**.

### Solution

A macOS menu bar app that intercepts Cmd+V in specified terminals via CGEvent Tap, swallows the paste event, reads the clipboard, and re-types the content character-by-character using CGEvent Unicode key events — completely bypassing paste detection.

```
Voice Input Tool -> Clipboard + Cmd+V
                                  |
InterceptService   ->  CGEvent Tap intercepts Cmd+V -> swallow -> read clipboard
                                  |
TypeService        ->  CGEvent keyboardSetUnicodeString (chunked typing, up to 20 UTF-16 units per event)
                       -> post to .cgAnnotatedSessionEventTap (bypass tap interference)
                                  |
Terminal / Claude Code ->  Receives keyboard input (not paste) -> no bracket paste mode
```

### Supported Terminals

Ghostty, Otty, Terminal.app, iTerm2, Alacritty, WezTerm, kitty, Warp — configurable via the menu bar UI.

### Installation

#### Option 1: Download pre-built binary

Download the latest `VoiceInput.app.zip` from [Releases](https://github.com/BigKunLun/VoiceInput-Patch/releases), unzip, and drag `VoiceInput.app` to your Applications folder.

#### Option 2: Build from source

```bash
# Requires Xcode Command Line Tools
# If not installed: xcode-select --install

git clone https://github.com/BigKunLun/VoiceInput-Patch.git
cd VoiceInput-Patch
./build.sh

open VoiceInput.app
```

#### Can't open the app?

Since the app is not notarized by Apple, macOS may block it. Use any of these methods:

**Method A: Remove quarantine via terminal (recommended)**

```bash
xattr -cr VoiceInput.app
```

**Method B: Right-click open**

Right-click `VoiceInput.app` → Select "Open" → Click "Open" in the dialog

**Method C: System Settings**

After the app is blocked, go to System Settings → Privacy & Security → scroll down to find "VoiceInput was blocked" → click "Open Anyway"

#### Grant Accessibility Permission

System Settings → Privacy & Security → Accessibility → Add and enable VoiceInput

### Usage

1. After launch, the app appears in the menu bar (waveform icon)
2. Click the icon to open the menu, check the terminals you want to monitor
3. Click the start button to begin interception
4. Use voice input normally in the specified terminals — paste in non-whitelisted apps is unaffected

5. Not in the list? Click **Add app…** and pick any `.app` — its bundle identifier is read automatically, no rebuild needed.

### Notes

- **Newlines**: pick a *Newline mode* in the menu bar. Default is **Ctrl+J**, which sends LF instead of Enter's CR — most TUIs treat it as a line break rather than a submit. If your terminal submits anyway, switch to another mode without restarting: `\` + Enter (shell continuation), Option+Enter (needs `option-as-alt`), Shift+Enter (needs a terminal keybind, e.g. Claude Code's `/terminal-setup`), or *Space* which is always safe but flattens multi-line text.
- **Clipboard write-back**: in *Space* mode only, the sanitized single-line text is written back to the clipboard so a manual Cmd+Shift+V stays paste-safe. Other modes leave the clipboard untouched — they type the original line breaks, and overwriting the clipboard would destroy that structure for good.
- **Typing is aborted if you switch apps** mid-way, so the remaining text never lands in the wrong window.
- **Escape hatch**: Cmd+Shift+V is never intercepted — use it when you want the terminal's native paste.
- **Launch at login** uses `SMAppService`; the app must live in `/Applications`.
- Text longer than 10,000 characters is truncated for safety.

### Stable code signing (recommended when building from source)

Ad-hoc signing produces a new identity on every build, so macOS treats the app as new and the granted Accessibility permission is lost. Create a fixed self-signed certificate once:

```bash
./scripts/create-signing-cert.sh
```

`build.sh` picks it up automatically on subsequent builds.

### Requirements

- macOS 13.0+ (Apple Silicon / Intel)
- Xcode Command Line Tools
- Accessibility permission

---

## 中文

### 问题

许多语音输入法（闪电说、讯飞语音等）通过「剪贴板 + Cmd+V」粘贴识别结果。在 Claude Code 等终端应用中，多行粘贴会触发 Bracket Paste Mode，导致语音输入内容被折叠、乱码，甚至**终端完全冻结**。

### 解决方案

macOS 菜单栏应用，通过 CGEvent Tap 拦截指定终端中的 Cmd+V，吞掉粘贴事件，改用 CGEvent Unicode 逐字键入，绕过粘贴检测。

```
语音输入法 -> 写入剪贴板 + Cmd+V
                              |
InterceptService          ->  CGEvent Tap 拦截 Cmd+V -> 吞掉 -> 读取剪贴板
                              |
TypeService               ->  CGEvent keyboardSetUnicodeString 分块键入（每事件最多 20 UTF-16 码元）
                              -> post 到 .cgAnnotatedSessionEventTap（绕过 tap 干扰）
                              |
终端 / Claude Code         ->  收到逐字键盘输入（非粘贴）-> 不触发折叠
```

### 适用范围

#### 语音输入法

兼容所有通过「写入剪贴板 + 模拟 Cmd+V」工作的语音输入法（闪电说、讯飞语音等）。

> 通过输入法框架直接输入的方式（如 macOS 系统听写）本身就是逐字输入，不会触发折叠，无需本工具。

#### 终端

预设支持 Ghostty、Otty、Terminal、iTerm2、Alacritty、WezTerm、kitty、Warp，可通过菜单栏界面勾选。

### 安装

#### 方式一：下载预编译版本

从 [Releases](https://github.com/BigKunLun/VoiceInput-Patch/releases) 下载最新的 `VoiceInput.app.zip`，解压后将 `VoiceInput.app` 拖入应用程序文件夹。

#### 方式二：从源码构建

```bash
# 需要 Xcode Command Line Tools
# 如未安装: xcode-select --install

git clone https://github.com/BigKunLun/VoiceInput-Patch.git
cd VoiceInput-Patch
./build.sh

open VoiceInput.app
```

#### 无法打开？

由于应用未经 Apple 公证，macOS 可能阻止打开。任选一种方式解决：

**方式 A：命令行解除隔离（推荐）**

```bash
xattr -cr VoiceInput.app
```

**方式 B：右键打开**

右键点击 `VoiceInput.app` → 选择「打开」→ 在弹窗中点击「打开」

**方式 C：系统设置放行**

打开应用被阻止后，前往 系统设置 → 隐私与安全性 → 下方会显示「已阻止 VoiceInput」→ 点击「仍要打开」

#### 授予辅助功能权限

系统设置 → 隐私与安全性 → 辅助功能 → 添加并勾选 VoiceInput

### 使用

1. 启动后应用显示在菜单栏（波形图标）
2. 点击图标打开菜单，勾选需要监听的终端
3. 点击启动按钮开始拦截
4. 在指定终端中正常使用语音输入即可，非白名单应用中的粘贴不受影响

5. 列表里没有你的终端？点击 **添加应用…** 选择任意 `.app`，会自动读取其 bundleIdentifier，无需改代码重新编译。

### 注意事项

- **换行处理**：菜单栏可选「换行方式」，默认 **Ctrl+J**——发送 LF 而非 Enter 的 CR，多数 TUI 视为换行而非提交。若你的终端仍然把它当提交，无需重启直接换一个：反斜杠 + Enter（shell 续行写法）、Option+Enter（需终端开启 option-as-alt）、Shift+Enter（需终端配过 keybind，如 Claude Code 的 `/terminal-setup`），或「转为空格」——永远安全，代价是丢多行结构。
- **剪贴板写回**：仅「转为空格」模式下，处理后的单行安全版本会写回剪贴板，手动 Cmd+Shift+V 粘贴也不会卡住终端。其余模式不动剪贴板——它们键入的是带换行的原文，写回单行版会把原文的换行结构永久覆盖掉。
- **键入途中切换应用会自动中止**，剩余文本不会打进别的窗口。
- **逃生阀**：Cmd+Shift+V 永远不被拦截，需要终端原生粘贴时用它。
- **开机自启**基于 `SMAppService`，要求应用位于「应用程序」文件夹。
- 超过 10,000 字符的文本会被截断保护。

### 固定签名身份（从源码构建时推荐）

ad-hoc 签名每次构建都生成新的签名身份，macOS 会把它当成另一个应用，已授予的辅助功能权限随之失效。执行一次下面的脚本创建固定的自签名证书：

```bash
./scripts/create-signing-cert.sh
```

之后 `build.sh` 会自动使用该证书签名。

### 环境要求

- macOS 13.0+（Apple Silicon / Intel 均可）
- Xcode Command Line Tools
- 辅助功能权限

---

## 项目结构 / Project Structure

```
VoiceInput-Patch/
├── Package.swift                    # SPM 配置
├── Sources/
│   ├── VoiceInputApp.swift          # SwiftUI 应用入口（MenuBarExtra）
│   ├── Models/
│   │   ├── AppState.swift           # 运行状态、剪贴板写回、开机自启
│   │   └── Settings.swift           # 终端白名单（预设 + 自定义）、UserDefaults 持久化
│   ├── Services/
│   │   ├── InterceptService.swift   # CGEvent Tap 拦截 Cmd+V
│   │   └── TypeService.swift        # CGEvent Unicode 分块键入 + 软换行
│   └── Views/
│       └── MenuBarView.swift        # 菜单栏下拉菜单
├── build.sh                         # 构建脚本（swift build + 打包 .app）
├── scripts/
│   └── create-signing-cert.sh       # 创建固定自签名证书，避免权限反复失效
└── docs/
    └── technical-notes.md           # 技术要点与决策记录
```
