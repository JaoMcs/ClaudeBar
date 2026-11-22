# G07 — Spec técnica: ir para a sessão (F09, F10, F14, F26)

Insumos: `04-como-fazer/G07-ir-para-sessao.md`, `03-validacao/BACKLOG.md` (F09 M, F10/F14/F26 P), `00-PLANO.md` (guard rails).
Código lido em 2026-11-15 (`main` @ 80768db; `Sources/` igual ao f943cc4).

**Verificado nesta spec:** o código abaixo foi aplicado numa cópia do projeto real (com o diff do F01/G01 junto, que é pré-requisito do F14), Swift 6.3.3, tools 6.0:
- `swift build`: 0 avisos, 0 erros. `swift test`: **43 testes passam** (34 atuais + 9 novos).
- `SessionNavigator.app(for: <pid do claude desta sessão>, followTmux: false)` devolveu `com.anthropic.claudefordesktop` (cadeia `claude` → `disclaimer` → `Claude`).
- `claudebar-hook status` e `status --json` responderam com stdin num pty (`script -q /dev/null …`), sem travar. `next` sem sessão esperando imprime "nenhuma sessão esperando você" e sai com 1. O hook normal (`echo … | claudebar-hook working --pid 1`) continua gravando.
- **Não** executado: ativar app de verdade (mexeria na tela do usuário), tmux (não instalado), outros terminais.

## Arquivos por funcionalidade (para o gestor ordenar)

| F | Arquivos | Depende de | Esforço |
|---|---|---|---|
| **F09** | novo `Sources/ClaudeBarCore/SessionNavigator.swift`; `git mv Sources/ClaudeBar/Shell.swift Sources/ClaudeBarCore/Shell.swift` (+`public`); `Sources/ClaudeBar/SessionStore.swift` (`goToSession`); `Sources/ClaudeBar/MenuContent.swift` (item); novo `Tests/ClaudeBarTests/SessionNavigatorTests.swift`; `README.md`, `README.pt-BR.md` | — | 3 h |
| **F10** | `Sources/ClaudeBar/StatusHUD.swift`, `Sources/ClaudeBar/Notifier.swift` (`onOpen`), `Sources/ClaudeBar/SessionStore.swift` (`notifyTransitions`); READMEs | F09 | 1 h |
| **F14** | `Sources/ClaudeBar/Notifier.swift` (`playSound`), `Sources/ClaudeBar/SessionStore.swift` (`isLookingAt` + `notifyTransitions`); READMEs | F09, **F01** (mesmo início de `post`) | 1 h |
| **F26** | `Sources/claudebar-hook/main.swift`; READMEs | F09 (para `next`) | 1,5 h |

Ordem: **F01 → F09 → F10 → F14 → F26** (F26 pode vir logo depois do F09; não toca nos arquivos do F10/F14).
Conflitos: F10 e F14 mexem nas mesmas linhas de `Notifier.post` e `notifyTransitions` → sequenciais. G06/F07.2 (`.failed`) também mexe em `Notifier`, `StatusHUD`, `SessionStore.notifyTransitions` → sequencial com F10/F14. F11 (abrir pasta) toca `MenuContent` no mesmo submenu → conflito trivial.
Não tocam: `Package.swift` (o Core já é dependência do hook), `scripts/`, `Info.plist`, `StatusDirectory`, `SessionStatus` (formato do arquivo não muda).

---

## F09 — Ir para a sessão (camada 1 + tmux)

### Objetivo

Item **"Ir para a sessão"** no submenu de cada sessão: traz para a frente o app que hospeda a sessão (Terminal, Ghostty, iTerm2, VS Code, Cursor, Warp, Claude.app). No tmux, troca também o cliente para o pane certo. Traz a janela, não a aba (aba exata = F30). Sem permissão TCC, sem shell.

### Decisão técnica

1. **Subir a árvore** a partir de `row.pid` (o processo `claude`, que vem do `claude agents --json` ou do `--pid $PPID` do hook) com `sysctl(KERN_PROC_PID)` → `kp_eproc.e_ppid`, até o primeiro `NSRunningApplication` com `activationPolicy == .regular`.
2. **Sem app na subida → tmux:** TTY do `claude` (`e_tdev` + `devname_r`) → `tmux list-panes -a` casando `pane_tty` → `list-clients -t <session_id>` → cliente de maior `client_activity` → `select-window`/`select-pane` no pane + `switch-client -c <client_tty> -t <session_id>` → subir a partir do `client_pid`.
3. **Ativar:** `activate(options: [])`; se recusado, `NSWorkspace.openApplication(at: bundleURL)`, que faz a ativação cooperativa sozinho.
4. **Onde fica:** `enum SessionNavigator` em `ClaudeBarCore` (com `import AppKit`) e `Shell` movido para o Core, porque o F26 usa o mesmo código no `claudebar-hook` e um executável do SwiftPM não pode depender de outro. Custo medido de AppKit no hook: ~1 ms por execução.
5. **Testabilidade:** a subida é uma função pura com `parent`/`isApp` injetados; o parsing do tmux é função pura sobre a string de saída.

