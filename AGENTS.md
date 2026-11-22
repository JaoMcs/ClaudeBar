# AGENTS.md — como os agentes trabalham neste repo

Vale para qualquer orquestração (Workflow, Agent, sessão nova). O objetivo é gastar o mínimo de tokens sem perder qualidade.

## Papéis

| Papel | Definição | Modelo | Ferramentas | Recebe |
|---|---|---|---|---|
| Orquestrador | a sessão principal | o da sessão | todas | o plano, o INDEX, os resultados no protocolo `wire` |
| Implementador | `.claude/agents/implementer.md` | pelo roteador (abaixo) | todas, em worktree | só o caminho da task + branch |
| Revisor | `.claude/agents/reviewer.md` | o mesmo da task | só leitura + `gh` | só o número do PR + o caminho da task |
| Corretor | `implementer` com `ROLE:fix` | o mesmo da task | todas, em worktree | PR, branch e os achados no `wire` |
| Merge | `.claude/agents/merger.md` | haiku, effort low | só Bash | PR + id da task |

## Roteamento por complexidade

`scripts/dev/route.sh <task.md>` dá uma nota de 0 a 6:

- **esforço** da task: ≤ 1 h = 0 · ≤ 2 h = 1 · mais = 2
- **arquivos citados** (`.swift`, `.sh`, `.yml`, `.strings`, `.plist`): ≤ 3 = 0 · ≤ 7 = 1 · mais = 2
- **risco** (settings.json, MainActor/concorrência, Process/sysctl/kill, NSPanel/NSWindow, SMAppService, tmux, codesign, statusLine, segurança): nenhum = 0 · 1–2 = 1 · mais = 2
- **−1** se a task não toca `Sources/` (só docs, testes, scripts)

| Nota | Modelo |
|---|---|
| 0–1 | `haiku` |
| 2–3 | `sonnet` |
| 4+ | `opus` |

O orquestrador pode subir um nível (nunca descer) quando a task escreve em arquivo do usuário fora do repo ou quando a tentativa anterior falhou. Se um modelo errar duas vezes na mesma task, a próxima tentativa sobe um nível.

## Contexto mínimo (regra dura)

- Subagente recebe **só a task dele**: caminho do `.md` da task, branch e o que precisa devolver. Nada de plano mestre, histórico da conversa, outras tasks ou resultados de outros agentes.
- Ele lê o que precisa sozinho (task → spec citada → código). Ninguém cola arquivo inteiro no prompt; passa o caminho.
- `planning/` é versionada e existe em todo worktree: use caminho relativo à raiz do repo.
- O revisor não recebe o raciocínio nem o resumo do implementador, só o PR. Revisão independente = contexto independente.

## Revisor: só revisa

Lê a task (objetivo + critérios de aceite), o diff e o código em volta. Posta **uma** revisão em português no PR (`gh pr review <n> --comment`, porque o GitHub não deixa a mesma conta aprovar). Não edita arquivo, não troca branch, não faz commit, não roda build. O CI já roda os testes; ele só lê o resultado com `scripts/dev/ci-wait.sh`.

Severidades: `BL` bloqueante (bug, regressão de garantia, critério de aceite não cumprido, CI vermelho) · `SG` sugestão · `NIT` detalhe.

## Fluxo de uma task

1. `route.sh` → modelo.
2. Implementador: `git fetch -q origin && git switch -c <branch> origin/main` → código + testes → `scripts/dev/gates.sh` → commit → `scripts/dev/pr-open.sh`.
3. Revisor → achados.
4. Corretor só se houver `BL` ou `SG`, ou CI vermelho. Só `NIT` não abre rodada. No máximo 2 rodadas. Depois da correção não há nova revisão: o merge confia no CI verde e no `blno` (quantos BL o corretor recusou).
5. Merge (`scripts/dev/merge.sh <pr> <Txx>`) **só** se: CI verde e nenhum `BL` recusado pelo corretor. `BL` recusado (ex.: precisa de teste manual na tela) = task `AGUARDA-USUARIO`, PR aberto, o lote para.
6. Entre lotes: `scripts/dev/clean.sh`.

Workflow pronto: `.claude/workflows/impl-loop.js`, args `{"root":"<raiz do clone>","tasks":[{"id":"T19-ir-para-sessao","model":"opus"}]}`.

## Protocolo entre agentes: `wire`

Toda mensagem agente↔agente (prompt de subagente, retorno, `SendMessage`) usa a skill `wire`: chave:valor, sem prosa, sem cortesia, caminhos em vez de conteúdo, retorno em JSON mínimo. É lido por máquina, não por gente.

**Exceção:** o que fica no GitHub (commit, título e corpo do PR, comentário de revisão) e o que vai para o usuário continua em português completo e legível. O repo é público.

## Outras economias

- Trabalho mecânico (esperar CI, merge, limpar worktree, gates) é script em `scripts/dev/`, não raciocínio de agente.
- `effort: 'low'` em etapa mecânica. Worktree só para quem escreve.
- Sem `resumo` longo no retorno: o orquestrador lê o PR se precisar.
- Workflow interrompido: retomar com `resumeFromRunId` (o que já terminou volta do cache).
- `CLAUDE.md` é carregado em **todo** subagente: mantê-lo curto. Regra que só um papel usa mora na definição do agente, não no `CLAUDE.md`.

## Regras do projeto que todo agente segue

Sem rede. Não ler conversas do usuário. Estado em `0700`/`0600`, escrita atômica. `Process` com argumentos separados, nunca shell com interpolação. Hook fail-open. **Nunca tocar no `~/.claude` real** em teste ou experimento: use `mktemp -d` e `CFFIXED_USER_HOME`. Não usar `NSApplication.activate(ignoringOtherApps:)`. Swift 6 strict concurrency. Comentários em português. README.md e README.pt-BR.md juntos. Nada de caminho da máquina, e-mail ou dado pessoal em commit, PR ou comentário. Commit: `tipo: descrição` em português + `Co-Authored-By:` com o modelo que de fato rodou.

## Opcionais (ainda não instalados, decisão do dono)

- Plugin oficial `swift-lsp` (`/plugin install swift-lsp@claude-plugins-official`): navegação por símbolo e erro de tipo após cada edição, menos leitura de arquivo.
- Skills do AvdLee: `SwiftUI-Agent-Skill`, `Swift-Concurrency-Agent-Skill`, `Swift-Testing-Agent-Skill` (MIT). Disparar só quando o diff toca UI, concorrência ou testes; não pré-carregar sempre.
- Hook `Stop` com `swift build`/`swift test` só para o implementador. Num hook global ele rodaria a cada parada da sessão principal, então ficou de fora; o `gates.sh` cobre.
- Descartados por custo ou duplicação: BMAD, Spec Kit, Kiro, agent teams (~7x tokens), coleções grandes de agentes.
