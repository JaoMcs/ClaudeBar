import ClaudeBarCore
import Foundation

/// O cruzamento das duas origens, isolado em funções puras: nada de disco, de
/// processo ou de relógio aqui dentro — o que torna a regra testável.
enum SessionMerge {
    /// Cruza a lista do CLI com o estado gravado pelos hooks.
    ///
    /// O CLI manda em *quais* sessões existem; o hook, quando presente, manda no
    /// *estado* daquela sessão. Sessão que só os hooks conhecem entra do mesmo
    /// jeito — se o CLI estiver indisponível, nada se perde.
    static func rows(agents: [AgentSession], statuses: [SessionStatus]) -> [SessionRow] {
        let byId = Dictionary(statuses.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })

        var merged: [SessionRow] = agents.compactMap { agent in
            guard let sessionId = agent.identifier else { return nil }
            let hook = byId[sessionId]
            return SessionRow(
                sessionId: sessionId,
                name: agent.name,
                cwd: hook?.cwd ?? agent.cwd,
                state: hook?.state ?? agent.sessionState,
                updatedAt: hook?.updatedAt ?? agent.startedAtDate,
                message: hook?.message,
                isSubagent: agent.isSubagent,
                // O hook grava o PID do Claude que o disparou; serve de reserva
                // quando a listagem do CLI não traz um.
                pid: agent.pid ?? hook?.pid,
                backgroundId: agent.isSubagent ? agent.id : nil
            )
        }

        let known = Set(merged.map(\.sessionId))
        merged += statuses
            .filter { !known.contains($0.sessionId) }
            .map { status in
                SessionRow(
                    sessionId: status.sessionId,
                    name: nil,
                    cwd: status.cwd,
                    state: status.state,
                    updatedAt: status.updatedAt,
                    message: status.message,
                    isSubagent: false,
                    pid: status.pid
                )
            }

        // Suas sessões primeiro, subagentes agrupados no fim.
        return merged.sorted { first, second in
            if first.isSubagent != second.isSubagent { return !first.isSubagent }
            return (first.updatedAt ?? .distantPast) > (second.updatedAt ?? .distantPast)
        }
    }

    /// O estado do ícone. Subagente é ignorado: é trabalho delegado, não uma
    /// sessão sua esperando resposta.
    static func barState(rows: [SessionRow], acknowledged: Set<String>) -> BarState {
        let own = rows.filter { !$0.isSubagent }
        if own.contains(where: { $0.state == .waiting }) { return .waiting }
        if own.contains(where: { $0.state == .idle && !acknowledged.contains($0.sessionId) }) { return .done }
        if own.contains(where: { $0.state == .working }) { return .working }
        return .idle
    }

    /// O número fixo na barra: só as suas sessões, sem subagente.
    static func openSessionCount(rows: [SessionRow]) -> Int {
        rows.filter { !$0.isSubagent }.count
    }
}
