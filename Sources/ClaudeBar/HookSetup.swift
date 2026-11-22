import AppKit
import ClaudeBarCore
import Observation

/// A integração com o Claude Code vista pelo app: detecta o estado, mostra o
/// diff exato e só grava com o seu clique. Nunca repara em silêncio.
@MainActor
@Observable
final class HookSetup {
    private(set) var state: IntegrationState = .notInstalled
    /// Gemini CLI instalado: só então aparecem os itens dele no menu.
    private(set) var geminiDetected = false
    private let defaults = UserDefaults.standard

    /// Último estado já oferecido no launch: oferecer de novo só se mudar.
    private static let offeredKey = "hookSetupOfferedState"

    /// O hook que veio neste `.app`. No `swift run`, o executável ao lado.
    private let bundledBinary = Bundle.main.url(forAuxiliaryExecutable: "claudebar-hook")

    init() {
        refresh()
        // Fora do init: o `SessionStore` nasce antes do app terminar de
        // abrir, e um alerta modal ali apareceria cedo demais.
        Task { @MainActor in self.offerIfNeeded() }
    }

    var menuTitle: String {
        switch state {
        case .ok: String(localized: "Claude Code integration: ok")
        case .notInstalled: String(localized: "Integration: hooks not installed")
        default: String(localized: "⚠︎ Integration needs attention")
        }
    }

    var summary: String {
        switch state {
        case .ok: String(localized: "Hooks registered and executable up to date")
        case .notInstalled: String(localized: "Without hooks, the app only sees sessions once a minute")
        case .binaryMissing: String(localized: "The hook executable is gone from ~/.claude/claudebar/bin")
        case .binaryOutdated: String(localized: "The hook executable is from another version of the app")
        case .hooksOutdated: String(localized: "Awaitbar hooks are missing from settings.json")
        case .legacyHooks: String(localized: "Hooks in the old format (path inside the .app)")
        case .invalidSettings: String(localized: "settings.json is not valid JSON — nothing will be changed")
        case .readOnlySettings: String(localized: "settings.json is read-only: paste the JSON into the tool that generates it")
        case .hooksDisabled: String(localized: "disableAllHooks is on in your settings.json")
        }
    }

    var canRemove: Bool {
        ![.notInstalled, .invalidSettings, .readOnlySettings].contains(state)
    }

    func refresh() {
        state = HookInstaller.state(bundledBinary: bundledBinary)
        geminiDetected = GeminiHooks.cliDetected()
        // Voltou ao normal: a próxima quebra (ex.: atualização do app) pode ser oferecida.
        if state == .ok {
            defaults.removeObject(forKey: Self.offeredKey)
        }
    }

    /// Oferece instalar ou reparar uma vez por estado novo. "Pular" não grava nada.
    private func offerIfNeeded() {
        let offerable: [IntegrationState] = [.notInstalled, .binaryMissing, .binaryOutdated, .hooksOutdated, .legacyHooks]
        let key = "\(state)"
        guard offerable.contains(state), defaults.string(forKey: Self.offeredKey) != key else { return }
        defaults.set(key, forKey: Self.offeredKey)
        review(.install, cancelTitle: String(localized: "Skip"))
    }

