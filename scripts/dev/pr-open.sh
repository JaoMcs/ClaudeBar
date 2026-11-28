#!/bin/bash
# Abre o PR da branch atual com o rodapé do Claude Code. Faz push antes.
# Uso: scripts/dev/pr-open.sh "<título>" <arquivo-do-corpo>
#      scripts/dev/pr-open.sh --task <task.md> [corpo-extra.md]
#        título = campo PR da task; corpo = Objetivo + Critérios de aceite da task + o extra ("Não verificado").
# Saída: número do PR.
set -eu
body=$(mktemp)
if [ "${1:-}" = --task ]; then
  [ $# -ge 2 ] || { echo "uso: pr-open.sh --task <task.md> [extra.md]" >&2; exit 1; }
  t=$(sed -nE 's/^- \*\*PR:\*\* `([^`]+)`.*/\1/p' "$2" | head -1)
  [ -n "$t" ] || { echo "task sem campo PR" >&2; exit 1; }
  # seções copiadas da task, com o título rebaixado para ###
  for s in Objetivo 'Critérios de aceite'; do
    awk -v s="## $s" 'index($0, s)==1 {f=1; print "#" $0; next} /^## /{f=0} f' "$2"
  done >"$body"
  [ $# -ge 3 ] && { echo; cat "$3"; } >>"$body"
  set -- "$t" "$body"
else
  [ $# -eq 2 ] || { echo "uso: pr-open.sh <título> <corpo.md>" >&2; exit 1; }
  cat "$2" >"$body"
fi
printf '\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' >>"$body"
if [ "${PII_SKIP:-0}" = 1 ]; then
  echo "aviso: pii-check pulado (PII_SKIP=1)" >&2
else
  # arquivos da branch e o corpo do PR
  pii_out=$("$(dirname "$0")/pii-check.sh") || { echo "$pii_out"; rm -f "$body"; exit 1; }
  pii_out=$("$(dirname "$0")/pii-check.sh" "$body") || { echo "$pii_out"; rm -f "$body"; exit 1; }
fi
b=$(git branch --show-current)
git push -q -u origin "$b"
gh pr create --base main --head "$b" --title "$1" --body-file "$body" >/dev/null
gh pr view "$b" --json number --jq .number
git switch -q --detach   # libera a branch para outro worktree
