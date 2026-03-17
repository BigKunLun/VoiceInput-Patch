#!/usr/bin/env python3
"""
voice_type.py — 闪电说 → Claude Code 粘贴拦截器 v3

架构:
  intercept_paste (Swift CGEvent Tap) — 拦截 Cmd+V，吞掉粘贴，通过 stdout 输出内容
  voice_type.py (本脚本) — 读取 stdout，调用 type_unicode 逐字输入
  type_unicode (Swift) — 通过 CGEvent Unicode 模拟键盘输入

两个进程完全隔离，避免 CGEvent Tap 干扰打字事件。

用法:
  python3 voice_type.py --whitelist Ghostty   # 监听模式
  python3 voice_type.py --once                # 单次键入剪贴板内容
"""

import subprocess
import time
import sys
import signal
import argparse
import os
import logging
import base64

# ======================== 配置 ========================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TYPE_TOOL = os.path.join(SCRIPT_DIR, "type_unicode")
INTERCEPT_TOOL = os.path.join(SCRIPT_DIR, "intercept_paste")
LOG_FILE = os.path.join(SCRIPT_DIR, "voice_type.log")

DEFAULT_TERMINALS = {
    "Ghostty", "Terminal", "iTerm2",
    "Alacritty", "WezTerm", "kitty", "Warp",
}

# ======================== 日志 ========================

log = logging.getLogger("voice_type")
log.setLevel(logging.DEBUG)

_fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
_fh.setLevel(logging.DEBUG)
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
log.addHandler(_fh)

_ch = logging.StreamHandler()
_ch.setLevel(logging.INFO)
_ch.setFormatter(logging.Formatter("%(message)s"))
log.addHandler(_ch)

# ======================== 工具编译 ========================


def ensure_swift_tool(name: str):
    tool_path = os.path.join(SCRIPT_DIR, name)
    if os.path.isfile(tool_path) and os.access(tool_path, os.X_OK):
        return

    swift_src = os.path.join(SCRIPT_DIR, f"{name}.swift")
    if not os.path.isfile(swift_src):
        log.error("找不到 %s", swift_src)
        sys.exit(1)

    log.info("🔨 编译 %s ...", name)
    cmd = ["swiftc", "-O", swift_src, "-o", tool_path]
    if name == "intercept_paste":
        cmd += ["-framework", "Cocoa"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        log.error("编译失败:\n%s", r.stderr)
        sys.exit(1)

    os.chmod(tool_path, 0o755)
    log.info("✅ %s 编译完成", name)


# ======================== 打字 ========================


def type_text(text: str):
    """调用 type_unicode 进程逐字输入文本"""
    if not text:
        return
    try:
        p = subprocess.Popen(
            [TYPE_TOOL], stdin=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        _, err = p.communicate(text.encode("utf-8"), timeout=120)
        if p.returncode != 0:
            log.warning("type_unicode 错误: %s", err.decode().strip())
    except subprocess.TimeoutExpired:
        p.kill()
        log.warning("type_unicode 超时")


# ======================== 运行模式 ========================


def run_once():
    ensure_swift_tool("type_unicode")
    try:
        r = subprocess.run(["pbpaste"], capture_output=True, text=True, timeout=1)
        text = r.stdout
    except Exception:
        text = ""

    if not text.strip():
        log.error("剪贴板为空")
        sys.exit(1)

    char_count = len(text)
    preview = text[:80].replace("\n", "↵")
    log.info("⌨️  准备键入: %d 字, 预览: %s...", char_count, preview)
    log.info("   2 秒后开始...")
    time.sleep(2)
    type_text(text)
    log.info("✅ 键入完成")


def run_monitor(terminals: set):
    ensure_swift_tool("type_unicode")
    ensure_swift_tool("intercept_paste")

    cmd = [INTERCEPT_TOOL, "--whitelist"] + list(terminals)
    log.info("启动 CGEvent Tap 拦截器...")

    # 启动拦截器子进程，读取其 stdout
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=1,
    )

    log.info("✅ 监听中，等待闪电说输入...")

    try:
        for line in proc.stdout:
            b64_text = line.decode("utf-8").strip()
            if not b64_text:
                continue

            try:
                text = base64.b64decode(b64_text).decode("utf-8")
            except Exception:
                log.warning("解码失败: %s", b64_text[:50])
                continue

            # 换行替换为空格，避免在 Claude Code 中触发提交
            text = text.replace("\n", " ")
            char_count = len(text)
            preview = text[:60]
            log.info("⌨️  收到文本: %d字 | %s...", char_count, preview)

            # 等待 Cmd 键释放
            time.sleep(0.2)

            # 暂停 CGEvent Tap（SIGUSR1），避免干扰 type_unicode
            os.kill(proc.pid, signal.SIGUSR1)
            time.sleep(0.05)

            # 由本进程（独立于 CGEvent Tap）调用 type_unicode
            type_text(text)

            # 恢复 CGEvent Tap（SIGUSR2）
            os.kill(proc.pid, signal.SIGUSR2)
            log.info("   ✅ 已键入 %d 字符", char_count)

    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()


# ======================== 入口 ========================


def main():
    parser = argparse.ArgumentParser(
        description="闪电说 → Claude Code 拦截器 v3",
    )
    parser.add_argument("--once", action="store_true", help="单次键入剪贴板内容")
    parser.add_argument("--whitelist", nargs="+", metavar="APP", help="指定终端应用名")
    args = parser.parse_args()

    terminals = set(args.whitelist) if args.whitelist else DEFAULT_TERMINALS

    signal.signal(signal.SIGINT, lambda *_: (log.info("👋 已退出"), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    if args.once:
        run_once()
    else:
        run_monitor(terminals)


if __name__ == "__main__":
    main()
