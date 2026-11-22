# T19 — Ir para a sessão (árvore de processos + tmux)

- **Funcionalidade:** F09 — spec [G07, F09](../05-specs/G07-ir-para-sessao.md)
- **Épico:** Navegação · **Prioridade:** P1 (o produto: 24 pts no painel) · **Esforço:** 3 h
- **Depende de:** T11 (`Shell` com `input`/`timeout`), T18 · **Bloqueia:** T20, T21, T22
- **Branch:** `feat/ir-para-sessao`
- **PR:** `feat: ir para a sessão pelo menu`

## Objetivo

Item **Ir para a sessão** no submenu: sobe a árvore de processos do `claude` até o app que hospeda a sessão (Terminal, Ghostty, iTerm2, VS Code, Cursor, Warp, Claude.app) e traz para a frente. No tmux, troca também o cliente para o pane certo. Traz a janela, não a aba. Sem permissão TCC, sem shell.

## Subtasks

- [ ] `git mv Sources/ClaudeBar/Shell.swift Sources/ClaudeBarCore/Shell.swift`; `public enum Shell` e `public static func output(of:arguments:input:timeout:)` (assinatura que veio do T11).
- [ ] Criar `Sources/ClaudeBarCore/SessionNavigator.swift` (spec G07 linhas 66–217).
- [ ] `SessionStore.goToSession(_:)` antes de `confirmTermination`.
- [ ] `MenuContent`: botão logo depois do primeiro `Divider()` do submenu, só para `!row.isSubagent && pid > 0`.
- [ ] `SessionNavigatorTests.swift` (9).
- [ ] Verificação manual 1–6 da spec, por terminal disponível. Preencher a matriz no README só com o que foi verificado.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/Shell.swift` | movido, `public` |
| `Sources/ClaudeBarCore/SessionNavigator.swift` | novo |
| `Sources/ClaudeBar/SessionStore.swift` | `goToSession` |
| `Sources/ClaudeBar/MenuContent.swift` | item |
| `Tests/ClaudeBarTests/SessionNavigatorTests.swift` | novo |
| READMEs | "Going to a session" + matriz |

`AgentsProbe`, `SessionTerminator`, `HookSetup` e testes já importam `ClaudeBarCore`; conferir que compilam sem outra mudança.

## Código-chave (da spec)

```swift
public enum SessionNavigator {
    /// Síncrono e pode rodar `tmux`: chame fora da main actor.
    public static func app(for pid: Int32, followTmux: Bool = true) -> NSRunningApplication? {
        if let found = ancestor(of: pid, parent: parentPID, isApp: isRegularApp) {
            return NSRunningApplication(processIdentifier: found)
        }
        guard followTmux,
              let client = switchTmuxClient(toSessionOf: pid),
              let found = ancestor(of: client, parent: parentPID, isApp: isRegularApp)
        else { return nil }
        return NSRunningApplication(processIdentifier: found)
    }

    @MainActor
    public static func bringToFront(_ app: NSRunningApplication) async -> Bool {
        if app.activate(options: []) { return true }
        guard let url = app.bundleURL else { return false }
        let opened = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return opened != nil
    }

    static func ancestor(of pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        for _ in 0..<64 where current > 1 {
            if isApp(current) { return current }
            guard let next = parent(current), next != current else { return nil }
            current = next
        }
        return nil
    }

    /// `sysctl`, não `proc_pidinfo`: este falha em processo de root (`login`).
    static func parentPID(_ pid: Int32) -> Int32? { kinfo(pid).map { $0.kp_eproc.e_ppid } }
    // ttyPath (devname_r, NODEV = -1), kinfo, tmuxURL (caminhos fixos),
    // switchTmuxClient (list-panes/list-clients/select-window/select-pane/switch-client
    // com argumentos separados), pane(forTTY:in:), mostRecentClient(in:) — como na spec.
}
```

```swift
    /// Traz para a frente o app onde a sessão roda. No tmux, troca também o pane.
    func goToSession(_ row: SessionRow) {
        guard let pid = row.pid, pid > 0 else { return }
        acknowledged.insert(row.sessionId)
        Task {
            // `sysctl` e `tmux` são síncronos: fora da main actor.
            let app = await Task.detached(priority: .userInitiated) { SessionNavigator.app(for: pid) }.value
            if let app, await SessionNavigator.bringToFront(app) { return }
            report(title: "Não foi possível ir até \(row.name)", message: """
                \(row.cwd)

                Não achei o terminal ou app dessa sessão. No tmux, só o socket \
                padrão é suportado e precisa haver um terminal anexado. A pasta \
                do projeto continua em "Abrir pasta do projeto".
                """)
        }
    }
```

Decisão: na falha, **não** abrir o Finder sozinho (seria uma ação que o usuário não pediu); o alerta aponta para o item do T18.

## Testes obrigatórios

`SessionNavigatorTreeTests` (5: Terminal sobe até o app, helper do Electron fica para trás, tmux sem app, ciclo não trava, `parentPID` de verdade) e `TmuxParsingTests` (4: pane pelo TTY, TTY parecido não casa, cliente usado por último, sem cliente), como na spec. **Não** ativar app em `swift test`.

## Critérios de aceite

- `SessionNavigator` no Core, sem protocolo; `Shell` público no Core; nenhum `/bin/sh`/`zsh` novo.
- tmux só por caminho absoluto e argumentos separados.
- `app(for:)` com tmux só fora da main actor.
- Item aparece para `pid > 0` e não para subagente; falha mostra alerta, sem crash.
- README com a matriz e status reais (nada "verificado" sem o passo manual).
- `swift test` = anterior + 9.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Submenu ganha **Ir para a sessão**. Subseção "Going to a session": sobe a árvore até o app; no tmux troca o pane (socket padrão, precisa de cliente anexado); traz a janela, não a aba; sem permissão. Matriz de suporte (Claude desktop app / Terminal.app / Ghostty / iTerm2 / VS Code / Cursor / Warp / tmux) com "verificado" ou "não verificado". Project structure: `Shell.swift` no Core, `SessionNavigator.swift`. Security: `tmux` ao lado de `claude` (caminho conhecido, argumentos separados).

## Riscos

| Risco | Mitigação |
|---|---|
| iTerm2 com `iTermServer` filho do `launchd` | alerta honesto; plano B (`__CFBundleIdentifier`) em PR próprio só se a verificação mostrar falha |
| `activate` recusado vindo de app `.accessory` | fallback `openApplication` |
| tmux com socket não padrão | não suportado, mensagem explícita |
| AppKit no Core entra no binário do hook | ~1 ms medido; o caminho do hook não chama AppKit |

## Fora do escopo

Aba exata/AppleScript (F30), Accessibility, `proc_pidinfo` para PPID, procurar tmux com `zsh -lc`, gravar `TMUX_PANE`/bundle id, clique no popup (T20), "não tocar som" (T21), CLI `next` (T22).
