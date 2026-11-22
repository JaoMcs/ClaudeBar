# G10 — Spec técnica: Ajustes mínimos (F15) e modo "nunca mostrar conteúdo" (F25)

Insumos: `04-como-fazer/G10-ajustes-privacidade.md` (pesquisa), `03-validacao/BACKLOG.md` (F15: M, depende de F01; F25: P, depende de F15), `00-PLANO.md` (guard rails), `05-specs/G01-som-toggle.md` (F01, que esta spec pressupõe aplicada).
Código lido em 2026-11-15 (`chore/ci-github-actions` @ 3561ab8, igual a `main` em `Sources/` e `Tests/`).

**Verificado nesta spec:** todo o código abaixo (F01 + F15.1 + F15.2 + F25 juntos) foi aplicado numa cópia do projeto real, com Swift 6.3.3 / tools 6.0 / SDK macOS 26:
- `swift build`: 0 avisos. `swift test`: 41 testes passam (34 atuais + 1 do F01 + 6 desta spec).
- Mutação: sem o guard por tipo em `post`, o teste `tipoDesligadoNosAjustesNaoAvisa` falha (`tocados → [.finished]`).
- **Não verificado:** a aparência da janela, a ordem real das janelas na tela e o login item (precisam de teste manual, ver cada seção).

## Visão geral para o gestor

Três PRs, nesta ordem (todos mexem em `SettingsWindow.swift` e/ou `Notifier.swift`, então sequenciais):

| Id | Entrega | Arquivos | Esforço |
|---|---|---|---|
| **F15.1** | Janela de Ajustes: avisar por tipo, som on/off, escolha do som com prévia, Sobre | cria `Sources/ClaudeBar/SettingsWindow.swift`; altera `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/AlertTests.swift`, `README.md`, `README.pt-BR.md` | 2,5 h |
| **F15.2** | Abrir no login (`SMAppService.mainApp`) — **só entra se passar no teste manual com ad-hoc** | `Sources/ClaudeBar/SettingsWindow.swift`, `README.md`, `README.pt-BR.md` (+ `PENDENCIAS.md` no plano B) | 1,5 h |
| **F25** | Modo "nunca mostrar conteúdo" | `Sources/ClaudeBar/SessionRow.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/SettingsWindow.swift`, `Tests/ClaudeBarTests/AlertTests.swift`, `README.md`, `README.pt-BR.md` | 1 h |

Não tocam: `ClaudeBarCore`, `claudebar-hook`, `scripts/`, `Package.swift`, `StatusHUD.swift`, `ClaudeBarApp.swift`.

Ordem: **F01 → F15.1 → F15.2 → F25** (F25 pode vir antes de F15.2; os dois só se cruzam em `SettingsWindow.swift`).

Conflitos com outras specs:
- **F13 (lembrete, G09):** o toggle e os minutos do lembrete entram na `SettingsView` (seção "Avisos"), não no menu. O texto do lembrete deve usar `row.waitingBody(hidingContent:)` do F25 (ver F25).
- **F07.2 (aviso de erro, G06) e F24 (permissão × pergunta):** cada `case` novo em `Alert` precisa de `enabledKey` e `soundKey`. Os `switch` são exaustivos, então o build obriga. Cada um ganha um Picker na `SettingsView` e uma entrada no `register(defaults:)`.
- **F12 (popup persistente):** mexe em `StatusHUD`/`post`, mas não nas mesmas linhas.
- **F21 (idiomas):** as strings novas de `SettingsWindow.swift` entram na extração.
- **F38:** qualquer exibição futura de conteúdo lê `notifier.hidesContent`.

---

## F15.1 — Janela de Ajustes

### Objetivo

Um item **Ajustes… ⌘,** no menu abre uma janela, na frente das outras, com:
- avisar quando terminar (liga/desliga),
- avisar quando estiver esperando você (liga/desliga),
- tocar som (liga/desliga, sem desligar o popup),
- som de cada aviso, entre os sons do sistema, com prévia ao trocar,
- botão **Sobre o ClaudeBar** (painel padrão do macOS).

O toggle **Notificações** do menu continua sendo o interruptor geral (F01: desligado = silêncio total).

### Decisão técnica e por quê

- **`NSWindow` + `NSHostingController` próprios, não a cena `Settings`.** Num app accessory, `SettingsLink`/`openSettings` dentro de `MenuBarExtra` `.menu` abre a janela atrás do app da frente (fórum da Apple 731628, 836619). A correção conhecida usa identificador privado, delays e troca de activation policy. Com a janela na mão, `orderFrontRegardless()` coloca a janela na frente mesmo com o app inativo (doc oficial). É o mesmo padrão do `StatusHUD`.
  - Descartada: cena `Settings` + `SettingsLink`/`openSettings`. Abre atrás, e não há onde pôr código antes ou depois do clique no estilo `.menu`.
  - Descartada: SettingsAccess (orchetect). Dependência nova para 3 linhas, e não garante a ordem no macOS 26.
  - Descartada: `Window(id:)` + `openWindow`. `.defaultLaunchBehavior(.suppressed)` só existe a partir do macOS 15, e o alvo é 14 (risco de abrir sozinha no launch, não confirmado).
  - Descartada: `NSApp.sendAction("showSettingsWindow:")`. Parou no Sonoma.
