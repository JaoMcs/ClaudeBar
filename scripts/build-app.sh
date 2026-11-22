#!/bin/bash
# Compila o pacote e monta build/Awaitbar.app — um app de barra de menu
# (LSUIElement), assinado ad-hoc para as notificações do sistema funcionarem.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE="build/Awaitbar.app"
BUNDLE_ID="io.github.jaomcs.awaitbar"

# Versão visível vem do arquivo VERSION (X.Y.Z, regra da Apple para
# CFBundleShortVersionString). O build é a contagem de commits: sobe a cada
# commit em main; fora de um repositório git cai para 0.
VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION inválida: '$VERSION' (use X.Y.Z, só dígitos e pontos)" >&2
    exit 1
fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

# UNIVERSAL=1 compila arm64 + x86_64 (usado pelo make-dmg.sh). Sem ele, só a
# arquitetura desta máquina, que é mais rápido para o install.sh.
ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compilando em release ($VERSION, build $BUILD)"
# "${ARCH_ARGS[@]+...}": com set -u, array vazio quebra no bash 3.2 do macOS.
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
# Os mesmos --arch aqui, senão o caminho aponta para o binário de uma arquitetura só.
BIN_DIR="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"

echo "==> Montando $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN_DIR/ClaudeBar" "$BUNDLE/Contents/MacOS/Awaitbar"
cp "$BIN_DIR/claudebar-hook" "$BUNDLE/Contents/MacOS/claudebar-hook"
# O sistema lê o ícone daqui (CFBundleIconFile). Copiar antes de assinar:
# arquivo que entra depois do codesign invalida o selo.
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
# Traduções (Bundle.main). Valida antes: .strings quebrado não dá erro em
# runtime, só mostra a chave em inglês. Copiar antes de assinar.
plutil -lint Resources/en.lproj/Localizable.strings Resources/pt-BR.lproj/Localizable.strings
cp -R Resources/en.lproj Resources/pt-BR.lproj "$BUNDLE/Contents/Resources/"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Awaitbar</string>
    <key>CFBundleExecutable</key>
    <string>Awaitbar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Awaitbar</string>
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
# De dentro para fora: o hook é um segundo executável em Contents/MacOS e o
# build universal sai sem assinatura nenhuma; sem isso o `--verify --strict`
# do bundle falha ("code object is not signed at all").
codesign --force --sign - --timestamp=none "$BUNDLE/Contents/MacOS/claudebar-hook" >/dev/null
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null

echo "==> Pronto: $BUNDLE"
