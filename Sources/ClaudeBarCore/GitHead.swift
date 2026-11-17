import Foundation

/// Branch do repositório git que contém uma pasta, lida direto do arquivo `HEAD`.
///
/// Sem rodar `git`: é só um arquivo de texto. Quem chama é o hook, que roda
/// dentro do terminal do Claude Code. O app nunca lê nada dentro do projeto,
/// para não disparar o pedido de acesso a Documentos/Mesa (TCC) do macOS.
public enum GitHead {
    /// `"main"`, `"@1a2b3c4"` com HEAD solto, ou `nil` quando a pasta não está
    /// num repositório ou o HEAD não diz a branch (repositório reftable).
    public static func branch(at cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        // O `cwd` pode ser subpasta do repositório: sobe até achar o `.git`.
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            if let head = headURL(dotGit: dotGit) {
                return readRegularFile(head).flatMap(parse)
            }
            if dir.path == "/" { return nil }
            dir.deleteLastPathComponent()
        }
    }

    /// `HEAD` dentro de `.git`, ou no destino do `gitdir:` quando `.git` é um
    /// arquivo (worktree linkado ou submódulo). O HEAD de um worktree é dele.
    static func headURL(dotGit: URL) -> URL? {
        if (try? dotGit.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return dotGit.appendingPathComponent("HEAD")
        }
        guard let text = readRegularFile(dotGit),
              let line = firstLine(text), line.hasPrefix("gitdir:")
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        // `gitdir:` relativo (`git worktree add --relative-paths`) parte da pasta do `.git`.
        return URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent())
            .appendingPathComponent("HEAD")
    }

    static func parse(_ text: String) -> String? {
        guard let head = firstLine(text) else { return nil }
        if head.hasPrefix("ref: ") {
            var ref = head.dropFirst("ref: ".count)
            if ref.hasPrefix("refs/heads/") { ref = ref.dropFirst("refs/heads/".count) }
            // Reftable (Git 2.45+): HEAD é um stub fixo e a branch real fica em
            // binário. Sem rodar git, o honesto é não mostrar branch.
            guard !ref.isEmpty, ref != ".invalid" else { return nil }
            // Vai para texto de menu: limitamos o tamanho, como a `message`.
            return String(ref.prefix(80))
        }
        // HEAD solto: o arquivo traz o SHA do commit (SHA-1 ou SHA-256).
        let isSHA = (head.count == 40 || head.count == 64) && head.allSatisfy(\.isHexDigit)
        return isSHA ? "@\(head.prefix(7))" : nil
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Só arquivo comum: um FIFO chamado `HEAD` travaria o hook, e com ele a sessão.
    private static func readRegularFile(_ url: URL) -> String? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