- **`enum SettingsWindow` com `static var window`, `@MainActor`.** Há uma janela só e nenhum estado além dela, então não precisa de classe nem de instância guardada no `ClaudeBarApp`/`AppDelegate`.
- **Janela fechada → janela nova; aberta → só traz para a frente.** O estado da view (inclusive o login item do F15.2) é relido a cada abertura, sem `onAppear` em janela reaproveitada.
- **`isReleasedWhenClosed = false` explícito.** Isso resolve o item não confirmado da pesquisa: qualquer que seja o padrão sob ARC, quem mantém a janela viva é a `static var`.
- **Preferências em `UserDefaults`, lidas pelo `Notifier` na hora do `post`.** A view escreve com `@AppStorage`; o `Notifier` lê `defaults.bool(forKey:)` a cada aviso, sem cópia, então não há estado duplicado para sincronizar.
  - O interruptor geral (`notificationsEnabled`) **continua só no menu**, com o `isEnabled` armazenado e `@Observable` de hoje. Ter o mesmo valor em dois lugares (menu via `Notifier`, janela via `@AppStorage`) criaria dois escritores e o menu ficaria velho. Por isso a janela não repete esse toggle.
  - Descartada: tornar o `isEnabled` computado. O menu depende da observação do `@Observable`, e um computado sobre `UserDefaults` não é observado.
- **Semântica:** geral desligado → nada. Tipo desligado → nada daquele tipo, nem som. Som desligado → popup sem som. Uma regra por chave, sem combinações escondidas.
- **Lista de sons = `contentsOfDirectory("/System/Library/Sounds")` sem extensão.** `NSSound(named:)` prefere o nome sem extensão (doc). Não há API pública que liste os sons do sistema. Ler o diretório acompanha o SO, e um nome salvo que sumir dá `NSSound` nulo, que o `play` já trata saindo calado.
  - Descartada: lista fixa dos 14 nomes. Mesma quantidade de código e fica velha.
  - Descartada: incluir `~/Library/Sounds`. Ninguém pediu (YAGNI).
- **Prévia:** `.onChange` do Picker chama `notifier.preview(nome, for:)` com o valor novo recebido no closure, sem depender da ordem entre a escrita do `@AppStorage` e o `onChange`. A prévia toca mesmo com o som desligado, porque é uma ação explícita (e o Picker fica desabilitado nesse caso).
- **Sobre = `orderFrontStandardAboutPanel(options:)` chamado de um botão dentro da janela de Ajustes, não do menu.** O clique veio da nossa janela, então o app já está ativo e o painel abre na frente. Isso elimina o item não confirmado "painel atrás num app accessory". Nome e versão vão nas opções (`.applicationName`, `.applicationVersion` a partir do `Info.plist`, `"dev"` sem bundle), o que elimina o outro item não confirmado ("vem sozinho do Info.plist?").
  - Descartada: item "Sobre" no próprio menu. Num app inativo cai no mesmo problema de ordem de janelas, sem referência à janela do painel.
  - Descartada: só uma linha de versão no rodapé. O backlog (A13) pede o painel padrão, e o custo é o mesmo.

### Código

#### `Sources/ClaudeBar/Notifier.swift` (sobre o estado pós-F01)

No `enum Alert`, depois de `soundName`:

```swift
    /// Chave em `UserDefaults` do "avisar" deste tipo (Ajustes).
    var enabledKey: String {
        switch self {
        case .finished: "notifyFinished"
        case .waiting: "notifyWaiting"
        }
    }

    /// Chave em `UserDefaults` do som escolhido para este tipo (Ajustes).
    var soundKey: String {
        switch self {
        case .finished: "soundFinished"
        case .waiting: "soundWaiting"
        }
    }
```

`Alert.soundName` continua existindo e passa a ser o **padrão** de cada tipo (os testes atuais continuam valendo).

Na classe, junto de `enabledKey`:

```swift
    private static let enabledKey = "notificationsEnabled"
    static let soundEnabledKey = "soundEnabled"

    /// Sons do sistema, sem extensão — é como o `NSSound(named:)` prefere o nome.
    /// Lidos do disco para acompanhar o que o macOS instalado tiver.
    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()
```

No `init(defaults:playSound:)` do F01, o `register` passa a ser:

```swift
        // Padrão ligado: quem instalou um app de aviso quer ser avisado.
        defaults.register(defaults: [
            Self.enabledKey: true,
            Self.soundEnabledKey: true,
            Alert.finished.enabledKey: true,
            Alert.waiting.enabledKey: true,
            Alert.finished.soundKey: Alert.finished.soundName,
            Alert.waiting.soundKey: Alert.waiting.soundName,
        ])
```

Antes de `showSample`:

