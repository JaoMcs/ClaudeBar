#!/bin/bash
# Entrega ao implementador um mapa curto dos arquivos citados na tabela Arquivos da task.
# Uso: scripts/dev/ctx.sh <task.md>
set -eu

[ $# -eq 1 ] || { echo "uso: ctx.sh <task.md>" >&2; exit 1; }
task="$1"
[ -f "$task" ] || { echo "arquivo não encontrado: $task" >&2; exit 1; }

root=$(git rev-parse --show-toplevel)
regex='^[[:space:]]*(public |private |fileprivate |internal |static |@MainActor )*(func|struct|enum|class|extension|protocol|case|let|var) '

awk '/^## Arquivos/{f=1;next} /^## /{f=0} f && /^\|/ && !/^\| *-/ && !/^\| *Arquivo *\|/' "$task" | while IFS= read -r l; do
  is_new=0
  echo "$l" | grep -qiE '(^|[^a-z])nov[oa]s?([^a-z]|$)' && is_new=1
  for p in $(echo "$l" | cut -d'|' -f2 | grep -oE '`[^`]+`' | tr -d '`'); do
    matches=""
    case "$p" in
      */*)
        matches=$(cd "$root" && ls -d $p 2>/dev/null || true)
        ;;
      *)
        p_esc=$(printf '%s' "$p" | sed 's/[.[\*^$()+?{|]/\\&/g')
        matches=$(git -C "$root" ls-files | grep -E "(^|/)$p_esc\$" || true)
        ;;
    esac
    if [ -z "$matches" ]; then
      [ "$is_new" -eq 1 ] && echo "== $p (novo)"
      continue
    fi
    for rel in $matches; do
      full="$root/$rel"
      [ -f "$full" ] || continue
      n=$(wc -l < "$full" | tr -d ' ')
      echo "== $rel ($n linhas)"
      case "$rel" in
        *.md|*.strings) continue ;;
      esac
      hits=$(grep -nE "$regex" "$full" || true)
      [ -z "$hits" ] && continue
      total=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
      printf '%s\n' "$hits" | head -n 60
      if [ "$total" -gt 60 ]; then
        echo "... (cortado: $total linhas, mostrando 60)"
      fi
    done
  done
done