    /// Mostra exatamente o que muda e grava só se você clicar na ação.
    /// `gemini`: o mesmo fluxo sobre o `~/.gemini/settings.json` (só `.install`/`.uninstall`).
    func review(_ action: HookAction, gemini: Bool = false, cancelTitle: String = String(localized: "Cancel")) {
        let plan: HookPlan
        do {
            plan = try gemini ? GeminiHooks.plan(action) : HookInstaller.plan(action)
        } catch {
            return report(title: String(localized: "Could not read settings.json"), message: error.localizedDescription)
        }

        let stable = HookInstaller.stableBinary
        let installs = action == .install || action == .installStatusLine
        if installs, bundledBinary == nil, !FileManager.default.isExecutableFile(atPath: stable.path) {
            return report(
                title: String(localized: "Hook executable not found"),
                message: String(localized: "Open Awaitbar from the .app.")
            )
        }
        let copiesBinary = installs && bundledBinary.map {
            !FileManager.default.contentsEqual(atPath: $0.path, andPath: stable.path)
        } == true
        // Remover também apaga a cópia do executável: conta como mudança e aparece no alerta.
        // Se o statusline ou os hooks ainda a chamam, ela fica.
        let removesBinary = !installs && !plan.binaryInUse
            && FileManager.default.fileExists(atPath: stable.path)

        guard plan.hasChanges || copiesBinary || removesBinary else {
            return report(title: String(localized: "Nothing to change"), message: plan.settingsURL.path)
        }

        let backups = gemini ? GeminiHooks.backupsURL : HookInstaller.backupsURL
        let alert = NSAlert()
        alert.messageText = switch action {
        case .install where gemini: String(localized: "Register the Awaitbar hooks in Gemini CLI?")
        case .uninstall where gemini: String(localized: "Remove the Awaitbar hooks from Gemini CLI?")
        case .install: String(localized: "Register the Awaitbar hooks in Claude Code?")
        case .uninstall: String(localized: "Remove the Awaitbar hooks?")
        case .installStatusLine: String(localized: "Show usage limits in the Claude Code footer?")
        case .uninstallStatusLine: String(localized: "Stop showing limits in the Claude Code footer?")
        }
        var info: [String] = []
        if plan.hasChanges {
            info.append(String(localized: "File: \(plan.settingsURL.path)"))
            info.append(String(localized: "Backup before writing, in \(backups.path)"))
            if plan.reformats {
                info.append(String(localized: """
                The file will be reformatted (key order); outside "hooks" and "statusLine" \
                the content doesn't change.
                """))
            }
            // Só `hooks` e `statusLine`: o resto do settings pode ter token em `env`.
            alert.accessoryView = codeView(plan.diff)
        }
        if copiesBinary {
            info.append(String(localized: "Copies the hook executable to \(stable.path)."))
        }
        if removesBinary {
            info.append(String(localized: "Deletes the hook executable at \(stable.path)."))
        }
        switch (action, plan.statusLineOriginal) {
        case (.installStatusLine, .save?):
            info.append(String(localized: """
                Your statusline keeps showing as before. Awaitbar only reads the limits before \
                passing it on. The original is kept at \(StatusDirectory.originalStatusLineURL.path).
                """))
        case (.installStatusLine, _):
            // O exemplo fica fora da chave: é a saída real do statusline, e o `%` dele
            // viraria `%%` na tabela.
            let example = "`5h 23% · sem 41%`"
            info.append(String(localized: """
                Claude Code hides some footer hints (like `esc to interrupt`) when there is a \
                statusline. In their place you see \(example). Limits only show for Pro, Max \
                and Ultra subscribers.
                """))
        case (.uninstallStatusLine, _):
            info.append(String(localized: "The statusLine you had before comes back as it was; if you changed it since, yours stays."))
        default:
            info.append(
                [
                    String(localized: "Only Awaitbar's entries change; your own hooks stay as they are."),
                    action == .install && !gemini ? String(localized: "\"Remove hooks…\" in the menu undoes it.") : nil,
                    action == .install && gemini ? String(localized: "\"Remove Gemini hooks…\" in the menu undoes it.") : nil,
                    gemini
                        ? String(localized: "Gemini CLI sessions already open may need a restart.")
                        : String(localized: "Claude Code applies it without restarting."),
                ].compactMap(\.self).joined(separator: " ")
            )
        }
        alert.informativeText = info.joined(separator: "\n\n")
        alert.addButton(withTitle: installs ? String(localized: "Install") : String(localized: "Remove"))
        alert.addButton(withTitle: cancelTitle)

        guard runInFront(alert) == .alertFirstButtonReturn else { return }

        do {
            // Executável antes do settings: hook registrado nunca aponta para o nada.
            if installs, let bundledBinary {
                try HookInstaller.installBinary(from: bundledBinary)
            }
            if plan.hasChanges {
                try HookInstaller.apply(plan, backups: backups)
            }
            if removesBinary {
                try? FileManager.default.removeItem(at: stable)
            }
        } catch HookInstallError.changedSinceReview {
            // Mudou enquanto você lia: mostra a prévia nova, nunca grava às cegas.
            return review(action, gemini: gemini, cancelTitle: cancelTitle)
        } catch {
            report(title: String(localized: "Could not write"), message: error.localizedDescription)
        }
        refresh()
    }

    /// Settings somente leitura: copia o executável e entrega o JSON para colar.
    func copySnippet() {
        if let bundledBinary {
            try? HookInstaller.installBinary(from: bundledBinary)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HookInstaller.snippet(), forType: .string)
        refresh()
    }

