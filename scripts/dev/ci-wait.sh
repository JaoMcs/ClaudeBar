#!/bin/bash
# Espera os checks do PR aparecerem e terminarem. Saída: "ci=verde" (exit 0) ou "ci=vermelho" + log da falha (exit 1).
# Uso: scripts/dev/ci-wait.sh <pr>
set -u
pr=$1
# até 5 min para os checks aparecerem
for _ in $(seq 1 30); do gh pr checks "$pr" 2>&1 | grep -q 'no checks reported' || break; sleep 10; done
if gh pr checks "$pr" --watch --interval 20 >/dev/null 2>&1; then echo ci=verde; exit 0; fi
echo ci=vermelho
run=$(gh pr checks "$pr" --json link --jq '.[0].link' | grep -oE 'runs/[0-9]+' | cut -d/ -f2)
[ -n "$run" ] && gh run view "$run" --log-failed 2>/dev/null | tail -40
exit 1