```swift
    /// Som a tocar para o aviso, ou `nil` com o som desligado nos Ajustes.
    func soundName(for alert: Alert) -> String? {
        guard defaults.bool(forKey: Self.soundEnabledKey) else { return nil }
        return defaults.string(forKey: alert.soundKey) ?? alert.soundName
    }

    /// Toca o som escolhido nos Ajustes, para você ouvir antes de decidir.
    func preview(_ soundName: String, for alert: Alert) {
        play(soundName, volume: alert.volume)
    }
```

Início de `post` (troca o bloco do F01; o resto da função não muda):

```swift
    func post(_ alert: Alert, body: String) {
        // Desligado no menu, ou este tipo desligado nos Ajustes = silêncio total.
        guard isEnabled, defaults.bool(forKey: alert.enabledKey) else { return }

        if let soundName = soundName(for: alert) {
            if let soundOverride {
                soundOverride(alert)
            } else {
                play(soundName, volume: alert.volume)
            }
        }

        guard canUseSystemNotifications else {
```

`play` passa a receber nome e volume (o cache `sounds` já era indexado por nome):

```swift
    private func play(_ name: String, volume: Float) {
        // O NSSound é reaproveitado por nome; tocar de novo enquanto ainda soa
        // não faz nada, então rebobina antes. Nome que sumiu do sistema dá
        // `nil` e o aviso sai calado, sem quebrar.
        let sound = sounds[name] ?? NSSound(named: name)
        guard let sound else { return }
        sounds[name] = sound

        if sound.isPlaying {
            sound.stop()
        }
        sound.volume = volume
        sound.play()
    }
```

#### `Sources/ClaudeBar/SettingsWindow.swift` (novo)

```swift
import AppKit
import SwiftUI

/// Janela de Ajustes, aberta pelo item "Ajustes…" do menu.
///
/// `NSWindow` próprio em vez da cena `Settings`: num app accessory, o
/// `SettingsLink`/`openSettings` dentro de um `MenuBarExtra` `.menu` abre a
/// janela atrás do app da frente, e a correção conhecida depende de
/// identificador privado e de delays. Aqui a janela está na mão, e
/// `orderFrontRegardless` traz para a frente mesmo com o app inativo.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(notifier: Notifier) {
        // Fechada = janela nova, com estado relido (inclusive o login item).
        // Aberta = só traz para a frente.
        if window?.isVisible != true {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(notifier: notifier)
            ))
            window.title = "Ajustes do ClaudeBar"
            window.styleMask = [.titled, .closable]
            // Quem mantém a janela viva é a referência acima; sem isso o
            // `close()` a liberaria por conta própria.
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        // `activate()` não garante ativação (é cooperativa no macOS 14+);
        // `orderFrontRegardless` garante a janela visível na frente.
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Conteúdo da janela de Ajustes. Tudo fica em `UserDefaults`; o `Notifier` lê
/// cada valor na hora do aviso, então não há cópia para sincronizar.
private struct SettingsView: View {
    let notifier: Notifier

    @AppStorage(Alert.finished.enabledKey) private var notifyFinished = true
    @AppStorage(Alert.waiting.enabledKey) private var notifyWaiting = true
    @AppStorage(Notifier.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Alert.finished.soundKey) private var soundFinished = Alert.finished.soundName
    @AppStorage(Alert.waiting.soundKey) private var soundWaiting = Alert.waiting.soundName

    var body: some View {
        Form {
            Section("Avisos") {
                Toggle("Avisar quando o Claude terminar", isOn: $notifyFinished)
                Toggle("Avisar quando o Claude esperar você", isOn: $notifyWaiting)
            }

            Section("Som") {
                Toggle("Tocar som", isOn: $soundEnabled)
                soundPicker("Terminou", selection: $soundFinished, alert: .finished)
                soundPicker("Esperando você", selection: $soundWaiting, alert: .waiting)
            }

            Section("Sistema") {
                Button("Sobre o ClaudeBar") {
                    // O clique veio desta janela, então o app já está ativo e o
                    // painel nasce na frente. Nome e versão passados à mão: sem
                    // bundle (`swift run`) não há Info.plist.
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "ClaudeBar",
                        .applicationVersion: Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "dev",
                        .credits: NSAttributedString(
                            string: "Sem rede, sem login. Não lê suas conversas."
                        ),
                    ])
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func soundPicker(_ title: String, selection: Binding<String>, alert: Alert) -> some View {
        Picker(title, selection: selection) {
            ForEach(Notifier.systemSounds, id: \.self) { Text($0) }
        }
        .disabled(!soundEnabled)
        .onChange(of: selection.wrappedValue) { _, name in
            notifier.preview(name, for: alert)
        }
    }
}
```

Notas de Swift 6: `SettingsWindow` e `SettingsView.body` ficam na `@MainActor`, assim como `Notifier`. `static var window` num `enum` `@MainActor` é isolado pelo ator global, sem erro de concorrência. `NSApplication.shared.activate()` existe a partir do macOS 14 (o alvo do pacote) e não gera aviso. **Não** trocar os `activate(ignoringOtherApps:)` do `SessionStore` neste PR (fora do escopo).

