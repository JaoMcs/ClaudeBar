import ClaudeBarCore
import Foundation

/// Uma sessão como o próprio Claude Code a reporta em `claude agents --json`.
///
/// Os dois formatos convivem no mesmo array e diferem em campos obrigatórios:
/// uma sessão interativa traz `pid` e `status`; um agente background traz `id` e
/// `state`, e pode não trazer `pid`. Por isso quase tudo aqui é opcional — um
/// campo obrigatório a mais derrubaria o decode do array inteiro.
struct AgentSession: Decodable, Sendable {
    let pid: Int32?
    let cwd: String
    let kind: String
    let id: String?
    let sessionId: String?
    let name: String?
    /// Estado de uma sessão interativa: `idle`, `waiting`, `blocked`…
    let status: String?
    /// Estado de um agente background: `running`, `queued`, `completed`, `failed`…
    let state: String?
    /// Milissegundos desde a época.
    let startedAt: Double?

    /// Agente despachado em background — roda no processo dele, e é o único tipo
    /// de subagente que aparece nessa listagem. Subagente in-process (a ferramenta
    /// Task) roda dentro da sessão que o criou e não é listado.
    var isSubagent: Bool {
        kind == "background"
    }

    /// O `id` só existe em agente background; sessão interativa usa `sessionId`.
    var identifier: String? {
        sessionId ?? id
    }

    var startedAtDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Traduz o vocabulário do CLI para o do app.
    ///
    /// Em sessão interativa o campo é omitido enquanto ela está ocupada, então
    /// ausência de estado significa "processando", não "sem informação".
    var sessionState: SessionState {
        switch status ?? state {
        case "idle", "completed", "failed": .idle
        case "waiting", "blocked": .waiting
        default: .working
        }
    }
}

/// Pergunta ao CLI do Claude Code quais sessões estão abertas.
///
/// É a fonte de verdade da *lista* de sessões: os hooks só conhecem sessões que
/// já dispararam algum evento, enquanto o CLI enxerga todas — inclusive as que
/// você abriu e não usou ainda.
enum AgentsProbe {
    /// Caminhos onde o `claude` costuma estar. Um app de barra de menu não herda
    /// o `PATH` do seu shell, então não dá para confiar em `command -v`.
    private static let candidatePaths = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
    ]

    /// Resolvido uma única vez: se o `claude` não estiver nos caminhos conhecidos,
    /// pergunta ao shell de login.
    static let executableURL: URL? = {
        if let known = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: known)
        }
        guard let output = Shell.output(of: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v claude"]),
              let path = output.split(separator: "\n").first.map(String.init),
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }()

    /// `nil` quando não foi possível falar com o CLI — nesse caso o app cai de
    /// volta para o que os hooks gravaram, em vez de zerar a lista.
    ///
    /// Sem `--all` de propósito: só interessa o que está ativo agora.
    static func probe() -> [AgentSession]? {
        guard let executableURL,
              let output = Shell.output(of: executableURL, arguments: ["agents", "--json"]),
              let data = output.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode([AgentSession].self, from: data)
    }
}
