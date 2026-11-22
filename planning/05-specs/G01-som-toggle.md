# G01 — Spec técnica: som respeita o toggle (F01)

Insumos: `04-como-fazer/G01-som-toggle.md`, `03-validacao/BACKLOG.md` (F01: P0, P, bug, sem dependência), `00-PLANO.md` (guard rails).
Código lido em 2026-11-15 (`main` @ f943cc4).

**Verificado nesta spec:** o diff abaixo foi aplicado numa cópia do projeto real (não num protótipo reduzido), com Swift 6.3.3 / tools 6.0:
- `swift build`: 0 avisos. `swift test`: 35 testes passam (34 atuais + o novo).
- Com o guard de volta abaixo do som (o bug), o teste novo falha: `tocados → [.finished, .waiting]`. Ou seja, o teste pega a regressão.

Isso fecha o item "o protótipo compilou numa cópia reduzida" da pesquisa.

## Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/Notifier.swift` | guard antes do som; `init(defaults:playSound:)` |
| `Tests/ClaudeBarTests/AlertTests.swift` | 1 teste novo |
| `README.md` | seção "Alerts", bullet do toggle |

Não toca: `SessionStore.swift`, `MenuContent.swift`, `StatusHUD.swift`, `ClaudeBarCore`, `claudebar-hook`, `scripts/`, `Package.swift`.
Conflito provável com: F15 (mesmo `Notifier.swift` e mesmo toggle) — F15 já depende de F01, então ordem natural.

---

## F01 — Som respeita o toggle

### Objetivo

Com o toggle **Notificações** desligado, nenhum aviso sai: nem popup, nem notificação nativa, nem som. Hoje `Notifier.post` chama `play(alert)` antes de `guard isEnabled`, então o som toca com o toggle desligado.

### Decisão técnica

Mover `guard isEnabled else { return }` para a primeira linha de `post(_:body:)`. Todos os chamadores passam por ali (`SessionStore.notifyTransitions` l. 174 e 179; `showSample` l. 107), então um guard só cobre todos. O toggle continua sendo um só e desliga popup e som juntos; nenhuma chave nova em `UserDefaults`.

Para testar sem tocar som e sem sujar `UserDefaults.standard`: `init` ganha dois parâmetros opcionais com padrão, `defaults` e `playSound`. `SessionStore` continua com `Notifier()`, sem mudança.

Alternativas descartadas:
- Só mover o guard, sem teste: o backlog pede teste, e um reordenamento futuro voltaria sem aviso.
- Guard em cada chamador do `SessionStore`: dois lugares em vez de um, e `showSample` ficaria de fora.
- Função pura `effects(enabled:)` testada à parte: não pega a ordem dentro de `post`, que é onde o bug está.
- Chave de som separada (`soundEnabled`) agora: é o F15; criaria UI que o F15 substitui (YAGNI).
- Protocolo `SoundPlayer` + implementação fake: protocolo com uma implementação real é abstração especulativa; uma closure opcional basta.
- `sound.stop()` ao desligar: os sons do sistema duram cerca de 1 s. Não vale o código.

### Código — `Sources/ClaudeBar/Notifier.swift`

Propriedades (substitui `private let defaults = UserDefaults.standard`):

```swift
    private let isBundled = Bundle.main.bundleIdentifier != nil
    private let defaults: UserDefaults
    /// Só para teste: observa o som em vez de tocar. `nil` toca de verdade.
    private let soundOverride: (@MainActor (Alert) -> Void)?
    private let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "notifications")
```

`init` (o corpo atual continua igual depois das duas atribuições):

```swift
    init(defaults: UserDefaults = .standard, playSound: (@MainActor (Alert) -> Void)? = nil) {
        self.defaults = defaults
        soundOverride = playSound
        // Padrão ligado: quem instalou um app de aviso quer ser avisado.
        defaults.register(defaults: [Self.enabledKey: true])
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        ...
```

Início de `post` (o resto da função não muda):

```swift
    func post(_ alert: Alert, body: String) {
        // Desligado no menu = silêncio total: nem popup nem som.
        guard isEnabled else { return }

        if let soundOverride {
            soundOverride(alert)
        } else {
            play(alert)
        }

        guard canUseSystemNotifications else {
            // Caminho normal com assinatura ad-hoc: popup desenhado pelo app.
            hud.show(alert, body: body)
            return
        }
        ...
```

Por que closure opcional e não `= play`: um argumento padrão não pode referenciar `self`. `play(_:)` e o cache `sounds` ficam como estão.

