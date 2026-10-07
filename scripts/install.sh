#!/bin/bash
# Instala o ClaudeBar em ~/Applications e registra os hooks no
# ~/.claude/settings.json (fazendo backup antes e preservando o resto do arquivo).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications"
APP="$APP_DIR/ClaudeBar.app"
HOOK="$APP/Contents/MacOS/claudebar-hook"
SETTINGS="$HOME/.claude/settings.json"

./scripts/build-app.sh

echo "==> Instalando em $APP"
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R build/ClaudeBar.app "$APP"

echo "==> Registrando hooks em $SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

# $PPID é o PID do processo do Claude Code que disparou o hook: o app usa isso
# para descartar sessões que morreram sem avisar.
jq --arg hook "$HOOK" '
  def entry($state): [{ hooks: [{ type: "command", command: ($hook + " " + $state + " --pid $PPID") }] }];
  .hooks = ((.hooks // {}) + {
    UserPromptSubmit: entry("working"),
    Stop: entry("idle"),
    Notification: entry("waiting"),
    SessionEnd: entry("end")
  })
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "==> Abrindo o app"
open "$APP"

echo
echo "Pronto. O ícone está na barra de menu."
echo "Os hooks passam a valer nas *novas* sessões do Claude Code."
