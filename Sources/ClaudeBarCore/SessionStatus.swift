import Foundation

/// Estado em que uma sessão do Claude Code se encontra.
public enum SessionState: String, Codable, Sendable, CaseIterable {
    /// Prompt enviado — o Claude está trabalhando.
    case working
    /// O Claude terminou de responder e está ocioso.
    case idle
    /// O Claude está esperando algo de você (permissão, escolha).
    case waiting
}

/// Uma linha do estado compartilhado: um arquivo por sessão do Claude Code.
public struct SessionStatus: Codable, Identifiable, Sendable, Equatable {
    public let sessionId: String
    public let state: SessionState
    public let cwd: String
    public let pid: Int32
    public let updatedAt: Date
    public let message: String?

    public var id: String { sessionId }

    /// Nome curto do projeto, usado como rótulo no menu.
    public var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    /// `false` quando o processo do Claude morreu sem disparar o hook de saída.
    public var isAlive: Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    public init(
        sessionId: String,
        state: SessionState,
        cwd: String,
        pid: Int32,
        updatedAt: Date = Date(),
        message: String? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.cwd = cwd
        self.pid = pid
        self.updatedAt = updatedAt
        self.message = message
    }
}
