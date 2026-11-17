#!/bin/bash
# Gera dist/ClaudeBar-<versão>.dmg (arm64 + x86_64) e o .sha256 ao lado.
# Assinatura ad-hoc: o DMG não passa no Gatekeeper sem o "Abrir Mesmo Assim".
# Não assina o DMG, não notariza, não publica nada — sem rede.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/ClaudeBar.app"

UNIVERSAL=1 ./scripts/build-app.sh

echo "==> Conferindo arquiteturas e assinatura"
for binary in ClaudeBar claudebar-hook; do
    archs="$(lipo -archs "$APP/Contents/MacOS/$binary")"
    if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
        echo "$binary não é universal: $archs" >&2
        exit 1
    fi
done
codesign --verify --strict "$APP"

# build-app.sh já validou o formato.
VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="ClaudeBar-$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ClaudeBar.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Gerando dist/$NAME.dmg"
mkdir -p dist
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg" >/dev/null
hdiutil verify "dist/$NAME.dmg" >/dev/null

# De dentro de dist/, para `shasum -c` funcionar sem caminho absoluto.
(cd dist && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")

echo "==> Pronto:"
cat "dist/$NAME.dmg.sha256"
