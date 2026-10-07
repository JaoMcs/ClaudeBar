import Foundation

/// Diretório compartilhado entre os hooks (escrevem) e o app (lê).
///
/// Cada sessão do Claude Code escreve **seu próprio** arquivo, o que elimina
/// qualquer disputa de escrita entre sessões simultâneas.
public enum StatusDirectory {
    public static let url: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("claudebar", isDirectory: true)

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    public static func fileURL(sessionId: String) -> URL {
        url.appendingPathComponent("\(sanitize(sessionId)).json")
    }

    /// O estado guarda caminhos dos seus projetos e as mensagens do Claude, então
    /// o diretório é só seu: `0700` nele, `0600` em cada arquivo.
    public static func createIfNeeded() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } else {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    /// Grava de forma atômica, para o app nunca ler um JSON pela metade.
    public static func write(_ status: SessionStatus) throws {
        try createIfNeeded()
        let data = try encoder.encode(status)
        let file = fileURL(sessionId: status.sessionId)
        try data.write(to: file, options: .atomic)
        // A escrita atômica cria o arquivo novo pelo umask; reforçamos depois.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public static func remove(sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(sessionId: sessionId))
    }

    /// Lê todas as sessões, descartando arquivos inválidos ou de processos mortos.
    public static func readAll() -> [SessionStatus] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let status = try? decoder.decode(SessionStatus.self, from: data)
                else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                guard status.isAlive else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                return status
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func sanitize(_ sessionId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = sessionId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return cleaned.isEmpty ? "unknown" : String(cleaned)
    }
}
