#!/bin/bash
# Metadados de uma task para montar os args do impl-loop.
# Uso: scripts/dev/task-meta.sh <task.md>   Saída (separada por TAB): id branch título nota modelo
# Sai 1 se faltar Branch ou PR (título) no cabeçalho.
set -eu
f=$1
id=$(basename "$f" .md)
b=$(sed -nE 's/^- \*\*Branch:\*\* `([^`]+)`.*/\1/p' "$f" | head -1)
t=$(sed -nE 's/^- \*\*PR:\*\* `([^`]+)`.*/\1/p' "$f" | head -1)
[ -n "$b" ] && [ -n "$t" ] || { echo "$id ERRO falta Branch ou PR no cabeçalho" >&2; exit 1; }
# route.sh: "id nota modelo e=.. f=.. r=.."
r=$("$(dirname "$0")/route.sh" "$f")
set -- $r
printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$b" "$t" "$2" "$3"
