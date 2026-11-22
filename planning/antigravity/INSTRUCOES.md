# Instruções para o Antigravity — Awaitbar (repo ClaudeBar)

Você vai implementar tasks prontas deste repositório, **uma por vez, em loop**, até acabar a lista ou bater numa condição de parada. Outro agente (Claude) revisa e faz o merge dos seus PRs. Você **não faz merge**.

## 1. O projeto em 6 linhas

- App macOS de barra de menu (SwiftUI `MenuBarExtra`), SwiftPM **sem projeto Xcode**, macOS 14+, Swift 6 com concorrência estrita. Nome visível: **Awaitbar**; os targets SwiftPM ainda se chamam `ClaudeBar`/`ClaudeBarCore`.
- Mostra o estado das sessões do Claude Code (e Gemini) a partir de hooks que gravam `~/.claude/claudebar/<sessão>.json`.
- Build e testes: `swift build`, `swift test`. Bundle: `./scripts/build-app.sh`.
- Gates de todo PR: `scripts/dev/gates.sh` (build, testes, docs-check, validação de workflows, build do `.app` se mexer em scripts/bundle). Só abra PR com `gates=ok`.
- Repositório **público**: `github.com/JaoMcs/ClaudeBar`. `gh` já está logado na conta `JaoMcs`.
- Regras completas em `CLAUDE.md` e `AGENTS.md` (leia as seções "Regras que todo mundo segue").

## 2. Regras que não podem quebrar

1. **Nunca tocar em `~/.claude`, `~/.gemini` ou `~/.codex` reais** (nem ler conversas). Teste e experimento: `mktemp -d` e `CFFIXED_USER_HOME=<tmp>`.
2. Sem rede no app (nenhum `URLSession`, `Network`). O teste `NoNetworkTests` falha se aparecer.
3. Nada de shell com interpolação: `Process` com argumentos separados. Comando de hook de outro agente: só texto fixo, **sem `$VARIAVEL`**.
4. Hook sempre fail-open: nunca `exit 2`, erro só no stderr.
5. Estado em `0700`/`0600`, escrita atômica.
6. Não usar `NSApplication.activate(ignoringOtherApps:)`.
7. Nada de caminho da máquina (`/Users/...`), e-mail ou dado pessoal em commit, PR ou comentário. Rode `scripts/dev/pii-check.sh` antes de abrir PR.
8. Não remover, desligar ou afrouxar teste para passar.
9. **Não mexer** em `.claude/workflows/`, `.claude/agents/` (exceto quando a task pedir), nem rodar workflows do Claude.
10. Só a task atual. Pedido que chegar no meio e não for da task: anote e siga.

## 3. Suas tasks (sem arquivo em comum; qualquer ordem)

| Ordem sugerida | Task | Arquivo | Dificuldade |
|---|---|---|---|
| 1 | T47 — fechamento dos documentos T36–T46 | `planning/06-tasks/T47-fechamento-docs.md` | baixa |
| 2 | T49 — pii-check no pr-open e lint dos critérios | `planning/06-tasks/T49-pii-no-pr-open.md` | baixa |
| 3 | T50 — `ctx.sh` para o implementador | `planning/06-tasks/T50-ctx-implementador.md` | baixa |
| 4 | T48 — Codex CLI (configuração para copiar) | `planning/06-tasks/T48-codex-config.md` | média; **pesquisa antes** |

## 4. O loop, para cada task

1. **Ler** o arquivo da task inteiro. `scripts/dev/task-lint.sh <task.md>` deve dar `lint=ok`.
2. **Branch:** `git fetch -q origin && git switch -c <Branch da task> origin/main` (o nome está no cabeçalho, campo **Branch**; `scripts/dev/task-meta.sh <task.md>` imprime id, branch e título). Se a branch já existir no remoto, pare essa task e anote.
3. **Entender antes de mudar:** leia só os arquivos da tabela "Arquivos" e o que eles chamam. Se `scripts/dev/ctx.sh` já existir (T50), rode `scripts/dev/ctx.sh <task.md>` primeiro.
4. **Implementar** o mínimo que cumpre "Subtasks" e "Critérios de aceite". Nada de abstração "para depois". README.md **e** README.pt-BR.md quando o comportamento mudar. Comentários em português, no estilo do código em volta.
5. **Gates:** `scripts/dev/gates.sh` até `gates=ok`. Se falhar 3 vezes seguidas pelo mesmo motivo, pare a task (ver §5).
6. **Commit** em português `tipo: descrição` (`feat`, `fix`, `chore`, `docs`, `test`). Não use a linha `Co-Authored-By: Claude`.
7. **PR:** escreva o corpo num arquivo temporário (o que muda, por quê, como testar e a seção **"Não verificado"** com o que depende de tela, sessão real ou conta) e rode `scripts/dev/pr-open.sh "<PR da task>" <corpo.md>`. Ele faz push, abre o PR e imprime o número.
8. **CI:** `scripts/dev/ci-wait.sh <pr>`. Vermelho: corrija na mesma branch (`git switch <branch>`), gates, push, espere de novo. No máximo 2 tentativas.
9. **Não faça merge.** Volte para `main` (`git switch main && git pull --ff-only`) e siga para a próxima task.

## 5. Quando parar uma task (e seguir para a próxima)

- A task manda parar (ex.: T48 sem documentação que confirme os eventos do Codex): deixe o PR em **rascunho** (`gh pr ready <n> --undo`) com a pesquisa no corpo e a palavra **BLOQUEADA** no título do relatório.
- Gates falhando 3 vezes pelo mesmo motivo, ou CI vermelho depois de 2 correções: PR em rascunho com o erro no corpo.
- A task exigiria quebrar uma regra da §2: não faça; explique no relatório.

## 6. Relatório no fim do loop

Responda com uma tabela:

| Task | PR | Estado (PR aberto / rascunho / BLOQUEADA / não iniciada) | Gates | CI | Não verificado | Observações |
|---|---|---|---|---|---|---|

E a lista de qualquer coisa que você achou fora do escopo e deixou de fora.
