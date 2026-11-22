# G10 — Ajustes mínimos (F15) e modo "nunca mostrar conteúdo" (F25)

Pesquisa de COMO FAZER. Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial (Apple / Claude Code) lida nesta pesquisa; **[COMUNIDADE]** = fórum, blog ou repo open source; **[SUPOSIÇÃO]** = minha inferência, precisa de teste.

Datas: pesquisa em 2026-11-15, Mac de teste com macOS 26.5.2.

---

## 0. Ponto de partida no código

- `Sources/ClaudeBar/ClaudeBarApp.swift`: só uma cena `MenuBarExtra` (`.menuBarExtraStyle(.menu)`), `AppDelegate` chama `setActivationPolicy(.accessory)`. `Info.plist` (gerado em `scripts/build-app.sh`) tem `LSUIElement = true`, `CFBundleShortVersionString = 1.0`, sem ícone (`CFBundleIconFile` ausente).
- `Sources/ClaudeBar/Notifier.swift`: `@MainActor @Observable`. Uma chave só em `UserDefaults` (`notificationsEnabled`, padrão `true`). Os sons estão fixos em `Alert.soundName` (`Glass` / `Submarine`) e `Alert.volume`. Detalhe: `post(_:body:)` chama `play(alert)` **antes** do `guard isEnabled`, então hoje o som toca mesmo com avisos desligados. Isso precisa ser decidido de propósito na spec do F15 (toggle de som separado).
- `Sources/ClaudeBar/MenuContent.swift`: o menu tem um `Toggle("Notificações")` que lê e escreve `store.notifier`. O menu **não mostra `message`** hoje: o rótulo é ícone, nome, estado e tempo, e o submenu mostra o `cwd`.
- Onde `message` chega à tela hoje (um lugar só): `SessionStore.notifyTransitions`, linha ~179: `notifier.post(.waiting, body: row.message ?? row.name)`. Esse `body` vai para o popup próprio (`StatusHUD`, `Text(body_)`) ou para a `UNNotification`, se um dia houver Developer ID.
- `Sources/claudebar-hook/main.swift`: grava `message` do payload no JSON da sessão, truncado em 200 caracteres.

---

## 1. Janela de Ajustes num app accessory/LSUIElement

### O que as fontes oficiais dizem
- `Settings` (cena), macOS 11+. A Apple recomenda `@AppStorage` para os controles. **[CONFIRMADO]** https://developer.apple.com/documentation/swiftui/settings
- `SettingsLink`, macOS 14+: "clicking on the link opens the window for the scene or orders it to the front if it is already open". **[CONFIRMADO]** https://developer.apple.com/documentation/swiftui/settingslink
- `@Environment(\.openSettings)` / `OpenSettingsAction`, macOS 14+. **[CONFIRMADO]** https://developer.apple.com/documentation/swiftui/opensettingsaction
- `NSApplication.activate()`, macOS 14+: "calling this method doesn't guarantee app activation" (ativação cooperativa). **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nsapplication/activate()
- `activate(ignoringOtherApps:)` aparece como depreciado no JSON da documentação (o campo `deprecatedAt` diz `27.0`; o Xcode já avisa desde o SDK 14). **[CONFIRMADO, quanto a estar depreciado]** https://developer.apple.com/documentation/appkit/nsapplication/activate(ignoringotherapps:)
- `.accessory`: "may be activated programmatically or by clicking on one of its windows". É o equivalente de `LSUIElement = 1`. **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory
- `NSWindow.orderFrontRegardless()`: "Moves the window to the front of its level, even if its application isn't active". **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()

