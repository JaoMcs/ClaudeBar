#!/bin/bash
# Pares de tasks que citam o mesmo arquivo na tabela Arquivos e ondas que podem rodar em paralelo.
# Uso: scripts/dev/overlap.sh <task.md…>
# Saída: "par Txx Tyy: arq…" por colisão e "ondaN: Txx Tyy" (gulosa, na ordem dada; respeita "Depende de").
# Ignora README*.md, Localizable.strings, TODO.md e INDEX.md (merge=union + docs-check).
# ponytail: compara por nome de arquivo (basename) citado na task, não pelo diff real; arquivo tocado fora da tabela escapa.
set -eu
for f in "$@"; do
  id=$(basename "$f" .md | cut -d- -f1)
  echo "T $id"
  awk '/^## Arquivos/{f=1;next} /^## /{f=0} f && /^\|/' "$f" | cut -d'|' -f2 | grep -oE '`[^`]+`' | tr -d '`' \
    | sed 's#.*/##' | grep -vE '^(README.*\.md|Localizable\.strings|TODO\.md|INDEX\.md)$' | sort -u | sed "s/^/F $id /" || true
  sed -nE 's/^- \*\*Depende de:\*\* ([^·]*).*/\1/p' "$f" | grep -oE 'T[0-9]+' | sed "s/^/D $id /" || true
done | awk '
  $1=="T" { ord[++n]=$2; next }
  $1=="F" { quem[$3]=quem[$3] " " $2; next }
  $1=="D" { dep[$2]=dep[$2] " " $3 }
  END {
    for (a in quem) { k=split(quem[a], v, " ")
      for (i=1;i<=k;i++) for (j=i+1;j<=k;j++) {
        x=(v[i]<v[j])?v[i]:v[j]; y=(v[i]<v[j])?v[j]:v[i]; par[x" "y]=par[x" "y] " " a } }
    m=0; for (p in par) { print "par " p ":" par[p] | "sort"; m++ }
    close("sort")
    if (m==0) print "pares: nenhum"
    for (i=1;i<=n;i++) { t=ord[i]; min=1
      k=split(dep[t], d, " ")
      for (j=1;j<=k;j++) if ((d[j] in onda) && onda[d[j]]>=min) min=onda[d[j]]+1
      for (w=min;;w++) { ok=1
        for (j=1;j<i;j++) { u=ord[j]; if (onda[u]!=w) continue
          x=(t<u)?t:u; y=(t<u)?u:t; if ((x" "y) in par) { ok=0; break } }
        if (ok) break }
      onda[t]=w; lista[w]=lista[w] " " t; if (w>maxw) maxw=w }
    for (w=1;w<=maxw;w++) print "onda" w ":" lista[w]
  }'
