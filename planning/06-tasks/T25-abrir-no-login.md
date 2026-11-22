# T25 — Abrir no login (`SMAppService.mainApp`)

- **Funcionalidade:** F15, parte 2 de 2 (F15.2) — spec [G10, F15.2](../05-specs/G10-ajustes-privacidade.md)
- **Épico:** UI/Ajustes · **Prioridade:** P1 · **Esforço:** 1,5 h
- **Depende de:** T24 · **Bloqueia:** —
- **Branch:** `feat/abrir-no-login`
- **PR:** `feat: abrir o ClaudeBar ao iniciar sessão no Mac`

## Objetivo

Toggle **Abrir ao iniciar sessão no Mac** nos Ajustes, **desligado por padrão**, que mostra o estado real do sistema (`SMAppService.mainApp.status`, nunca guardado). Substitui a instrução manual do README.

## Gate de decisão (não é bloqueio)

Não se sabe se `SMAppService.mainApp` funciona com assinatura ad-hoc. A task **começa** pelo teste manual, num build do branch:

1. Ligar o toggle → sem erro, `status == .enabled`, item aparece **uma vez** em Ajustes do Sistema → Itens de Início.
2. Rebuild (`./scripts/install.sh`) → anotar o status; religar e conferir que não duplicou.
3. Desligar pelo toggle no fim → item some (deixar o sistema como estava).
4. Logout/login: o implementador não consegue fazer; vai como "não verificado" no PR.

- **1 passou** → **plano A**: toggle como abaixo. Se só o 2 falhar, README avisa "after rebuilding, turn it on again".
- **1 falhou** (erro no `register` ou `notFound` logo depois) → **plano B**: no lugar do toggle, só o botão "Abrir Itens de Início…"; README mantém a instrução manual; acrescentar em `PENDENCIAS.md` (raiz): "Toggle 'abrir no login' via `SMAppService.mainApp` depende de Developer ID (F28); com ad-hoc, `<sintoma observado>`."

## Subtasks

- [ ] Rodar o gate acima e decidir A ou B. Registrar o resultado no PR.
- [ ] `SettingsWindow.swift`: `import ServiceManagement`; `@State loginStatus`, `@State loginError`; toggle (A) ou botão (B); releitura em `NSApplication.didBecomeActiveNotification`; `setLaunchAtLogin(_:)`.
- [ ] READMEs (e `PENDENCIAS.md` no plano B).
- [ ] Gates, commit, PR.

## Arquivos

`SettingsWindow.swift`, READMEs (+ `PENDENCIAS.md` no plano B).

## Código-chave (da spec)

```swift
    /// Lido do sistema, nunca guardado: dá para mudar em Ajustes do Sistema sem o app saber.
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

                Toggle("Abrir ao iniciar sessão no Mac", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginStatus == .requiresApproval {
                    Text("Falta aprovar em Ajustes do Sistema → Itens de Início.").font(.caption)
                    Button("Abrir Itens de Início") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }

        // Voltou de Ajustes do Sistema: relê o login item (não há aviso de mudança).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }

    /// Só roda com clique: abrir no login começa desligado.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Não foi possível mudar: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
```

Plano B:

```swift
                // Plano B (ad-hoc não registra): o usuário adiciona à mão.
                Button("Abrir Itens de Início…") { SMAppService.openSystemSettingsLoginItems() }
```

## Testes obrigatórios

Nenhum automatizado (`SMAppService` mexe no estado real do sistema; abstração só para teste é ponytail ao contrário). O gate manual é o teste.

## Critérios de aceite

- Mac limpo: toggle desligado; `register()` só dentro de `setLaunchAtLogin`.
- O toggle reflete `SMAppService.mainApp.status`, sem chave em `UserDefaults` (`grep -n "launchAtLogin\|loginItem" Sources` sem chave de defaults).
- Resultado do gate registrado no PR; plano A ou B aplicado de acordo.
- Nenhuma dependência nova.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Plano A:

```markdown
To start at login: **Ajustes… → Abrir ao iniciar sessão no Mac** (off by
default). If macOS asks for approval, the window links to System Settings →
Login Items. After rebuilding the app, turn it on again.
```

Plano B: manter a linha atual e acrescentar "or use **Ajustes… → Abrir Itens de Início**".

## Riscos

| Risco | Mitigação |
|---|---|
| Ad-hoc não registra | gate + plano B + `PENDENCIAS.md` (F28) |
| Item duplicado a cada rebuild | passo 2; aviso no README; nunca `unregister` automático |
| `register()` lento na main | chamada dentro de um clique; aceitável |

## Fora do escopo

LaunchAtLogin-Modern; `~/Library/LaunchAgents`; `register()` no launch; `sfltool resetbtm` (nunca rodar nem sugerir).
