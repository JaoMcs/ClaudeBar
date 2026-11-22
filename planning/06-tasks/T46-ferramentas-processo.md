# T46 — Ferramentas do processo (propostas da análise)

- **Funcionalidade:** processo de desenvolvimento — fonte: `planning/10-analise-processo.md`, seção 4
- **Esforço:** 2,5 h
- **Depende de:** — · **Bloqueia:** próximas rodadas do loop
- **Branch:** `chore/ferramentas-processo`
- **PR:** `chore: ferramentas do processo de agentes (lint, ondas, docs-check, corretor só BL)`

## Objetivo

Aplicar as propostas da análise que tiram trabalho mecânico dos agentes, sem mexer no app. Nada em `Sources/`.

## Subtasks

- [ ] `.claude/workflows/impl-loop.js`:
  - corretor só roda com achado `BL` ou CI vermelho; `SG` entra no corpo do retorno (`sg`) e não abre rodada, **exceto** se a task tiver nota ≥ 4 (args `score`);
  - o brief do implementador recebe a branch e o título já resolvidos (args `branch`, `title`), não o texto `<campo Branch da task>`; 2ª tentativa usa `<branch>-r2`;
  - brief do implementador e do corretor com `IGNORE:mensagens fora desta task`;
  - CI esperado uma vez ao fim da implementação (`scripts/dev/ci-wait.sh`) e passado ao revisor como `CI:1|0` para ele não esperar de novo;
  - revisor com modelo `haiku` quando a nota for ≤ 1, senão o modelo da task.
- [ ] `scripts/dev/task-meta.sh <task.md>`: imprime `id branch título nota modelo` (lê `Branch:`/`PR:` do cabeçalho e reaproveita `route.sh`). Sai com 1 se faltar branch ou título.
- [ ] `scripts/dev/task-lint.sh <task.md…>`: confere cabeçalho (Branch, PR, Esforço, Depende de), seções obrigatórias (Objetivo, Subtasks, Arquivos, Critérios de aceite) e que todo caminho da tabela Arquivos existe ou está marcado "novo". Saída `lint=ok` ou a lista.
- [ ] `scripts/dev/overlap.sh <task.md…>`: lê a tabela Arquivos de cada task e imprime os pares que se sobrepõem (ignorando README*.md, `Localizable.strings`, `TODO.md`) e uma sugestão de ondas paralelas (tasks sem sobreposição e sem dependência entre si na mesma onda).
- [ ] `.gitattributes`: `README.md`, `README.pt-BR.md`, `Resources/*/Localizable.strings`, `TODO.md` com `merge=union`.
- [ ] `scripts/dev/rebase-auto.sh <pr>`: `gh pr update-branch --rebase` quando o PR estiver BEHIND; se CONFLICTING, rebase local em origin/main num worktree temporário (union resolve docs), `gates.sh`, `push --force-with-lease`; sai 1 se sobrar conflito em código. O impl-loop chama este script (via agente merger) antes de cair no agente de rebase.
- [ ] `scripts/dev/docs-check.sh`: paridade de seções `##` entre README.md e README.pt-BR.md e as mesmas chaves nas duas `Localizable.strings`; chamado pelo `gates.sh`.
- [ ] `scripts/dev/pr-open.sh --task <task.md> [corpo-extra.md]`: título e "Objetivo"/"Critérios de aceite" vêm da task; o extra traz "Não verificado".
- [ ] `scripts/dev/index-mark.sh <Txx>=<pr>…`: marca `FEITA (#pr)` no INDEX (para um PR de docs por lote).
- [ ] `AGENTS.md` e skill `task-loop`: ondas paralelas com `overlap.sh`, `task-meta.sh` para montar os args, `index-mark.sh` no fim do lote.
- [ ] `bash -n` em tudo; rodar `task-lint.sh` e `overlap.sh` nas T38–T46 e colar a saída no PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `.claude/workflows/impl-loop.js` | regras acima |
| `scripts/dev/task-meta.sh`, `task-lint.sh`, `overlap.sh`, `rebase-auto.sh`, `docs-check.sh`, `index-mark.sh` | novos |
| `scripts/dev/gates.sh`, `scripts/dev/pr-open.sh` | docs-check e `--task` |
| `.gitattributes` | novo |
| `AGENTS.md`, `.claude/skills/task-loop/SKILL.md` | uso |

## Critérios de aceite

- Todos os scripts passam `bash -n`, são bash 3.2 (macOS) e não usam GNU-only (`timeout`, `sed -i` sem `''`, `readlink -f`).
- `overlap.sh` nas T38–T45 aponta os pares que de fato colidiram e propõe ondas.
- `gates.sh` continua `gates=ok` na main.
- O workflow passa `node --check` com o corpo dentro de uma async function e sem o `export` (o runtime exige `export const meta` e `return` de topo); o `gates.sh` faz essa checagem.

## Fora do escopo

Merge direto por shell dentro do workflow (o runtime não roda shell sem agente).
