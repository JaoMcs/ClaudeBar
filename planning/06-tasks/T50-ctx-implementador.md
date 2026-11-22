# T50 — Contexto enxuto para o implementador (ctx.sh)

- **Funcionalidade:** processo — o implementador é ~73% do custo (`planning/11-analise-rodadas.md`)
- **Esforço:** 1,5 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `chore/ctx-implementador`
- **PR:** `chore: ctx.sh entrega ao implementador o mapa dos arquivos da task`

## Objetivo

Antes de ler arquivos inteiros, o implementador recebe um mapa curto do que a task toca: para cada arquivo da tabela "Arquivos", as declarações de topo com número de linha. Menos leitura, menos tokens.

## Subtasks

- [ ] `scripts/dev/ctx.sh <task.md>`: para cada caminho da tabela "Arquivos" que existe, imprime `== <caminho> (<n> linhas)` e as linhas que casam `^\s*(public |private |fileprivate |internal |static |@MainActor )*(func|struct|enum|class|extension|protocol|case|let|var) ` com número de linha (máximo 60 por arquivo; avisa se cortou). Caminhos marcados "novo" saem como `== <caminho> (novo)`. Arquivos `.md`/`.strings`: só o número de linhas.
- [ ] `.claude/agents/implementer.md`: passo 2 passa a ser "rode `scripts/dev/ctx.sh <SRC>` e leia só os trechos que vai mudar (Read com offset/limit)".
- [ ] `AGENTS.md`: uma linha em "Outras economias" sobre o `ctx.sh`.
- [ ] Rodar `scripts/dev/ctx.sh planning/06-tasks/T45-rotulo-desktop-terminal.md` e colar a saída no PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `scripts/dev/ctx.sh` | novo |
| `.claude/agents/implementer.md` | passo 2 |
| `AGENTS.md` | uma linha |

## Critérios de aceite

- `bash -n scripts/dev/ctx.sh`; bash 3.2 do macOS.
- Saída da T45 com menos de 150 linhas.
- `scripts/dev/gates.sh` → `gates=ok`.

## Fora do escopo

Mudar o `.claude/workflows/impl-loop.js` (o Claude integra depois).
