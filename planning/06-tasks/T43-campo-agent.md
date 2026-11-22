# T43 — Multiagente, parte 1: campo `agent`

- **Funcionalidade:** F53 (1/2) — "Support other coding agents" do `TODO.md`
- **Esforço:** 2 h
- **Depende de:** — · **Bloqueia:** T44
- **Branch:** `feat/campo-agent`
- **PR:** `feat: campo agent no estado da sessão e rótulo no menu`

## Objetivo

Preparar o terreno para outros agentes sem registrar nenhum hook novo. Um campo opcional `agent` em `SessionStatus` (arquivo antigo, sem o campo, continua decodificando e vale `claude`), a flag `--agent <nome>` no `claudebar-hook` (padrão `claude`) e o rótulo do agente na linha do menu **só quando não for `claude`**. Os hooks do Claude Code instalados hoje não mudam.

## Subtasks

- [ ] `Sources/ClaudeBarCore/SessionStatus.swift`: `public let agent: String?` (texto, não enum, pelo mesmo motivo de `kind`: valor desconhecido não pode derrubar o decode, e `StatusDirectory.readAll` apaga arquivo que não decodifica). Parâmetro `agent: String? = nil` no `init`. Computed `agentName: String { agent ?? "claude" }`.
- [ ] Não gravar a chave quando for `claude`/`nil` (arquivo igual ao de hoje, como o teste `semKindNaoGravaAChave` faz com `kind`).
- [ ] `Sources/claudebar-hook/main.swift`: `value(after: "--agent", in: arguments)`; ausente = `nil`; passa ao `SessionStatus`. Atualizar o comentário de uso no topo do arquivo.
- [ ] `parsePID` hoje só aceita pai com `claude` no caminho; deixar anotado (comentário) que outro agente exige `--pid` ou outra checagem — a mudança em si fica na T44.
- [ ] `Sources/ClaudeBar/SessionRow.swift`: `let agent: String?` (padrão `nil` no `init`); `Sources/ClaudeBar/SessionMerge.swift`: repassar `hook?.agent` nas duas construções de `SessionRow` (`rows(agents:statuses:)`).
- [ ] `Sources/ClaudeBar/MenuContent.swift`, `label(for:now:)`: prefixo/sufixo `[gemini]` só se `agent != nil && agent != "claude"` (mesmo estilo do `[subagent]`). Sessão sem hook (só vinda do `claude agents --json`) fica sem rótulo.
- [ ] `AccessibilityTests`/`description(for:)`: o rótulo entra no texto lido pelo VoiceOver, se `label` for usado ali.
- [ ] Testes (`SessionStatusTests.swift`): arquivo antigo sem `agent` decodifica e `agentName == "claude"`; `agent: "gemini"` faz round-trip; sem agente não grava a chave; valor desconhecido decodifica. `SessionMergeTests.swift`: o `agent` do hook chega na linha. `MenuContent`: rótulo ausente para `claude`, presente para `gemini`.
- [ ] Strings novas (se o rótulo for traduzível) em `en.lproj` e `pt-BR.lproj`; nome do agente não é traduzido.
- [ ] READMEs: `--agent` no uso do CLI e o campo no exemplo de arquivo de estado.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/SessionStatus.swift` | campo `agent`, `agentName` |
| `Sources/claudebar-hook/main.swift` | flag `--agent` |
| `Sources/ClaudeBar/SessionRow.swift` | campo `agent` |
| `Sources/ClaudeBar/SessionMerge.swift` | repassa o `agent` |
| `Sources/ClaudeBar/MenuContent.swift` | rótulo em `label(for:now:)` |
| `Tests/ClaudeBarTests/SessionStatusTests.swift`, `Tests/ClaudeBarTests/SessionMergeTests.swift` | testes de decode e de repasse |
| `README.md`, `README.pt-BR.md` | flag e campo |

## Critérios de aceite

- Arquivos de estado antigos continuam decodificando (teste explícito).
- Sem `--agent`, o arquivo gravado é byte a byte o de hoje.
- Nenhuma linha de sessão do Claude ganha rótulo novo.
- `HookInstaller.entries` e `HookInstaller.state` inalterados (nenhum usuário vê "hooks desatualizados" por causa desta task).
- `swift build` e `swift test` verdes (anterior + novos).

## Fora do escopo

Registrar hooks de Gemini/Codex (T44), ícone por agente, `AgentsProbe` e `SessionTerminator` (continuam só Claude), mover a pasta de estado para fora de `~/.claude`.
