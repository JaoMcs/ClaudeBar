# T10 — Instalar/remover hooks pelo app, com diff e consentimento

- **Funcionalidade:** F16 — spec [G03, F16](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P1 (inovação N4) · **Esforço:** 3 h
- **Depende de:** T06, T09 · **Bloqueia:** T11, T14, T30, T33
- **Branch:** `feat/integracao-transparente`
- **PR:** `feat: instalar e remover hooks pelo app com diff e consentimento`

## Objetivo

Antes de gravar, o usuário vê o arquivo real (symlink resolvido), o diff exato do bloco `hooks`, onde fica o backup, e decide: Instalar / Remover / Pular. No 1º uso (e a cada estado novo que pede reparo) o mesmo alerta aparece **uma vez**; "Pular" não grava nada e não pergunta de novo enquanto o estado não mudar. Settings só leitura → "Copiar JSON dos hooks".

## Subtasks

- [ ] Criar `Sources/ClaudeBar/HookSetup.swift` (spec G03 linhas 979–1144, **sem** `selfTest`/`check`, que são de T11).
- [ ] `SessionStore`: `let hookSetup = HookSetup()`.
- [ ] `MenuContent`: `integrationMenu` antes de "Atualizar"; "Atualizar" também chama `store.hookSetup.refresh()`.
- [ ] Verificação manual 1–7 da spec (alerta na frente no 1º launch; "Pular" sem escrita; instalar; VoiceOver no alerta; corrida com `/model`; `chmod 444`; migração de hooks legados). Se o alerta aparecer antes do ícone ou não aparecer, aplicar o plano B (`NSApplication.didFinishLaunchingNotification`) e registrar.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/HookSetup.swift` | novo |
| `Sources/ClaudeBar/SessionStore.swift` | 1 linha |
| `Sources/ClaudeBar/MenuContent.swift` | submenu de integração |
| READMEs | seção "Integração com o Claude Code" |

## Código-chave (da spec)

```swift
@MainActor
@Observable
final class HookSetup {
    private(set) var state: IntegrationState = .notInstalled
    private let defaults = UserDefaults.standard
    /// Último estado já oferecido no launch: oferecer de novo só se mudar.
    private static let offeredKey = "hookSetupOfferedState"
    /// O hook que veio neste `.app`. No `swift run`, o executável ao lado.
    private let bundledBinary = Bundle.main.url(forAuxiliaryExecutable: "claudebar-hook")

    init() {
        refresh()
        // Fora do init: o `SessionStore` nasce antes do app terminar de abrir.
        Task { @MainActor in self.offerIfNeeded() }
    }

    func refresh() {
        state = HookInstaller.state(bundledBinary: bundledBinary)
        if state == .ok { defaults.removeObject(forKey: Self.offeredKey) }
    }

    private func offerIfNeeded() {
        let offerable: [IntegrationState] = [.notInstalled, .binaryMissing, .binaryOutdated, .hooksOutdated, .legacyHooks]
        let key = "\(state)"
        guard offerable.contains(state), defaults.string(forKey: Self.offeredKey) != key else { return }
        defaults.set(key, forKey: Self.offeredKey)
        review(.install, cancelTitle: "Pular")
    }
```

Em `review(_:cancelTitle:)` (código completo na spec): executável **antes** do settings (`installBinary` → `apply`); `catch HookInstallError.changedSinceReview` → `review` de novo (nunca grava às cegas); `NSAlert` com `accessoryView` monoespaçado só leitura (`setAccessibilityLabel("Alterações no settings.json")`), `NSApplication.shared.activate(ignoringOtherApps: true)` + `runModal()`.

Menu:

```swift
    @ViewBuilder private var integrationMenu: some View {
        let setup = store.hookSetup
        Menu(setup.menuTitle) {
            Text(setup.summary)
            Divider()
            switch setup.state {
            case .readOnlySettings:
                Button("Copiar JSON dos hooks") { setup.copySnippet() }
            case .invalidSettings, .hooksDisabled:
                EmptyView()
            default:
                Button(setup.state == .ok ? "Reinstalar hooks…" : "Instalar hooks…") { setup.review(.install) }
            }
            if setup.canRemove {
                Button("Remover hooks…") { setup.review(.uninstall) }
            }
        }
    }
```

## Testes obrigatórios

Nenhum teste novo de UI. **Não instanciar `HookSetup` nem `SessionStore` em teste** (o `init` abre alerta modal). Toda a lógica que o alerta mostra/grava já é testada no Core (T03, T04, T06).

## Critérios de aceite

- Nenhuma escrita sem clique em "Instalar"/"Remover"/"Copiar JSON" (grep: `installBinary`/`apply` só em `HookSetup.review`, `HookSetup.copySnippet` e no CLI).
- "Pular" não grava (`shasum` igual) e não reaparece até o estado mudar; `.ok` limpa a chave.
- O alerta mostra arquivo real, diff, pasta do backup e aviso de reformatação quando houver.
- Nunca mostra o settings inteiro.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Seção "Integração com o Claude Code" no menu: o que cada item faz, que nada é gravado sem o alerta, que "Pular" não pergunta de novo enquanto o estado não mudar, e que o app oferece atualizar a cópia do hook depois de atualizar o `.app`.

## Riscos

| Risco | Mitigação |
|---|---|
| Alerta atrás das janelas | `activate(ignoringOtherApps:)`, padrão já usado em `confirmTermination` |
| Alerta cedo demais no launch (inferência) | verificação 1; plano B `didFinishLaunchingNotification` |
| Usuário clica sem ler | texto diz que só entradas do ClaudeBar mudam + backup + "Remover" desfaz |

## Fora do escopo

Janela SwiftUI/cena `Settings`, tour, trocar activation policy, reparar no launch, "Testar integração" (T11), statusline (T30).

> **Nota do usuário:** `activate(ignoringOtherApps:)` vai ser descontinuada numa versão futura do macOS. Não usar em código novo (ver TODO.md, "Deprecated APIs"). Pesquisar a substituta depois.
