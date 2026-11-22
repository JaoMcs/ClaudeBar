#!/bin/bash
# Merge seguro: CI verde + OPEN/MERGEABLE -> squash, apaga a branch e marca a task no INDEX (se existir).
# Uso: scripts/dev/merge.sh <pr> [Txx]   Saída: "merged=<sha>" ou "merged=nao motivo=<...>" (exit 1).
# Não mexe no checkout local.
set -u
pr=$1; task=${2:-}
d=$(dirname "$0")
"$d/ci-wait.sh" "$pr" >/dev/null || { echo "merged=nao motivo=ci"; exit 1; }
# mergeable fica UNKNOWN alguns segundos depois do CI
for _ in 1 2 3 4 5; do st=$(gh pr view "$pr" --json state,mergeable --jq '.state+" "+.mergeable'); [ "${st#* }" != UNKNOWN ] && break; sleep 3; done
[ "$st" = "OPEN MERGEABLE" ] || { echo "merged=nao motivo=$st"; exit 1; }
# --delete-branch pode falhar só na parte local (branch presa em worktree) com o PR já mergeado
gh pr merge "$pr" --squash --delete-branch >/dev/null 2>&1 || [ "$(gh pr view "$pr" --json state --jq .state)" = MERGED ] || { echo "merged=nao motivo=gh"; exit 1; }
sha=$(gh pr view "$pr" --json mergeCommit --jq .mergeCommit.oid)
idx="$(git rev-parse --path-format=absolute --git-common-dir)/../${TASKS_INDEX:-planning/06-tasks/INDEX.md}"
# INDEX versionado: não editar aqui (deixaria a main local suja); o orquestrador atualiza num PR de docs.
if [ -n "$task" ] && [ -f "$idx" ] && ! git ls-files --error-unmatch "$idx" >/dev/null 2>&1; then
  # troca a última coluna (Status) da linha da task por FEITA (#pr)
  sed -i '' -E "/^\| \[$task\]/ s/\| [^|]*\|[[:space:]]*$/| FEITA (#$pr) |/" "$idx"
fi
echo "merged=${sha:0:7}"
