#!/bin/bash
# Confere o formato das tasks antes de rodar o loop.
# Uso: scripts/dev/task-lint.sh <task.md…>   Saída: "lint=ok" ou uma linha "<id>: <problema>" por erro (exit 1).
# Caminho da tabela Arquivos tem de existir, salvo se a linha disser "novo"/"nova"/"novos".
set -u
root=$(git rev-parse --show-toplevel)
out=$(mktemp); trap 'rm -f "$out"' EXIT
for f in "$@"; do
  id=$(basename "$f" .md | cut -d- -f1)
  for c in Branch PR Esforço 'Depende de'; do
    grep -q "^- \*\*$c:\*\*" "$f" || echo "$id: falta o campo $c" >>"$out"
  done
  for s in Objetivo Subtasks Arquivos 'Critérios de aceite'; do
    grep -q "^## $s" "$f" || echo "$id: falta a seção ## $s" >>"$out"
  done
  # linhas de dados da tabela Arquivos (sem cabeçalho e separador)
  awk '/^## Arquivos/{f=1;next} /^## /{f=0} f && /^\|/ && !/^\| *-/ && !/^\| *Arquivo *\|/' "$f" >"$out.l"
  while IFS= read -r l; do
    echo "$l" | grep -qiE '(^|[^a-z])nov[oa]s?([^a-z]|$)' && continue
    for p in $(echo "$l" | cut -d'|' -f2 | grep -oE '`[^`]+`' | tr -d '`'); do
      case "$p" in
        */*) ( cd "$root" && ls -d $p >/dev/null 2>&1 ) || echo "$id: caminho não existe: $p" >>"$out" ;;
        *) git -C "$root" ls-files | grep -qE "(^|/)$p\$" || echo "$id: arquivo não existe: $p" >>"$out" ;;
      esac
    done
  done <"$out.l"
  rm -f "$out.l"
  # caminhos citados na seção Critérios de aceite
  awk '/^## Critérios de aceite/{f=1;next} /^## /{f=0} f' "$f" >"$out.c"
  while IFS= read -r l; do
    echo "$l" | grep -qiE '(^|[^a-z])nov[oa]s?([^a-z]|$)' && continue
    for p in $(echo "$l" | grep -oE '`[^`]+`' | tr -d '`'); do
      case "$p" in
        scripts/*|Sources/*|Tests/*|.claude/*)
          ( cd "$root" && ls -d $p >/dev/null 2>&1 ) || echo "$id: critério cita $p que não existe" >>"$out"
          ;;
      esac
    done
  done <"$out.c"
  rm -f "$out.c"
done
[ -s "$out" ] && cat "$out" && exit 1
echo lint=ok