Alternativas descartadas:
- `proc_pidinfo(PROC_PIDTBSDINFO)`: falha em processo de root (`/usr/bin/login` do Terminal.app); testado na pesquisa.
- Estender `ProcessProbe` (recomendação da pesquisa): ele vive no target `ClaudeBar`, invisível para a CLI; movê-lo exigiria init público e mexeria nos testes do terminator. Closures injetadas na função pura dão o mesmo teste.
- Protocolo `Navigating` + fake: uma implementação só, abstração especulativa.
- `activateIgnoringOtherApps` / `NSApp.activate(ignoringOtherApps:)`: sem efeito no macOS 14.
- AppleScript/`osascript`: Apple Events → TCC de Automação, instável com ad-hoc (F30).
- `switch-client -t %pane`: versão mínima do tmux não confirmada; `select-window` + `select-pane` + `switch-client -t <sessão>` existem em qualquer tmux.
- `TMUX_PANE`/`__CFBundleIdentifier` gravados pelo hook (plano B do agentoast): muda o formato do arquivo; só se a verificação manual mostrar que a subida falha (iTerm2, socket não padrão).
- `zsh -lc "command -v tmux"`: shell com string; se não está em caminho conhecido, não há tmux.
- Varredura `KERN_PROC_ALL`: só precisamos subir de um PID.
- Checar `executablePath` contém "claude" antes de navegar (como o terminator): ação não destrutiva; PID reciclado no pior caso ativa um app errado. `readAll` já descarta PID morto.

### Código — `Sources/ClaudeBarCore/Shell.swift` (movido)

`git mv Sources/ClaudeBar/Shell.swift Sources/ClaudeBarCore/Shell.swift`, só muda a visibilidade:

```swift
public enum Shell {
    public static func output(of url: URL, arguments: [String]) -> String? {
```

`AgentsProbe.swift`, `SessionTerminator.swift` e `SessionTerminatorTests.swift` já fazem `import ClaudeBarCore`: nenhuma outra mudança.

### Código — `Sources/ClaudeBarCore/SessionNavigator.swift` (novo, compilado)

```swift
import AppKit
import Darwin

/// Leva você até a sessão: sobe a árvore de processos do `claude` até o app que
/// a hospeda (terminal, editor, Claude.app) e traz esse app para a frente.
///
/// Nada aqui pede permissão: `sysctl`, `NSRunningApplication` e `NSWorkspace`
/// funcionam com assinatura ad-hoc. Trazer a **aba** exata exigiria Apple Events
/// (Automação), que fica para depois.
public enum SessionNavigator {
    /// App que hospeda a sessão do `pid` (o processo do `claude`).
    ///
    /// Dentro do tmux a subida termina no servidor (filho do `launchd`), então o
    /// caminho é outro: achar o pane pelo TTY, trocar o cliente para ele e subir
    /// a partir do cliente. `followTmux: false` pula essa parte — ela troca o
    /// pane de verdade, então só deve rodar quando você pediu para ir.
    ///
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

    /// Traz o app para a frente. No macOS 14 a ativação é cooperativa: o
    /// `activate` pode ser recusado quando quem pede não é o app ativo (um app
    /// de barra de menu, uma CLI). O `NSWorkspace` faz a cessão por nós.
    @MainActor
    public static func bringToFront(_ app: NSRunningApplication) async -> Bool {
        if app.activate(options: []) { return true }
        guard let url = app.bundleURL else { return false }
        // `activates` já é `true` por padrão; app em execução é reaproveitado.
        let opened = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return opened != nil
    }

    // MARK: - Árvore de processos

    /// Primeiro ancestral (incluindo o próprio `pid`) que é um app com janela.
    ///
    /// Função pura, para os testes descreverem árvores falsas. O limite evita
    /// laço infinito numa árvore inesperada.
    static func ancestor(of pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        for _ in 0..<64 where current > 1 {
            if isApp(current) { return current }
            guard let next = parent(current), next != current else { return nil }
            current = next
        }
        return nil
    }

    /// `.regular` pula helpers (Electron, `LSUIElement`), que também aparecem
    /// como `NSRunningApplication` mas não têm a janela da sessão.
    private static func isRegularApp(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    /// `sysctl`, não `proc_pidinfo`: este falha em processo de root, e o
    /// Terminal.app põe um `/usr/bin/login` (setuid root) entre ele e o shell.
    static func parentPID(_ pid: Int32) -> Int32? {
        kinfo(pid).map { $0.kp_eproc.e_ppid }
    }

    /// Terminal de controle do processo (ex. `/dev/ttys003`), ou `nil` sem TTY.
    static func ttyPath(of pid: Int32) -> String? {
        // `-1` é o `NODEV` do C (não importado pelo Swift): processo sem terminal.
        guard let device = kinfo(pid)?.kp_eproc.e_tdev, device != -1 else { return nil }
        var buffer = [CChar](repeating: 0, count: 64)
        // `devname_r`, não `devname`: este devolve um buffer estático.
        let name = buffer.withUnsafeMutableBufferPointer { pointer in
            devname_r(device, S_IFCHR, pointer.baseAddress, Int32(pointer.count)).map { String(cString: $0) }
        }
        guard let name, name != "??" else { return nil }
        return "/dev/\(name)"
    }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // PID inexistente devolve sucesso com `size == 0`.
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    // MARK: - tmux

    /// Um app de barra de menu não herda o `PATH` do shell. Sem `zsh -lc` de
    /// reserva: se o tmux não está num caminho conhecido, não há tmux.
    private static let tmuxURL: URL? = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    .first { FileManager.default.isExecutableFile(atPath: $0) }
    .map { URL(fileURLWithPath: $0) }

    /// Troca o cliente tmux mais recente para o pane da sessão e devolve o PID
    /// dele — é o cliente que roda dentro do terminal. Só o socket padrão.
    ///
    /// `select-window` + `select-pane` + `switch-client` para a sessão existem em
    /// qualquer tmux; `switch-client -t %pane` só nas versões novas.
    private static func switchTmuxClient(toSessionOf pid: Int32) -> Int32? {
        guard let tmux = tmuxURL,
              let tty = ttyPath(of: pid),
              let panes = Shell.output(of: tmux, arguments: ["list-panes", "-a", "-F", "#{pane_tty}\t#{pane_id}\t#{session_id}"]),
              let target = pane(forTTY: tty, in: panes),
              let clients = Shell.output(of: tmux, arguments: ["list-clients", "-t", target.session, "-F", "#{client_activity}\t#{client_tty}\t#{client_pid}"]),
              let client = mostRecentClient(in: clients)
        else { return nil }

        // Argumentos separados, nunca interpolados: id e tty vêm do tmux, mas
        // continuam não passando por shell.
        _ = Shell.output(of: tmux, arguments: ["select-window", "-t", target.pane])
        _ = Shell.output(of: tmux, arguments: ["select-pane", "-t", target.pane])
        _ = Shell.output(of: tmux, arguments: ["switch-client", "-c", client.tty, "-t", target.session])
        return client.pid
    }

    /// Linha de `list-panes -a -F '#{pane_tty}\t#{pane_id}\t#{session_id}'`
    /// cujo TTY é o do `claude`. Linha fora do formato é ignorada.
    static func pane(forTTY tty: String, in listPanes: String) -> (pane: String, session: String)? {
        for line in listPanes.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 3, fields[0] == tty {
                return (String(fields[1]), String(fields[2]))
            }
        }
        return nil
    }

    /// Com vários terminais anexados à mesma sessão, o que você usou por último.
    static func mostRecentClient(in listClients: String) -> (tty: String, pid: Int32)? {
        listClients.split(separator: "\n")
            .compactMap { line -> (activity: Int, tty: String, pid: Int32)? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count == 3, let activity = Int(fields[0]), let pid = Int32(fields[2]) else { return nil }
                return (activity, String(fields[1]), pid)
            }
            .max { $0.activity < $1.activity }
            .map { ($0.tty, $0.pid) }
    }
}
```

