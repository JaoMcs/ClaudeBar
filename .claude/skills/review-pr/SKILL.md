---
name: review-pr
description: Revisão independente e barata de um PR do ClaudeBar com o agente reviewer (contexto mínimo, só leitura). Usar quando pedirem para revisar um PR ou revalidar um PR depois de correções.
---
# review-pr

1. `scripts/dev/route.sh <task.md>` para o modelo (sem task: diff < 150 linhas → haiku, senão sonnet; código de segurança/settings.json → opus).
2. Agent `subagent_type: reviewer`, `model: <modelo>`, prompt no `wire`:
   `ROLE:rev PR:<n> SRC:<caminho absoluto da task ou "-"> RET:{"ci":1,"a":[{"s","f","d"}]}`
3. Não passe resumo do implementador nem sua opinião: revisão independente.
4. Relate ao usuário em português: CI, achados por severidade, link do PR.
