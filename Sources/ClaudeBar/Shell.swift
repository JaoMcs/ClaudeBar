import Foundation

/// Execução de processo sem shell: argumentos vão separados, então não há
/// interpolação e não há injeção.
enum Shell {
    /// `input` vai para o stdin do filho; `timeout` encerra um filho travado
    /// (devolve `nil`), para quem chama da main não congelar o app.
    static func output(of url: URL, arguments: [String], input: Data? = nil,
                       timeout: TimeInterval? = nil) -> String? {
        let process = Process()
        let pipe = Pipe()
        let stdin = Pipe()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if input != nil { process.standardInput = stdin }

        do {
            try process.run()
        } catch {
            return nil
        }

        // ponytail: só SIGTERM, sem escalar para SIGKILL. Um filho que ignore
        // SIGTERM, ou um neto segurando o pipe de stdout, ainda trava quem
        // chama. O hook não faz nenhuma das duas; se um dia fizer, SIGKILL
        // depois de um prazo e leitura do pipe fora da main.
        let pid = process.processIdentifier
        let deadline = DispatchWorkItem { _ = kill(pid, SIGTERM) }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        }
        defer { deadline.cancel() }

        if let input {
            let handle = stdin.fileHandleForWriting
            // Filho que morreu cedo (ex.: barrado pelo Gatekeeper) não pode
            // derrubar o app com SIGPIPE: vira só um erro de escrita, ignorado.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? handle.write(contentsOf: input)
            try? handle.close()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
