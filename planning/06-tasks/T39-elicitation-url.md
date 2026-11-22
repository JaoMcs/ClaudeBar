# T39 — `elicitation_url_dialog` também vira pergunta

- **Funcionalidade:** F49 (ajuste) — item "Adiados pelas specs" do `ROADMAP.md`
- **Esforço:** 0,5 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `feat/elicitation-url`
- **PR:** `feat: elicitation_url_dialog conta como pergunta`

## Objetivo

Hoje `HookInstaller.entries` registra `Notification` com matcher `elicitation_dialog` → `["waiting", "--kind", "question"]`. O Claude Code também dispara `elicitation_url_dialog` (pedido de abrir uma URL), que hoje não chama o binário, então a sessão parada não acende nada. Trocar o matcher para `elicitation_dialog|elicitation_url_dialog` (matcher é regex/alternância no Claude Code), mantendo o mesmo `args`.

## Subtasks

- [ ] `Sources/ClaudeBarCore/HookInstaller.swift`: no `Entry` de `Notification` com `elicitation_dialog`, trocar `matcher` por `"elicitation_dialog|elicitation_url_dialog"`.
- [ ] `Tests/ClaudeBarTests/HookInstallerTests.swift`, `notificationTemDoisMatchers`: a asserção `("elicitation_dialog", ["waiting","--kind","question"])` passa a usar o matcher novo; continuam 2 grupos.
- [ ] Teste de migração: um settings com a entrada antiga (`elicitation_dialog`) é lido por `HookInstaller.state` como `.hooksOutdated` (a comparação de `state` é por `matcher` exato) e `install` o troca sem duplicar (idempotente).
- [ ] Comentário em `WaitKind.question` (`SessionStatus.swift`) cita os dois tipos.
- [ ] `ROADMAP.md`: tirar o item de "Adiados pelas specs". READMEs: conferir se citam o matcher e atualizar nas duas línguas.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | matcher de `entries` |
| `Sources/ClaudeBarCore/SessionStatus.swift` | comentário de `WaitKind.question` |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | matcher novo + migração |
| `ROADMAP.md`, `README.md`, `README.pt-BR.md` | item removido / menção ao matcher |

## Critérios de aceite

- `entries` tem exatamente uma entrada de `Notification` por tipo de espera (permissão, pergunta); o matcher da pergunta cobre os dois eventos.
- Quem já tinha os hooks instalados vê "hooks desatualizados" no app e reinstala pela prévia de sempre (nenhuma escrita sem prévia + backup).
- `swift build` e `swift test` verdes, nenhum teste afrouxado.

## Não verificado (declarar no PR)

- Que o Claude Code de hoje realmente emite `elicitation_url_dialog` com esse nome e aceita a alternância `a|b` no matcher: conferir na doc de hooks do Claude Code antes de abrir o PR; se a doc não confirmar, marcar como "não verificado".

## Fora do escopo

Outros tipos de `Notification` (`idle_prompt`, `auth_success`…), mudar o `WaitKind`.