Notas de compilação (encontradas ao compilar): `NODEV` não é importado pelo Swift (usar `-1`); `#{session_id}` (`$N`) em vez de `session_name` evita nome com `:`/espaço virar alvo ambíguo no `-t`.

### Código — `Sources/ClaudeBar/SessionStore.swift`

Novo método público, antes de `confirmTermination`:

```swift
    /// Traz para a frente o app (terminal, editor, Claude.app) onde a sessão
    /// roda. No tmux, troca também o pane. Traz a janela, não a aba.
    func goToSession(_ row: SessionRow) {
        guard let pid = row.pid, pid > 0 else { return }
        acknowledged.insert(row.sessionId)

        Task {
            // `sysctl` e `tmux` são síncronos: fora da main actor.
            let app = await Task.detached(priority: .userInitiated) {
                SessionNavigator.app(for: pid)
            }.value
            if let app, await SessionNavigator.bringToFront(app) { return }
            report(
                title: "Não foi possível ir até \(row.name)",
                message: """
                \(row.cwd)

                Não achei o terminal ou app dessa sessão. No tmux, só o socket \
                padrão é suportado e precisa haver um terminal anexado.
                """
            )
        }
    }
```

`Task { }` dentro de método `@MainActor` herda a main actor; `NSRunningApplication` é `Sendable`. Se o F11 já estiver em `main`, trocar o `report` por abrir a pasta (`NSWorkspace.shared.open(URL(fileURLWithPath: row.cwd))`) é a próxima linha natural — não antes.

### Código — `Sources/ClaudeBar/MenuContent.swift`

Dentro do `Menu(label(for: row))`, logo depois do primeiro `Divider()`:

```swift
                    // Subagente background não tem terminal para onde ir.
                    if !row.isSubagent, let pid = row.pid, pid > 0 {
                        Button("Ir para a sessão") {
                            store.goToSession(row)
                        }
                    }
```

Clicar na linha principal continua só abrindo o submenu (nada de ação ao passar o mouse).

### Testes — `Tests/ClaudeBarTests/SessionNavigatorTests.swift` (novo, 9 testes, passando)