### Armadilhas conhecidas [COMUNIDADE]
- O `SettingsLink` dentro de `MenuBarExtra` abre a janela **sem ativar o app**, então ela fica atrás da janela da frente. No estilo `.menu` não dá para pôr código antes ou depois do clique. Fórum da Apple: https://developer.apple.com/forums/thread/731628
- `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` parou no Sonoma e loga "Please use SettingsLink". Mesmo thread acima, mais https://github.com/orchetect/SettingsAccess
- `NSApp.activate()` não traz a janela para a frente em app de barra de menu sem janela ativa. Um engenheiro da Apple (DTS) diz que isso é intencional e sugere `openWindow(id:)`, sem solução validada. Bugs abertos: FB23508310 e FB23519126. https://developer.apple.com/forums/thread/836619
- steipete (2025): `openSettings()` precisa de uma árvore SwiftUI viva. O truque é uma `Window` oculta declarada **antes** da `Settings`, trocar para `.regular`, esperar cerca de 100 a 200 ms, e depois `orderFrontRegardless()`. O autor relata que falha no macOS 26. https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/
- O VibeTunnel (`SettingsOpener.swift`) precisa de Dock temporário, `Task.sleep`, busca da janela pelo identificador privado `"com_apple_SwiftUI_Settings_window"` e troca de `level`. Mostra o custo do caminho "cena Settings": https://github.com/amantus-ai/vibetunnel/blob/main/mac/VibeTunnel/Utilities/SettingsOpener.swift
- O SettingsAccess (orchetect) avisa: "`openSettingsLegacy()` is not usable within a `menu`-based `MenuBarExtra`". O pacote oferece um `SettingsLink` com `preAction`/`postAction`, mas é uma dependência nova.

### Alternativas
| | Como | Prós | Contras |
|---|---|---|---|
| A. Cena `Settings` + botão | `Settings { SettingsView(store:) }`; no menu, `Button("Ajustes…") { NSApp.activate(); openSettings() }` | É o que o backlog escreveu; `@AppStorage` grátis; pouco código | Não temos referência para a janela. Se abrir atrás, a correção exige identificador privado, delays e troca de policy (ver acima). `openSettings` vindo do conteúdo de um MenuBarExtra `.menu` funcionar **[SUPOSIÇÃO]** |
| B. `NSWindow` próprio + `NSHostingController` | Um `SettingsWindow` `@MainActor` com `NSWindow(contentViewController: NSHostingController(rootView: SettingsView(...)))`, criado sob demanda; abrir com `NSApp.activate()` + `makeKeyAndOrderFront(nil)` + `orderFrontRegardless()` | Temos a janela na mão, e `orderFrontRegardless` é oficial para app não ativo. Mesmo padrão do `StatusHUD` (que já usa `NSPanel`). Sem API privada, sem delay | ~25 linhas. Sem `Cmd+,` (app accessory não tem menu de app, então não perde nada). Foge da palavra "cena Settings" do backlog |
| C. SettingsAccess | dependência SwiftPM | Resolve o pre/post action | Dependência nova para algo de 3 linhas, e não garante a ordem no macOS 26 |
| D. `Window(id:)` + `openWindow` | sugestão do DTS | API oficial | No macOS 14 não existe `.defaultLaunchBehavior(.suppressed)` (é macOS 15+, **[CONFIRMADO]** https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)). Risco de a janela abrir sozinha no launch **[SUPOSIÇÃO]** |

**Recomendação: B.** É determinístico com APIs públicas e reaproveita o padrão que o app já tem. Se a spec quiser manter A, o critério de aceite precisa ser "abre na frente, com outro app em foco, no macOS 14 e no 26", testado à mão. As fontes acima indicam que A tende a falhar nesse teste.

Esboço B (ilustrativo, não testado):
```swift
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    func show(store: SessionStore) {
        let window = self.window ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            w.title = "Ajustes do ClaudeBar"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false   // NSWindow criado à mão: senão fechar libera a janela
            w.center()
            return w
        }()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
```
- `isReleasedWhenClosed = false`: o padrão é `true` para `NSWindow` criado sem window controller. Sem isso, reabrir depois de fechar acessa uma janela já liberada. **[COMUNIDADE/conhecimento AppKit; SUPOSIÇÃO quanto ao comportamento exato sob ARC]**
- Swift 6: `NSWindow`, `NSHostingController` e `NSApp` são `@MainActor`, e a classe também, então não há problema de isolamento. `SessionStore` já é passado ao `MenuContent` como `let store`; o `ClaudeBarApp` guarda o `SettingsWindow` como `@State`, ou ele vive no `AppDelegate`.

---

## 2. Toggles de aviso e de som, escolha do som

