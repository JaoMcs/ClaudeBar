# T20 — Clique no popup leva à sessão

- **Funcionalidade:** F10 — spec [G07, F10](../05-specs/G07-ir-para-sessao.md)
- **Épico:** Navegação · **Prioridade:** P1 · **Esforço:** 1 h
- **Depende de:** T19, T17 · **Bloqueia:** T21, T26
- **Branch:** `feat/alerta-leva-a-sessao`
- **PR:** `feat: clique no popup leva à sessão`

## Objetivo

Clicar no popup de um aviso real (terminou, falhou, permissão, pergunta, esperando) chama `goToSession` daquela sessão e fecha o popup. O popup de exemplo continua só fechando.

## Subtasks

- [ ] `StatusHUD.show(_:body:sessionId:onOpen:)`: o clique chama `onOpen?()` e depois `dismiss()`. `HUDView` não muda.
- [ ] `Notifier.post(_:body:sessionId:onOpen:)` repassa ao `hud.show`; notificação nativa ignora `onOpen` (até F28).
- [ ] `SessionStore.notifyTransitions`: `let open: @MainActor () -> Void = { [weak self] in self?.goToSession(row) }` antes do `switch`; todos os `post` passam `onOpen: open`. `showSample()` sem `onOpen`.
- [ ] Verificação manual 1–4 da spec.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`StatusHUD.swift`, `Notifier.swift`, `SessionStore.swift`, READMEs.

## Código-chave (da spec, com o `sessionId` do T17)

```swift
    /// - Parameter onOpen: chamado no clique, antes de fechar — leva à sessão.
    func show(_ alert: Alert, body: String, sessionId: String? = nil, onOpen: (@MainActor () -> Void)? = nil) {
        // … regra de "não tapar espera" do T17 …
        let content = HUDView(alert: alert, body: body, width: Self.width) { [weak self] in
            onOpen?()
            self?.dismiss()
        }
```

```swift
            // Clique no popup leva à sessão (F10).
            let open: @MainActor () -> Void = { [weak self] in self?.goToSession(row) }
            // … notifier.post(.finished, body: row.name, sessionId: row.sessionId, onOpen: open)
```

## Testes obrigatórios

Nenhum novo (repassar closure; testar exigiria `NSPanel` e clique simulado). Build + testes existentes verdes.

## Critérios de aceite

- Clique no popup chama `goToSession` da sessão do aviso e fecha o popup; a sessão fica marcada como vista.
- Popup de exemplo sem navegação.
- `HUDView` sem referência a `SessionNavigator`/`SessionRow`.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

Alerts: "Clicking the popup takes you to the session (same as **Ir para a sessão**); the sample popup only closes."

## Riscos

| Risco | Mitigação |
|---|---|
| Painel `.nonactivatingPanel` + app `.accessory` → `activate` recusado | fallback `openApplication` do T19; verificar no passo 1 |
| Sessão fechou entre o aviso e o clique | `goToSession` cai no alerta; não destrutivo |

## Fora do escopo

Tornar o painel ativável/`canBecomeKey`, delegate de notificação nativa, botões no popup.