#### `Sources/ClaudeBar/MenuContent.swift`

Logo depois do bloco `if store.notifier.state != .off { … }` e antes do `Divider()` de "Atualizar":

```swift
        Button("Ajustes…") {
            SettingsWindow.show(notifier: store.notifier)
        }
        .keyboardShortcut(",")
```

### Testes — `Tests/ClaudeBarTests/AlertTests.swift`

Dentro da `@Suite("Avisos sonoros")`, junto do `desligadoNaoTocaSom` do F01 (que pode passar a usar o mesmo helper):

```swift
    /// Suíte de `UserDefaults` descartável: nunca `.standard` em teste.
    private func scratchDefaults() throws -> (UserDefaults, String) {
        let suite = "claudebar.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// "Avisar quando terminar" desligado nos Ajustes cala esse aviso, som
    /// incluído, com o toggle geral ligado (F15).
    @MainActor @Test func tipoDesligadoNosAjustesNaoAvisa() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var tocados: [Alert] = []
        let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
        notifier.setEnabled(true)
        defaults.set(false, forKey: Alert.finished.enabledKey)

        notifier.post(.finished, body: "projeto")

        #expect(tocados.isEmpty)
    }

    /// Som escolhido nos Ajustes vale no próximo aviso; som desligado = nenhum
    /// nome. Lido na hora, sem reiniciar o `Notifier` (F15).
    @MainActor @Test func somVemDosAjustes() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let notifier = Notifier(defaults: defaults, playSound: { _ in })
        defaults.set(true, forKey: Notifier.soundEnabledKey)
        #expect(notifier.soundName(for: .finished) == "Glass")

        defaults.set("Ping", forKey: Alert.finished.soundKey)
        #expect(notifier.soundName(for: .finished) == "Ping")
        #expect(notifier.soundName(for: .waiting) == "Submarine")

        defaults.set(false, forKey: Notifier.soundEnabledKey)
        #expect(notifier.soundName(for: .finished) == nil)
    }

    /// A lista do Picker tem os dois padrões, sem extensão (F15).
    @MainActor @Test func listaDeSonsTemOsPadroes() {
        #expect(Notifier.systemSounds.contains(Alert.finished.soundName))
        #expect(Notifier.systemSounds.contains(Alert.waiting.soundName))
        #expect(!Notifier.systemSounds.contains { $0.hasSuffix(".aiff") })
    }
```

Detalhes:
- `@MainActor` é obrigatório, inclusive em `listaDeSonsTemOsPadroes`: `systemSounds` herda o isolamento do `Notifier`. Sem ele, o build dá erro de isolamento (verificado).
- Valores setados explicitamente (`set(true, forKey: soundEnabledKey)`): o domínio de registro é do processo, então não dá para contar com o padrão.
- Não testar a `SettingsView` nem `SettingsWindow.show` (UI). Verificação manual.

### README / scripts

`README.md`, seção "The menu": acrescentar a linha `Ajustes…   ⌘,   (settings)` depois de "Ver exemplo de popup". Na seção "Alerts", acrescentar:

```markdown
- **Ajustes… (⌘,)** opens a settings window: turn each alert on or off, turn
  the sound off while keeping the popup, and pick each alert's sound from the
  macOS system sounds (it plays when you pick it). The menu toggle
  **Notificações** stays the master switch.
```

E na tabela de alertas, trocar "`Glass`" e "`Submarine`" por "`Glass` (default)" e "`Submarine` (default)". Em "Project structure", acrescentar `SettingsWindow.swift   settings window (NSWindow, not the Settings scene)`. Fazer o mesmo no `README.pt-BR.md`. Scripts: nenhuma mudança.

### Verificação manual

Com `./scripts/install.sh`:
1. Deixar outro app em foco (Terminal em tela cheia e depois janela normal). Menu → **Ajustes…** → a janela aparece **na frente**. Repetir com ⌘, com o menu aberto.
2. Com a janela aberta e atrás de outra, Menu → **Ajustes…** de novo → volta para a frente, sem segunda janela.
3. Fechar com o botão vermelho e reabrir → abre normalmente (sem crash, o que prova o `isReleasedWhenClosed`).
4. Trocar o som de "Terminou" → toca na hora. Desligar "Tocar som" → os Pickers ficam desabilitados.
5. "Ver exemplo de popup" com "Tocar som" desligado → popup sem som. Com "Avisar quando o Claude esperar você" desligado → nada.
6. Sessão real: terminar um prompt → toca o som escolhido.
7. **Sobre o ClaudeBar** → painel na frente com "ClaudeBar", versão "1.0" e a linha de créditos.
8. Sair e reabrir o app → as escolhas continuam.
9. Fazer os passos 1 e 7 no macOS 14 se houver um Mac ou VM disponível. Se não houver, registrar como "não verificado no 14".

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Janela abre atrás mesmo com `orderFrontRegardless` (ativação cooperativa) | `orderFrontRegardless` é documentado para app inativo. Se falhar no passo 1, aplicar `window.level = .floating` só enquanto abre. Não usar truques de activation policy. |
| Layout do `Form` (estilo `.columns`) feio ou cortado no `NSHostingController` | Verificação manual (passo 4). Plano B: `.formStyle(.grouped)` + `.frame(width: 420, height: 480)`. |
| Som salvo que não existe mais no macOS | `NSSound(named:)` → `nil` → `play` sai calado. O Picker mostra seleção vazia, e o usuário escolhe outro. |
| `@AppStorage` e `register(defaults:)` com padrões diferentes | Os dois usam `Alert.soundName` / `true`. O `register` roda no `init` do `Notifier`, que nasce com o `SessionStore` antes de qualquer janela. |
| Teste sujando o `UserDefaults` do app | Só suítes descartáveis, sempre com `removePersistentDomain`. |
| `post` com tipo ligado e som desligado cria `NSPanel` no teste | Nenhum teste exercita esse caminho. A regra do som fica coberta por `soundName(for:)`. |

