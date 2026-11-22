# T24 — Janela de Ajustes: avisar por tipo, som, Sobre

- **Funcionalidade:** F15, parte 1 de 2 (F15.1) — spec [G10, F15.1](../05-specs/G10-ajustes-privacidade.md)
- **Épico:** UI/Ajustes · **Prioridade:** P1 · **Esforço:** 2,5 h
- **Depende de:** T01, T13, T16, T21 (todos os casos de `Alert` e a assinatura final de `post`) · **Bloqueia:** T25, T26, T27
- **Branch:** `feat/janela-ajustes`
- **PR:** `feat: janela de Ajustes com avisos e sons`

## Objetivo

Item **Ajustes… ⌘,** no menu abre uma janela **na frente** das outras com: avisar por tipo (liga/desliga), tocar som (liga/desliga, sem desligar o popup), som de cada aviso entre os sons do sistema com prévia, e botão **Sobre o ClaudeBar** (painel padrão). O toggle **Notificações** do menu continua sendo o interruptor geral.

## Ajuste sobre a spec (5 casos de `Alert`)

| `Alert` | `enabledKey` | `soundKey` | padrão |
|---|---|---|---|
| `.finished` | `notifyFinished` | `soundFinished` | `Glass` |
| `.waiting`, `.permission` | `notifyWaiting` | `soundWaiting` | `Submarine` |
| `.question` | `notifyWaiting` | `soundQuestion` | `Purr` |
| `.failed` | `notifyFailed` | `soundFailed` | `Basso` |

Três toggles ("terminar", "esperar você", "a resposta falhar") e quatro Pickers ("Terminou", "Pede permissão / esperando", "Pergunta", "Falhou").

## Subtasks

- [ ] `Notifier`: `Alert.enabledKey`/`soundKey` (tabela acima); `soundEnabledKey`; `systemSounds` (lê `/System/Library/Sounds`, sem extensão); `register(defaults:)` com todas as chaves; `soundName(for:)`; `preview(_:for:)`; `play(_ name:volume:)`.
- [ ] Início de `post`: `guard isEnabled, defaults.bool(forKey: alert.enabledKey) else { return }`; som só se `playSound` **e** `soundName(for:) != nil`.
- [ ] Criar `Sources/ClaudeBar/SettingsWindow.swift` (`NSWindow` + `NSHostingController`, `isReleasedWhenClosed = false`, `orderFrontRegardless`).
- [ ] `MenuContent`: "Ajustes…" com `.keyboardShortcut(",")` depois do bloco de notificações.
- [ ] Testes (abaixo).
- [ ] Verificação manual 1–9 da spec. Se a janela abrir atrás, `window.level = .floating` só enquanto abre; se o `Form` ficar cortado, `.formStyle(.grouped)` + altura fixa. Registrar.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`Notifier.swift`, `SettingsWindow.swift` (novo), `MenuContent.swift`, `AlertTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    func post(_ alert: Alert, body: String, sessionId: String? = nil,
              playSound: Bool = true, onOpen: (@MainActor () -> Void)? = nil) {
        // Desligado no menu, ou este tipo desligado nos Ajustes = silêncio total.
        guard isEnabled, defaults.bool(forKey: alert.enabledKey) else { return }
        if playSound, let soundName = soundName(for: alert) {
            if let soundOverride { soundOverride(alert) } else { play(soundName, volume: alert.volume) }
        }
        // … resto igual …
    }

    /// Som a tocar para o aviso, ou `nil` com o som desligado nos Ajustes.
    func soundName(for alert: Alert) -> String? {
        guard defaults.bool(forKey: Self.soundEnabledKey) else { return nil }
        return defaults.string(forKey: alert.soundKey) ?? alert.soundName
    }

    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()
```

```swift
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(notifier: Notifier) {
        // Fechada = janela nova, com estado relido. Aberta = só traz para a frente.
        if window?.isVisible != true {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(notifier: notifier)))
            window.title = "Ajustes do ClaudeBar"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
```

`SettingsView`: `@AppStorage` para cada chave; Seções "Avisos", "Som" (Pickers `.disabled(!soundEnabled)`, `.onChange { _, name in notifier.preview(name, for: alert) }`) e "Sistema" com o botão Sobre:

```swift
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "ClaudeBar",
                        .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                        .credits: NSAttributedString(string: "Sem rede, sem login. Não lê suas conversas."),
                    ])
```

## Testes obrigatórios

Em `AlertTests` (com o helper `scratchDefaults()`): `tipoDesligadoNosAjustesNaoAvisa` (mutação: sem o guard por tipo, falha), `somVemDosAjustes`, `listaDeSonsTemOsPadroes` (os 4 sons padrão: `Glass`, `Submarine`, `Purr`, `Basso`; nenhum com `.aiff`). Todos `@MainActor`. `permissaoEEsperaDividemOToggle`: `Alert.permission.enabledKey == Alert.waiting.enabledKey`.

## Critérios de aceite

- Primeira instrução de `post`: `guard isEnabled, defaults.bool(forKey: alert.enabledKey)`.
- Nenhuma cópia em memória das preferências no `Notifier` (só leituras de `defaults`, o `register` e as declarações).
- Sem `SettingsLink`, `openSettings`, `showSettingsWindow:`, `setActivationPolicy`, `Task.sleep`; nenhuma dependência nova.
- O toggle geral **não** é repetido na janela.
- `swift test` = anterior + 4. Passos manuais registrados (o 9, macOS 14, como "não verificado" se não houver máquina).

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

"The menu": `Ajustes…   ⌘,`. "Alerts": bullet da spec sobre a janela; sons padrão marcados "(default)". Project structure: `SettingsWindow.swift   settings window (NSWindow, not the Settings scene)`.

## Riscos

| Risco | Mitigação |
|---|---|
| Janela abre atrás | `orderFrontRegardless`; plano `.floating` |
| Som salvo que sumiu do macOS | `NSSound(named:)` nil → sai calado |
| Mudar o som de "esperando" muda o de "permissão" | documentado: os dois compartilham `soundWaiting` |

## Fora do escopo

Cena `Settings`/SettingsAccess; activation policy `.regular`; sons de `~/Library/Sounds`; ícone no Sobre (T32); abrir no login (T25); lembrete (T26); modo sem conteúdo (T27).