    /// Prova ponta a ponta: roda o hook instalado como o Claude Code rodaria
    /// (sem shell, payload no stdin) e confere o arquivo que ele grava.
    func selfTest(openSessions: Int) {
        refresh()
        let manager = FileManager.default
        let hook = HookInstaller.stableBinary
        let id = "claudebar-selftest"
        let file = StatusDirectory.fileURL(sessionId: id)
        let payload = Data(#"{"session_id":"\#(id)","cwd":"/"}"#.utf8)

        // `--pid 0`: sem pid, o arquivo de teste não depende de processo vivo.
        let ran = Shell.output(of: hook, arguments: ["waiting", "--pid", "0"], input: payload, timeout: 3) != nil
        let wrote = manager.fileExists(atPath: file.path)
        _ = Shell.output(of: hook, arguments: ["end"], input: payload, timeout: 3)
        // O `end` também pode travar ou falhar: o arquivo de teste nunca sobra.
        try? manager.removeItem(at: file)

        // Só afirma o que foi de fato conferido: com JSON inválido ou
        // `disableAllHooks` o estado sai antes de olhar os hooks.
        let registered: Bool? = switch state {
        case .ok, .binaryMissing, .binaryOutdated: true
        case .invalidSettings, .hooksDisabled: nil
        default: false
        }
        // Compara os bytes aqui: `.binaryOutdated` só existe com o settings em dia.
        let sameBinary = bundledBinary.map { manager.contentsEqual(atPath: $0.path, andPath: hook.path) }
        var lines = [
            check(registered, String(localized: "Hooks registered in settings.json")),
            check(manager.isExecutableFile(atPath: hook.path), String(localized: "Executable at \(hook.path)")),
            check(sameBinary, String(localized: "Executable identical to this app's")),
            check(ran && wrote, String(localized: "The hook ran and wrote the state")),
        ]
        if state == .hooksDisabled {
            lines.append(String(localized: "⚠︎ disableAllHooks is on: Claude Code runs no hooks."))
        }

        let lastEvent = StatusDirectory.readAll(isAlive: ProcessProbe.live.isAlive)
            .filter { $0.sessionId != id }.map(\.updatedAt).max()
        if let lastEvent {
            let when = lastEvent.formatted(.relative(presentation: .named))
            lines.append(String(localized: "Last event received: \(when)"))
        } else if openSessions > 0 {
            lines.append(String(localized: """
            ⚠︎ There are open sessions and no event has arrived. Has the folder been accepted \
            in Claude Code's trust dialog? Until then it holds back the hooks. \
            Also check `disableAllHooks` and `/hooks` inside Claude Code.
            """))
        }

        report(title: String(localized: "Integration test"), message: lines.joined(separator: "\n"))
    }

    /// Mostra a prévia e só copia com o clique. Nada de `cwd`, projeto ou mensagem.
    func copyDiagnostics(rows: [SessionRow]) {
        var counts: [SessionState: Int] = [:]
        for row in rows where !row.isSubagent { counts[row.state, default: 0] += 1 }
        var text = Diagnostics.text(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            integration: state,
            counts: counts,
            paths: [
                ("settings", HookInstaller.settingsURL.path),
                ("hook", HookInstaller.stableBinary.path),
                ("status", StatusDirectory.url.path),
            ],
            home: NSHomeDirectory())
        text += "\nSubagents: \(rows.filter(\.isSubagent).count)"
        let alert = NSAlert()
        alert.messageText = String(localized: "Copy diagnostics?")
        alert.informativeText = String(localized: "This text goes to the clipboard. No project name, folder, branch or message is included.")
        alert.accessoryView = codeView(text)
        alert.addButton(withTitle: String(localized: "Copy"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard runInFront(alert) == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// `nil`: não deu para conferir. Nunca vira ✓.
    private func check(_ passed: Bool?, _ text: String) -> String {
        guard let passed else { return "? " + String(localized: "\(text) (not verified)") }
        return "\(passed ? "✓" : "✗") \(text)"
    }

    /// Texto monoespaçado, só leitura e selecionável, dentro do alerta.
    private func codeView(_ text: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 560, height: 260)
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.string = text
            textView.setAccessibilityLabel(String(localized: "Changes to settings.json"))
        }
        return scroll
    }

    private func report(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        _ = runInFront(alert)
    }

    /// O app é accessory: sem isto o alerta nasce atrás das outras janelas.
    /// `activate()` é só um pedido (ativação cooperativa, o sistema pode
    /// negar), então a janela também sobe de nível.
    private func runInFront(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.window.level = .floating
        NSApplication.shared.activate()
        return alert.runModal()
    }
}