```swift
import Foundation
import Testing

@testable import ClaudeBarCore

/// Árvore falsa: `filho → pai`. O que não está aqui não tem pai.
private func tree(_ edges: [Int32: Int32]) -> (Int32) -> Int32? {
    { edges[$0] }
}

@Suite("Subida até o app da sessão")
struct SessionNavigatorTreeTests {
    /// Terminal.app: claude → zsh → login (root) → Terminal.
    @Test func terminalSobeAteOApp() {
        let parent = tree([500: 400, 400: 300, 300: 200, 200: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { $0 == 200 }) == 200)
    }

    /// VS Code/Cursor: o helper do Electron não é `.regular` e fica para trás.
    @Test func helperNaoEOApp() {
        let parent = tree([500: 450, 450: 200, 200: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { $0 == 200 }) == 200)
    }

    /// tmux: claude → servidor tmux → launchd. Sem app: cai no caminho do tmux.
    @Test func tmuxTerminaSemApp() {
        let parent = tree([500: 300, 300: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { _ in false }) == nil)
    }

    @Test func cicloNaoTravaASubida() {
        let parent = tree([500: 400, 400: 500])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { _ in false }) == nil)
    }

    /// Processo de teste tem pai, e PID inexistente não tem.
    @Test func parentPidDeVerdade() {
        #expect(SessionNavigator.parentPID(getpid()) == getppid())
        #expect(SessionNavigator.parentPID(99_999_999) == nil)
    }
}

@Suite("Saídas do tmux")
struct TmuxParsingTests {
    private let panes = "/dev/ttys001\t%0\t$0\n/dev/ttys004\t%7\t$2\n"

    @Test func achaOPanePeloTTY() {
        let found = SessionNavigator.pane(forTTY: "/dev/ttys004", in: panes)
        #expect(found?.pane == "%7")
        #expect(found?.session == "$2")
    }

    /// `ttys00` não pode casar com `ttys001`: comparação exata, não prefixo.
    @Test func ttyParecidoNaoCasa() {
        #expect(SessionNavigator.pane(forTTY: "/dev/ttys00", in: panes) == nil)
    }

    @Test func escolheOClienteUsadoPorUltimo() {
        let clients = "1700000000\t/dev/ttys002\t111\n1700000500\t/dev/ttys009\t222\nlixo\n"
        let client = SessionNavigator.mostRecentClient(in: clients)
        #expect(client?.tty == "/dev/ttys009")
        #expect(client?.pid == 222)
    }

    @Test func semClienteAnexado() {
        #expect(SessionNavigator.mostRecentClient(in: "") == nil)
    }
}
```

Não testar `bringToFront` nem `app(for:)` com ativação real em `swift test` (mudaria o foco da tela de quem roda e o CI não tem sessão gráfica).

### README / scripts

- `README.md` e `README.pt-BR.md`, em "The menu": submenu ganha **Ir para a sessão** (*go to session*). Nova subseção "Going to a session" com: sobe a árvore de processos até o app; no tmux troca o pane (socket padrão, precisa de cliente anexado); traz a janela, não a aba; sem permissão. E a **matriz de suporte** com status honesto:

  | Terminal | Status |
  |---|---|
  | Claude desktop app | verificado (traz o app, não a conversa) |
  | Terminal.app, Ghostty, iTerm2, VS Code, Cursor, Warp | não verificado |
  | tmux (socket padrão) | não verificado |

  Cada linha vira "verificado" só depois do passo manual abaixo.
- "Project structure": `Shell.swift` sai de `Sources/ClaudeBar/` e entra em `Sources/ClaudeBarCore/`; nova linha `SessionNavigator.swift   process tree → app, tmux pane, activation`.
- "Security": no bullet "No command goes through a shell", citar `tmux` ao lado de `claude` (executado por caminho conhecido, argumentos separados).
- `scripts/`: nenhuma mudança.

### Verificação manual (não verificável por agente)

Com `scripts/install.sh` aplicado e uma sessão aberta em cada terminal:
1. Para cada terminal da matriz: deixar outro app na frente → menu → sessão → **Ir para a sessão** → o terminal certo vem para a frente. Anotar o resultado na matriz.
2. Se falhar: `ps -o pid,ppid,user,comm -p <pid>` subindo até achar o app; anotar a cadeia (é o insumo para o plano B).
3. tmux: duas sessões tmux, `claude` no pane 2 da janela 2 da sessão B, terminal anexado mostrando a sessão A → **Ir para a sessão** → o terminal vem para a frente mostrando sessão B, janela 2, pane 2.
4. tmux sem cliente anexado (`tmux detach`) → alerta "Não foi possível ir até…".
5. Sessão do Claude.app → o app vem para a frente (pode estar em outra conversa: esperado).
6. Subagente background → o item não aparece.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| iTerm2: `iTermServer` com pai `launchd` (não confirmado) → subida não acha app | Alerta honesto. Se confirmado no passo manual 2: plano B em PR próprio — hook grava `__CFBundleIdentifier` como campo **opcional** em `SessionStatus` (o `Codable` sintetizado usa `decodeIfPresent`, arquivos antigos seguem válidos) e o navegador ativa por bundle id. |
| `activate` recusado a partir de app `.accessory` (não confirmado) | Fallback `openApplication`, que a Apple documenta como fazendo a cessão cooperativa. Se ambos falharem na verificação: anotar e avaliar `/usr/bin/open -b <bundleId>` via `Shell` (não antes). |
| `openApplication` abrir segunda instância | `createsNewApplicationInstance` é `false` por padrão; conferir no passo 1. |
| tmux com socket não padrão (`-L`, `TMUX_TMPDIR`) | Não suportado; `list-panes` falha → alerta cita "só o socket padrão". Plano B (`TMUX` gravado pelo hook) só se alguém pedir. Não replicar o `env_remove("TMPDIR")` do agentoast: o tmux usa `TMUX_TMPDIR`, não `TMPDIR`. |
| `switch-client -c <tty>` de fora do tmux não funcionar (não confirmado) | Resultado de cada comando é ignorado; o terminal do cliente vem para a frente mesmo assim (degrada para "janela certa, pane talvez não"). |
| Servidor tmux com ancestral GUI (não daemonizado) | A subida acha o terminal que iniciou o servidor e ativa sem trocar pane. Aceito. |
| `Shell.output` bloqueia | Sempre em `Task.detached`; nunca na main actor com `followTmux: true`. |
| PID reciclado | Não destrutivo; `readAll` já remove PID morto. |
| Mover `Shell` quebra algo | Só visibilidade; build e 34 testes atuais verdes na cópia. |

