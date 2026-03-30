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

RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 复制可执行文件
cp .build/release/VoiceInput "${MACOS_DIR}/${APP_NAME}"

# 复制应用图标
cp Assets/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

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
    <string>1.2.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 BigKunLun. All rights reserved.</string>
</dict>
</plist>
EOF

chmod +x "${MACOS_DIR}/${APP_NAME}"

# 代码签名：优先使用本地自签名证书（身份固定，辅助功能权限不会失效），
# 找不到则 fallback 到 ad-hoc 签名（适用于 CI / 其他人的机器）
echo "🔏 签名应用..."
if security find-identity -v -p codesigning 2>/dev/null | grep -q "VoiceInput Dev"; then
    codesign --force --deep --sign "VoiceInput Dev" "${APP_DIR}"
    echo "   使用证书: VoiceInput Dev"
else
    codesign --force --deep --sign - "${APP_DIR}"
    echo "   使用 ad-hoc 签名（未找到 VoiceInput Dev 证书）"
fi

echo "✅ 构建完成: ${APP_DIR}"
