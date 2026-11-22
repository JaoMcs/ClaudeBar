# ClaudeBar

App macOS de barra de menu (SwiftUI `MenuBarExtra`), SwiftPM sem Xcode project, macOS 14+, Swift 6. Build e testes: `swift build`, `swift test`; bundle: `scripts/build-app.sh`. Gates de PR: `scripts/dev/gates.sh`.

## Se você é um subagente
- Trabalhe **só na sua task**: o brief traz o caminho dela. Não leia `planning/` além da task e da spec que ela cita, nem tente reconstruir o plano geral.
- Fale com outros agentes e devolva resultado no protocolo `wire` (skill `wire`): curto, sem prosa.
- Seu papel e seus passos estão na sua definição em `.claude/agents/`.

## Orquestração
Papéis, roteamento de modelo por complexidade (`scripts/dev/route.sh`), contexto mínimo e regras do revisor: `AGENTS.md`. Executar tasks: skill `task-loop`. Revisar PR: skill `review-pr`.

## Scripts sem IA (`scripts/dev/`)
Trabalho mecânico é script, não raciocínio: `route.sh` (modelo), `gates.sh` (build/testes), `pr-open.sh`, `ci-wait.sh`, `merge.sh`, `clean.sh`, `wt-prune.sh`, `pii-check.sh` (dado pessoal antes de publicar), `side-pr.sh` (PR sem trocar a branch do checkout), `install-local.sh` (build para o dono testar), `wf-report.sh` (tokens por papel). Prefira o script a refazer os passos à mão.

## Worktrees
- Worktree de agente (`.claude/worktrees/`) é apagado assim que a task termina: o `merge.sh` chama `scripts/dev/wt-prune.sh` depois de cada merge, e o orquestrador roda o mesmo script quando um workflow acaba. Só ficam os com lock (agente ainda trabalhando).
- Nunca deixe worktree próprio para trás: ao terminar, `git switch --detach` e saia; quem apaga é o prune.

## Regras que todo mundo segue
- **Nunca tocar no `~/.claude` real** (settings.json, claudebar/) em teste ou experimento: `mktemp -d` + `CFFIXED_USER_HOME`.
- Sem rede no app. Não ler conversas do usuário. Estado `0700`/`0600`. `Process` com argumentos separados, nunca shell com interpolação. Hook fail-open.
- Não usar `NSApplication.activate(ignoringOtherApps:)` (ver `TODO.md`).
- Repo público: nada de caminho da máquina, e-mail ou dado pessoal em commit, PR ou comentário.
- Comentários e commits em português; README.md e README.pt-BR.md juntos.
