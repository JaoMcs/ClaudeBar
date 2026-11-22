# G01 — Som respeita o toggle (F01)

Pesquisa de implementação. Backlog: F01 (P0, tamanho P, bug, sem dependência). Origem: E1 nas lentes de valor, viabilidade e risco.

## Ponto de partida (lido no código, 2026-11-15)

- `Sources/ClaudeBar/Notifier.swift`, `post(_:body:)`: `play(alert)` na linha 111, `guard isEnabled else { return }` na linha 113. Com o toggle desligado o `NSSound` toca e só o popup é suprimido.
- Quem chama `post`: `SessionStore.notifyTransitions` (l. 174 e 179) e `Notifier.showSample()` (l. 107). Este último só aparece no menu quando `state != .off`, então na prática o bug vem só do `SessionStore`. Os dois caminhos passam por `post`, então o guard ali cobre todos.
- `MenuContent.swift` l. 52: um único `Toggle("Notificações")` ligado a `isEnabled`. A chave em `UserDefaults` é `notificationsEnabled`, com padrão `true`.
- O README (seção "Alerts") documenta o bug: "Note: in the current code the sound still plays when the toggle is off".
- Testes: `Tests/ClaudeBarTests/AlertTests.swift` cobre só o enum `Alert`. Nenhum teste instancia `Notifier`.

## Decisão de semântica

**Recomendo: no F01, o toggle "Notificações" desliga popup e som juntos.** O F15 depois separa "terminou", "esperando" e "som" em chaves próprias.

Motivos:
- O título do E1 nas três lentes é "Desligar notificação desliga som", e a lente de valor diz que um som com o aviso desligado "quebra confiança".
- Hoje só existe um toggle. Separar o som agora significaria criar uma UI que o F15 vai substituir (YAGNI).
- Precedente: o Nudgy guarda o som numa chave separada (`nudgy.soundEnabled`) com seu próprio `guard isEnabled` em `play`. É o modelo para o F15, não para agora. Link: https://github.com/Hamma111/nudgy/blob/main/Sources/Nudge/Services/SoundManager.swift
  ```swift
  func play(_ effect: SoundEffect) {
      guard isEnabled else { return }
  ```
- Compatibilidade com o F15: a chave `notificationsEnabled` pode virar o "mestre" (desliga tudo), ou ser migrada para as chaves novas. Isso fica para o F15 decidir. O F01 não cria chave nova, então não há nada a migrar.

## Como fazer (diff mínimo)

### 1. Correção, uma linha movida

```swift
func post(_ alert: Alert, body: String) {
    guard isEnabled else { return }
    playSound(alert)        // antes: play(alert), acima do guard
    guard canUseSystemNotifications else { ... }
```

Corrigir no `post` resolve para todos os chamadores. Não é preciso guard no `SessionStore`.

### 2. Ponto de injeção para o teste "desligado = silêncio"

O teste precisa observar se o som tocou, sem tocar som de verdade e sem usar `UserDefaults.standard`. O menor ponto de injeção:

```swift
private let defaults: UserDefaults
private let soundOverride: (@MainActor (Alert) -> Void)?

init(defaults: UserDefaults = .standard,
     playSound: (@MainActor (Alert) -> Void)? = nil) {
    self.defaults = defaults
    self.soundOverride = playSound
    ...
}

private func playSound(_ alert: Alert) {
    if let soundOverride { soundOverride(alert) } else { play(alert) }
}
```

A closure é opcional porque um argumento padrão não pode referenciar `self.play`. O cache `sounds` continua na instância. `SessionStore` continua chamando `Notifier()` sem mudança.

### 3. Teste (Swift Testing, como o resto da suíte)

```swift
@MainActor @Test func desligadoNaoTocaSom() throws {
    let suite = "claudebar.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var tocados: [Alert] = []
    let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
    notifier.setEnabled(false)
    notifier.post(.finished, body: "x")
    notifier.post(.waiting, body: "y")
    #expect(tocados.isEmpty)
}
```

**Verificado localmente** com um protótipo num pacote de rascunho (Swift 6.3.3, tools 6.0, modo Swift 6): o mesmo formato de `init(defaults:playSound:)`, a captura de `var tocados` numa closure `@MainActor` e o teste `@MainActor @Test` compilam sem aviso e passam. O teste também conferiu o caso ligado (`tocados == [.finished]`). No `Notifier` real esse caso chamaria `hud.show`, que cria um `NSPanel` dentro do processo de teste. Por isso recomendo testar só o caso desligado, que é o que o F01 pede. Que o caso ligado seja frágil é SUPOSIÇÃO: não testei.

Não copiar o teste do Nudgy (`testSoundDisabledDoesNotPlay`): ele chama `play` sem nenhum `#expect` ou `XCTAssert`, então passa até com o bug. Link: https://github.com/Hamma111/nudgy/blob/main/Tests/NudgeTests/SoundManagerTests.swift

