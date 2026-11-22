#!/bin/bash
# Compila a main e instala o app em ~/Applications para teste do dono: fecha o app aberto,
# manda a versão anterior para o Lixo (recuperável) e abre a nova.
# Uso: scripts/dev/install-local.sh   Saída: nome, versão e build instalados.
set -eu
cd "$(git rev-parse --show-toplevel)"
./scripts/build-app.sh >/dev/null
app=$(ls -d build/*.app | head -1); name=$(basename "$app" .app)
dest="$HOME/Applications/$name.app"
for old in "$HOME/Applications/$name.app" "$HOME/Applications/ClaudeBar.app"; do
  [ -d "$old" ] || continue
  pkill -x "$(basename "$old" .app)" 2>/dev/null || true
  lixo="$HOME/.Trash/$(basename "$old" .app)-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$lixo"; mv "$old" "$lixo/"
done
mkdir -p "$HOME/Applications"; ditto "$app" "$dest"; open "$dest"
v=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$dest/Contents/Info.plist")
n=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$dest/Contents/Info.plist")
echo "instalado=$name versao=$v build=$n"
