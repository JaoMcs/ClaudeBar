# T40 — Atalho global "ir para a próxima sessão esperando"

- **Funcionalidade:** F50 (extensão da T22) — atalho global, sem Acessibilidade
- **Esforço:** 3 h
- **Depende de:** T19, T22 · **Bloqueia:** —
- **Branch:** `feat/atalho-proxima-sessao`
- **PR:** `feat: atalho global para a próxima sessão que espera`

## Objetivo

Um atalho de teclado global que leva à sessão que espera há mais tempo, o mesmo que `claudebar-hook next` faz hoje em `goToNextWaiting()` (`Sources/claudebar-hook/main.swift`: `state == .waiting && pid > 0`, `min` por `updatedAt`). Registro com `RegisterEventHotKey` (Carbon), que não exige permissão de Acessibilidade nem Monitoramento de Entrada. Liga/desliga nos Ajustes, **padrão desligado** (atalho global toma uma combinação do sistema inteiro, então é opt-in).

## Subtasks

- [ ] Função pura de escolha, no Core para o CLI e o app usarem a mesma: `SessionNavigator.nextWaiting(in: [SessionStatus]) -> SessionStatus?` (`state == .waiting`, `pid > 0`, mais antigo por `updatedAt`; empate estável por `sessionId`). `goToNextWaiting()` do CLI passa a chamá-la.
- [ ] `Sources/ClaudeBar/GlobalHotKey.swift` (novo): `import Carbon.HIToolbox`; `RegisterEventHotKey` + `InstallEventHandler` (`kEventClassKeyboard`, `kEventHotKeyPressed`); `register()`/`unregister()` idempotentes; falha de registro (combinação já tomada) devolve erro, sem crash.
- [ ] Combinação fixa e pouco comum (a decidir no PR, ex. `⌃⌥⌘N`); sem gravador de atalho nesta task.
- [ ] `SessionStore`: método `goToNextWaiting()` que escolhe a linha entre `rows` (`!isSubagent`, `state == .waiting`, `pid > 0`, mais antiga por `updatedAt`) e chama `goToSession(_:)`; sem sessão esperando, nada acontece (sem alerta, é um atalho).
- [ ] `SettingsWindow.swift`: `Toggle` "Atalho global para a próxima sessão esperando" em `Section("System")` ou seção própria, `@AppStorage` com chave nova (padrão `false`); registra/desregistra ao mudar; se o registro falhar, texto de erro como `loginError`. Strings novas em `en.lproj` e `pt-BR.lproj`.
- [ ] Ao abrir o app com a opção ligada, registrar o atalho (em `SessionStore.init` ou no `AppDelegate`).
- [ ] Testes: `nextWaiting` (pega o mais antigo, ignora `pid 0`, ignora `working/idle/error`, lista vazia = `nil`, empate estável). Não registrar hotkey em teste.
- [ ] READMEs: seção do atalho, com a combinação e que não pede permissão.
- [ ] Gates (`swift build`, `swift test`, `./scripts/build-app.sh`), commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/SessionNavigator.swift` | `nextWaiting(in:)` pura |
| `Sources/claudebar-hook/main.swift` | `goToNextWaiting()` usa a função |
| `Sources/ClaudeBar/GlobalHotKey.swift` | novo (Carbon) |
| `Sources/ClaudeBar/SessionStore.swift` | `goToNextWaiting()` |
| `Sources/ClaudeBar/SettingsWindow.swift` | toggle + erro de registro |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | strings novas |
| `Tests/ClaudeBarTests/SessionNavigatorTests.swift` | testes de `nextWaiting` |
| `README.md`, `README.pt-BR.md` | seção do atalho |

## Critérios de aceite

- Atalho desligado por padrão; ligar registra, desligar libera a combinação.
- Nenhum pedido de Acessibilidade/Monitoramento de Entrada; nenhuma rede.
- CLI `next` e atalho escolhem a mesma sessão (mesma função).
- `goToSession` continua sendo o único caminho que traz a janela (nada de `activate` novo à parte).
- `swift test` = anterior + testes de `nextWaiting`.
- No PR, "Não verificado: pressionar o atalho com o app em segundo plano (depende de teclado e foco)".

## Fora do escopo

Gravador de atalho configurável, atalho para a sessão N, atalho para "marcar como visto".