O comentário existente no bloco da notificação nativa ("quem toca é o `NSSound` acima") continua correto.

### Teste — `Tests/ClaudeBarTests/AlertTests.swift`

Dentro da `@Suite("Avisos sonoros")` existente, depois de `cadaAvisoTemSeuTitulo`:

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

Detalhes que importam:
- `@MainActor` é obrigatório: `Notifier` é `@MainActor` e o Swift Testing roda em task arbitrária por padrão.
- `setEnabled(false)` explícito: suítes de `UserDefaults` compartilham o domínio de registro, então não dá para contar com o padrão.
- `setEnabled(false)` chama `hud.dismiss()`, que é seguro com `panel == nil` (o `NSPanel` só nasce no primeiro `show`).
- `init` com `isEnabled == true` chama `requestAuthorization()`, que retorna no `guard isBundled` (sob `swift test`, `bundleIdentifier` é nil). Sem esse guard o processo de teste cai em `UNUserNotificationCenter.current()`.

**Não** testar o caso "ligado toca" no `Notifier` real: ele cairia em `hud.show` e criaria um `NSPanel` no processo de teste. Não confirmado se é frágil; o F01 não precisa desse caso. Adiar.

### README

Em "Alerts", trocar o bullet do toggle por:

```markdown
- The **Notificações** toggle in the menu turns alerts on and off — popup and
  sound together. The choice is saved in `UserDefaults` and is on by default.
```

(Remove a frase "Note: in the current code the sound still plays when the toggle is off ...".) A linha da árvore de arquivos (`Notifier.swift  sound per alert, toggle, ...`) continua certa. Scripts: nenhuma mudança.

### Verificação

Gate (00-PLANO): `swift build && swift test` verdes. Não precisa de `scripts/build-app.sh`: não mexe em bundle, recursos, hook nem assinatura.

Manual (opcional, com o app instalado via `scripts/install.sh`):
1. Menu → desligar **Notificações**. "Ver exemplo de popup" some do menu.
2. Numa sessão do Claude Code, mandar um prompt e esperar terminar → sem som `Glass`, sem popup.
3. Provocar um pedido de permissão (ex.: comando Bash fora da allowlist) → sem som `Submarine`, sem popup.
4. Religar **Notificações** e repetir o passo 2 → toca `Glass` e aparece o popup.
5. Sair e reabrir o app → o toggle mantém o último estado.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Teste chamar `UNUserNotificationCenter` e derrubar o processo | Manter o `guard isBundled` em `requestAuthorization`/`refreshAuthorization`; não chamar `UNUserNotificationCenter` fora dele. Revisão deve recusar remoção. |
| Teste vazar estado para o app real | Suíte `UserDefaults` descartável com `removePersistentDomain` no `defer`; nunca `.standard` no teste. |
| `NSSound` fora do main thread (thread-safety não documentada) | Nada muda: `play` continua no `Notifier` `@MainActor`. Não mover som para fila própria (como faz o Nudgy). |
| Alguém reordenar o `post` de novo | O teste novo falha nesse caso (verificado). |
| Usuário esperar som com popup desligado | Comportamento agora documentado no README; separar som é o F15. |

### Critérios de aceite

- Em `Notifier.post`, `guard isEnabled else { return }` é a primeira instrução, antes de qualquer som, `hud.show` ou `UNUserNotificationCenter`.
- `desligadoNaoTocaSom` existe, passa, e falha se o guard voltar para baixo do som.
- `swift build` sem avisos novos; `swift test` com 35 testes passando e nenhum removido.
- `SessionStore.swift` e `MenuContent.swift` sem diff.
- Nenhuma chave nova em `UserDefaults` (`notificationsEnabled` continua a única).
- README sem a frase do bug, dizendo que o toggle desliga popup e som.

### O que NÃO fazer

- Não criar chave/toggle de som separado (F15).
- Não criar protocolo/fake de som, nem tornar `Notifier` não-`@MainActor`.
- Não remover nem contornar o `guard isBundled`.
- Não testar o caminho "ligado" com `hud.show` real.
- Não mexer em Foco/Não Perturbar (E4, fora do escopo).
- Não copiar o teste do Nudgy (`testSoundDisabledDoesNotPlay`): não tem `#expect` e passa com o bug.
- Não tocar em hook, `scripts/`, `Info.plist` ou assinatura.

### Esforço

~0,5 h (diff já validado; inclui README e PR).
