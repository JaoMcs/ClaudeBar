# T31 — VoiceOver + legenda dos estados

- **Funcionalidade:** F19 — spec [G12, F19](../05-specs/G12-a11y-i18n.md)
- **Épico:** i18n/a11y · **Prioridade:** P1 · **Esforço:** 2 h
- **Depende de:** T16 (todos os casos de `BarState`), T23 (`label` com branch), T29 (linhas de limite) · **Bloqueia:** T34
- **Branch:** `feat/voiceover-legenda`
- **PR:** `feat: VoiceOver na barra e legenda dos ícones`

## Objetivo

Quem usa VoiceOver sabe, sem ver o símbolo: o que é o item da barra, quantas sessões e qual estado; o estado de cada linha por extenso (sem nome de emoji); que um popup apareceu. Quem enxerga ganha uma legenda dos símbolos dentro do menu.

## Ajuste sobre a spec

A spec foi escrita com 4 estados. Em `main` agora `BarState` tem 7 (`permission`, `question`, `waiting`, `error`, `done`, `working`, `idle`) e a linha depende de `(state, kind)`:

```swift
    /// O mesmo símbolo da barra para o mesmo estado, então a legenda vale para as linhas.
    private static func symbolName(for row: SessionRow) -> String {
        switch (row.state, row.kind) {
        case (.working, _): BarState.working.symbolName
        case (.idle, _): BarState.done.symbolName
        case (.error, _): BarState.error.symbolName
        case (.waiting, .permission): BarState.permission.symbolName
        case (.waiting, .question): BarState.question.symbolName
        case (.waiting, nil): BarState.waiting.symbolName
        }
    }
```

Títulos (pt-BR, o T34 traduz): `permission` "Claude pede permissão", `question` "Claude fez uma pergunta", `waiting` "Claude está esperando você", `error` "Uma resposta falhou, ainda não vista", `done` "Resposta pronta, ainda não vista", `working` "Claude está trabalhando", `idle` "Nada acontecendo".

## Subtasks

- [ ] `BarState: CaseIterable`, `title`, `accessibilityLabel(openSessions:)`.
- [ ] `ClaudeBarApp`: label em `HStack` com `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)`.
- [ ] `MenuContent`: linha vira `Label(Self.label(for: row), systemImage: Self.symbolName(for: row))`; `label(for:now:)`, `description(for:)` `static`; emojis saem do texto; submenu "O que os ícones significam" com `ForEach(BarState.allCases)`.
- [ ] `StatusHUD`: `announce(_:body:)` depois do `orderFrontRegardless`; `HUDView` com `.accessibilityElement(children: .combine)`.
- [ ] `AccessibilityTests.swift` novo (3).
- [ ] Verificação 1–2 por script (System Events) e 3–5 da spec. O 3 (VoiceOver ouvido) vai como "fala"/"não fala"/"não verificado" — nunca "ok" sem teste. Se mudo, testar `element: panel` (passo 4).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`ClaudeBarApp.swift`, `SessionStore.swift` (só `BarState`), `MenuContent.swift`, `StatusHUD.swift`, `AccessibilityTests.swift` (novo), READMEs.

## Código-chave (da spec)

```swift
    /// Rótulo do item da barra para o VoiceOver. Sem plural de propósito
    /// ("Sessões: 1"): dispensa `.stringsdict` quando o texto for traduzido.
    func accessibilityLabel(openSessions: Int) -> String {
        "ClaudeBar. Sessões: \(openSessions). \(title)"
    }
```

```swift
        } label: {
            HStack {
                Image(systemName: store.barState.symbolName)
                Text("\(store.openSessionCount)")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.barState.accessibilityLabel(openSessions: store.openSessionCount))
        }
```

```swift
    /// O painel não toma foco, então o VoiceOver não passa por ele sozinho.
    private func announce(_ alert: Alert, body: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(alert.title). \(body)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
```

```swift
        Menu("O que os ícones significam") {
            ForEach(BarState.allCases, id: \.self) { state in
                Label(state.title, systemImage: state.symbolName)
            }
        }
```

## Testes obrigatórios

`AccessibilityTests` da spec: `rotuloDaBarraDizAppContagemEEstado`, `cadaEstadoTemTituloProprio` (7 títulos distintos), `linhaDoMenuSemEmoji` (todos os `SessionState.allCases`, incluindo `error`, com `kind` nil/permission/question; `@MainActor`).

## Critérios de aceite

- `title` do item da barra (System Events) contém "ClaudeBar", a contagem e o estado.
- A barra continua com símbolo e número.
- Nenhum título de item do menu tem emoji; cada linha tem o SF Symbol igual ao da barra para o mesmo estado.
- Legenda lista exatamente `BarState.allCases`.
- `StatusHUD.show` posta `.announcementRequested` com prioridade alta; resultado do VoiceOver registrado.
- `swift test` = anterior + 3.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh` (para o passo por System Events).

## README (as duas línguas)

Exemplo do menu sem emojis (ou com os nomes dos símbolos), linha `O que os ícones significam ▸`, bullet "**VoiceOver** — the menu bar item reads e.g. "ClaudeBar. Sessions: 2. Claude is waiting for you"; popups are announced (when VoiceOver allows announcements from background apps)".

## Riscos

| Risco | Mitigação |
|---|---|
| Anúncio mudo em app `.accessory` | código inofensivo; testar `element: panel`; registrar limitação |
| Menus do macOS 14/15 sem o ícone do `Label` | o texto já diz o estado |
| Novo caso em `BarState` sem título | `switch` exaustivo + `cadaEstadoTemTituloProprio` |

## Fora do escopo

`Label` no label da barra; `.accessibilityLabel` nas linhas (ignorado no `.menu`); `AVSpeechSynthesizer`; ativar o app para anunciar; textos em inglês (T34).
