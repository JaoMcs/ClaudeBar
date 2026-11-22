import Foundation

/// Payload JSON que o Codex CLI passa como último argumento ao executar `notify`.
/// Apenas `thread-id` e `cwd` são lidos; `input-messages` e `last-assistant-message`
/// ficam de fora (o app não lê conteúdo de conversa).
public struct CodexNotifyPayload: Decodable, Equatable, Sendable {
    public let type: String?
    public let threadId: String?
    public let sessionId: String?
    public let cwd: String?

    enum CodingKeys: String, CodingKey {
        case type
        case threadId = "thread-id"
        case sessionId = "session_id"
        case cwd
    }

    public var resolvedSessionId: String? { threadId ?? sessionId }
}

/// Integração somente leitura com o Codex CLI (`~/.codex/config.toml`).
/// O app não edita TOML para não depender de parser externo: gera o trecho
/// para o usuário colar e confere se já está no arquivo.
public enum CodexConfig {
    public static let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex", isDirectory: true)
    public static let configURL = folder.appendingPathComponent("config.toml")

    /// Caminhos fixos onde o Codex costuma ser instalado, sem shell de login.
    public static var defaultPaths: [String] {
        [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
    }

    public static func cliDetected(
        paths: [String] = defaultPaths,
        manager: FileManager = .default
    ) -> Bool {
        paths.contains { manager.isExecutableFile(atPath: $0) }
    }

    /// Linha TOML fixa para o usuário colar no topo de `~/.codex/config.toml`.
    /// Sem shell nem variável (`$`).
    public static func snippet(binary: String = HookInstaller.stableBinary.path) -> String {
        let escaped = binary
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "notify = [\"\(escaped)\", \"idle\", \"--agent\", \"codex\"]"
    }

    /// Busca simples por linha (ignora comentários `#`): não escreve nem interpreta TOML.
    public static func isConfigured(
        configText: String,
        binary: String = HookInstaller.stableBinary.path
    ) -> Bool {
        configText.split(whereSeparator: \.isNewline).contains { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), line.hasPrefix("notify") else { return false }
            return line.contains(binary) && line.contains("codex")
        }
    }

    /// Só leitura em `url`. Retorna `false` se o arquivo não existir ou não puder ser lido.
    public static func isConfigured(
        at url: URL = configURL,
        binary: String = HookInstaller.stableBinary.path
    ) -> Bool {
        let real = url.resolvingSymlinksInPath()
        guard let text = try? String(contentsOf: real, encoding: .utf8) else { return false }
        return isConfigured(configText: text, binary: binary)
    }

    /// Extrai o JSON passado pelo Codex como último argumento de linha de comando.
    public static func payloadData(from arguments: [String]) -> Data? {
        guard let last = arguments.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        else { return nil }
        return Data(last.utf8)
    }

    public static func parsePayload(_ data: Data) -> CodexNotifyPayload? {
        try? JSONDecoder().decode(CodexNotifyPayload.self, from: data)
    }
}
