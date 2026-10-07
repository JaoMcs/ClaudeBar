import AppKit
import ClaudeBarCore
import Foundation
import Observation

/// Estado agregado de todas as sessões, que define o ícone na barra.
enum BarState {
    /// Alguma sessão está esperando você (permissão, escolha).
    case waiting
    /// Alguma sessão terminou e você ainda não viu.
    case done
    /// Tem sessão processando, nada pendente.
    case working
    /// Nada acontecendo.
    case idle

    var symbolName: String {
        switch self {
        case .waiting: "exclamationmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .working: "ellipsis.circle"
        case .idle: "circle.dotted"
        }
    }
}

/// Fonte de verdade do app.
///
/// Cruza duas origens, cada uma boa no que a outra é ruim:
/// - `claude agents --json` sabe **quais** sessões existem, inclusive as que
///   nunca dispararam um hook — mas só é consultado de tempo em tempo.
/// - Os arquivos gravados pelos hooks sabem **em que estado** cada sessão está,
///   e chegam no instante em que o estado muda.
@MainActor
@Observable
final class SessionStore {
    private(set) var rows: [SessionRow] = []
    /// Última lista devolvida pelo CLI. Vazia até a primeira consulta responder.
    private var agents: [AgentSession] = []
    /// Sessões concluídas que já foram vistas — não acendem mais o ícone verde.
    private var acknowledged: Set<String> = []
    /// Último estado conhecido de cada sessão, para detectar transições.
    private var previousStates: [String: SessionState] = [:]
    private var watcher: DirectoryWatcher?
    private var pollTimer: Timer?
    /// Exposto porque o menu liga e desliga as notificações por ele.
    let notifier = Notifier()

    var barState: BarState {
        SessionMerge.barState(rows: rows, acknowledged: acknowledged)
    }

    /// Quantas sessões do Claude Code estão abertas agora — o número fixo na barra.
    var openSessionCount: Int {
        SessionMerge.openSessionCount(rows: rows)
    }

    init() {
        try? StatusDirectory.createIfNeeded()
        merge()
        startWatching()
        refreshAgents()
    }

    /// Recalcula as linhas a partir das duas origens já em memória/disco.
    func merge() {
        let merged = SessionMerge.rows(agents: agents, statuses: StatusDirectory.readAll())

        notifyTransitions(in: merged)

        acknowledged.formIntersection(Set(merged.map(\.sessionId)))
        previousStates = Dictionary(uniqueKeysWithValues: merged.map { ($0.sessionId, $0.state) })
        rows = merged
    }

    /// Pergunta ao CLI quais sessões existem e recalcula as linhas.
    func refreshAgents() {
        Task.detached(priority: .utility) {
            let probed = AgentsProbe.probe()
            await MainActor.run {
                if let probed {
                    self.agents = probed.filter { $0.sessionId != nil }
                }
                self.merge()
            }
        }
    }

    /// Marca uma sessão como vista, apagando o destaque no ícone.
    func acknowledge(_ row: SessionRow) {
        acknowledged.insert(row.sessionId)
    }

    func acknowledgeAll() {
        acknowledged.formUnion(rows.map(\.sessionId))
    }

    /// Encerra uma sessão, confirmando antes: um clique errado aqui mata o
    /// processo errado, e o menu se reordena conforme as sessões mudam de estado.
    func terminate(_ row: SessionRow) {
        guard confirmTermination(of: row) else { return }

        switch SessionTerminator.terminate(row) {
        case .terminated:
            merge()
            refreshAgents()
        case .failed(let reason):
            report(title: "Não foi possível finalizar \(row.name)", message: reason)
        }
    }

    private func confirmTermination(of row: SessionRow) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Finalizar \(row.name)?"
        alert.informativeText = switch SessionTerminator.target(for: row) {
        case .signal(let pid):
            """
            \(row.cwd)

            O processo \(pid) recebe SIGTERM. A conversa fica salva (dá para \
            voltar com `claude --resume`), mas o que estiver em andamento para \
            na hora e o terminal fica com um shell vazio.
            """
        case .backgroundStop(let id):
            """
            \(row.cwd)

            `claude stop \(id)` encerra o agente preservando a conversa: você \
            pode retomá-la depois com `claude attach \(id)`.
            """
        case .hostedByApp, .unavailable:
            row.cwd
        }
        alert.addButton(withTitle: "Finalizar")
        alert.addButton(withTitle: "Cancelar")

        // O app é accessory: sem ativar, o alerta nasce atrás das outras janelas.
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func report(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func startWatching() {
        // Mudança de estado: chega em milissegundos, direto do hook.
        watcher = DirectoryWatcher(url: StatusDirectory.url) { [weak self] in
            Task { @MainActor in self?.merge() }
        }

        // Sessão aberta ou fechada: só o CLI sabe, então consultamos de tempo em
        // tempo. A chamada custa ~150 ms e roda fora da main thread.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAgents() }
        }
    }

    private func notifyTransitions(in merged: [SessionRow]) {
        // Subagente é trabalho delegado: aparece no menu, mas não avisa nada.
        for row in merged where !row.isSubagent {
            let previous = previousStates[row.sessionId]
            guard previous != nil, previous != row.state else { continue }

            switch row.state {
            case .idle where previous == .working:
                acknowledged.remove(row.sessionId)
                notifier.post(.finished, body: row.name)
            case .waiting:
                acknowledged.remove(row.sessionId)
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto quando ele está travado.
                notifier.post(.waiting, body: row.message ?? row.name)
            default:
                break
            }
        }
    }
}