### 4. README

Apagar a frase "Note: in the current code the sound still plays..." e dizer que o toggle desliga popup e som. Isso não está na regra "não regredir", mas é a doc do bug.

## Armadilhas

| Armadilha | Status | Detalhe |
|---|---|---|
| `UNUserNotificationCenter.current()` sob `swift test` derruba o processo | **CONFIRMADO localmente** | No protótipo, `Bundle.main.bundleIdentifier` foi `nil` (o runner é `swiftpm-testing-helper`) e `current()` lançou `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil`. O `Notifier` já está protegido porque `isBundled` é falso no teste e `requestAuthorization` e `refreshAuthorization` dão guard nele. **Não remover esse guard** e não chamar `UNUserNotificationCenter` fora dele. |
| Swift Testing não roda no main actor por padrão | **CONFIRMADO (Apple)** | "the testing library runs all test functions on an arbitrary task. If a test function must run on the main thread, isolate it to the main actor with @MainActor". `Notifier` é `@MainActor`, então o teste precisa de `@MainActor`. Fonte: https://developer.apple.com/documentation/testing/migratingfromxctest |
| `UserDefaults(suiteName:)` não isola o domínio de registro | **CONFIRMADO (Apple)** | "Every instance of UserDefaults shares the contents of the argument and registration domains." O `register(defaults:)` do `Notifier` vale para o processo todo, o que é inofensivo porque o valor é o mesmo. O teste precisa gravar `setEnabled(false)` explicitamente, como acima, e não depender do padrão. Fonte: https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:) |
| `NSSound` fora do main thread | Cuidado | O Nudgy toca numa `DispatchQueue` própria com `@unchecked Sendable`. Não copiar: o `Notifier` já é `@MainActor` e `play()` é assíncrono por natureza ("initiates playback asynchronously and returns control to your application", https://developer.apple.com/documentation/appkit/nssound/play()). No SDK local, `NSSound.h` só marca o método de delegate `didFinishPlaying` como `NS_SWIFT_UI_ACTOR`. A classe em si não é marcada. |
| Som pela notificação nativa | **CONFIRMADO (Apple)** | `UNMutableNotificationContent.sound` é `UNNotificationSound?`. O código já não define som ali, e "If your app isn't authorized to play sounds for notifications, the system ignores this property". Então com o toggle desligado o caminho nativo também fica mudo, porque o `post` retorna antes. Fonte: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/sound |
| Foco / Não Perturbar | Fora do escopo (E4) | O `NSSound` próprio ignora o Foco. Isso é o E4 ("depois"). O F01 não muda nada aqui. |
| LSUIElement / assinatura ad-hoc / bundle | Sem impacto | A mudança não mexe em bundle nem em recursos. Pelos guard rails do 00-PLANO basta `swift build` e `swift test` verdes, sem precisar rodar `scripts/build-app.sh`. |
| Hooks / statusline / settings do Claude Code | Sem impacto | O F01 é só app. O payload do hook não muda. |

## Alternativas consideradas

1. **Só mover o guard, sem teste.** É a menor mudança, mas o backlog pede teste e uma regressão (alguém reordenar de novo) voltaria sem aviso. Rejeitada.
2. **Extrair uma função pura `effects(enabled:) -> (som, popup)` e testar só ela.** É testável sem instanciar o `Notifier`, mas o bug estava na ordem dentro de `post`, e uma função pura ao lado não pegaria essa ordem. Rejeitada.
3. **Chave de som separada já no F01.** Antecipa o F15 e exige UI nova. Rejeitada (YAGNI). Fica no F15.
4. **Parar o som em andamento ao desligar o toggle (`sound.stop()` em `setEnabled(false)`).** Os sons do sistema duram cerca de 1 s. Pulado; adicionar se alguém reclamar.

**Recomendada:** guard antes do som em `post`, com um ponto de injeção opcional `init(defaults:playSound:)` e um teste `@MainActor` "desligado = silêncio" usando um `UserDefaults` de suíte descartável.

## Não confirmado / suposições

- SUPOSIÇÃO: o caso "ligado toca", testado no `Notifier` real, é frágil porque `hud.show` cria um `NSPanel` no processo de teste. Não testei.
- SUPOSIÇÃO: os nomes `playSound` e `soundOverride` são sugestões. Não são API da Apple.
- O protótipo compilou numa cópia reduzida do `Notifier`, não no arquivo real. A compilação no projeto real ainda não foi feita.
- Não achei, em fonte oficial da Apple, documentação dizendo que `NSSound` é thread-safe ou que exige o main thread. A recomendação de manter no `@MainActor` vem do código atual, não de uma regra documentada.
- Concorrentes citados na busca (ClaudeDot, ClaudioBar, claude-notify) têm toggle de som segundo os READMEs ou listagens, mas só o código do Nudgy foi lido.
