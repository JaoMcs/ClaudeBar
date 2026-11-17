import Foundation

/// Execução de processo sem shell: argumentos vão separados, então não há
/// interpolação e não há injeção.
public enum Shell {
    /// `input` vai para o stdin do filho; `timeout` encerra um filho travado
    /// (devolve `nil`), para quem chama da main não congelar o app.
    public static func output(of url: URL, arguments: [String], input: Data? = nil,
                       timeout: TimeInterval? = nil) -> String? {
        guard let result = run(url, arguments: arguments, input: input, timeout: timeout),
              result.status == 0
        else { return nil }
        return String(data: result.output, encoding: .utf8)
    }

    /// Como `output`, mas devolve o stdout e o código de saída mesmo quando o
    /// filho sai com erro. `nil` se não deu para rodar ou se o filho morreu por
    /// sinal (inclusive o do `timeout`).
    public static func run(_ url: URL, arguments: [String], input: Data? = nil,
                           environment: [String: String]? = nil,
                           standardError: FileHandle = .nullDevice,
                           timeout: TimeInterval? = nil) -> (output: Data, status: Int32)? {
        let process = Process()
        let pipe = Pipe()
        let stdin = Pipe()
        process.executableURL = url
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = pipe
        process.standardError = standardError
        if input != nil { process.standardInput = stdin }

        do {
            try process.run()
        } catch {
            return nil
        }

        // ponytail: só SIGTERM, sem escalar para SIGKILL. Um filho que ignore
        // SIGTERM, ou um neto segurando o pipe de stdout (`cmd &`), ainda trava
        // quem chama. Se aparecer, SIGKILL depois de um prazo e grupo de processos.
        let pid = process.processIdentifier
        let deadline = DispatchWorkItem { _ = kill(pid, SIGTERM) }
        if let timeout {
            // Fila serial própria, não a global: fila criada assim ganha thread
            // mesmo com o pool cheio de threads presas esperando processo (no
            // runner de 3 vCPU, a global chegou a não rodar o prazo por segundos).
            DispatchQueue(label: "Shell.deadline").asyncAfter(deadline: .now() + timeout, execute: deadline)
        }
        defer { deadline.cancel() }

        if let input {
            let handle = stdin.fileHandleForWriting
            // Filho que morreu cedo (ex.: barrado pelo Gatekeeper) ou que nem lê
            // o stdin não pode derrubar quem chama com SIGPIPE: vira só um erro
            // de escrita, ignorado.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            // Escreve em thread própria enquanto esta lê o stdout: o pipe tem
            // buffer finito, e escrever tudo antes de ler trava se o filho
            // imprimir muito antes de ler o resto. Thread própria,
            // pelo mesmo motivo do prazo.
            Thread.detachNewThread {
                try? handle.write(contentsOf: input)
                try? handle.close()
            }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationReason == .exit else { return nil }
        return (data, process.terminationStatus)
    }
}
