import Foundation
import Testing

/// Rede zero (F27): o app não fala com a internet. Se este teste falhar, ou a
/// mudança é rede de verdade (precisa ser opt-in, explícita e documentada no
/// README) ou é falso positivo: reescreva a linha.
@Suite("Rede zero")
struct NoNetworkTests {
    /// APIs de rede conhecidas. A lista é curta de propósito: cresce quando
    /// aparecer API nova, nunca afrouxa.
    static let proibidos = [
        #"\bimport\s+(Network|CFNetwork|WebKit)\b"#,
        #"\bURLSession\b"#, #"\bNSURLConnection\b"#,
        #"\bNW(Connection|Listener|PathMonitor|Browser|Endpoint)\b"#, #"\bnw_[a-z_]+\("#,
        #"\bCFSocket"#, #"\bCFStreamCreatePairWithSocket"#, #"getStreamsToHost"#,
        #"\bsocket\("#, #"\bgetaddrinfo\("#,
        #""https?://"#,
    ]

    /// Devolve o padrão se a linha parece rede. Comentário `//` não conta.
    static func acerto(em linha: Substring) -> String? {
        guard !linha.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { return nil }
        // ICU, não `Regex` nativo: o `\b` Unicode acha que "URLSession.shared"
        // é uma palavra só e não casa.
        return proibidos.first { linha.range(of: $0, options: .regularExpression) != nil }
    }

    @Test func sourcesNaoUsamRede() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ClaudeBarTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // raiz do pacote
            .appendingPathComponent("Sources")
        let arquivos = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        // Caminho errado = lista vazia = teste verde sem varrer nada.
        #expect(arquivos.count > 5, "não achou os fontes em \(sources.path)")

        for arquivo in arquivos {
            let linhas = try String(contentsOf: arquivo, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (i, linha) in linhas.enumerated() {
                if let padrao = Self.acerto(em: linha) {
                    Issue.record("\(arquivo.lastPathComponent):\(i + 1) parece rede (\(padrao))")
                }
            }
        }
    }

    /// Prova que a varredura pega o que deve — inclusive o caso em que o
    /// `Regex` nativo falharia — e não pega comentário nem arquivo local.
    @Test(arguments: [
        "import Network",
        "let s = URLSession.shared",
        "let c = NWConnection(host: h, port: p, using: .tcp)",
        #"let u = URL(string: "https://exemplo.com")!"#,
        "let fd = socket(AF_INET, SOCK_STREAM, 0)",
    ])
    func pegaRede(_ linha: String) {
        #expect(Self.acerto(em: Substring(linha)) != nil)
    }

    @Test(arguments: [
        "// URLSession em comentário não conta",
        "let data = try Data(contentsOf: arquivo)",
        "import Foundation",
    ])
    func ignoraNaoRede(_ linha: String) {
        #expect(Self.acerto(em: Substring(linha)) == nil)
    }
}
