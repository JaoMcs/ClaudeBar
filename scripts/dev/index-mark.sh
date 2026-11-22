#!/bin/bash
# Marca tasks como FEITA (#pr) no INDEX (o orquestrador commita num PR de docs por lote).
# Uso: scripts/dev/index-mark.sh T40=51 T41=52 …   Saída: "<Txx> marcada" ou "<Txx> não achada" (exit 1).
set -eu
idx="$(git rev-parse --show-toplevel)/${TASKS_INDEX:-planning/06-tasks/INDEX.md}"
falhou=0
for par in "$@"; do
  t=${par%%=*}; pr=${par#*=}
  if grep -q "^| \[$t\]" "$idx"; then
    # troca a última coluna (Status) da linha da task
    sed -i '' -E "/^\| \[$t\]/ s/\| [^|]*\|[[:space:]]*$/| FEITA (#$pr) |/" "$idx"
    echo "$t marcada"
  else
    echo "$t não achada"; falhou=1
  fi
done
exit $falhou
