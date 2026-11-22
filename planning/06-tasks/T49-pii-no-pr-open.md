# T49 — pii-check no pr-open e lint dos critérios de aceite

- **Funcionalidade:** processo — `planning/11-analise-rodadas.md`, "Próximas economias"
- **Esforço:** 1 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `chore/pii-e-lint-criterios`
- **PR:** `chore: pr-open checa dado pessoal e task-lint confere os critérios`

## Objetivo

1. Nenhum PR sai com caminho da máquina ou e-mail: `pr-open.sh` roda `pii-check.sh` antes de criar o PR e para se achar algo.
2. Critério de aceite que cita script do repo precisa apontar para algo que existe (na T46 um critério pedia uma checagem impossível).

## Subtasks

- [ ] `scripts/dev/pr-open.sh`: antes do `gh pr create`, `scripts/dev/pii-check.sh` (sem argumento = diff da branch); se sair 1, imprime o achado e sai 1 sem abrir PR. Variável `PII_SKIP=1` para pular, com aviso no stderr.
- [ ] `scripts/dev/task-lint.sh`: na seção "Critérios de aceite", todo caminho entre crases que comece com `scripts/`, `Sources/`, `Tests/` ou `.claude/` precisa existir (ou a linha dizer "novo"). Erro: `<id>: critério cita <caminho> que não existe`.
- [ ] Rodar `scripts/dev/task-lint.sh planning/06-tasks/T*.md` e colar o resultado no PR (tasks antigas que falharem: só listar, não corrigir).
- [ ] `bash -n` em tudo; bash 3.2 do macOS (sem `timeout`, `readlink -f`, `sed -i` sem `''`).

## Arquivos

| Arquivo | Mudança |
|---|---|
| `scripts/dev/pr-open.sh` | pii-check |
| `scripts/dev/task-lint.sh` | critérios |

## Critérios de aceite

- Um arquivo de teste com um e-mail em maiúsculas (montado no próprio teste, ex. `printf "Foo%sX.COM" @`) numa branch faz `scripts/dev/pr-open.sh` sair 1 sem PR (testar num repo em `mktemp -d`, sem abrir PR real).
- `scripts/dev/task-lint.sh` acusa critério com caminho inexistente.
- `scripts/dev/gates.sh` → `gates=ok`.

## Fora do escopo

Rodar os comandos dos critérios.
