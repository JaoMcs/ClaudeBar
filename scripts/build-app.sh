#!/bin/bash
# Compila o pacote e monta build/ClaudeBar.app — um app de barra de menu
# (LSUIElement), assinado ad-hoc para as notificações do sistema funcionarem.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE="build/ClaudeBar.app"
BUNDLE_ID="com.joaomarcos.claudebar"

# Versão visível vem do arquivo VERSION (X.Y.Z, regra da Apple para
# CFBundleShortVersionString). O build é a contagem de commits: sobe a cada
# commit em main; fora de um repositório git cai para 0.
VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION inválida: '$VERSION' (use X.Y.Z, só dígitos e pontos)" >&2
    exit 1
fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

echo "==> Compilando em release ($VERSION, build $BUILD)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Montando $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN_DIR/ClaudeBar" "$BUNDLE/Contents/MacOS/ClaudeBar"
cp "$BIN_DIR/claudebar-hook" "$BUNDLE/Contents/MacOS/claudebar-hook"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt_BR</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeBar</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>ClaudeBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Assinando (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null

echo "==> Pronto: $BUNDLE"