### Critérios de aceite

- `swift build` sem avisos novos; `swift test` com os 9 testes novos passando e nenhum removido.
- `SessionNavigator` em `ClaudeBarCore`, sem protocolo; `Shell` público no Core; nenhum `Process` com `/bin/sh`/`zsh` novo.
- O tmux só é chamado com caminho absoluto e argumentos separados; nenhuma string montada vira comando.
- `SessionNavigator.app(for:)` (com tmux) só é chamado fora da main actor.
- Item "Ir para a sessão" aparece para sessão com `pid > 0` e não aparece para subagente.
- Falha mostra alerta com nome e pasta, sem crash.
- README com a matriz e os status reais (nada "verificado" sem o passo manual).

### O que NÃO fazer

- Não usar `proc_pidinfo` para PPID, nem `devname` (sem `_r`).
- Não usar `activateIgnoringOtherApps`, AppleScript, `osascript`, Accessibility ou qualquer coisa que peça TCC.
- Não procurar o tmux com `zsh -lc`; não rodar tmux via shell.
- Não gravar `TMUX_PANE`/`__CFBundleIdentifier` agora; não mudar o formato do arquivo de estado.
- Não criar protocolo/fake de navegador nem mover `ProcessProbe`.
- Não chamar `claude agents` do navegador.
- Não ativar app nos testes automáticos.

---

## F10 — Alerta leva à sessão

### Objetivo

Clicar no popup do ClaudeBar ("Claude terminou" / "Claude está esperando você") leva à sessão (F09) e fecha o popup. O popup de exemplo continua só fechando.

### Decisão técnica

Closure opcional `onOpen: (@MainActor () -> Void)?` passada de `SessionStore` → `Notifier.post` → `StatusHUD.show` → chamada no `onTapGesture` antes do `dismiss`. O HUD não conhece sessão nem navegador.

Alternativas descartadas:
- Passar `sessionId`/`pid` para o HUD e ele chamar o navegador: acopla UI a processo.
- Botão "Ir" separado no popup: clique no popup inteiro já é o gesto esperado; mais layout sem ganho.
- `UNUserNotificationCenterDelegate` para a notificação nativa: só existe com Developer ID (F28); hoje sempre cai no HUD. Fazer junto do F28.

### Código

`Sources/ClaudeBar/StatusHUD.swift`:

```swift
    /// - Parameter onOpen: chamado no clique, antes de fechar — leva à sessão.
    func show(_ alert: Alert, body: String, onOpen: (@MainActor () -> Void)? = nil) {
        let content = HUDView(alert: alert, body: body, width: Self.width) { [weak self] in
            onOpen?()
            self?.dismiss()
        }
```

(`HUDView` não muda: `onDismiss` passa a ser "ao clicar".)

`Sources/ClaudeBar/Notifier.swift` (assinatura final, já com F14 e F01; se o F10 entrar antes do F14, sem `playSound`):

```swift
    /// - Parameters:
    ///   - playSound: `false` quando você já está olhando o app da sessão (F14):
    ///     o popup ainda aparece, só o som fica quieto.
    ///   - onOpen: o que o clique no popup faz (F10). `nil` = só fecha.
    func post(
        _ alert: Alert,
        body: String,
        playSound: Bool = true,
        onOpen: (@MainActor () -> Void)? = nil
    ) {
        // Desligado no menu = silêncio total: nem popup nem som.
        guard isEnabled else { return }

        if playSound {
            if let soundOverride {
                soundOverride(alert)
            } else {
                play(alert)
            }
        }

        guard canUseSystemNotifications else {
            // Caminho normal com assinatura ad-hoc: popup desenhado pelo app.
            hud.show(alert, body: body, onOpen: onOpen)
            return
        }
        // … resto igual (notificação nativa ignora `onOpen` até o F28)
```

`Sources/ClaudeBar/SessionStore.swift`, dentro do `for` de `notifyTransitions`, antes do `switch`:

```swift
            // Clique no popup leva à sessão (F10).
            let open: @MainActor () -> Void = { [weak self] in self?.goToSession(row) }
```

e nos dois `post`: `…, onOpen: open)`. `showSample()` não muda (sem `onOpen`).

### Testes

