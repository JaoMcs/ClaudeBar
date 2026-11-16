import ClaudeBarCore
import Darwin
import Foundation

/// O que o app precisa saber sobre um processo antes de sinalizá-lo. Injetável
/// para os testes poderem descrever topologias sem subir processo de verdade.
struct ProcessProbe: Sendable {
    /// O processo é líder do próprio grupo?
    ///
    /// Sessão de terminal é (`pgid == pid`). Sessão do app desktop **não é**: ela
    /// vive no grupo do `Claude.app`, junto das sessões irmãs e do app inteiro.
    var isGroupLeader: @Sendable (Int32) -> Bool

    /// Caminho do executável, para conferir que o PID ainda é uma sessão do
    /// Claude e não um processo qualquer que herdou o número.
    var executablePath: @Sendable (Int32) -> String?

    /// `false` só quando o sistema garante que o PID não existe (`ESRCH`).
    /// `EPERM` conta como existente: há processo, só não é nosso.
    var exists: @Sendable (Int32) -> Bool = { _ in true }

    /// Quando o processo começou. `nil` = sem informação.
    var startTime: @Sendable (Int32) -> Date? = { _ in nil }

    static let live = ProcessProbe(
        isGroupLeader: { pid in
            let pgid = getpgid(pid)
            return pgid > 0 && pgid == pid
        },
        executablePath: { processExecutablePath($0) },
        exists: { pid in
            kill(pid, 0) == 0 || errno != ESRCH
        },
        startTime: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        }
    )
}

extension ProcessProbe {
    /// O arquivo de um hook ainda descreve uma sessão viva?
    ///
    /// Conservador: só devolve `false` com prova de que o processo que gravou o
    /// arquivo não está mais lá. Sem informação, mantém — limpar demais esconde
    /// sessão real, e o CLI ainda pode tirar a linha no cruzamento.
    func isAlive(_ status: SessionStatus) -> Bool {
        // Sem PID não há o que provar aqui: quem decide é o CLI, no cruzamento.
        guard status.pid > 0 else { return true }
        guard exists(status.pid) else { return false }
        // Sem caminho (outro usuário, corrida com a saída): sem informação.
        guard let path = executablePath(status.pid) else { return true }
        // PID reciclado por outro programa.
        guard path.lowercased().contains("claude") else { return false }
        // PID reciclado por outro `claude`: quem gravou o arquivo nasceu antes
        // da gravação. A folga de 1 s cobre arredondamento de relógio.
        if let start = startTime(status.pid), start > status.updatedAt.addingTimeInterval(1) {
            return false
        }
        return true
    }
}
