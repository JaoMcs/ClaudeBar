---
name: task-loop
description: Rodar tasks do ClaudeBar no loop implementar→PR→revisar→corrigir→merge com o modelo certo por complexidade. Usar quando o usuário pedir para executar, retomar ou continuar tasks/lotes.
---
# task-loop

1. Estado: `git status -sb`, `gh pr list --state open`, `git worktree list`. Worktree sobrando → `scripts/dev/clean.sh`.
2. Modelos: `scripts/dev/route.sh <tasks .md…>` → `id nota modelo`. Respeite dependências do INDEX (ordem sequencial; tasks que tocam os mesmos arquivos nunca em paralelo).
3. Rode o Workflow salvo `impl-loop` com args `{"root":"<raiz do clone>","tasks":[{"id":"Txx-slug","model":"<modelo>"}…]}` (ids = nome do arquivo sem `.md`). Lotes de até ~8 tasks.
4. Ao terminar: leia o retorno (status por task), `scripts/dev/clean.sh`, conte os testes, informe o usuário em português: PRs mergeados, o que ficou `AGUARDA-USUARIO` ou `BLOQUEADA` e por quê, o que ficou não verificado.
5. Pausa pedida "no fim do PR atual": espere o merge do PR em curso e pare o workflow (TaskStop) antes da próxima task.

Regras de papel e contexto: `AGENTS.md`. Mensagens entre agentes: skill `wire`.