- Fonte única: `UserDefaults`. Na view de ajustes, `@AppStorage("chave")`, o padrão que a Apple mostra para `Settings` (**[CONFIRMADO]**, doc da cena `Settings`). O `@AppStorage` funciona em qualquer view SwiftUI, inclusive dentro de `NSHostingController` **[SUPOSIÇÃO, comportamento padrão]**.
- Armadilha de estado duplicado: hoje o `Notifier.isEnabled` é uma propriedade armazenada, lida do defaults só no `init`. Se a tela de ajustes escrever via `@AppStorage`, o `Notifier` não vê a mudança. O jeito mais simples é o `Notifier` ler `defaults.bool(forKey:)` **no momento do `post`**, sem cópia. O menu também passa a usar `@AppStorage` com a mesma chave. Efeitos colaterais de hoje (`requestAuthorization`, `hud.dismiss()`) vão para `.onChange` na view ou continuam num `setEnabled` chamado pelo binding. **[SUPOSIÇÃO de design]**
- Chaves sugeridas (registrar padrões com `defaults.register`): `notificationsEnabled` (já existe; manter o nome evita migração), `notifyFinished`, `notifyWaiting`, `soundEnabled`, `soundFinished` (padrão `"Glass"`), `soundWaiting` (padrão `"Submarine"`), `hideContent` (F25, padrão `false`).
- Lista de sons: `NSSound(named:)` procura no bundle, depois em `~/Library/Sounds`, `/Library/Sounds`, `/Network/Library/Sounds` e `/System/Library/Sounds`, e "the preferred way ... is to pass a name without the file extension". **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nssound/init(named:)
  - Neste Mac (macOS 26.5.2), `/System/Library/Sounds` tem: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink (`.aiff`). Não há API pública que liste "sons do sistema" **[SUPOSIÇÃO: não achei]**. Duas opções: ler o diretório com `FileManager.contentsOfDirectory` e tirar a extensão, ou fixar essa lista de 14 nomes. Ler o diretório acompanha mudanças do SO. Se um nome salvo sumir, `NSSound(named:)` devolve `nil` e o `play` atual já sai em silêncio pelo `guard`.
  - Na troca do `Picker`, tocar o som escolhido (o `Notifier.play` já existe; basta expor um `preview(soundName:)`).
- `Notifier.play` precisa passar a ler o nome do defaults, em vez de `Alert.soundName` fixo. O cache `sounds[name]` continua valendo porque é indexado por nome.

---

## 3. Abrir no login: `SMAppService.mainApp`

### Oficial [CONFIRMADO]
- `SMAppService.mainApp`, macOS 13+: "An app service object that corresponds to the main application as a login item." https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
- `register()`: para o app principal, "the application launches on subsequent logins". "If the service is already registered, this method returns" um erro (o texto da doc cita a constante sem nome no JSON). https://developer.apple.com/documentation/servicemanagement/smappservice/register()
- `unregister()`: o app principal "continues running, but becomes unregistered". https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()
- `status`: `notRegistered`, `enabled`, `requiresApproval`, `notFound`. Sobre `requiresApproval`: "The framework also returns this status if the user revokes consent ... in System Settings". https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum
- `SMAppService.openSystemSettingsLoginItems()` abre Ajustes > Itens de Início. https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems()

### Padrão open source
`sindresorhus/LaunchAtLogin-Modern` (`Sources/LaunchAtLogin/LaunchAtLogin.swift`): o estado é **sempre** lido de `SMAppService.mainApp.status == .enabled`, sem cópia em defaults. Para ligar, se já estiver `.enabled`, ele faz `unregister` antes do `register`. O README cita a regra da App Store de não ligar por padrão. https://github.com/sindresorhus/LaunchAtLogin-Modern
```swift
get { SMAppService.mainApp.status == .enabled }
set { ... try SMAppService.mainApp.register() ... try SMAppService.mainApp.unregister() }
```
Não vale adicionar a dependência: são 10 linhas.

