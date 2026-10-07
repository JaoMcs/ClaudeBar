import ClaudeBarCore
import Foundation

/// Uma linha do menu: o cruzamento entre o que o `claude agents --json` sabe
/// (quais sessões existem) e o que os hooks gravaram (em que estado elas estão).
struct SessionRow: Identifiable, Equatable {
    let sessionId: String
    /// Nome dado pelo Claude Code (ex. `my-app-4d`), ou a pasta como reserva.
    let name: String
    let cwd: String
    let state: SessionState
    /// Quando o estado mudou — ou quando a sessão começou, para quem nunca
    /// disparou um hook. `nil` quando nenhuma das duas coisas é conhecida.
    let updatedAt: Date?
    let message: String?
    /// Agente background. Aparece no menu, mas não conta no número da barra nem
    /// dispara som: é trabalho que você delegou, não sessão sua esperando.
    let isSubagent: Bool
    /// Processo do Claude Code. Entrada de background normalmente não expõe um.
    let pid: Int32?
    /// Id curto do agente background, aceito por `claude stop`.
    let backgroundId: String?

    var id: String { sessionId }

    init(
        sessionId: String,
        name: String?,
        cwd: String,
        state: SessionState,
        updatedAt: Date?,
        message: String?,
        isSubagent: Bool,
        pid: Int32? = nil,
        backgroundId: String? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.state = state
        self.updatedAt = updatedAt
        self.message = message
        self.isSubagent = isSubagent
        self.pid = pid
        self.backgroundId = backgroundId

        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        self.name = name ?? (folder.isEmpty ? cwd : folder)
    }
}