### Critérios de aceite

- `swift build` sem avisos novos; `swift test` com F01 + 3 testes novos passando, nenhum removido.
- No `Notifier.post`, a primeira instrução é `guard isEnabled, defaults.bool(forKey: alert.enabledKey)`, antes de som, HUD e `UNUserNotificationCenter`.
- `tipoDesligadoNosAjustesNaoAvisa` falha se o guard por tipo for removido.
- Nenhum `Notifier` guarda cópia de `notifyFinished`/`notifyWaiting`/`soundEnabled`/`soundFinished`/`soundWaiting`: `grep -n "soundEnabledKey\|enabledKey\|soundKey" Sources/ClaudeBar/Notifier.swift` mostra só leituras de `defaults`, o `register` e as declarações.
- O código novo não usa `SettingsLink`, `openSettings`, `showSettingsWindow:`, `"com_apple_SwiftUI_Settings_window"`, `setActivationPolicy` nem `Task.sleep`.
- Nenhuma dependência nova no `Package.swift`.
- Passos 1 a 8 da verificação manual ok no macOS 26 (registrar no PR).

### O que NÃO fazer

- Não usar a cena `Settings` nem a dependência SettingsAccess.
- Não trocar a activation policy para `.regular` (o ícone aparece no Dock).
- Não repetir o toggle geral **Notificações** na janela.
- Não criar tipo `Preferences`/`SettingsStore`/protocolo: as chaves ficam em `Alert` e `Notifier`, onde são lidas.
- Não listar sons de `~/Library/Sounds` nem aceitar arquivo do usuário.
- Não adicionar ícone ao painel Sobre (é o F18).
- Não pôr o lembrete (F13) neste PR. Ele entra na `SettingsView` quando o F13 for feito.

---

## F15.2 — Abrir no login

### Objetivo

Um toggle **Abrir ao iniciar sessão no Mac** na janela de Ajustes, **desligado por padrão**, que mostra o estado real do sistema. Isso substitui a instrução manual do README ("System Settings → General → Login Items → add").

### Decisão técnica e por quê

- **`SMAppService.mainApp` (macOS 13+), com o estado sempre lido de `.status` e nunca guardado.** O usuário pode mudar o item em Ajustes do Sistema por fora. Mesmo padrão do LaunchAtLogin-Modern, sem adicionar a dependência (são 10 linhas).
  - Descartada: dependência LaunchAtLogin-Modern. Seria código de terceiro para 10 linhas.
  - Descartada: plist em `~/Library/LaunchAgents`. É legado e cria configuração persistente fora do controle do SO.
  - Descartada: guardar um `Bool` em `UserDefaults`. Ficaria divergente do sistema.
- **Mapeamento:** `.enabled` e `.requiresApproval` → ligado. `.requiresApproval` também mostra a nota e o botão `openSystemSettingsLoginItems()`. `.notRegistered` e `.notFound` → desligado. Erro de `register`/`unregister` → texto vermelho abaixo, sem esconder.
- **Releitura do estado:** ao abrir a janela (janela nova a cada abertura, F15.1) e em `NSApplication.didBecomeActiveNotification`, que cobre a volta de Ajustes do Sistema. Não existe aviso ou KVO conhecido para mudança feita por fora (não confirmado), e essa releitura cobre o caso sem depender disso.
- **`register()` só com clique.** Nunca no launch, nunca por padrão (A8, regra da App Store).

### Não confirmado → como se proteger

**Não se sabe se `SMAppService.mainApp` funciona com assinatura ad-hoc, nem se o registro sobrevive a um rebuild** (cdhash novo; há relatos de `notFound` e de itens duplicados). Por isso:
1. O PR do F15.2 **começa pelo teste manual abaixo**, num branch, antes de qualquer README.
2. **Passou** → o toggle entra como está.
3. **Falhou** (erro no `register`, `notFound` logo depois de ligar, ou não abre após logout/login) → **plano B**: no lugar do toggle, entra só o botão abaixo. O README mantém a instrução manual, e o `PENDENCIAS.md` recebe: "Toggle 'abrir no login' via `SMAppService.mainApp` depende de Developer ID (F28); com ad-hoc, `<sintoma observado>`."

