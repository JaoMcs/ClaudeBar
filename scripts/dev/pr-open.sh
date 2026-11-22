#!/bin/bash
# Abre o PR da branch atual com o rodapé do Claude Code. Faz push antes.
# Uso: scripts/dev/pr-open.sh "<título>" <arquivo-do-corpo>   Saída: número do PR.
set -eu
[ $# -eq 2 ] || { echo "uso: pr-open.sh <título> <corpo.md>" >&2; exit 1; }
b=$(git branch --show-current)
git push -q -u origin "$b"
body=$(mktemp); { cat "$2"; printf '\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n'; } >"$body"
gh pr create --base main --head "$b" --title "$1" --body-file "$body" >/dev/null
gh pr view "$b" --json number --jq .number
git switch -q --detach   # libera a branch para outro worktree
