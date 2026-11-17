import AppKit
import ClaudeBarCore
import Observation

/// A integração com o Claude Code vista pelo app: detecta o estado, mostra o
/// diff exato e só grava com o seu clique. Nunca repara em silêncio.
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
        // Fora do init: o `SessionStore` nasce antes do app terminar de
        // abrir, e um alerta modal ali apareceria cedo demais.
        Task { @MainActor in self.offerIfNeeded() }
    }

    var menuTitle: String {
        switch state {
        case .ok: "Integração com o Claude Code: ok"
        case .notInstalled: "Integração: hooks não instalados"
        default: "⚠︎ Integração precisa de atenção"
        }
    }

    var summary: String {
        switch state {
        case .ok: "Hooks registrados e executável em dia"
        case .notInstalled: "Sem hooks, o app só vê as sessões a cada minuto"
        case .binaryMissing: "O executável do hook sumiu de ~/.claude/claudebar/bin"
        case .binaryOutdated: "O executável do hook é de outra versão do app"
        case .hooksOutdated: "Faltam hooks do ClaudeBar no settings.json"
        case .legacyHooks: "Hooks no formato antigo (caminho dentro do .app)"
        case .invalidSettings: "O settings.json não é um JSON válido — nada será alterado"
        case .readOnlySettings: "O settings.json é somente leitura: cole o JSON na ferramenta que o gera"
        case .hooksDisabled: "disableAllHooks está ligado no seu settings.json"
        }
    }

    var canRemove: Bool {
        ![.notInstalled, .invalidSettings, .readOnlySettings].contains(state)
    }

    func refresh() {
        state = HookInstaller.state(bundledBinary: bundledBinary)
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
        review(.install, cancelTitle: "Pular")
    }

    /// Mostra exatamente o que muda e grava só se você clicar na ação.
    func review(_ action: HookAction, cancelTitle: String = "Cancelar") {
        let plan: HookPlan
        do {
            plan = try HookInstaller.plan(action)
        } catch {
            return report(title: "Não foi possível ler o settings.json", message: error.localizedDescription)
        }

        let stable = HookInstaller.stableBinary
        let installs = action == .install || action == .installStatusLine
        if installs, bundledBinary == nil, !FileManager.default.isExecutableFile(atPath: stable.path) {
            return report(title: "Executável do hook não encontrado", message: "Abra o ClaudeBar a partir do .app.")
        }
        let copiesBinary = installs && bundledBinary.map {
            !FileManager.default.contentsEqual(atPath: $0.path, andPath: stable.path)
        } == true
        // Remover também apaga a cópia do executável: conta como mudança e aparece no alerta.
        // Se o statusline ou os hooks ainda a chamam, ela fica.
        let removesBinary = !installs && !plan.binaryInUse
            && FileManager.default.fileExists(atPath: stable.path)

        guard plan.hasChanges || copiesBinary || removesBinary else {
            return report(title: "Nada a mudar", message: plan.settingsURL.path)
        }

        let alert = NSAlert()
        alert.messageText = switch action {
        case .install: "Registrar os hooks do ClaudeBar no Claude Code?"
        case .uninstall: "Remover os hooks do ClaudeBar?"
        case .installStatusLine: "Mostrar os limites de uso no rodapé do Claude Code?"
        case .uninstallStatusLine: "Parar de mostrar os limites no rodapé do Claude Code?"
        }
        var info: [String] = []
        if plan.hasChanges {
            info.append("Arquivo: \(plan.settingsURL.path)")
            info.append("Backup antes de gravar, em \(HookInstaller.backupsURL.path)")
            if plan.reformats {
                info.append("O arquivo será reformatado (ordem das chaves); fora de \"hooks\" e \"statusLine\" o conteúdo não muda.")
            }
            // Só `hooks` e `statusLine`: o resto do settings pode ter token em `env`.
            alert.accessoryView = codeView(plan.diff)
        }
        if copiesBinary {
            info.append("Copia o executável do hook para \(stable.path).")
        }
        if removesBinary {
            info.append("Apaga o executável do hook em \(stable.path).")
        }
        switch (action, plan.statusLineOriginal) {
        case (.installStatusLine, .save?):
            info.append(
                "Seu statusline continua aparecendo igual. O ClaudeBar só lê os limites antes de repassar. "
                    + "O original fica guardado em \(StatusDirectory.originalStatusLineURL.path)."
            )
        case (.installStatusLine, _):
            info.append(
                "O Claude Code esconde algumas dicas do rodapé (como `esc to interrupt`) quando existe um "
                    + "statusline. No lugar delas aparece `5h 23% · sem 41%`. Os limites só aparecem para "
                    + "assinantes Pro, Max e Ultra."
            )
        case (.uninstallStatusLine, _):
            info.append("O statusLine que você tinha antes volta igual; se você o trocou depois, ele fica.")
        default:
            info.append(
                "Só as entradas do ClaudeBar mudam; hooks seus ficam como estão. "
                    + (action == .install ? "\"Remover hooks…\" no menu desfaz. " : "")
                    + "O Claude Code aplica sem reiniciar."
            )
        }
        alert.informativeText = info.joined(separator: "\n\n")
        alert.addButton(withTitle: installs ? "Instalar" : "Remover")
        alert.addButton(withTitle: cancelTitle)

        guard runInFront(alert) == .alertFirstButtonReturn else { return }

        do {
            // Executável antes do settings: hook registrado nunca aponta para o nada.
            if installs, let bundledBinary {
                try HookInstaller.installBinary(from: bundledBinary)
            }
            if plan.hasChanges {
                try HookInstaller.apply(plan)
            }
            if removesBinary {
                try? FileManager.default.removeItem(at: stable)
            }
        } catch HookInstallError.changedSinceReview {
            // Mudou enquanto você lia: mostra a prévia nova, nunca grava às cegas.
            return review(action, cancelTitle: cancelTitle)
        } catch {
            report(title: "Não foi possível gravar", message: error.localizedDescription)
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
            check(registered, "Hooks registrados no settings.json"),
            check(manager.isExecutableFile(atPath: hook.path), "Executável em \(hook.path)"),
            check(sameBinary, "Executável igual ao deste app"),
            check(ran && wrote, "O hook rodou e gravou o estado"),
        ]
        if state == .hooksDisabled {
            lines.append("⚠︎ disableAllHooks está ligado: o Claude Code não roda nenhum hook.")
        }

        let lastEvent = StatusDirectory.readAll(isAlive: ProcessProbe.live.isAlive)
            .filter { $0.sessionId != id }.map(\.updatedAt).max()
        if let lastEvent {
            lines.append("Último evento recebido: \(lastEvent.formatted(.relative(presentation: .named)))")
        } else if openSessions > 0 {
            lines.append("""
            ⚠︎ Há sessões abertas e nenhum evento chegou. A pasta já foi aceita no \
            diálogo de confiança do Claude Code? Antes disso ele retém os hooks. \
            Confira também `disableAllHooks` e o `/hooks` dentro do Claude Code.
            """)
        }

        report(title: "Teste da integração", message: lines.joined(separator: "\n"))
    }

    /// `nil`: não deu para conferir. Nunca vira ✓.
    private func check(_ passed: Bool?, _ text: String) -> String {
        guard let passed else { return "? \(text) (não verificado)" }
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
            textView.setAccessibilityLabel("Alterações no settings.json")
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
