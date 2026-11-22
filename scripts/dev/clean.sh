#!/bin/bash
# Entre lotes: remove worktrees de agentes, poda, atualiza a main local e roda os testes.
# Uso: scripts/dev/clean.sh   Saída: worktrees restantes, sha da main e total de testes.
set -eu
cd "$(git rev-parse --path-format=absolute --git-common-dir)/.."
git worktree list --porcelain | awk '/^worktree .*\/\.claude\/worktrees\//{print $2}' | while read -r w; do
  git worktree unlock "$w" 2>/dev/null || true
  git worktree remove --force "$w"
done
git worktree prune
[ "$(git branch --show-current)" = main ] && git pull -q --ff-only
git worktree list
git log --oneline -1
swift test 2>&1 | grep -o 'Test run with [0-9]* tests.*' | tail -1
