# VoiceInput-Patch 技术要点

## 核心原理

通过 CGEvent Tap 拦截终端中的 Cmd+V，吞掉粘贴事件，改用 CGEvent Unicode 逐字键入，绕过终端的 Bracket Paste Mode 检测。

## 关键技术决策

### 1. CGEvent post 位置：`.cgAnnotatedSessionEventTap`

macOS 事件管道流程：

```
硬件/CGEvent.post(.cghidEventTap)
  -> IOKit HID
  -> WindowServer
  -> cgSessionEventTap         <- CGEvent Tap 注册在这里
  -> cgAnnotatedSessionEventTap
  -> 目标应用
```

如果 post 到 `.cghidEventTap`（管道顶部），事件会经过 CGEvent Tap，导致高频 Mach IPC 往返（~2500 events/sec），事件队列拥塞丢字。

**解决方案**：post 到 `.cgAnnotatedSessionEventTap`（管道下游），跳过 CGEvent Tap，消除干扰。

### 2. 清除修饰键标记 `flags = []`

`CGEventSource(.hidSystemState)` 会继承系统当前的修饰键状态。如果用户按 Cmd+V 时 Cmd 键还没松开，键入事件会带 Cmd 标记，导致触发 Cmd+A 等快捷键。

**解决方案**：显式设置 `keyDown.flags = []` 和 `keyUp.flags = []`。

注意：曾尝试用 `.privateState` 替代 `.hidSystemState`，但 `.privateState` + `.cgAnnotatedSessionEventTap` 组合会丢字。

### 3. 换行替换为空格

语音识别文本可能包含换行符，`\n` 会被当作 Return 键发送，在 Claude Code 中会提前提交消息。

### 4. Bracket Paste Mode 机制

- Claude Code 发送 `\e[?2004h` 启用 bracket paste mode
- 终端收到 Cmd+V 时在粘贴内容前后添加 `\e[200~` / `\e[201~`
- Claude Code 检测到这些序列 -> 判定为粘贴 -> 折叠显示
- 外部无法覆盖 Claude Code 自己启用的 bracket paste

### 5. CGEvent Tap 类型选择

使用 `.defaultTap`（可修改/吞掉事件），而非 `.listenerTap`（只能监听）。这是 WindowServer 事件管道中的同步阻塞节点，仅 `tapEnable(false)` 不够，Mach port 仍注册在 WindowServer 中。

## 曾排除的方案

| 方案 | 排除原因 |
|------|----------|
| 剪贴板轮询 + 清空抢跑 | 时序竞争，轮询抢不赢语音输入法的写入+粘贴 |
| 同进程内 tap + 打字 | CGEvent Tap 干扰打字事件，高频 IPC 丢字 |
| 仅 `tapEnable(false)` 暂停 | Mach port 仍注册，信号方式有时序竞争 |
| RegisterEventHotKey (Carbon) | 备选方案，当前方案稳定后未采用 |
| `.privateState` EventSource | 与 `.cgAnnotatedSessionEventTap` 组合会丢字 |
