#!/bin/bash
# Apaga os worktrees de agentes que já terminaram: os de .claude/worktrees sem lock.
# Worktree com lock = agente ainda trabalhando nele; fica. Roda sozinho no fim do merge.sh.
# Uso: scripts/dev/wt-prune.sh   Saída: "wt-prune removidos=<n> ativos=<n>".
set -u
cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." || exit 1
rm=0; ativos=0
while read -r w locked; do
  if [ "$locked" = 1 ]; then ativos=$((ativos+1)); continue; fi
  git worktree remove --force "$w" 2>/dev/null && rm=$((rm+1))
done < <(git worktree list --porcelain | awk '/^worktree/{w=$2;l=0} /^locked/{l=1} /^$/{if (w ~ /\/\.claude\/worktrees\//) print w, l}')
git worktree prune
echo "wt-prune removidos=$rm ativos=$ativos"
