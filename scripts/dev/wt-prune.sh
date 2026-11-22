#!/bin/bash
# Apaga os worktrees de agentes que já terminaram: os de .claude/worktrees sem lock.
# Worktree com lock = agente ainda trabalhando nele; fica. Worktree sujo (mudança não
# commitada) também fica e é avisado no stderr: nada é apagado à força.
# Roda sozinho no fim do merge.sh. Uso: scripts/dev/wt-prune.sh
# Saída: "wt-prune removidos=<n> ativos=<n> sujos=<n>".
set -u
cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." || exit 1
rm=0; ativos=0; sujos=0
while IFS=$'\t' read -r locked w; do
  if [ "$locked" = 1 ]; then ativos=$((ativos+1)); continue; fi
  if git worktree remove "$w"; then rm=$((rm+1)); else sujos=$((sujos+1)); echo "wt-prune: mantido (sujo): $w" >&2; fi
done < <(git worktree list --porcelain | awk '/^worktree /{w=substr($0,10);l=0} /^locked/{l=1} /^$/{if (w ~ /\/\.claude\/worktrees\//) print l "\t" w}')
git worktree prune
echo "wt-prune removidos=$rm ativos=$ativos sujos=$sujos"
