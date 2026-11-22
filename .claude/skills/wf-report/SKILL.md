---
name: wf-report
description: Relatório de tokens por agente e por papel de um ou mais workflows (implementer, rev, fix, merge). Usar em análises de custo do processo ou ao fechar um lote.
---
1. As pastas ficam em `~/.claude/projects/<projeto>/<sessão>/subagents/workflows/wf_*` (o resultado do Workflow mostra o `Transcript dir`).
2. `scripts/dev/wf-report.sh <pasta>...` → tabela por agente e total/média por papel (tokens ponderados: entrada + 1,25×cache escrito + 0,1×cache lido + 5×saída).
3. Compare lotes sempre com o mesmo script. Tokens não são preço: Haiku custa menos por token.