Nenhum automático novo: a lógica é repassar uma closure; testar exigiria criar `NSPanel` e simular clique no processo de teste (G01 já decidiu evitar `hud.show` real em teste). O caminho de navegação está coberto no F09. Gate: build + testes existentes verdes.

### README

"Alerts": "Clicking the popup takes you to the session (same as **Go to session**); the sample popup only closes." Idem pt-BR.

### Verificação manual

1. Outro app na frente; sessão termina → popup aparece → clicar → terminal da sessão vem para a frente e o popup some.
2. Sessão esperando permissão → popup → clicar → idem; o ícone deixa de mostrar "pronto" para aquela sessão (ela foi marcada como vista).
3. "Ver exemplo de popup" → clicar → só fecha.
4. Não clicar → some em 4 s como hoje.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Painel `.nonactivatingPanel` + app `.accessory` → `activate` recusado (não confirmado) | Fallback `openApplication` do F09. Verificar no passo 1. |
| `row` capturado fica velho (sessão fechou) | `goToSession` cai no alerta de falha; não destrutivo. |
| Popup de outra sessão substitui o atual (mesmo painel) | O `HUDView` novo carrega a closure nova: o clique vai para a sessão mostrada. |

### Critérios de aceite

- Clique no popup chama `goToSession` da sessão do aviso e fecha o popup.
- Popup de exemplo sem navegação.
- `HUDView` sem referência a `SessionNavigator`/`SessionRow`.
- Build sem avisos, testes existentes verdes.

### O que NÃO fazer

- Não tornar o painel ativável (`canBecomeKey`) nem tirar `.nonactivatingPanel`: roubaria foco.
- Não implementar delegate de notificação nativa agora.
- Não adicionar botões ao popup.

---

## F14 — Não tocar som se você já está olhando (nível app)

### Objetivo

Se o app que hospeda a sessão já é o app da frente, o aviso sai sem som (o popup continua). Ex.: você está no Terminal onde o Claude acabou de responder.

### Decisão técnica

`playSound: Bool = true` em `Notifier.post`. Em `notifyTransitions`, `playSound: !isLookingAt(row)`, com `isLookingAt` comparando `SessionNavigator.app(for: pid, followTmux: false)?.processIdentifier` com `NSWorkspace.shared.frontmostApplication?.processIdentifier`. Sem tmux: seguir o tmux **troca o pane** (efeito colateral) e roda processo na main actor. A subida é só `sysctl` (microssegundos), roda na main actor sem cache.

Alternativas descartadas:
- Suprimir o popup também: o backlog pede só o som; o popup é silencioso e some sozinho.
- Ler pane ativo do tmux (`#{pane_active}`, `client_tty`) para acertar no tmux: mais 2 processos por aviso na main; depois, se pedirem.
- Nível aba/conversa: exige Apple Events (F30).
- Cache do app por sessão: custo já é desprezível.
- Observar `NSWorkspace.didActivateApplicationNotification`: `frontmostApplication` lido na hora basta.

### Código

`Notifier.post`: ver a assinatura em F10 (bloco `if playSound { … }`). **Pré-requisito F01** (G01): o `guard isEnabled` já na primeira linha e o `soundOverride`; o F14 só envolve a chamada do som no `if playSound`.

`Sources/ClaudeBar/SessionStore.swift`, novo método privado (perto de `goToSession`):

```swift
    /// Você já está olhando o app da sessão? Então o som é dispensável (F14).
    ///
    /// Nível app: Claude.app na frente com outra conversa aberta também conta
    /// como "olhando". Sem tmux aqui — seguir o tmux troca o pane de verdade.
    private func isLookingAt(_ row: SessionRow) -> Bool {
        guard let pid = row.pid, pid > 0,
              let front = NSWorkspace.shared.frontmostApplication,
              let app = SessionNavigator.app(for: pid, followTmux: false)
        else { return false }
        return app.processIdentifier == front.processIdentifier
    }
```

e em `notifyTransitions`:

```swift
            case .idle where previous == .working:
                acknowledged.remove(row.sessionId)
                notifier.post(.finished, body: row.name, playSound: !isLookingAt(row), onOpen: open)
            case .waiting:
                acknowledged.remove(row.sessionId)
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto quando ele está travado.
                notifier.post(.waiting, body: row.message ?? row.name, playSound: !isLookingAt(row), onOpen: open)
```

(`SessionStore.swift` já faz `import AppKit`.)

### Testes — `Tests/ClaudeBarTests/AlertTests.swift`

Um teste, no estilo do `desligadoNaoTocaSom` do G01, mas pelo caminho que **não** cria painel: com `playSound: false` não pode haver som. Como `post` ligado chega a `hud.show`, e o G01 decidiu não criar `NSPanel` em teste, o teste de F14 fica **adiado** junto com o "ligado toca" do G01. A decisão (`processIdentifier ==`) é uma linha; a subida está coberta pelos testes do F09. Gate: build + testes verdes.

Se o gestor quiser cobertura: extrair `static func shouldPlaySound(sessionApp: pid_t?, frontmost: pid_t?) -> Bool` só se a regra crescer (ex.: tmux, F15 com opção "sempre tocar"). Hoje não.

### README

