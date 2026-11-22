#!/bin/bash
# Paridade de documentação: mesmo número de seções "##" nos dois READMEs e mesmas chaves nas duas Localizable.strings.
# Uso: scripts/dev/docs-check.sh   Saída: "docs=ok" ou a lista de diferenças (exit 1). Chamado pelo gates.sh.
set -eu
cd "$(git rev-parse --show-toplevel)"
ruim=0
en=$(grep -c '^## ' README.md || true); pt=$(grep -c '^## ' README.pt-BR.md || true)
[ "$en" = "$pt" ] || { echo "README.md tem $en seções ## e README.pt-BR.md tem $pt"; ruim=1; }
chaves() { grep -oE '^"([^"\\]|\\.)*"[[:space:]]*=' "$1" | sed -E 's/[[:space:]]*=$//' | sort -u || true; }
a=$(mktemp); b=$(mktemp); trap 'rm -f "$a" "$b"' EXIT
chaves Resources/en.lproj/Localizable.strings >"$a"
chaves Resources/pt-BR.lproj/Localizable.strings >"$b"
# en.lproj vazio de propósito (a chave já é o texto em inglês): aí não há o que comparar.
if [ -s "$a" ]; then
  d=$(comm -3 "$a" "$b")
  [ -z "$d" ] || { echo "chaves diferentes entre en.lproj e pt-BR.lproj:"; echo "$d"; ruim=1; }
fi
[ "$ruim" = 0 ] || exit 1
echo docs=ok
