@testable import ClaudeBarCore
import Foundation
import Testing

/// Recorte do exemplo oficial do stdin do statusline (code.claude.com/docs/en/statusline).
private let statusLineJSON = """
{
  "session_id": "abc",
  "transcript_path": "/Users/dev/.claude/projects/x.jsonl",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
"""

@Suite("Limites do statusline")
struct RateLimitsTests {
    @Test func decodificaOExemploOficial() throws {
        let now = Date(timeIntervalSince1970: 1_738_400_000)
        let limits = try #require(RateLimits.fromStatusLine(Data(statusLineJSON.utf8), now: now))
        #expect(limits.fiveHour == RateWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)))
        #expect(limits.sevenDay?.usedPercentage == 41.2)
        #expect(limits.updatedAt == now)
    }

    /// Chave de API ou sessão antes da 1ª resposta: não grava nada, para não
    /// apagar o dado bom de outra sessão.
    @Test(arguments: [#"{"session_id":"abc"}"#, #"{"rate_limits":{}}"#, #"{"rate_limits":null}"#, "lixo"])
    func semCampoNaoGrava(json: String) {
        #expect(RateLimits.fromStatusLine(Data(json.utf8)) == nil)
    }

    @Test func umaJanelaSo() throws {
        let json = #"{"rate_limits":{"seven_day":{"used_percentage":12,"resets_at":1738857600}}}"#
        let limits = try #require(RateLimits.fromStatusLine(Data(json.utf8)))
        #expect(limits.fiveHour == nil)
        #expect(limits.sevenDay?.displayPercent == 12)
    }

    @Test func percentualPresoEntre0e100() {
        let reset = Date()
        #expect(RateWindow(usedPercentage: 104.7, resetsAt: reset).displayPercent == 100)
        #expect(RateWindow(usedPercentage: -1, resetsAt: reset).displayPercent == 0)
        #expect(RateWindow(usedPercentage: 23.5, resetsAt: reset).displayPercent == 24)
    }

    @Test func resumoDoRodape() {
        let now = Date(timeIntervalSince1970: 1_000)
        let limits = RateLimits(
            fiveHour: RateWindow(usedPercentage: 23.4, resetsAt: Date(timeIntervalSince1970: 500)),
            sevenDay: RateWindow(usedPercentage: 41.2, resetsAt: Date(timeIntervalSince1970: 2_000))
        )
        // 5 h já renovou: "–", nunca 0% nem o número velho.
        #expect(limits.summary(now: now) == "5h – · sem 41%")
        #expect(RateLimits().summary(now: now) == "5h – · sem –")
    }

    /// O rodapé atualiza a cada poucos segundos; regravar sem mudança acordaria
    /// o app à toa.
    @Test func soRegravaQuandoMuda() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = RateWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 20_000))
        let novo = RateLimits(fiveHour: window, updatedAt: now)
        #expect(novo.needsWrite(over: nil, now: now))
        #expect(!novo.needsWrite(over: RateLimits(fiveHour: window, updatedAt: now - 10), now: now))
        #expect(novo.needsWrite(over: RateLimits(fiveHour: window, updatedAt: now - 61), now: now))
        let outro = RateWindow(usedPercentage: 24, resetsAt: window.resetsAt)
        #expect(novo.needsWrite(over: RateLimits(fiveHour: outro, updatedAt: now - 10), now: now))
    }

    /// `readAll` apagava todo `*.json` que não fosse sessão.
    @Test func readAllNaoApagaOsArquivosDoStatusline() {
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.limitsURL))
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.originalStatusLineURL))
        #expect(StatusDirectory.isSessionFile(StatusDirectory.fileURL(sessionId: "abc")))
    }
}

/// Em série: cada teste prende uma thread do pool esperando o filho, e o
/// runner de CI tem só 3 vCPU.
@Suite("Encadeamento do statusline", .serialized)
struct StatusLineChainTests {
    @Test func repassaStdinEDevolveStdout() throws {
        let input = Data(String(repeating: "x", count: 200_000).utf8) // maior que o buffer do pipe
        let result = try #require(StatusLineChain.run(command: "cat", input: input, timeout: 5))
        #expect(result.output == input)
        #expect(result.status == 0)
    }

    @Test func repassaCodigoDeSaida() throws {
        let result = try #require(StatusLineChain.run(command: "echo oi; exit 3", input: Data(), timeout: 5))
        #expect(String(decoding: result.output, as: UTF8.self) == "oi\n")
        #expect(result.status == 3)
    }

    /// Filho que nem lê o stdin não pode derrubar o hook com SIGPIPE.
    @Test func filhoQueIgnoraStdin() throws {
        let input = Data(count: 1_000_000)
        let result = try #require(StatusLineChain.run(command: "echo ok", input: input, timeout: 5))
        #expect(result.status == 0)
    }

    @Test func estouraOTimeout() {
        let start = Date()
        #expect(StatusLineChain.run(command: "sleep 10", input: Data(), timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func originalComONossoComandoNaoEncadeia() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("statusline-original.json")

        try Data(#"{"type":"command","command":"~/bin/minha-linha.sh","padding":2}"#.utf8).write(to: file)
        #expect(StatusLineChain.originalCommand(at: file) == "~/bin/minha-linha.sh")

        try Data(#"{"type":"command","command":"/x/claudebar-hook statusline"}"#.utf8).write(to: file)
        #expect(StatusLineChain.originalCommand(at: file) == nil)

        #expect(StatusLineChain.originalCommand(at: dir.appendingPathComponent("nao-existe.json")) == nil)
    }
}
