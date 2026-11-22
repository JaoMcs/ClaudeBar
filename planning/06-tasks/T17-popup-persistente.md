# T17 — Popup de espera fica até o clique ou a transição; canto longe do cursor

- **Funcionalidade:** F12 — spec [G09, F12](../05-specs/G09-popup-lembrete.md)
- **Épico:** Notificações · **Prioridade:** P1 · **Esforço:** 2 h
- **Depende de:** T09 (sem `waiting` falso), T16 (avisos de espera por tipo) · **Bloqueia:** T20, T26
- **Branch:** `feat/popup-persistente`
- **PR:** `feat: popup de espera fica até você responder`

## Objetivo

O popup de espera (permissão, pergunta ou genérico) fica na tela até você clicar ou **aquela** sessão sair de `waiting`. "Terminou" e "falhou" continuam sumindo em 4 s e nunca tapam um popup de espera aberto. O popup não nasce debaixo do cursor.

## Ajuste sobre a spec

A spec fala só de `.waiting`. Com T13 e T16 em `main`, a regra vale para os três avisos de espera. Uma propriedade em `Alert`:

```swift
    /// Avisos que pedem ação sua: ficam na tela até você agir.
    var staysUntilAnswered: Bool {
        switch self {
        case .waiting, .permission, .question: true
        case .finished, .failed: false
        }
    }
```

## Subtasks

- [ ] `Alert.staysUntilAnswered`.
- [ ] `StatusHUD`: `shownAlert`, `shownSessionId`; `show(_:body:sessionId:)`; timer só para quem não fica; `dismissWaiting(for:)`; `dismiss()` limpa os dois.
- [ ] `StatusHUD.origin(for:in:avoiding:margin:)` `nonisolated static`, pura; `reposition` usa.
- [ ] `Notifier`: `post(_:body:sessionId:)` repassa; `dismissWaiting(for:)`.
- [ ] `SessionStore.notifyTransitions`: antes do loop de avisos, fechar o popup de toda sessão que estava `waiting` em `previousRows` e não está mais (ou sumiu); os `post` passam `sessionId: row.sessionId`. `showSample` sem `sessionId`.
- [ ] Testes `PopupCornerTests` (5) + `avisosDeEsperaFicam`.
- [ ] Verificação manual 1–7 da spec. Se o passo 1 mostrar **2 cliques** para fechar, aplicar o plano B (`FirstClickHostingView`); se o passo 6 mostrar que some ao trocar de Space, tirar só `.transient`. Registrar os dois resultados.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`StatusHUD.swift`, `Notifier.swift`, `SessionStore.swift`, `AlertTests.swift`, READMEs.

## Código-chave (da spec, adaptado)

```swift
    func show(_ alert: Alert, body: String, sessionId: String? = nil) {
        // Aviso informativo não tapa um de espera ainda aberto: fica só o som.
        if !alert.staysUntilAnswered, shownAlert?.staysUntilAnswered == true { return }
        // … igual até `panel.orderFrontRegardless()` …
        shownAlert = alert
        shownSessionId = sessionId
        dismissTask?.cancel()
        dismissTask = nil
        guard !alert.staysUntilAnswered else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Fecha o aviso de espera se ele for desta sessão.
    func dismissWaiting(for sessionId: String) {
        guard shownAlert?.staysUntilAnswered == true, shownSessionId == sessionId else { return }
        dismiss()
    }

    nonisolated static func origin(for size: NSSize, in frame: NSRect, avoiding mouse: NSPoint, margin: CGFloat) -> NSPoint {
        let right = frame.maxX - size.width - margin
        let left = frame.minX + margin
        let top = frame.maxY - size.height - margin
        let bottom = frame.minY + margin
        let corners = [NSPoint(x: right, y: top), NSPoint(x: right, y: bottom), NSPoint(x: left, y: top)]
        // A margem entra na conta: cursor encostado na borda do popup também conta.
        return corners.first { corner in
            !NSRect(origin: corner, size: size).insetBy(dx: -margin, dy: -margin).contains(mouse)
        } ?? corners[0]
    }
```

`SessionStore`, começo de `notifyTransitions`:

```swift
        // Saiu de "esperando" (respondeu, terminou) ou sumiu (fechou): o popup
        // daquela sessão fecha, antes de qualquer aviso novo.
        let current = Dictionary(merged.map { ($0.sessionId, $0.state) }, uniquingKeysWith: { first, _ in first })
        for (sessionId, previous) in previousRows where previous.state == .waiting && current[sessionId] != .waiting {
            notifier.dismissWaiting(for: sessionId)
        }
```

## Testes obrigatórios

- `PopupCornerTests` da spec (5 casos, incluindo tela com origem negativa).
- `avisosDeEsperaFicam`: `.waiting/.permission/.question` → `true`; `.finished/.failed` → `false`.
- Não testar `show`/`dismissWaiting` reais (criam `NSPanel`).

## Critérios de aceite

- Aviso de espera não agenda `dismissTask`; "terminou"/"falhou" agendam 4 s.
- "Terminou" com espera na tela não troca o conteúdo do painel.
- `dismissWaiting(for:)` só fecha se o que está na tela é espera daquela sessão.
- `origin` é `nonisolated static` e pura; não lê `NSEvent.mouseLocation` dentro.
- Resultados dos passos 1 e 6 registrados no PR.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Em "Why the app draws its own popup", trocar "It disappears after 4 seconds or on click" pelo texto da spec, citando os três avisos de espera e que "terminou"/"falhou" nunca cobrem um de espera aberto.

## Riscos

| Risco | Mitigação |
|---|---|
| Clique acidental no popup persistente | nasce longe do cursor; o clique só fecha |
| Duas sessões esperando, só a última aparece | ícone da barra continua avisando; `ponytail:` sem fila |
| Esc no prompt não dispara hook | fica até o clique; aceito |

## Fora do escopo

Botão "Aprovar" (F46, vetado); fila de avisos; `NSApp.activate`; mudar nível do painel; caminho `UNUserNotificationCenter` (F28); clique levando à sessão (T20).
