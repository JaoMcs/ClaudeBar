import Foundation

/// Estado em que uma sessão do Claude Code se encontra.
public enum SessionState: String, Codable, Sendable, CaseIterable {
    /// Prompt enviado — o Claude está trabalhando.
    case working
    /// O Claude terminou de responder e está ocioso.
    case idle
    /// O Claude está esperando algo de você (permissão, escolha).
    case waiting
    /// A resposta falhou por erro de API (limite, sobrecarga, autenticação…).
    /// Não é "pronto": o turno acabou sem resposta.
    case error
}

/// Por que a sessão está esperando você.
///
/// No arquivo o campo é texto (`kind: String?`), não este enum: um valor que o
/// app não conhece (hook mais novo, downgrade) faria o decode falhar, e
/// `StatusDirectory.readAll` apaga arquivo que não decodifica.
public enum WaitKind: String, Sendable {
    /// Aprovar uma ferramenta (`Notification` `permission_prompt`).
    case permission
    /// Responder uma pergunta (`PreToolUse` `AskUserQuestion`), um
    /// formulário (`Notification` `elicitation_dialog`) ou abrir uma URL
    /// (`Notification` `elicitation_url_dialog`).
    case question
}

/// Uma linha do estado compartilhado: um arquivo por sessão do Claude Code.
public struct SessionStatus: Codable, Identifiable, Sendable, Equatable {
    public let sessionId: String
    public let state: SessionState
    public let cwd: String
    public let pid: Int32
    public let updatedAt: Date
    public let message: String?
    /// `WaitKind` em texto. `nil` em arquivo antigo e fora de `waiting`.
    public let kind: String?
    /// Branch do repositório do `cwd` (`@sha7` com HEAD solto), lida pelo hook.
    /// Opcional: arquivos gravados antes deste campo continuam válidos.
    public let branch: String?

    /// `nil` também para valor desconhecido: espera genérica.
    public var waitKind: WaitKind? { kind.flatMap(WaitKind.init(rawValue:)) }

    public var id: String { sessionId }

    /// O `AskUserQuestion` grava a pergunta na hora (`PreToolUse`) e, ~6 s
    /// depois, o Claude Code dispara um `permission_prompt` para a mesma tela.
    /// Essa "permissão" não pode apagar a pergunta aberta.
    public func absorbs(_ state: SessionState, kind: WaitKind?) -> Bool {
        self.state == .waiting && waitKind == .question && state == .waiting && kind == .permission
    }

    /// Nome curto do projeto, usado como rótulo no menu.
    public var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    public init(
        sessionId: String,
        state: SessionState,
        cwd: String,
        pid: Int32,
        updatedAt: Date = Date(),
        message: String? = nil,
        kind: WaitKind? = nil,
        branch: String? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.cwd = cwd
        self.pid = pid
        self.updatedAt = updatedAt
        self.message = message
        self.kind = kind?.rawValue
        self.branch = branch
    }
}

/// Caminho do executável de um processo (`proc_pidpath`), ou `nil` se ele não
/// existe mais. Usado para conferir que um PID ainda é o Claude.
public func processExecutablePath(_ pid: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer[..<Int(length)], as: UTF8.self)
}
