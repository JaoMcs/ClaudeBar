#!/bin/bash
# Atualiza um PR atrás da main sem agente.
# BEHIND -> gh pr update-branch --rebase. CONFLICTING -> rebase local num worktree temporário
# (README/strings/TODO resolvem por merge=union do .gitattributes), gates.sh e push --force-with-lease.
# Uso: scripts/dev/rebase-auto.sh <pr>
# Saída: "rebase=ok", "rebase=nada estado=<..>" ou "rebase=CONFLITO <arquivos>" (exit 1; aí sim o agente de rebase).
set -u
pr=$1
for _ in 1 2 3 4 5; do
  st=$(gh pr view "$pr" --json mergeStateStatus,mergeable,headRefName --jq '.mergeStateStatus+" "+.mergeable+" "+.headRefName')
  case "$st" in *UNKNOWN*) sleep 3 ;; *) break ;; esac
done
set -- $st; ms=$1; mg=$2; b=$3
if [ "$mg" != CONFLICTING ] && [ "$ms" != DIRTY ]; then
  [ "$ms" = BEHIND ] || { echo "rebase=nada estado=$ms"; exit 0; }
  gh pr update-branch "$pr" --rebase >/dev/null && { echo rebase=ok; exit 0; }
  echo "rebase=falhou update-branch"; exit 1
fi
root=$(git rev-parse --show-toplevel); cd "$root"
git fetch -q origin main "$b"
w="$(mktemp -d)/rb"
trap 'cd "$root"; git worktree remove --force "$w" >/dev/null 2>&1; git worktree prune; true' EXIT
git worktree add -q --detach "$w" "origin/$b" || { echo "rebase=falhou worktree"; exit 1; }
cd "$w"
if ! git rebase -q origin/main >/dev/null 2>&1; then
  c=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
  git rebase --abort
  echo "rebase=CONFLITO $c"; exit 1
fi
out=$(scripts/dev/gates.sh 2>&1) || { echo "rebase=gates"; echo "$out" | tail -25; exit 1; }
git push -q --force-with-lease="$b:origin/$b" origin "HEAD:$b" || { echo "rebase=falhou push"; exit 1; }
echo rebase=ok
