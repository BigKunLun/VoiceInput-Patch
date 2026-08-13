#!/bin/bash
# 创建本地自签名代码签名证书 "VoiceInput Dev"
#
# 为什么需要：ad-hoc 签名（codesign -s -）每次构建都会产生新的签名身份，
# macOS 会认为这是另一个应用，已授予的「辅助功能」权限随之失效。
# 用固定的自签名证书签名后，签名身份稳定，权限只需授予一次。
#
# 运行过程中会弹出钥匙串授权对话框，输入登录密码即可。

set -e

CERT_NAME="VoiceInput Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# p12 传输口令，仅用于本地导入这一步，导入后即失效
P12_PASS="voiceinput"

# 固定用系统自带的 LibreSSL：Homebrew OpenSSL 3.x 导出的 PKCS#12
# 默认使用 AES-256-CBC + PBKDF2，macOS Security framework 无法解析，
# 导入时会报 "MAC verification failed"
OPENSSL="/usr/bin/openssl"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✅ 证书 \"$CERT_NAME\" 已存在，无需重复创建"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 用配置文件声明扩展，避免依赖 -addext（LibreSSL 与 OpenSSL 行为不一致）
cat > "$TMP_DIR/openssl.cnf" << EOF
[req]
distinguished_name = dn
x509_extensions = v3_codesign
prompt = no

[dn]
CN = $CERT_NAME

[v3_codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "🔑 生成自签名证书..."
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP_DIR/key.pem" \
    -out "$TMP_DIR/cert.pem" \
    -config "$TMP_DIR/openssl.cnf" \
    -extensions v3_codesign 2>/dev/null

"$OPENSSL" pkcs12 -export \
    -inkey "$TMP_DIR/key.pem" \
    -in "$TMP_DIR/cert.pem" \
    -out "$TMP_DIR/cert.p12" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS"

echo "📥 导入钥匙串..."
security import "$TMP_DIR/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "🔒 设置为受信任的代码签名证书（会弹窗要求输入登录密码）..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"

echo ""
echo "✅ 完成。现在运行 ./build.sh 会自动使用该证书签名。"
echo "   首次签名若弹出「codesign 想使用密钥」，请点「始终允许」。"
