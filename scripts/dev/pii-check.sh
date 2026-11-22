#!/bin/bash
# Procura dado pessoal antes de publicar (repo público): caminho de home, usuário da máquina,
# e-mails do git config e endereços de e-mail em geral (menos noreply).
# Uso: scripts/dev/pii-check.sh [arquivos...]   (sem argumento: o diff da branch contra origin/main)
# Saída: "pii=ok" ou as linhas suspeitas (exit 1).
set -u
cd "$(git rev-parse --show-toplevel)"
if [ $# -eq 0 ]; then set -- $(git diff --name-only --diff-filter=AM origin/main...HEAD); fi
[ $# -eq 0 ] && { echo pii=ok; exit 0; }
pad="$HOME|/Users/$(id -un)|$(id -un)"
for e in $(git config --get-all user.email 2>/dev/null) $(git config --global --get-all user.email 2>/dev/null); do
  case "$e" in *noreply*) ;; *) pad="$pad|$e";; esac
done
hits=$(grep -nIE "$pad|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}" "$@" 2>/dev/null | grep -v 'noreply@' || true)
[ -z "$hits" ] && { echo pii=ok; exit 0; }
echo "pii=SUSPEITO"; echo "$hits" | head -40; exit 1