"Alerts": "No sound if the session's app is already in front (the popup still shows). App level only: with the Claude desktop app in front, any of its conversations counts; inside tmux the sound always plays." Idem pt-BR.

### Verificação manual

1. Terminal da sessão na frente → sessão termina → popup aparece **sem** `Glass`.
2. Outro app na frente → toca `Glass`.
3. Pedido de permissão com o terminal na frente → popup sem `Submarine`.
4. Sessão em tmux com o terminal na frente → toca (limite documentado).

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Claude.app na frente, outra conversa → silencia errado | Aceito pelo backlog (nível app); documentado no README. Popup continua. |
| tmux sempre toca | Documentado; melhoria futura listada acima. |
| `frontmostApplication` desatualizado | Só atualiza com o run loop principal girando — é o caso no app (`notifyTransitions` roda na main). |
| Subida falha (iTerm2) → toca | Comportamento de hoje; falha segura (melhor tocar a mais que a menos). |

### Critérios de aceite

- `post(..., playSound: false)` não toca som e ainda mostra o popup.
- `isLookingAt` usa `followTmux: false` (nenhum `tmux` disparado por aviso).
- Toggle desligado continua silenciando tudo (teste do F01 verde).

### O que NÃO fazer

- Não esconder o popup.
- Não chamar tmux na main actor nem trocar pane ao avisar.
- Não criar chave de ajuste para isso (F15 decide).

---

## F26 — CLI `status` / `next`

### Objetivo

Sem abrir o menu:
- `claudebar-hook status [--json]`: lista as sessões (uma por linha, `estado<TAB>projeto<TAB>pasta`; `--json` no formato dos arquivos de estado). Serve para a barra do tmux, scripts e leitor de tela.
- `claudebar-hook next`: traz para a frente a sessão que espera você há mais tempo (F09). Sai com 1 se não houver.

Nenhuma ação destrutiva.

### Decisão técnica

- Despachar `status`/`next` **antes** de `run()`, que lê todo o stdin: digitado num terminal, o stdin é o tty e nunca chega EOF — o comando travaria. O caminho do hook (`working|idle|waiting|end`) fica byte a byte igual.
- `status` lê `StatusDirectory.readAll()` (já filtra morto e ordena do mais novo). Não chama `claude agents` (lento, ~150 ms, e o hook não deve depender do CLI).
- `next`: menor `updatedAt` entre `.waiting` com `pid > 0`; `SessionNavigator.app(for:)` + `bringToFront` com `await` no top-level do `main.swift` (Swift 6: top-level é `@MainActor` e aceita `await`), o que mantém o processo vivo até o `openApplication` responder.
- Mesmo binário: AppKit no hook custa ~1 ms (medido na pesquisa).

Alternativas descartadas:
- Binário `claudebar` separado: mais um target, mais um item no bundle e no install; o nome do executável não é o problema.
- `DispatchSemaphore`/`RunLoop.run(until:)` para esperar o `openApplication`: o `await` no top-level já resolve.
- Pedir ao app via URL scheme/socket: exige app aberto e um canal local novo.
- `--json` com formato próprio: reusar `StatusDirectory.encoder` dá saída estável e já documentada.
- Ler `isatty(0)` para decidir: ainda leria o stdin no caminho do hook; despachar pelo comando é mais simples e sem ambiguidade.

### Código — `Sources/claudebar-hook/main.swift` (compilado e executado)

Cabeçalho:

```swift
// Uso: claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>]
//      claudebar-hook status [--json]   lista as sessões (para você, não para o hook)
//      claudebar-hook next              vai para a sessão esperando há mais tempo
```

`run()` não muda. A última linha (`run()`) é substituída por:

```swift
/// `status`: o que os hooks gravaram, uma sessão por linha, separada por tab
/// (estado, projeto, pasta) — fácil de usar na barra do tmux. `--json` reusa o
/// formato dos arquivos de estado.
///
/// Só vê sessões que já dispararam um hook: não chama `claude agents`.
/// `readAll` apaga arquivos de processos mortos, como o app já faz.
private func printStatus(json: Bool) {
    let sessions = StatusDirectory.readAll()
    if json {
        let data = (try? StatusDirectory.encoder.encode(sessions)) ?? Data("[]".utf8)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        return
    }
    for session in sessions {
        print("\(session.state.rawValue)\t\(session.projectName)\t\(session.cwd)")
    }
}

/// `next`: a sessão que espera você há mais tempo vem para a frente.
@MainActor
private func goToNextWaiting() async -> Int32 {
    let waiting = StatusDirectory.readAll()
        .filter { $0.state == .waiting && $0.pid > 0 }
        .min { $0.updatedAt < $1.updatedAt }
    guard let waiting else {
        print("nenhuma sessão esperando você")
        return 1
    }
    guard let app = SessionNavigator.app(for: waiting.pid), await SessionNavigator.bringToFront(app) else {
        print("não achei o app de \(waiting.projectName) (\(waiting.cwd))")
        return 1
    }
    print(waiting.projectName)
    return 0
}

// `status` e `next` são digitados por você: o stdin é o terminal e nunca chega
// EOF. Por isso são tratados antes de `run()`, que lê o stdin inteiro.
let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "status":
    printStatus(json: arguments.contains("--json"))
case "next":
    exit(await goToNextWaiting())
default:
    run()
}
```

