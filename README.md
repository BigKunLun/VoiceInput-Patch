# VoiceInput-Patch — 终端语音输入补丁

## 问题

许多语音输入法（闪电说、讯飞语音等）通过「剪贴板 + Cmd+V」粘贴识别结果。在 Claude Code 等终端应用中，多行粘贴会触发 Bracket Paste Mode 折叠显示，导致语音输入内容无法正常展开。

## 适用范围

### 语音输入法

兼容所有通过「写入剪贴板 + 模拟 Cmd+V」工作的语音输入法（闪电说、讯飞语音等）。

> 通过输入法框架直接输入的方式（如 macOS 系统听写）本身就是逐字输入，不会触发折叠，无需本工具。

### 终端

默认支持 Ghostty、Terminal、iTerm2、Alacritty、WezTerm、kitty、Warp，也可通过 `--whitelist` 指定任意终端应用。

## 解决方案

通过 CGEvent Tap 拦截 Cmd+V，吞掉粘贴事件，改用 CGEvent Unicode 逐字键入，绕过粘贴检测。

```
语音输入法 → 写入剪贴板 + Cmd+V
                                ↓
intercept_paste (Swift)     →  CGEvent Tap 拦截 Cmd+V → 吞掉 → 读剪贴板 → base64 → stdout
                                ↓
voice_type.py (Python)      →  读 stdout → 换行替换空格 → 调用 type_unicode
                                ↓
type_unicode (Swift)        →  CGEvent keyboardSetUnicodeString 逐字输入
                                → post 到 .cgAnnotatedSessionEventTap（绕过 tap 干扰）
                                ↓
终端 / Claude Code          →  收到逐字键盘输入（非粘贴）→ 不触发折叠
```

### 关键技术点

- **CGEvent post 到 `.cgAnnotatedSessionEventTap`**：事件从管道下游注入，跳过 CGEvent Tap，避免高频 IPC 导致丢字
- **`flags = []` 清除修饰键**：防止 Cmd+V 的 Cmd 状态泄露到键入事件
- **换行替换为空格**：避免 Return 键在 Claude Code 中提前提交消息
- **不走输入法**：`keyboardSetUnicodeString` 直接写 Unicode，微信输入法/搜狗/ABC 均兼容

## 安装

```bash
# 需要 Xcode Command Line Tools
# 如未安装: xcode-select --install

# 克隆仓库
git clone https://github.com/5Iris5/VoiceInput-Patch.git
cd VoiceInput-Patch

# 首次运行会自动编译 Swift 工具，无需手动编译
```

### 授予辅助功能权限

系统设置 → 隐私与安全性 → 辅助功能 → 勾选运行脚本的终端应用（Terminal / Ghostty 等）

## 使用

```bash
# 后台监听模式（推荐）- 只在指定终端中拦截
python3 voice_type.py --whitelist Ghostty

# 监听所有终端（默认包含 Ghostty/Terminal/iTerm2/Alacritty/WezTerm/kitty/Warp）
python3 voice_type.py

# 单次模式：把当前剪贴板内容键入到光标处
python3 voice_type.py --once
```

启动后正常使用语音输入即可。非白名单应用中的粘贴不受影响。

## 推荐 alias

```bash
# ~/.zshrc
alias vt='python3 ~/path/to/voice_type.py --once'
alias vtd='python3 ~/path/to/voice_type.py --whitelist Ghostty'
```

## 环境要求

- macOS（Apple Silicon / Intel 均可）
- Python 3
- Xcode Command Line Tools（用于编译 Swift）
- 辅助功能权限
