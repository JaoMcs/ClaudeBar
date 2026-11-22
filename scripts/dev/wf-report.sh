#!/bin/bash
# Tokens e tempo por agente de um ou mais workflows (lê os registros locais do Claude Code).
# Uso: scripts/dev/wf-report.sh <pasta-do-workflow>...   (as pastas wf_* de subagents/workflows/)
# Saída: uma linha por agente (rótulo, modelo, entrada, cache lido, saída, ponderado) e total por papel.
# Ponderado = entrada + 1,25×cache escrito + 0,1×cache lido + 5×saída (mesma régua de planning/10-analise-processo.md).
set -eu
[ $# -ge 1 ] || { echo "uso: wf-report.sh <pasta wf_*>..." >&2; exit 1; }
python3 - "$@" <<'PY'
import json, sys, glob, os, collections
papel = collections.defaultdict(lambda: [0, 0])
print(f"{'agente':28} {'modelo':7} {'entrada':>9} {'cache':>10} {'saida':>8} {'ponderado':>10}")
for d in sys.argv[1:]:
    for meta in sorted(glob.glob(os.path.join(d, 'agent-*.meta.json'))):
        m = json.load(open(meta)); lab = m.get('description', '?'); mod = m.get('model', '?')
        i = cw = cr = o = 0
        for line in open(meta.replace('.meta.json', '.jsonl')):
            try: u = json.loads(line).get('message', {}).get('usage')
            except Exception: continue
            if not u: continue
            i += u.get('input_tokens', 0); cw += u.get('cache_creation_input_tokens', 0)
            cr += u.get('cache_read_input_tokens', 0); o += u.get('output_tokens', 0)
        w = i + 1.25 * cw + 0.1 * cr + 5 * o
        papel[lab.split(':')[0]][0] += w; papel[lab.split(':')[0]][1] += 1
        print(f"{lab[:28]:28} {mod[:7]:7} {i+cw:9} {cr:10} {o:8} {int(w):10}")
print('\npapel        agentes   ponderado   média')
for k, (w, n) in sorted(papel.items(), key=lambda x: -x[1][0]):
    print(f"{k:12} {n:7} {int(w):11} {int(w/n):7}")
PY
