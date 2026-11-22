#!/bin/bash
# Calcula a complexidade de uma task (.md) e sugere o modelo.
# Uso: scripts/dev/route.sh <task.md> [...]   Saída por task: id score modelo e=<h> f=<arq> r=<risco>
# Pontos: esforço (0-2) + arquivos citados (0-2) + risco (0-2) - 1 se não toca Sources/.
# 0-1 haiku · 2-3 sonnet · >=4 opus. ponytail: heurística por texto; recalibrar se errar de modelo.
set -eu
RISCO='settings\.json|MainActor|concorr|sysctl|Process\(|NSPanel|NSWindow|SMAppService|tmux|codesign|notariz|statusLine|kill|SIGTERM|DispatchSource|segurança'
for f in "$@"; do
  e=$(grep -o 'Esforço:\*\* [0-9,]*' "$f" | grep -o '[0-9,]*$' | tr ',' '.' || true)
  e=${e:-1}
  pe=$(awk -v e="$e" 'BEGIN{print (e<=1)?0:(e<=2)?1:2}')
  nf=$(grep -oE '[A-Za-z0-9_.-]+\.(swift|sh|yml|strings|plist)' "$f" | sort -u | wc -l | tr -d ' ')
  pf=$(( nf<=3 ? 0 : (nf<=7 ? 1 : 2) ))
  nr=$(grep -oiE "$RISCO" "$f" | sort -u | wc -l | tr -d ' ')
  pr=$(( nr==0 ? 0 : (nr<=2 ? 1 : 2) ))
  ps=0; grep -q 'Sources/' "$f" || ps=1
  s=$(( pe + pf + pr - ps )); if (( s < 0 )); then s=0; fi
  m=haiku; if (( s >= 4 )); then m=opus; elif (( s >= 2 )); then m=sonnet; fi
  echo "$(basename "$f" .md) $s $m e=$e f=$nf r=$nr"
done
