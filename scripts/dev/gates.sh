#!/bin/bash
# Gates de todo PR. Roda swift build + test; bash -n e build-app.sh só se a branch mexe em scripts/, Resources/ ou no bundle.
# Uso: scripts/dev/gates.sh   (na raiz do worktree). Saída: "gates=ok" ou a primeira falha (últimas linhas).
set -eu
cd "$(git rev-parse --show-toplevel)"
falha() { echo "gates=FALHOU etapa=$1"; tail -25 "$2"; exit 1; }
log=$(mktemp)
swift build >"$log" 2>&1 || falha build "$log"
grep -q 'warning:' "$log" && echo "aviso: swift build tem warning" && grep 'warning:' "$log" | head -5
swift test >"$log" 2>&1 || falha test "$log"
echo "$(grep -o 'Test run with [0-9]* tests' "$log" | tail -1)"
"$(dirname "$0")/docs-check.sh" >"$log" 2>&1 || falha docs "$log"
if git diff --name-only origin/main...HEAD | grep -qE '^(scripts/|Resources/|Info\.plist)'; then
  for s in scripts/*.sh scripts/dev/*.sh; do bash -n "$s" || falha "bash-n $s" /dev/null; done
  ./scripts/build-app.sh >"$log" 2>&1 || falha build-app "$log"
fi
echo gates=ok
