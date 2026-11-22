# T21 — Sem som se o app da sessão já está na frente

- **Funcionalidade:** F14 — spec [G07, F14](../05-specs/G07-ir-para-sessao.md)
- **Épico:** Notificações · **Prioridade:** P1 · **Esforço:** 1 h
- **Depende de:** T19, T20, T01 · **Bloqueia:** T24, T26
- **Branch:** `feat/sem-som-se-olhando`
- **PR:** `feat: sem som quando você já está olhando a sessão`

## Objetivo

Se o app que hospeda a sessão é o app da frente, o aviso sai **sem som** (o popup continua). Nível app: com o Claude.app na frente, qualquer conversa dele conta. No tmux o som sempre toca (seguir o tmux trocaria o pane).

## Subtasks

- [ ] `Notifier.post(_:body:sessionId:playSound:onOpen:)`: o bloco de som fica dentro de `if playSound { … }`, depois do `guard isEnabled` do T01.
- [ ] `SessionStore.isLookingAt(_:)` privado, perto de `goToSession`, com `followTmux: false`.
- [ ] Todos os `post` do `notifyTransitions` passam `playSound: !isLookingAt(row)`.
- [ ] Verificação manual 1–4 da spec.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`Notifier.swift`, `SessionStore.swift`, READMEs.

## Código-chave (da spec)

Assinatura final de `post` (vale daqui em diante):

```swift
    func post(
        _ alert: Alert,
        body: String,
        sessionId: String? = nil,
        playSound: Bool = true,
        onOpen: (@MainActor () -> Void)? = nil
    ) {
        // Desligado no menu = silêncio total: nem popup nem som.
        guard isEnabled else { return }
        if playSound {
            if let soundOverride { soundOverride(alert) } else { play(alert) }
        }
        guard canUseSystemNotifications else {
            hud.show(alert, body: body, sessionId: sessionId, onOpen: onOpen)
            return
        }
        // … notificação nativa igual …
    }
```

```swift
    /// Você já está olhando o app da sessão? Então o som é dispensável (F14).
    /// Nível app; sem tmux aqui — seguir o tmux troca o pane de verdade.
    private func isLookingAt(_ row: SessionRow) -> Bool {
        guard let pid = row.pid, pid > 0,
              let front = NSWorkspace.shared.frontmostApplication,
              let app = SessionNavigator.app(for: pid, followTmux: false)
        else { return false }
        return app.processIdentifier == front.processIdentifier
    }
```

## Testes obrigatórios

Teste unitário de `playSound: false` fica **adiado** (exige o caminho que cria `NSPanel`, como decidido no G01). O teste `desligadoNaoTocaSom` do T01 tem de continuar verde. Gate: build + testes.

## Critérios de aceite

- `post(..., playSound: false)` não toca som e ainda mostra o popup.
- `isLookingAt` usa `followTmux: false`: nenhum `tmux` disparado por aviso.
- Toggle desligado continua silenciando tudo.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

Alerts: "No sound if the session's app is already in front (the popup still shows). App level only: with the Claude desktop app in front, any of its conversations counts; inside tmux the sound always plays."

## Riscos

| Risco | Mitigação |
|---|---|
| Claude.app na frente com outra conversa silencia errado | aceito (nível app), documentado; popup continua |
| Subida falha (iTerm2) | toca o som, como hoje (falha segura) |

## Fora do escopo

Esconder o popup; chamar tmux na main; chave de ajuste para isso.
