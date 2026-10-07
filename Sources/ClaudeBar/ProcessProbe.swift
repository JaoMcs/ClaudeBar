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

    static let live = ProcessProbe(
        isGroupLeader: { pid in
            let pgid = getpgid(pid)
            return pgid > 0 && pgid == pid
        },
        executablePath: { pid in
            var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { return nil }
            return String(decoding: buffer[..<Int(length)], as: UTF8.self)
        }
    )
}
