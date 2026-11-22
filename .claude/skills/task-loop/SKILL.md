---
name: task-loop
description: Rodar tasks do ClaudeBar no loop implementar→PR→revisar→corrigir→merge com o modelo certo por complexidade. Usar quando o usuário pedir para executar, retomar ou continuar tasks/lotes.
---
# task-loop

1. Estado: `git status -sb`, `gh pr list --state open`, `git worktree list`. Worktree sobrando → `scripts/dev/clean.sh`.
2. `scripts/dev/task-lint.sh <tasks .md…>` até `lint=ok`.
3. `scripts/dev/overlap.sh <tasks .md…>` → ondas (pares que colidem em código não vão juntos; respeita `Depende de`).
4. `scripts/dev/task-meta.sh <task.md>` por task → `id branch título nota modelo` (TAB) → args.
5. Por onda: rode o Workflow salvo `impl-loop` com `{"root":"<raiz do clone>","tasks":[{"id":"Txx-slug","model":"<modelo>","branch":"<branch>","title":"<título>","score":<nota>}…]}`. Tasks da mesma onda podem ir em workflows paralelos (até 3–4); a próxima onda só depois dos merges.
6. Ao terminar: leia o retorno (status por task, `sg` = sugestões não aplicadas), `scripts/dev/index-mark.sh Txx=<pr>…` num PR de docs, `scripts/dev/clean.sh`, conte os testes, informe o usuário em português: PRs mergeados, o que ficou `AGUARDA-USUARIO` ou `BLOQUEADA` e por quê, sugestões pendentes, o que ficou não verificado.
7. Pausa pedida "no fim do PR atual": espere o merge do PR em curso e pare o workflow (TaskStop) antes da próxima task.

Regras de papel e contexto: `AGENTS.md`. Mensagens entre agentes: skill `wire`.
