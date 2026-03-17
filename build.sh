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

# 代码签名（ad-hoc签名，保持应用身份稳定，避免每次重新授权辅助功能权限）
echo "🔏 签名应用..."
codesign --force --deep --sign "VoiceInput Dev" "${APP_DIR}"

echo "✅ 构建完成: ${APP_DIR}"
