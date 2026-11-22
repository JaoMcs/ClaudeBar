#!/bin/bash
# Instala o Awaitbar em ~/Applications e registra os hooks no
# ~/.claude/settings.json pelo próprio claudebar-hook: mostra a prévia, mexe só
# nas entradas do Awaitbar e guarda backup em ~/.claude/claudebar/backups.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications"
APP="$APP_DIR/Awaitbar.app"
OLD_APP="$APP_DIR/ClaudeBar.app"
HOOK="$APP/Contents/MacOS/claudebar-hook"

./scripts/build-app.sh

echo "==> Instalando em $APP"
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R build/Awaitbar.app "$APP"

echo "==> Prévia das mudanças no ~/.claude/settings.json"
"$HOOK" install --dry-run
read -r -p "Aplicar? [s/N] " resposta || true  # sem TTY (EOF): segue como "não"
if [[ "$resposta" =~ ^[sS]$ ]]; then
  "$HOOK" install
else
  echo "Hooks não registrados. Rode \"$HOOK\" install quando quiser."
fi

# Migra do nome antigo: o install novo reaponta os hooks que estavam dentro do
# app velho; só depois o app velho some.
if [[ -d "$OLD_APP" ]]; then
  echo "==> Migrando do ClaudeBar"
  if [[ "${resposta:-}" =~ ^[sS]$ ]]; then
    pkill -x ClaudeBar || true
    rm -rf "$OLD_APP"
  else
    echo "$OLD_APP mantido: hooks antigos ainda podem apontar para ele. Aplique o install e apague-o."
  fi
fi

echo "==> Abrindo o app"
open "$APP"

echo
echo "Pronto. O ícone está na barra de menu."
echo "O Claude Code recarrega o settings.json sozinho: sessões abertas já usam os hooks."