No `next`, o `SessionNavigator.app` roda síncrono na main da CLI: aceitável (não há UI para travar).

### Testes

Lógica nova é filtro + `min` sobre `readAll`, que já tem uso no app; o navegador está coberto no F09. Não criar teste que escreva em `~/.claude/claudebar` real (o `StatusDirectory.url` é fixo; torná-lo injetável só para isso é abstração especulativa). Verificação por execução, abaixo (já feita na cópia para `status`, `status --json` com pty e `next` sem sessão).

### README / scripts

- "Development" → "Hook CLI usage" vira:

  ```
  claudebar-hook <working|idle|waiting|end> [--pid <claude pid>]   # called by the hooks
  claudebar-hook status [--json]   # list sessions (state, project, folder)
  claudebar-hook next              # bring the longest-waiting session to the front
  ```

- Nova subseção curta "Command line" em Features com exemplo de alias e da barra do tmux:

  ```bash
  alias claudebar=~/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook
  # ~/.tmux.conf: quantas sessões esperando você
  set -g status-right '#(~/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook status | grep -c ^waiting)'
  ```

  Aviso: `status` só vê sessões que já dispararam hook (a contagem do menu também usa `claude agents`).
- `scripts/install.sh`: nenhuma mudança (não criar symlink em `PATH` — decisão do usuário).

### Verificação manual

1. `claudebar-hook status` num terminal → responde na hora (não espera Ctrl-D).
2. `claudebar-hook status --json | jq .` → array válido.
3. Sem sessão esperando: `claudebar-hook next; echo $?` → mensagem e `1`.
4. Com uma sessão esperando permissão em outro terminal: `claudebar-hook next` → aquele terminal vem para a frente; `0`. **Confere o caso não confirmado da pesquisa: ativação a partir de CLI.**
5. Hook continua: nova sessão do Claude Code → arquivo de estado aparece e muda com prompt/resposta.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Ativação a partir de CLI recusada (não confirmado) | `bringToFront` cai no `openApplication`. Se o passo 4 falhar: avaliar `/usr/bin/open -b <bundleId>` via `Shell` em PR próprio. `status` não é afetado. |
| AppKit no binário do hook atrasar/quebrar o hook | ~1 ms medido; o caminho do hook não chama AppKit. `run()` inalterado mantém o fail-open (erro só no stderr). |
| `status` apagar arquivos | Só de PID morto/JSON inválido, igual ao app. Documentado no comentário. |
| `next` com tmux troca pane do seu terminal | É o pedido explícito ("ir"); documentado. |
| `pid: 0` (hook sem `--pid`) | Filtrado em `next`; aparece normal em `status`. |

### Critérios de aceite

- `status`/`status --json`/`next` não leem stdin e retornam em < 1 s com stdin num tty.
- `--json` decodifica como `[SessionStatus]` com `StatusDirectory.decoder`.
- `next` sem sessão esperando: saída 1 e mensagem; com sessão: saída 0 e nome do projeto.
- Caminho `working|idle|waiting|end` sem diff em `run()`.
- Nenhuma escrita nova em disco; nenhuma ação destrutiva.

### O que NÃO fazer

- Não ler stdin antes do despacho; não usar `isatty` para decidir.
- Não chamar `claude agents` nem rede na CLI.
- Não criar comando que finalize/aprove sessão (F46 vetado).
- Não criar target/binário novo nem mexer no `install.sh`.

---

## Itens não confirmados da pesquisa → como a implementação se protege

| Não confirmado | Proteção nesta spec |
|---|---|
| Cadeia de processos em Terminal.app/Ghostty/iTerm2/VS Code/Cursor/Warp | `sysctl` (passa por `login` root) + filtro `.regular` (pula helpers); falha → alerta honesto; README marca "não verificado" até o passo manual. |
| iTerm2 com `iTermServer` filho do `launchd` | Plano B (`__CFBundleIdentifier` opcional) **adiado** até a verificação mostrar a falha. |
| `activate`/`openApplication` de app `.accessory` e de CLI | Dois caminhos encadeados; `/usr/bin/open -b` só se ambos falharem na verificação. |
| tmux: pai do servidor, `switch-client -t %pane`, `-c` de fora | Comandos de qualquer versão; resultados ignorados (degrada para "janela certa"); ancestral GUI aceito. |
| Socket fora do padrão / `TMPDIR` | Não suportado, mensagem explícita; nada de `env_remove`. |
| `__CFBundleIdentifier`, `TERM_PROGRAM` | Não usados. |
| Clique em `.nonactivatingPanel` | Verificação manual do F10. |
| `openApplication` reaproveitar instância | Padrão documentado (`createsNewApplicationInstance = false`); verificação manual. |

## Esforço total

F09 3 h · F10 1 h · F14 1 h · F26 1,5 h = **6,5 h** (código já validado em cópia; inclui READMEs, PRs e roteiro manual, não a execução manual em cada terminal, que depende do usuário).

> **Nota do usuário:** `activate(ignoringOtherApps:)` vai ser descontinuada numa versão futura do macOS. Não usar em código novo (ver TODO.md, "Deprecated APIs"). Pesquisar a substituta depois.
