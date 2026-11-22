# T01 — Som respeita o toggle de notificações

- **Funcionalidade:** F01 — spec [G01](../05-specs/G01-som-toggle.md)
- **Épico:** Base/Bugs · **Prioridade:** P0 · **Esforço:** 0,5 h
- **Depende de:** — · **Bloqueia:** T13, T21, T24 (mesmo `Notifier.post`)
- **Branch:** `fix/som-respeita-toggle`
- **PR:** `fix: som respeita o toggle de notificações`

## Objetivo

Com **Notificações** desligado no menu, nada sai: nem popup, nem notificação nativa, nem som. Hoje `Notifier.post` chama `play(alert)` antes do `guard isEnabled`.

## Subtasks

- [ ] `git fetch && git switch -c fix/som-respeita-toggle origin/main`
- [ ] `Notifier`: trocar `private let defaults = UserDefaults.standard` por `private let defaults: UserDefaults` e acrescentar `soundOverride`.
- [ ] `init(defaults: UserDefaults = .standard, playSound: (@MainActor (Alert) -> Void)? = nil)`; o resto do corpo do `init` fica igual.
- [ ] `post`: `guard isEnabled else { return }` vira a **primeira** instrução; som via `soundOverride` ou `play`.
- [ ] Teste `desligadoNaoTocaSom` na suíte "Avisos sonoros".
- [ ] Conferir a mutação: guard de volta abaixo do som → o teste falha. Desfazer.
- [ ] README e README.pt-BR (seção Alerts).
- [ ] Gates, commit, push, `gh pr create`.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/Notifier.swift` | guard antes do som; `init(defaults:playSound:)` |
| `Tests/ClaudeBarTests/AlertTests.swift` | 1 teste |
| `README.md`, `README.pt-BR.md` | bullet do toggle |

Não toca `SessionStore.swift`, `MenuContent.swift`, Core, hook, scripts.

## Código-chave (da spec)

```swift
    private let isBundled = Bundle.main.bundleIdentifier != nil
    private let defaults: UserDefaults
    /// Só para teste: observa o som em vez de tocar. `nil` toca de verdade.
    private let soundOverride: (@MainActor (Alert) -> Void)?

    init(defaults: UserDefaults = .standard, playSound: (@MainActor (Alert) -> Void)? = nil) {
        self.defaults = defaults
        soundOverride = playSound
        // Padrão ligado: quem instalou um app de aviso quer ser avisado.
        defaults.register(defaults: [Self.enabledKey: true])
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        // … resto igual …
    }

    func post(_ alert: Alert, body: String) {
        // Desligado no menu = silêncio total: nem popup nem som.
        guard isEnabled else { return }

        if let soundOverride {
            soundOverride(alert)
        } else {
            play(alert)
        }

        guard canUseSystemNotifications else {
            hud.show(alert, body: body)
            return
        }
        // … resto igual …
```

Closure opcional, e não `= play`: argumento padrão não pode referenciar `self`.

## Testes obrigatórios

```swift
    /// Toggle "Notificações" desligado não pode tocar som (F01).
    @MainActor @Test func desligadoNaoTocaSom() throws {
        let suite = "claudebar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var tocados: [Alert] = []
        let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
        notifier.setEnabled(false)

        notifier.post(.finished, body: "projeto")
        notifier.post(.waiting, body: "Claude needs your permission to use Bash")

        #expect(tocados.isEmpty)
    }
```

`@MainActor` obrigatório; `setEnabled(false)` explícito (o domínio de registro é do processo). Nunca usar `.standard` em teste.

## Critérios de aceite

- `guard isEnabled else { return }` é a primeira instrução de `post`.
- `desligadoNaoTocaSom` passa e falha com o guard abaixo do som (mutação conferida).
- `swift test`: 35 testes (34 + 1), nenhum removido. `SessionStore.swift` e `MenuContent.swift` sem diff.
- Nenhuma chave nova em `UserDefaults`.
- README sem a frase "Note: in the current code the sound still plays when the toggle is off".

## Gates

`swift build` (sem aviso novo) e `swift test`. Não mexe em bundle: `build-app.sh` não é obrigatório.

## README

Em "Alerts" (as duas línguas):

```markdown
- The **Notificações** toggle in the menu turns alerts on and off — popup and
  sound together. The choice is saved in `UserDefaults` and is on by default.
```

## Riscos

- Teste chamar `UNUserNotificationCenter` e derrubar o processo: manter o `guard isBundled` em `requestAuthorization`/`refreshAuthorization`.
- Teste sujar o `UserDefaults` real: suíte descartável + `removePersistentDomain`.

## Fora do escopo

Toggle de som separado (T24), protocolo/fake de som, testar o caminho "ligado" com `hud.show` real, Foco/Não Perturbar, hook, scripts.