```swift
                // Plano B (ad-hoc não registra): o usuário adiciona à mão.
                Button("Abrir Itens de Início…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
```

Em qualquer caso, o código trata erro e status sem crash. O pior caso visível é o toggle voltar para desligado com a mensagem de erro.

### Código — `Sources/ClaudeBar/SettingsWindow.swift`

`import ServiceManagement` no topo. Na `SettingsView`:

```swift
    /// Lido do sistema, nunca guardado: dá para mudar em Ajustes do Sistema sem
    /// o app saber.
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
```

Na `Section("Sistema")`, antes do botão Sobre:

```swift
                Toggle("Abrir ao iniciar sessão no Mac", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginStatus == .requiresApproval {
                    Text("Falta aprovar em Ajustes do Sistema → Itens de Início.")
                        .font(.caption)
                    Button("Abrir Itens de Início") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
```

Depois de `.frame(width: 420)`:

```swift
        // Voltou de Ajustes do Sistema: relê o login item (não há aviso de mudança).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
```

E o método:

```swift
    /// Só roda com clique: abrir no login começa desligado.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Não foi possível mudar: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
```

(Compila sem `import Combine` explícito: o SwiftUI já traz o `publisher(for:)`. Verificado.)

### Testes

Nenhum automatizado. `SMAppService` mexe no estado real do sistema do usuário, e não vale criar uma abstração só para trocá-lo num teste (ponytail). O teste é o roteiro manual abaixo, e o resultado vai no PR.

### Verificação manual (obrigatória, é o gate do F15.2)

1. `./scripts/install.sh` (ad-hoc, `~/Applications/ClaudeBar.app`). Ajustes → o toggle está **desligado**.
2. Ligar → sem erro vermelho; o toggle continua ligado depois de fechar e reabrir a janela. Ajustes do Sistema → Geral → Itens de Início mostra o ClaudeBar **uma vez**.
3. Opcional: `sfltool dumpbtm | grep -i -A8 claudebar` (só leitura; se pedir senha, usar `sudo`). **Nunca** rodar `sfltool resetbtm`, que apaga os itens de início de tudo.
4. Logout/login → o ClaudeBar abre sozinho.
5. Desligar em Ajustes do Sistema com a janela de Ajustes aberta → voltar ao ClaudeBar → o toggle mostra desligado (prova a releitura no `didBecomeActive`).
6. `./scripts/install.sh` de novo (rebuild = cdhash novo) → abrir Ajustes: anotar o status. Se mostrar desligado, ligar de novo e conferir que **não** ficaram dois itens em Itens de Início.
7. Desligar pelo toggle → o item some de Itens de Início, e o app continua rodando.

Se 2 ou 4 falharem → plano B. Se só o 6 falhar (perde ao recompilar) → o toggle fica, e o README avisa: "after rebuilding, turn it on again".

### README / scripts

Trocar a linha "To start at login: System Settings → General → Login Items → add …" por:

```markdown
To start at login: **Ajustes… → Abrir ao iniciar sessão no Mac** (off by
default). If macOS asks for approval, the window links to System Settings →
Login Items. After rebuilding the app, turn it on again.
```

