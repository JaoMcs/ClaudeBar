import AppKit
import ClaudeBarCore
import Foundation
import Observation

/// Estado agregado de todas as sessões, que define o ícone na barra.
enum BarState {
    /// Alguma sessão quer aprovar uma ferramenta.
    case permission
    /// Alguma sessão está esperando você, sem tipo conhecido (ou tipos misturados).
    case waiting
    /// Todas as esperas são perguntas do Claude.
    case question
    /// Alguma resposta falhou e você ainda não viu.
    case error
    /// Alguma sessão terminou e você ainda não viu.
    case done
    /// Tem sessão processando, nada pendente.
    case working
    /// Nada acontecendo.
    case idle

    var symbolName: String {
        switch self {
        case .permission: "hand.raised.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .question: "questionmark.bubble.fill"
        case .error: "exclamationmark.triangle.fill"
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
    /// Última lista devolvida pelo CLI. `nil` até a primeira consulta responder.
    private var agents: [AgentSession]?
    /// Sessões concluídas ou com falha que já foram vistas — não acendem mais o ícone.
    private var acknowledged: Set<String> = []
    /// Última linha conhecida de cada sessão, para detectar transições.
    private var previousRows: [String: SessionRow] = [:]
    private var watcher: DirectoryWatcher?
    private var exitWatcher: ProcessExitWatcher?
    private var pollTimer: Timer?
    /// Uma consulta ao CLI por vez, e no máximo uma a cada `minProbeInterval`.
    private var probing = false
    private var trailingRefresh = false
    private var lastProbe = Date.distantPast
    private static let minProbeInterval: TimeInterval = 2
    /// Exposto porque o menu liga e desliga as notificações por ele.
    let notifier = Notifier()
    /// Integração com o Claude Code (hooks + executável estável).
    let hookSetup = HookSetup()

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
        let probe = ProcessProbe.live
        // A lista do CLI pode ter até um minuto: sessão cujo processo já não
        // existe sai agora, sem esperar a próxima consulta.
        let current = agents?.filter { agent in agent.pid.map(probe.exists) ?? true }
        let merged = SessionMerge.rows(
            agents: current,
            statuses: StatusDirectory.readAll(isAlive: probe.isAlive)
        )

        notifyTransitions(in: merged)

        acknowledged.formIntersection(Set(merged.map(\.sessionId)))
        previousRows = Dictionary(uniqueKeysWithValues: merged.map { ($0.sessionId, $0) })
        rows = merged
        exitWatcher?.watch(Set(merged.compactMap(\.pid)))
    }

    /// Pergunta ao CLI quais sessões existem e recalcula as linhas.
    ///
    /// Cada consulta custa ~0,15 s de CPU e ~160 MB de pico. Pedido feito com
    /// uma consulta em andamento ou dentro da janela mínima não se perde: vira
    /// uma única consulta no fim da janela.
    func refreshAgents() {
        guard !probing, Date().timeIntervalSince(lastProbe) >= Self.minProbeInterval else {
            guard !trailingRefresh else { return }
            trailingRefresh = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.minProbeInterval))
                self?.trailingRefresh = false
                self?.refreshAgents()
            }
            return
        }

        probing = true
        lastProbe = Date()
        Task.detached(priority: .utility) {
            let probed = AgentsProbe.probe()
            await MainActor.run {
                if let probed {
                    self.agents = probed.filter { $0.sessionId != nil }
                }
                self.probing = false
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

    /// Abre a pasta do projeto no gerenciador de arquivos padrão (o Finder).
    func openFolder(_ row: SessionRow) {
        guard Self.isOpenableFolder(row.cwd),
              NSWorkspace.shared.open(URL(fileURLWithPath: row.cwd, isDirectory: true))
        else {
            report(title: "Não foi possível abrir a pasta",
                   message: "\(row.cwd)\n\nA pasta não existe mais ou o macOS negou o acesso.")
            return
        }
    }

    /// Só pasta de verdade: um `.app` também é diretório, e abri-lo executaria o app.
    static func isOpenableFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: path)
    }

    /// Você já está olhando o app da sessão? Então o som é dispensável (F14).
    /// Nível app; sem tmux aqui — seguir o tmux troca o pane de verdade. Sem
    /// tmux sobra só `sysctl`, barato o bastante para a main actor.
    private func isLookingAt(_ row: SessionRow) -> Bool {
        guard let pid = row.pid, pid > 0,
              let front = NSWorkspace.shared.frontmostApplication,
              let app = SessionNavigator.app(for: pid, followTmux: false)
        else { return false }
        return app.processIdentifier == front.processIdentifier
    }

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
            // Não abre o Finder sozinho: seria uma ação que você não pediu.
            report(
                title: "Não foi possível ir até \(row.name)",
                message: """
                \(row.cwd)

                Não achei o terminal ou app dessa sessão. No tmux, só o socket \
                padrão é suportado e precisa haver um terminal anexado. A pasta \
                do projeto continua em "Abrir pasta do projeto".
                """
            )
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
        // Mudança de estado: chega em milissegundos, direto do hook. Arquivo
        // novo ou apagado (`SessionStart`, `SessionEnd`) também muda a lista,
        // então o CLI é consultado — com o limite de `refreshAgents`.
        watcher = DirectoryWatcher(url: StatusDirectory.url) { [weak self] in
            Task { @MainActor in
                self?.merge()
                self?.refreshAgents()
            }
        }

        // Sessão que morreu sem hook (kill -9, crash, terminal fechado): o
        // sistema avisa na hora, sem esperar o polling.
        exitWatcher = ProcessExitWatcher { [weak self] in
            Task { @MainActor in
                self?.merge()
                self?.refreshAgents()
            }
        }

        // Rede de segurança para o que nenhum evento vê: sessão aberta antes de
        // os hooks existirem e agente background sem `pid`. Tolerância de 10%
        // deixa o sistema agrupar o disparo com outros (guia de energia da Apple).
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAgents() }
        }
        timer.tolerance = 6
        pollTimer = timer
    }

    private func notifyTransitions(in merged: [SessionRow]) {
        // Saiu de "esperando" (respondeu, terminou) ou sumiu (fechou): o popup
        // daquela sessão fecha, antes de qualquer aviso novo.
        let current = Dictionary(merged.map { ($0.sessionId, $0.state) }, uniquingKeysWith: { first, _ in first })
        for (sessionId, previous) in previousRows where previous.state == .waiting && current[sessionId] != .waiting {
            notifier.dismissWaiting(for: sessionId)
        }

        // Subagente é trabalho delegado: aparece no menu, mas não avisa nada.
        for row in merged where !row.isSubagent {
            let previous = previousRows[row.sessionId]
            guard SessionMerge.relights(from: previous, to: row) else { continue }
            acknowledged.remove(row.sessionId)

            // Clique no popup leva à sessão (F10).
            let open: @MainActor () -> Void = { [weak self] in self?.goToSession(row) }
            // `lazy`: só sobe a árvore de processos se for mesmo avisar.
            lazy var playSound = !isLookingAt(row)

            switch row.state {
            case .idle:
                notifier.post(
                    .finished, body: row.name, sessionId: row.sessionId, playSound: playSound, onOpen: open
                )
            case .waiting:
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto quando ele está travado.
                notifier.post(
                    Alert(waiting: row.kind),
                    body: row.message ?? row.name,
                    sessionId: row.sessionId,
                    playSound: playSound,
                    onOpen: open
                )
            case .error:
                if previous?.state == .working {
                    // O código do erro diz se vale reenviar ou esperar o limite.
                    notifier.post(
                        .failed,
                        body: row.message.map { "\(row.name): \($0)" } ?? row.name,
                        sessionId: row.sessionId,
                        playSound: playSound,
                        onOpen: open
                    )
                }
            case .working:
                break
            }
        }
    }
}
