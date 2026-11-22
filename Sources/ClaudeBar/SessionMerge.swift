import ClaudeBarCore
import Foundation

/// O cruzamento das duas origens, isolado em funções puras: nada de disco, de
/// processo ou de relógio aqui dentro — o que torna a regra testável.
enum SessionMerge {
    /// Cruza a lista do CLI com o estado gravado pelos hooks.
    ///
    /// O CLI manda em *quais* sessões existem; o hook, quando presente, manda no
    /// *estado* daquela sessão. Sessão que só os hooks conhecem entra do mesmo
    /// jeito, com duas exceções quando o CLI já respondeu (`agents != nil`):
    /// - `pid 0` do Claude: sem processo para conferir, o CLI é a única prova de vida;
    /// - PID que o CLI lista com outro `sessionId`: sobra de `/clear` ou
    ///   `/resume` cujo `SessionEnd` não rodou.
    ///
    /// `agents == nil` é "CLI ainda não respondeu": aí nada se esconde.
    static func rows(agents: [AgentSession]?, statuses: [SessionStatus]) -> [SessionRow] {
        let byId = Dictionary(statuses.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = agents ?? []
        let listedPids = Set(listed.compactMap(\.pid))

        var merged: [SessionRow] = listed.compactMap { agent in
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
                backgroundId: agent.isSubagent ? agent.id : nil,
                kind: hook?.waitKind,
                branch: hook?.branch,
                agent: hook?.agent
            )
        }

        let known = Set(merged.map(\.sessionId))
        merged += statuses
            .filter { !known.contains($0.sessionId) }
            .filter { status in
                guard agents != nil else { return true }
                // Outro agente (Gemini) não aparece no `claude agents`: o CLI não
                // prova nada sobre ele, e a linha vive pelos hooks dele.
                if status.agent != nil { return true }
                return status.pid > 0 && !listedPids.contains(status.pid)
            }
            .map { status in
                SessionRow(
                    sessionId: status.sessionId,
                    name: nil,
                    cwd: status.cwd,
                    state: status.state,
                    updatedAt: status.updatedAt,
                    message: status.message,
                    isSubagent: false,
                    pid: status.pid,
                    kind: status.waitKind,
                    branch: status.branch,
                    agent: status.agent
                )
            }

        // Suas sessões primeiro, subagentes agrupados no fim.
        return merged.sorted { first, second in
            if first.isSubagent != second.isSubagent { return !first.isSubagent }
            return (first.updatedAt ?? .distantPast) > (second.updatedAt ?? .distantPast)
        }
    }

    /// A transição reacende o destaque de uma sessão já marcada como vista?
    ///
    /// Sem `default`: estado novo não compila até alguém decidir aqui.
    static func relights(from previous: SessionState?, to state: SessionState) -> Bool {
        guard let previous, previous != state else { return false }
        switch state {
        case .idle: return previous == .working
        // Falha nova acende o ícone mesmo que a sessão já tenha sido marcada
        // como vista antes do prompt que falhou.
        case .waiting, .error: return true
        case .working: return false
        }
    }

    /// Igual à de cima, mais o motivo da espera: pergunta que vira permissão
    /// (ou o contrário) avisa de novo, mesmo sem mudar de estado.
    static func relights(from previous: SessionRow?, to row: SessionRow) -> Bool {
        if previous?.state == .waiting, row.state == .waiting, previous?.kind != row.kind { return true }
        return relights(from: previous?.state, to: row.state)
    }

    /// O estado do ícone. Subagente é ignorado: é trabalho delegado, não uma
    /// sessão sua esperando resposta.
    static func barState(rows: [SessionRow], acknowledged: Set<String>) -> BarState {
        let own = rows.filter { !$0.isSubagent }
        let unseen = own.filter { !acknowledged.contains($0.sessionId) }
        let waiting = own.filter { $0.state == .waiting }
        // Permissão vence: trava uma ferramenta já em andamento. Só mostra
        // "pergunta" quando todas as esperas são pergunta.
        if waiting.contains(where: { $0.kind == .permission }) { return .permission }
        if !waiting.isEmpty {
            return waiting.allSatisfy { $0.kind == .question } ? .question : .waiting
        }
        // Falha vence "pronto": uma resposta que não veio não pode se esconder
        // atrás de outra que veio.
        if unseen.contains(where: { $0.state == .error }) { return .error }
        if unseen.contains(where: { $0.state == .idle }) { return .done }
        if own.contains(where: { $0.state == .working }) { return .working }
        return .idle
    }

    /// Sessões suas que continuam esperando há `delay` ou mais e ainda não
    /// ganharam lembrete neste episódio. Só quem já estava esperando na rodada
    /// anterior: na rodada da transição o aviso normal acabou de tocar.
    static func dueReminders(rows: [SessionRow], previous: [String: SessionState],
                             reminded: Set<String>, now: Date, delay: TimeInterval) -> [SessionRow] {
        rows.filter { row in
            guard !row.isSubagent,
                  row.state == .waiting,
                  previous[row.sessionId] == .waiting,
                  let since = row.updatedAt,
                  let key = reminderKey(row)
            else { return false }
            return now.timeIntervalSince(since) >= delay && !reminded.contains(key)
        }
    }

    /// Um episódio de espera: a sessão + quando ela entrou em `waiting`.
    // ponytail: sessão só do CLI (sem hook) usa o início da sessão como
    // `updatedAt`, então o lembrete pode vir já no 2º merge; raro com hooks.
    static func reminderKey(_ row: SessionRow) -> String? {
        row.updatedAt.map { "\(row.sessionId)|\($0.timeIntervalSince1970)" }
    }

    /// O número fixo na barra: só as suas sessões, sem subagente.
    static func openSessionCount(rows: [SessionRow]) -> Int {
        rows.filter { !$0.isSubagent }.count
    }
}