(No plano B, manter a linha atual e acrescentar "or use **Ajustes… → Abrir Itens de Início**".) Fazer o mesmo no `README.pt-BR.md`. Scripts: nenhuma mudança.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Ad-hoc não registra | Gate manual + plano B + `PENDENCIAS.md` (F28). |
| Item duplicado a cada rebuild (relato LaunchAtLogin #100) | Passo 6. Só afeta quem recompila; avisar no README. Não "consertar" com `unregister` automático no launch, que mudaria o sistema sem clique. |
| `register()` lento na main thread | Chamada síncrona dentro de um clique, aceitável. Não mover para `Task.detached` (o `SMAppService` não está documentado como seguro fora da main). |
| Estado velho após mudança por fora | Releitura ao abrir e em `didBecomeActive`. |

### Critérios de aceite

- Primeira abertura num Mac limpo: toggle desligado; `register()` nunca é chamado fora de `setLaunchAtLogin`.
- O toggle reflete `SMAppService.mainApp.status`, sem `UserDefaults` para isso (`grep -n "launchAtLogin\|loginItem" Sources` sem chave de defaults).
- O resultado dos passos 1 a 7 está registrado no PR. Plano A ou B aplicado de acordo com ele.
- Nenhuma dependência nova; `swift build` / `swift test` verdes.

### O que NÃO fazer

- Não adicionar LaunchAtLogin nem escrever em `~/Library/LaunchAgents`.
- Não chamar `register()` no launch nem "reparar" o registro sozinho.
- Não rodar `sfltool resetbtm` nem pedir ao usuário que rode.
- Não prometer o toggle no README antes do teste manual.

---

## F25 — Modo "nunca mostrar conteúdo"

### Objetivo

Um toggle **Nunca mostrar o conteúdo da mensagem** em Ajustes, **desligado por padrão**. Ligado, o aviso "esperando você" mostra `"<projeto> precisa de você"` no lugar da `message` que o Claude Code manda ao hook `Notification` (ex.: "Claude needs your permission to use Bash"). Vale para o popup próprio e para a notificação nativa (caso um dia haja Developer ID), e passa a valer no próximo aviso, sem reiniciar o app.

### Decisão técnica e por quê

- **Troca num único ponto: `SessionStore.notifyTransitions`**, a única linha que leva `message` à tela hoje (`notifier.post(.waiting, body: row.message ?? row.name)`). O `.finished` já usa só `row.name`. Os dois caminhos de exibição (HUD e `UNNotification`) passam pelo `post`, então trocar o `body` antes cobre os dois.
  - Descartada: trocar dentro de `Notifier.post`. O `Notifier` não conhece o nome da sessão.
  - Descartada: `NSWindow.sharingType = .none` no painel. A Apple documenta como "legacy constant that macOS no longer uses". Não desenhar é a única proteção real.
  - Descartada: o hook deixar de gravar `message` em disco com o modo ligado. Exige o CLI ler as preferências do app (suposição não confirmada) e é YAGNI. O arquivo continua `0600`, truncado em 200 caracteres. O F25 é só de exibição.
- **Regra em função pura `SessionRow.waitingBody(hidingContent:)`**, testável sem UI. Todo aviso que hoje ou no futuro mostre `message` (F13 lembrete, F38) chama essa função.
- **Preferência lida na hora** por `notifier.hidesContent` (`defaults.bool`), sem cópia. Mesmo modelo do F15.1, e quem escreve é o `@AppStorage` da janela.
- **`showSample()` respeita o modo**: com ele ligado, o exemplo mostra o texto genérico. Assim o usuário vê como fica e não acha que o conteúdo está vazando.
- **Decisão sobre o `cwd` no submenu: não esconder.** O backlog pede só `message`. O submenu só abre com clique deliberado, e o popup é o que aparece sem ser chamado durante um compartilhamento de tela. O nome do projeto continua visível de propósito, como especificado. Se o usuário pedir, é um `if` em `MenuContent` (`Text(row.cwd)`) e no `confirmTermination`.

### Código

#### `Sources/ClaudeBar/SessionRow.swift`, depois de `var id`

```swift
    /// Texto do aviso "esperando você". Com "nunca mostrar conteúdo" ligado, a
    /// mensagem do Claude (que pode citar comando, arquivo ou pergunta) não é
    /// desenhada: fica só o nome do projeto, que o menu já mostra.
    func waitingBody(hidingContent: Bool) -> String {
        hidingContent ? "\(name) precisa de você" : message ?? name
    }
```

#### `Sources/ClaudeBar/SessionStore.swift`, em `notifyTransitions`, `case .waiting`

```swift
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto — salvo no modo "nunca mostrar
                // conteúdo", lido aqui a cada aviso.
                notifier.post(.waiting, body: row.waitingBody(hidingContent: notifier.hidesContent))
```

#### `Sources/ClaudeBar/Notifier.swift`

Junto das chaves: `static let hideContentKey = "hideContent"`. Sem `register`: o padrão `false` é o do `bool(forKey:)`. Antes de `soundName(for:)`:

```swift
    /// "Nunca mostrar conteúdo" (Ajustes): lido na hora, sem cópia, para valer
    /// no próximo aviso sem reiniciar o app.
    var hidesContent: Bool {
        defaults.bool(forKey: Self.hideContentKey)
    }
```

`showSample`:

```swift
    /// Mostra um popup de exemplo, para conferir o canto da tela e o estilo.
    func showSample() {
        post(.waiting, body: hidesContent
            ? "Exemplo: meu-projeto precisa de você"
            : "Exemplo: Claude needs your permission to use Bash")
    }
```

#### `Sources/ClaudeBar/SettingsWindow.swift`

```swift
    @AppStorage(Notifier.hideContentKey) private var hideContent = false
```

Na `Section("Avisos")`, depois dos dois toggles:

```swift
                Toggle("Nunca mostrar o conteúdo da mensagem", isOn: $hideContent)
                Text("O aviso diz só \"<projeto> precisa de você\". Útil ao compartilhar a tela.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

### Testes — `Tests/ClaudeBarTests/AlertTests.swift`

```swift
    /// Modo "nunca mostrar conteúdo": a mensagem do Claude não chega ao aviso,
    /// nem quando existe (F25).
    @Test func modoSemConteudoEscondeAMensagem() {
        let row = SessionRow(
            sessionId: "s1",
            name: nil,
            cwd: "/Users/dev/my-app",
            state: .waiting,
            updatedAt: nil,
            message: "Claude needs your permission to use Bash: rm -rf segredo",
            isSubagent: false
        )

        #expect(row.waitingBody(hidingContent: true) == "my-app precisa de você")
        #expect(!row.waitingBody(hidingContent: true).contains("Bash"))
        #expect(row.waitingBody(hidingContent: false) == row.message)
    }

    /// Sem mensagem gravada pelo hook, o modo normal cai no nome (como hoje).
    @Test func semMensagemUsaONome() {
        let row = SessionRow(
            sessionId: "s1", name: "my-app-4d", cwd: "/x", state: .waiting,
            updatedAt: nil, message: nil, isSubagent: false
        )
        #expect(row.waitingBody(hidingContent: false) == "my-app-4d")
    }

    /// A preferência é lida na hora do aviso, não copiada no `init` (F25).
    @MainActor @Test func modoSemConteudoLidoNaHora() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let notifier = Notifier(defaults: defaults, playSound: { _ in })
        #expect(!notifier.hidesContent)
        defaults.set(true, forKey: Notifier.hideContentKey)
        #expect(notifier.hidesContent)
    }