### Funciona com assinatura ad-hoc? NÃO CONFIRMADO
- Nenhuma fonte oficial diz que `mainApp` exige Developer ID.
- Um engenheiro da Apple (DTS), falando de **daemon** + helper: "If ... you are using ad hoc signing ... then you will see problems like this". https://developer.apple.com/forums/thread/799910 **[COMUNIDADE; não é sobre `mainApp`]**
- LaunchAtLogin issue #100: build sem assinatura local → `status == .notFound` a cada build nova, notificação "Login Item Added" a cada vez e mais de 100 itens duplicados em Ajustes. Fechada sem causa confirmada. https://github.com/sindresorhus/LaunchAtLogin/issues/100 **[COMUNIDADE]**
- Erro `SMAppServiceErrorDomain Code=1 "Operation not permitted"` com `BTMErrorDomain -98`. Para diagnosticar, o DTS recomenda `sfltool dumpbtm` / `resetbtm`. https://developer.apple.com/forums/thread/722338
- Hipótese **[SUPOSIÇÃO]**: o BTM identifica um app ad-hoc pelo cdhash, que muda a cada `build-app.sh`. Então o login item pode "sumir" (`notFound`) ou duplicar a cada rebuild, mas funcionar para quem instala uma vez e não recompila.

### Recomendação
- O toggle reflete `SMAppService.mainApp.status`, relido no `onAppear` da janela de ajustes e depois de cada `register`/`unregister`. Não achei notificação ou KVO para mudança feita em Ajustes do Sistema **[SUPOSIÇÃO]**.
- Mapeamento: `.enabled` → ligado; `.requiresApproval` → ligado com a nota "aprovar em Ajustes do Sistema" e um botão `openSystemSettingsLoginItems()`; `.notRegistered`/`.notFound` → desligado. Erro do `register` → texto curto abaixo do toggle, sem esconder.
- Padrão desligado. Nunca chamar `register()` sem clique (A8, mais a regra da App Store).
- Teste manual obrigatório antes de prometer no README: (1) `build-app.sh`, copiar para `/Applications`, ligar, conferir o `status`; (2) logout/login; (3) rebuild e conferir se o status virou `notFound` ou duplicou. Usar `sfltool dumpbtm` para olhar o registro (pode pedir admin, **[SUPOSIÇÃO]**). Se falhar com ad-hoc, o item vai para `PENDENCIAS` (depende de Developer ID, guard rail do plano) e o toggle mostra o motivo.
- Alternativa se ad-hoc não servir: só o botão "Abrir Itens de Início" (`openSystemSettingsLoginItems()`), para o usuário adicionar o app manualmente. Gravar plist em `~/Library/LaunchAgents` é legado e cria configuração persistente fora do controle do SO; não recomendo.
- Swift 6: as chamadas são síncronas e ficam na `@MainActor` (botão da view). `register()` pode demorar alguns ms **[SUPOSIÇÃO]**, o que é aceitável em toggle.

---

## 4. Sobre: `orderFrontStandardAboutPanel`

- `NSApplication.orderFrontStandardAboutPanel(_:)`: "Displays a standard About window". As chaves de `orderFrontStandardAboutPanel(options:)` são `applicationIcon`, `applicationName`, `applicationVersion`, `credits` e `version`. **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nsapplication/orderfrontstandardaboutpanel(_:) e https://developer.apple.com/documentation/appkit/nsapplication/aboutpaneloptionkey
- `credits`: se não for passado, o AppKit procura `Credits.html`, `.rtf` ou `.rtfd` no bundle; sem nenhum, a área fica em branco. **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nsapplication/aboutpaneloptionkey/credits
- Nome e versão vêm do `Info.plist` (`CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`), que o `build-app.sh` já grava **[SUPOSIÇÃO: comportamento padrão, não reli a doc do painel]**. Sem `CFBundleIconFile`, aparece o ícone genérico. O ícone original fica com o design (`planning/07-design/`).
- Num app accessory, chamar `NSApp.activate()` antes. Senão o painel pode abrir atrás, pela mesma causa da seção 1 **[SUPOSIÇÃO]**. Não temos referência à janela do painel para usar `orderFrontRegardless`.
- Alternativa mais preguiçosa e sem esse risco: uma linha "ClaudeBar 1.0 — repositório/licença" no rodapé da janela de ajustes (`Bundle.main.infoDictionary?["CFBundleShortVersionString"]`). O A13 pede o painel padrão; fica a critério da spec.
- Passar `credits` como `NSAttributedString` com a linha "sem rede, sem login" (as promessas do README) é opcional.

---

## 5. F25: modo "nunca mostrar conteúdo"

### O que é `message` [CONFIRMADO]
Hooks do Claude Code, seção "Notification input": "Notification hooks receive `message` with the notification text, an optional `title`, and `notification_type`". Exemplo: `"message": "Claude needs your permission"`, `"notification_type": "permission_prompt"`. https://code.claude.com/docs/en/hooks (seção Notification input)

