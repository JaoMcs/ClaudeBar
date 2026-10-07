import ClaudeBarCore
import Foundation

/// Encerra uma sessão. Primeira ação destrutiva do app — até aqui ele só lia.
enum SessionTerminator {
    /// Como aquela linha pode ser encerrada.
    enum Target: Equatable {
        /// `SIGTERM` no processo do Claude Code. Só para processo que é líder do
        /// próprio grupo, ou seja: sessão de terminal.
        case signal(Int32)
        /// `claude stop <id>`: caminho oficial do agente background, que preserva
        /// a conversa para um `claude attach` depois.
        case backgroundStop(String)
        /// Sessão rodando dentro do app desktop. Não se mata daqui: ela
        /// compartilha o grupo de processos com o app e com as sessões irmãs.
        case hostedByApp
        /// Não há como encerrar: sem `pid` utilizável e sem id de background.
        case unavailable
    }

    enum Outcome {
        case terminated
        case failed(String)
    }

    /// Decisão pura (dado o `probe`): qual alvo usar para aquela linha.
    ///
    /// Subagente vai por `claude stop` mesmo quando expõe `pid`: é o caminho
    /// oficial, preserva a conversa e evita sinalizar processo hospedado.
    static func target(for row: SessionRow, probe: ProcessProbe = .live) -> Target {
        if row.isSubagent, let backgroundId = row.backgroundId {
            return .backgroundStop(backgroundId)
        }

        if let pid = row.pid, pid > 0 {
            // Processo que não lidera o próprio grupo está hospedado por outro
            // (o app desktop). Sinalizar ali derruba sessões irmãs.
            guard probe.isGroupLeader(pid) else { return .hostedByApp }
            // PID é reciclado pelo sistema: confere que ainda é o Claude antes
            // de mandar sinal, senão um estado velho mataria processo alheio.
            guard let path = probe.executablePath(pid),
                  path.lowercased().contains("claude")
            else { return .unavailable }
            return .signal(pid)
        }

        if let backgroundId = row.backgroundId {
            return .backgroundStop(backgroundId)
        }
        return .unavailable
    }

    /// Texto do item de menu, para você ver o que vai acontecer antes de clicar.
    /// `nil` quando não há ação possível.
    static func actionTitle(for row: SessionRow, probe: ProcessProbe = .live) -> String? {
        switch target(for: row, probe: probe) {
        case .signal(let pid): "Finalizar sessão (kill \(pid))"
        case .backgroundStop(let id): "Finalizar subagente (claude stop \(id))"
        case .hostedByApp, .unavailable: nil
        }
    }

    /// Explicação mostrada no lugar do botão, quando não há ação.
    static func unavailableReason(for row: SessionRow, probe: ProcessProbe = .live) -> String? {
        switch target(for: row, probe: probe) {
        case .hostedByApp: "Sessão do app desktop — feche pelo próprio app"
        case .unavailable: "Sem processo identificável para encerrar"
        case .signal, .backgroundStop: nil
        }
    }

    static func terminate(_ row: SessionRow, probe: ProcessProbe = .live) -> Outcome {
        switch target(for: row, probe: probe) {
        case .signal(let pid):
            // SIGTERM, não SIGKILL: o Claude Code ainda consegue fechar o
            // transcript e rodar o hook de saída.
            guard kill(pid, SIGTERM) == 0 else {
                return .failed("não foi possível sinalizar o processo \(pid) (errno \(errno))")
            }
            StatusDirectory.remove(sessionId: row.sessionId)
            return .terminated

        case .backgroundStop(let id):
            guard let claude = AgentsProbe.executableURL else {
                return .failed("o executável do claude não foi encontrado")
            }
            guard Shell.output(of: claude, arguments: ["stop", id]) != nil else {
                return .failed("`claude stop \(id)` falhou")
            }
            StatusDirectory.remove(sessionId: row.sessionId)
            return .terminated

        case .hostedByApp:
            return .failed(
                """
                Essa sessão roda dentro do app do Claude e compartilha o grupo de \
                processos com ele. Feche a sessão pelo próprio app.
                """
            )

        case .unavailable:
            return .failed("essa sessão não expõe um processo que possa ser encerrado")
        }
    }
}
