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
        var environment = ProcessInfo.processInfo.environment
        environment[reentryVariable] = "1"
        // stderr do filho segue para o nosso: aparece no `claude --debug`.
        return Shell.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], input: input,
                         environment: environment, standardError: .standardError, timeout: timeout)
    }
}
