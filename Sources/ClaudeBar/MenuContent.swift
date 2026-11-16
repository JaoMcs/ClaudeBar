import ClaudeBarCore
import SwiftUI

/// Conteúdo do menu que abre ao clicar no ícone da barra.
struct MenuContent: View {
    let store: SessionStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        if store.rows.isEmpty {
            Text("Nenhuma sessão do Claude aberta")
        } else {
            // Cada sessão abre um submenu: clicar na linha não faz nada
            // destrutivo por acidente.
            ForEach(store.rows) { row in
                Menu(label(for: row)) {
                    Text(row.cwd)

                    Divider()

                    Button("Marcar como visto") {
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
                }
            }

            Divider()

            Button("Marcar tudo como visto") {
                store.acknowledgeAll()
            }
        }

        Divider()

        Toggle("Notificações", isOn: Binding(
            get: { store.notifier.isEnabled },
            set: { store.notifier.setEnabled($0) }
        ))

        if store.notifier.state != .off {
            Button("Ver exemplo de popup") {
                store.notifier.showSample()
            }
        }

        Divider()

        integrationMenu

        Button("Atualizar") {
            store.refreshAgents()
            store.hookSetup.refresh()
        }

        Button("Sair do ClaudeBar") {
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
                Button("Copiar JSON dos hooks") { setup.copySnippet() }
            case .invalidSettings, .hooksDisabled:
                EmptyView()
            default:
                Button(setup.state == .ok ? "Reinstalar hooks…" : "Instalar hooks…") {
                    setup.review(.install)
                }
            }

            if setup.canRemove {
                Button("Remover hooks…") { setup.review(.uninstall) }
            }

            Divider()

            Button("Testar integração") {
                setup.selfTest(openSessions: store.openSessionCount)
                store.notifier.showSample()
            }
        }
    }

    private func label(for row: SessionRow) -> String {
        var text = "\(icon(for: row.state))  "
        if row.isSubagent {
            text += "[subagente] "
        }
        text += "\(row.name) — \(description(for: row.state))"
        if let updatedAt = row.updatedAt {
            text += " (\(Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date())))"
        }
        return text
    }

    private func icon(for state: SessionState) -> String {
        switch state {
        case .working: "⏳"
        case .idle: "✅"
        case .waiting: "🔸"
        }
    }

    private func description(for state: SessionState) -> String {
        switch state {
        case .working: "processando"
        case .idle: "pronto"
        case .waiting: "aguardando você"
        }
    }
}