```

(`SessionRow` é struct sem isolamento, então os dois primeiros testes não precisam de `@MainActor`. `scratchDefaults()` é o helper do F15.1.)

### README / scripts

`README.md`, seção "Alerts", depois do bullet sobre a mensagem de "waiting":

```markdown
- **Ajustes… → Nunca mostrar o conteúdo da mensagem** (off by default) replaces
  Claude's message with "<project> precisa de você" in the popup — useful when
  sharing your screen. macOS no longer honours "hide this window from screen
  capture", so the only real protection is not drawing the text. The message is
  still stored in the state file (`0600`); this mode only changes what is shown.
```

Na seção "Security", acrescentar: `- **Optional "never show content" mode** — see Alerts.` Fazer o mesmo no `README.pt-BR.md`. Scripts: nenhuma mudança.

### Verificação manual

1. Ajustes → ligar **Nunca mostrar o conteúdo**. Menu → **Ver exemplo de popup** → mostra "Exemplo: meu-projeto precisa de você".
2. Sessão real: pedir um Bash fora da allowlist → o popup mostra "<projeto> precisa de você", sem "Bash".
3. Desligar o modo (sem reiniciar o app) → repetir o passo 2 → aparece a mensagem do Claude.
4. Com o modo ligado, `/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.joaomarcos.claudebar"'` → nenhuma linha com o texto da mensagem (hoje nenhum `Logger` loga `body`; garantir que continua assim).

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Uma feature futura (F13 lembrete, F38, F07.2) exibe `row.message` direto e fura o modo | Critério de aceite com grep (abaixo), repetido como critério do F13/F38. O revisor recusa `row.message` fora de `waitingBody`. |
| Usuário achar que o modo apaga o dado do disco | O README diz que só muda a exibição. |
| Nome do projeto também é sensível para alguém | Fora do escopo (backlog). Anotado como decisão; trocar por "uma sessão" seria uma linha. |

### Critérios de aceite

- `grep -rn "row\.message" Sources/ClaudeBar` não encontra nada (a única leitura de `message` para exibição fica dentro de `SessionRow.waitingBody`; o `SessionMerge` só copia o dado). Nenhum `notifier.post` recebe `row.message` direto.
- Os 3 testes novos passam; `swift build` sem avisos; nenhum teste removido.
- Modo desligado = comportamento atual, byte a byte (`message ?? name`).
- Ligar ou desligar vale no próximo aviso, sem reiniciar (`modoSemConteudoLidoNaHora` + passo 3).
- Nenhum uso de `sharingType`.

### O que NÃO fazer

- Não usar `NSWindow.sharingType = .none` como proteção.
- Não fazer o hook ler as preferências do app nem deixar de gravar `message` (outra feature, se pedida).
- Não esconder `cwd`/nome sem decisão do usuário.
- Não logar `body` em nenhum `Logger`.
- Não criar um "modo privacidade" com várias chaves: é um `Bool`.

---

## Resumo do que ficou não confirmado e como a spec trata

| Item da pesquisa | Tratamento |
|---|---|
| `SMAppService.mainApp` com ad-hoc / após rebuild | Gate manual no F15.2, com plano B (botão + `PENDENCIAS.md`). |
| `openSettings`/`SettingsLink` na frente no macOS 14/26 | Evitado: não usamos a cena `Settings`. |
| Painel Sobre na frente num app accessory | Evitado: chamado de dentro da janela de Ajustes, com o app já ativo. |
| Aviso/KVO de mudança do login item | Não depende disso: releitura ao abrir a janela e em `didBecomeActive`. |
| `sfltool dumpbtm` exige admin | Passo opcional; `sudo` se pedir. |
| Nome/versão no Sobre vindos do `Info.plist` | Evitado: passados nas opções. |
| `Window(id:)` abrindo sozinha no macOS 14 | Evitado: alternativa descartada. |
| `isReleasedWhenClosed` sob ARC | Evitado: `false` explícito + `static var` segurando a janela. |
| Janela na frente de fato com `orderFrontRegardless` no app accessory | Passo 1 da verificação manual; plano B com `level = .floating`. |

> **Nota do usuário:** `activate(ignoringOtherApps:)` vai ser descontinuada numa versão futura do macOS. Não usar em código novo (ver TODO.md, "Deprecated APIs"). Pesquisar a substituta depois.
