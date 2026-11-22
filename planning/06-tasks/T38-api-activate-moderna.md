# T38 — Trocar `activate(ignoringOtherApps:)` pela API moderna

- **Funcionalidade:** F48 (manutenção) — item "Deprecated APIs" do `TODO.md`; nota do dono de 2026-11-15
- **Esforço:** 0,5 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `chore/activate-moderno`
- **PR:** `chore: ativar o app com NSApp.activate() em vez da API a ser descontinuada`

## Objetivo

`SessionStore.swift` chama `NSApplication.shared.activate(ignoringOtherApps: true)` em dois lugares (`confirmTermination(of:)` e `report(title:message:)`). A Apple marca essa API como "will be deprecated" (sem aviso de compilação ainda). O alvo é macOS 14+ (`platforms: [.macOS(.v14)]` no `Package.swift`), onde existe `NSApp.activate()` (ativação cooperativa). `HookSetup.runInFront` já faz isso: `alert.window.level = .floating` + `NSApplication.shared.activate()`. Replicar o mesmo padrão, sem inventar outro.

## Subtasks

- [ ] `confirmTermination(of:)`: trocar a chamada por `NSApplication.shared.activate()` e subir `alert.window.level = .floating` antes de `runModal()`, como em `HookSetup.runInFront`.
- [ ] `report(title:message:)`: mesma troca e mesmo nível de janela.
- [ ] Atualizar o comentário ("O app é accessory: sem ativar, o alerta nasce atrás…") para dizer que a ativação é só um pedido e que o nível `.floating` garante a janela na frente.
- [ ] `TODO.md`: marcar o item de "Deprecated APIs" como `[x]`. Manter a frase "New code must not use it either".
- [ ] `grep -rn "ignoringOtherApps" Sources Tests` sem resultado.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/SessionStore.swift` | 2 chamadas (`confirmTermination`, `report`), comentário |
| `TODO.md` | item marcado |

## Critérios de aceite

- Nenhuma ocorrência de `ignoringOtherApps` em `Sources/` e `Tests/`.
- Os dois alertas continuam com o mesmo texto e botões; só a forma de trazer à frente muda.
- `swift build` sem aviso novo e `swift test` verdes.
- No PR, "Não verificado: o alerta de encerrar/erro aparece na frente de outro app em tela (depende de tela e foco)".

## Fora do escopo

Mudar o fluxo dos alertas, o `SettingsWindow.show` (já usa `activate()`), ou qualquer outra API do `TODO.md`.
