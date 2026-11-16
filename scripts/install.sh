#!/bin/bash
# Instala o ClaudeBar em ~/Applications e registra os hooks no
# ~/.claude/settings.json pelo próprio claudebar-hook: mostra a prévia, mexe só
# nas entradas do ClaudeBar e guarda backup em ~/.claude/claudebar/backups.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications"
APP="$APP_DIR/ClaudeBar.app"
HOOK="$APP/Contents/MacOS/claudebar-hook"

./scripts/build-app.sh

echo "==> Instalando em $APP"
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R build/ClaudeBar.app "$APP"

echo "==> Prévia das mudanças no ~/.claude/settings.json"
"$HOOK" install --dry-run
read -r -p "Aplicar? [s/N] " resposta || true  # sem TTY (EOF): segue como "não"
if [[ "$resposta" =~ ^[sS]$ ]]; then
  "$HOOK" install
else
  echo "Hooks não registrados. Rode \"$HOOK\" install quando quiser."
fi

echo "==> Abrindo o app"
open "$APP"

echo
echo "Pronto. O ícone está na barra de menu."
echo "O Claude Code recarrega o settings.json sozinho: sessões abertas já usam os hooks."