### Por que não dá para confiar em "esconder a janela do compartilhamento"
- `NSWindow.SharingType.none`: "A legacy constant that macOS no longer uses." **[CONFIRMADO]** https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
- Relatos de que o ScreenCaptureKit captura janelas `sharingType = .none` no macOS 15+. **[COMUNIDADE]** https://developer.apple.com/forums/thread/792152
- Conclusão: a única proteção real é **não desenhar** o conteúdo. É exatamente o que o F25 propõe.

### Implementação
- Um ponto só, onde todos os caminhos passam: `SessionStore.notifyTransitions` (o `post(.waiting, body:)`). Com `hideContent` ligado, `body = "\(row.name) precisa de você"`; desligado, continua `row.message ?? row.name`. O `.finished` já usa só `row.name`. Assim o popup próprio e a `UNNotification` (se um dia houver Developer ID) ficam cobertos de uma vez.
- Alternativa equivalente: fazer a troca dentro do `Notifier.post`. Mas o `Notifier` não conhece o nome da sessão, então o `SessionStore` é o lugar certo.
- Menu: hoje não mostra `message`, então não há nada a trocar. Qualquer exibição futura (F38) **deve** ler o mesmo `hideContent`. Isso vai como critério de aceite do F38.
- `showSample()` usa texto fixo de exemplo e não vaza nada. Com `hideContent` ligado, pode mostrar o texto genérico para o usuário ver como fica.
- Toggle na janela de ajustes (`@AppStorage("hideContent")`), padrão desligado. Leitura no momento do aviso, sem cópia.

### Pontos em aberto para a spec
- O submenu da sessão mostra o `cwd` completo (`Text(row.cwd)`), que contém usuário e projeto. Esconder também no modo F25? O backlog fala só de `message`. **[decisão]**
- O hook continua gravando `message` em disco (`~/.claude/claudebar/*.json`, 0600, 200 caracteres). O F25 é só de exibição. O CLI ler a preferência do app (`UserDefaults(suiteName: "com.joaomarcos.claudebar")`) é possível para app não sandboxed **[SUPOSIÇÃO]**, mas é YAGNI agora.
- O nome do projeto (`row.name`) continua visível no modo genérico, que é o que o backlog especifica.

---

## 6. Resumo da recomendação
1. Janela de ajustes = `NSWindow` + `NSHostingController` (opção B), aberta por um `Button("Ajustes…")` no menu com `NSApp.activate()` + `makeKeyAndOrderFront` + `orderFrontRegardless`. A cena `Settings` (A) só se passar no teste "abre na frente" no macOS 14 e no 26.
2. Preferências em `UserDefaults` via `@AppStorage`, lidas no momento do aviso pelo `Notifier` (sem cópia em propriedade).
3. Som por aviso escolhido de `/System/Library/Sounds`, com prévia ao trocar.
4. Abrir no login: `SMAppService.mainApp`, estado sempre lido do `status`, padrão desligado, com tratamento de `requiresApproval` e de erro. Comportamento com ad-hoc **a testar**; se falhar, vai para `PENDENCIAS`.
5. Sobre: `orderFrontStandardAboutPanel(options:)` depois de `NSApp.activate()`, ou uma linha de versão na própria janela.
6. F25: troca de texto num único ponto (`SessionStore.notifyTransitions`), sem depender de `sharingType`.

## 7. Não confirmado (precisa de teste ou de fonte)
- `SMAppService.mainApp.register()` com assinatura ad-hoc: se funciona, e se sobrevive a rebuild (cdhash).
- `openSettings()`/`SettingsLink` dentro de `MenuBarExtra` `.menu` abrindo **na frente** no macOS 14 e no 26.
- O painel Sobre aparecer na frente num app accessory depois de `NSApp.activate()`.
- Existir notificação ou KVO para mudança do status do login item feita em Ajustes do Sistema (não achei).
- `sfltool dumpbtm` exigir admin.
- O nome e a versão do painel Sobre virem automaticamente do `Info.plist` (comportamento conhecido, mas não relido na doc).
- A `Window(id:)` abrir sozinha no launch no macOS 14 (alternativa D).
