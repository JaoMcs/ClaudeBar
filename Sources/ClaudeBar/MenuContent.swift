import ClaudeBarCore
import SwiftUI

/// Conteúdo do menu que abre ao clicar no ícone da barra.
struct MenuContent: View {
    let store: SessionStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Linhas dos limites no topo do menu. Sem dado é "indisponível", nunca 0%.
    static func limitLines(_ limits: RateLimits?, now: Date) -> [String] {
        guard let limits else { return [String(localized: "Usage limits: unavailable")] }

        func line(_ title: String, _ window: RateWindow?) -> String {
            guard let window else { return String(localized: "\(title): unavailable") }
            // Depois do reset o número velho não vale; o novo chega com a próxima resposta.
            guard window.resetsAt > now else { return String(localized: "\(title): reset, waiting for new data") }
            let reset = Calendar.current.isDate(window.resetsAt, inSameDayAs: now)
                ? window.resetsAt.formatted(date: .omitted, time: .shortened)
                : window.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            // `%` fora da chave: na tabela ele viraria `%%`.
            let percent = "\(window.displayPercent)%"
            return String(localized: "\(title): \(percent) · resets \(reset)")
        }

        var lines = [line(String(localized: "5 h limit"), limits.fiveHour), line(String(localized: "Weekly"), limits.sevenDay)]
        if let updatedAt = limits.updatedAt {
            let age = relativeFormatter.localizedString(for: updatedAt, relativeTo: now)
            lines.append(String(localized: "Updated \(age)"))
        }
        return lines
    }

    var body: some View {
        // Sem timer: a idade é calculada quando o SwiftUI monta o menu (ao abrir).
        ForEach(Self.limitLines(store.limits, now: Date()), id: \.self) { line in
            Text(line)
        }

        Divider()

        if store.rows.isEmpty {
            Text("No Claude sessions open")
        } else {
            // Cada sessão abre um submenu: clicar na linha não faz nada
            // destrutivo por acidente.
            ForEach(store.rows) { row in
                // Sem emoji no texto: o VoiceOver leria o nome dele. O símbolo é o da
                // barra para o mesmo estado, então a legenda vale para as linhas.
                Menu {
                    Text(row.cwd)

                    Button("Open project folder") {
                        store.openFolder(row)
                    }

                    // O código do erro ("rate_limit — 429 Too Many Requests")
                    // diz se vale reenviar agora ou esperar.
                    if row.state == .error, let message = row.message {
                        Text(message)
                    }

                    Divider()

                    // Subagente background não tem terminal para onde ir.
                    if !row.isSubagent, let pid = row.pid, pid > 0 {
                        Button("Go to session") {
                            store.goToSession(row)
                        }
                    }

                    Button("Mark as seen") {
                        store.acknowledge(row)
                    }

                    Divider()

                    if let title = SessionTerminator.actionTitle(for: row) {
                        Button(title) {
                            store.terminate(row)
                        }
                    } else if let reason = SessionTerminator.unavailableReason(for: row) {
                        Text(reason)
                    }
                } label: {
                    Label(Self.label(for: row), systemImage: Self.symbolName(for: row))
                }
            }

            Divider()

            Button("Mark all as seen") {
                store.acknowledgeAll()
            }
        }

        Divider()

        Menu("What the icons mean") {
            ForEach(BarState.allCases, id: \.self) { state in
                Label(state.title, systemImage: state.symbolName)
            }
        }

        Divider()

        Toggle("Notifications", isOn: Binding(
            get: { store.notifier.isEnabled },
            set: { store.notifier.setEnabled($0) }
        ))

        if store.notifier.state != .off {
            Button("Show sample popup") {
                store.notifier.showSample()
            }
        }

        Button("Settings…") {
            SettingsWindow.show(notifier: store.notifier)
        }
        .keyboardShortcut(",")

        Divider()

        integrationMenu

        Button("Refresh") {
            store.refreshAgents()
            store.hookSetup.refresh()
        }

        Button("Quit Awaitbar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Estado da integração e as ações sobre os hooks. Nada grava sem o alerta.
    @ViewBuilder private var integrationMenu: some View {
        let setup = store.hookSetup
        Menu(setup.menuTitle) {
            Text(setup.summary)

            Divider()

            switch setup.state {
            case .readOnlySettings:
                Button("Copy hooks JSON") { setup.copySnippet() }
            case .invalidSettings, .hooksDisabled:
                EmptyView()
            default:
                Button(setup.state == .ok ? "Reinstall hooks…" : "Install hooks…") {
                    setup.review(.install)
                }
            }

            if setup.canRemove {
                Button("Remove hooks…") { setup.review(.uninstall) }
            }

            Divider()

            // Opt-in próprio, desligado por padrão: muda o rodapé do Claude Code.
            Button("Show limits in the Claude Code footer…") { setup.review(.installStatusLine) }
            Button("Stop showing limits in the footer…") { setup.review(.uninstallStatusLine) }

            Divider()

            Button("Test integration") {
                setup.selfTest(openSessions: store.openSessionCount)
                store.notifier.showSample()
            }
            Button("Copy diagnostics…") { setup.copyDiagnostics(rows: store.rows) }
        }
    }

    static func label(for row: SessionRow, now: Date = Date(), probe: ProcessProbe = .live) -> String {
        var text = row.isSubagent ? String(localized: "[subagent]") + " " : ""
        // O nome do agente não se traduz.
        if let agent = row.agent, agent != "claude" { text += "[\(agent)] " }
        text += row.name
        // A branch distingue duas sessões do mesmo projeto em worktrees diferentes.
        if let branch = row.branch { text += " · \(branch)" }
        switch SessionTerminator.hostKind(for: row, probe: probe) {
        case .desktopApp: text += " · " + String(localized: "desktop app")
        case .terminal: text += " · " + String(localized: "terminal")
        case nil: break
        }
        text += " — \(description(for: row))"
        if let updatedAt = row.updatedAt {
            text += " (\(relativeFormatter.localizedString(for: updatedAt, relativeTo: now)))"
        }
        return text
    }

    /// O mesmo símbolo da barra para o mesmo estado, então a legenda vale para as linhas.
    private static func symbolName(for row: SessionRow) -> String {
        switch (row.state, row.kind) {
        case (.working, _): BarState.working.symbolName
        case (.idle, _): BarState.done.symbolName
        case (.error, _): BarState.error.symbolName
        case (.waiting, .permission): BarState.permission.symbolName
        case (.waiting, .question): BarState.question.symbolName
        case (.waiting, nil): BarState.waiting.symbolName
        }
    }

    static func description(for row: SessionRow) -> String {
        switch (row.state, row.kind) {
        case (.working, _): String(localized: "working")
        case (.idle, _): String(localized: "ready")
        case (.waiting, .permission): String(localized: "asks for permission")
        case (.waiting, .question): String(localized: "asked a question")
        case (.waiting, nil): String(localized: "waiting for you")
        case (.error, _): String(localized: "failed")
        }
    }
}
