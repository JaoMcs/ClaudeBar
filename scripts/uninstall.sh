#!/bin/bash
# Remove o ClaudeBar: tira só as entradas dele do settings.json (com backup),
# fecha o app e apaga o bundle. Estado e backups ficam em ~/.claude/claudebar.
set -euo pipefail

HOOK="$HOME/.claude/claudebar/bin/claudebar-hook"
[[ -x "$HOOK" ]] || HOOK="$HOME/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook"

"$HOOK" uninstall
pkill -x ClaudeBar || true
rm -rf "$HOME/Applications/ClaudeBar.app"

echo "Removido. Backups do settings.json em ~/.claude/claudebar/backups (apague à mão se quiser)."
