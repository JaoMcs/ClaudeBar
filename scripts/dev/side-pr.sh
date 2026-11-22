#!/bin/bash
# Abre um PR a partir de arquivos já editados no checkout principal, SEM trocar a branch dele
# (útil quando agentes estão usando o checkout para merge). Cria um worktree temporário de
# origin/main, copia os arquivos, roda pii-check, commita, abre o PR e apaga o worktree.
# Uso: scripts/dev/side-pr.sh <branch> "<título>" <corpo.md> <arquivo>...   Saída: número do PR.
set -eu
[ $# -ge 4 ] || { echo "uso: side-pr.sh <branch> <título> <corpo.md> <arquivos...>" >&2; exit 1; }
b=$1; t=$2; body=$3; shift 3
root=$(git rev-parse --show-toplevel); cd "$root"
git fetch -q origin
w=$(mktemp -d)/wt
git worktree add -q -b "$b" "$w" origin/main
for f in "$@"; do mkdir -p "$w/$(dirname "$f")"; cp -R "$f" "$w/$f"; done
cd "$w"
scripts/dev/pii-check.sh "$@" >&2 || { echo "side-pr: dado pessoal suspeito, nada enviado" >&2; exit 1; }
git add -- "$@"
git commit -q -m "$t

Co-Authored-By: ${CLAUDE_MODEL_NAME:-Claude Opus 5.5} <noreply@anthropic.com>"
n=$("$root/scripts/dev/pr-open.sh" "$t" "$body" | tail -1)
cd "$root"; git worktree remove --force "$w"
echo "$n"
