# T45 — Rótulo "app desktop" × "terminal" na linha da sessão

- **Funcionalidade:** F54 (extensão da F11/T18) — informação que o app já tem
- **Esforço:** 1,5 h
- **Depende de:** T19 · **Bloqueia:** —
- **Branch:** `feat/rotulo-desktop-terminal`
- **PR:** `feat: linha da sessão diz se roda no app desktop ou no terminal`

## Objetivo

Mostrar na linha da sessão onde ela roda, usando só o que o código já sabe, sem coletar nada novo. Duas fontes existem hoje:

- `ProcessProbe.isGroupLeader`: sessão de terminal lidera o próprio grupo (`pgid == pid`); a do app desktop vive no grupo do `Claude.app`. É a regra que `SessionTerminator.target(for:)` usa para devolver `.hostedByApp` (documentada no README, "Why desktop app sessions can't be terminated from here").
- `AgentSession.kind` (`claude agents --json`): só distingue `interactive` de `background` (README: "only lists `kind: "interactive"` and `kind: "background"`"). **Não** diz desktop × terminal, então não serve para este rótulo.

Decisão: reaproveitar a regra do `SessionTerminator` (`.hostedByApp` = app desktop; `.signal` = terminal). O rótulo vale só para sessão interativa com `pid > 0`; subagente e linha sem processo ficam sem rótulo.

## Subtasks

- [ ] Função pura `SessionTerminator.hostKind(for:probe:)` (ou `SessionRow.host(probe:)`) que devolve `enum SessionHost { case desktopApp, terminal }?`: `nil` para `isSubagent`, `pid` ausente/`<= 0`, ou `.unavailable`; `.desktopApp` quando o alvo é `.hostedByApp`; `.terminal` quando é `.signal`. Reaproveita `target(for:probe:)` em vez de duplicar `isGroupLeader`.
- [ ] `Sources/ClaudeBar/MenuContent.swift`, `label(for:now:)`: acrescentar o rótulo curto (`desktop app` / `terminal`) na linha, junto da branch. Mantê-lo curto: a linha já tem nome, branch, estado e tempo.
- [ ] Custo: `getpgid` é uma syscall barata, mas só chamar ao montar o menu (como `limitLines`), nunca num timer.
- [ ] Texto para o VoiceOver: incluir o rótulo em `description(for:)` só se `AccessibilityTests` ficarem coerentes com a legenda.
- [ ] Strings em `Resources/en.lproj/Localizable.strings` e `Resources/pt-BR.lproj/Localizable.strings` ("app desktop", "terminal").
- [ ] Testes (`SessionTerminatorTests.swift`, que já descreve as topologias com `ProcessProbe` injetável): líder do grupo = `terminal`; fora do grupo = `desktopApp`; subagente = `nil`; `pid 0` = `nil`; PID reciclado (executável que não é `claude`) = `nil`. Teste de `label` com e sem rótulo.
- [ ] READMEs: uma linha dizendo que a linha mostra onde a sessão roda e como o app decide.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/SessionTerminator.swift` | `hostKind`/`SessionHost`, reaproveitando `target(for:probe:)` |
| `Sources/ClaudeBar/MenuContent.swift` | rótulo em `label(for:now:)` |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | duas strings |
| `Tests/ClaudeBarTests/SessionTerminatorTests.swift`, `Tests/ClaudeBarTests/AccessibilityTests.swift` | testes |
| `README.md`, `README.pt-BR.md` | uma linha |

## Critérios de aceite

- O rótulo vem da mesma regra que decide se "Encerrar sessão" aparece (uma só fonte de verdade).
- Nenhuma leitura nova de conversa, nenhuma rede, nenhum processo novo.
- Linha de subagente e de sessão sem processo continua sem rótulo.
- `swift build` e `swift test` verdes (anterior + novos).

## Não verificado (declarar no PR)

- Que os hooks do Claude Code disparam nas sessões do app desktop: a `README` e o `SessionTerminator` só provam que existem sessões do desktop em `claude agents --json`, e a regra do `pgid` foi observada na máquina do autor. Se a sessão do desktop não gravar estado por hook, a linha vem só do CLI e ainda ganha o rótulo (ele não depende do hook), mas o estado pode ficar defasado. Confirmar abrindo uma sessão no app desktop com os hooks instalados; sem isso, o PR diz "não verificado".
- Sessões de editores (VS Code, Cursor) e do tmux: a regra do `pgid` classifica como `terminal`; se alguma cair em `desktopApp`, ajustar em outro PR.

## Fora do escopo

Ícone por host, ler o bundle id do app hospedeiro (`SessionNavigator.app(for:)` sobe a árvore e usa `sysctl`; reutilizar isso aqui custaria uma subida por linha a cada menu), agrupar o menu por host.
