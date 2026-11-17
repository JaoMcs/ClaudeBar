import Foundation

/// Roda o statusline que o usuário já tinha, para o ClaudeBar entrar no meio
/// sem tomar o lugar dele.
public enum StatusLineChain {
    /// Variável que o hook põe no ambiente do filho: se o "comando original"
    /// for o próprio hook, a segunda chamada não encadeia de novo (sem laço).
    public static let reentryVariable = "CLAUDEBAR_STATUSLINE"

    /// Lê o `statusLine` original salvo na instalação. Só `type: "command"` com
    /// comando não vazio conta; qualquer outra coisa é "não havia statusline".
    public static func originalCommand(at url: URL = StatusDirectory.originalStatusLineURL) -> String? {
        struct Original: Decodable {
            let type: String?
            let command: String?
        }
        guard let data = try? Data(contentsOf: url),
              let original = try? JSONDecoder().decode(Original.self, from: data),
              original.type == nil || original.type == "command",
              let command = original.command,
              !command.trimmingCharacters(in: .whitespaces).isEmpty,
              !command.contains("claudebar-hook")
        else { return nil }
        return command
    }

    /// Roda `command` em `/bin/sh -c`, entregando `input` no stdin.
    ///
    /// O comando é texto que o próprio usuário escreveu nos settings dele e vai
    /// como **um** argumento: o ClaudeBar não monta shell. Devolve o stdout e o
    /// código de saída do filho, ou `nil` se não deu para rodar ou estourou o
    /// `timeout` (aí o filho recebe SIGTERM).
    public static func run(
        command: String,
        input: Data,
        timeout: TimeInterval
    ) -> (output: Data, status: Int32)? {
        // Filho que sai sem ler o stdin faria o `write` abaixo matar o hook
        // com SIGPIPE. Ignorado, o `write` só lança erro.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        var environment = ProcessInfo.processInfo.environment
        environment[reentryVariable] = "1"
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        // stderr do filho segue para o nosso: aparece no `claude --debug`.
        process.standardError = FileHandle.standardError

        // Espera duas coisas: o EOF do stdout e o fim do processo, ambos dentro
        // do mesmo prazo.
        let done = DispatchGroup()
        done.enter()
        process.terminationHandler = { _ in done.leave() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // stdin e stdout em paralelo: o pipe tem buffer finito, e escrever tudo
        // antes de ler trava se o filho imprimir muito antes de ler o resto.
        let writer = stdin.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

        let output = OutputBox()
        let reader = stdout.fileHandleForReading
        done.enter()
        DispatchQueue.global().async {
            output.data = reader.readDataToEndOfFile()
            done.leave()
        }

        // ponytail: neto que herdou o stdout (`cmd &`) segura o EOF; o timeout
        // cobre, mas ele pode sobrar vivo. Grupo de processos se isso aparecer.
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return (output.data, process.terminationStatus)
    }
}

/// O `DispatchGroup` ordena a escrita (leitor) antes da leitura (quem espera).
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
