import Testing

@testable import ClaudeBarCore

@Suite("Diagnóstico")
struct DiagnosticsTests {
    @Test func homeViraTil() {
        #expect(Diagnostics.anonymize("/Users/ana/.claude/settings.json", home: "/Users/ana") == "~/.claude/settings.json")
        #expect(Diagnostics.anonymize("/Users/ana", home: "/Users/ana") == "~")
    }

    @Test func fronteiraDePasta() {
        #expect(Diagnostics.anonymize("/Users/ana2/x", home: "/Users/ana") == "/Users/ana2/x")
    }

    @Test func foraDoHomeFicaIgual() {
        #expect(Diagnostics.anonymize("/opt/x", home: "/Users/ana") == "/opt/x")
    }

    @Test func textoNaoTemHomeNemCwd() {
        let text = Diagnostics.text(
            appVersion: "1.0", osVersion: "macOS 15", integration: .ok,
            counts: [.working: 2], paths: [("settings", "/Users/ana/.claude/settings.json")],
            home: "/Users/ana")
        #expect(!text.contains("/Users/ana"))
        #expect(!text.contains("projeto-secreto"))
        #expect(text.contains("~/.claude/settings.json"))
        #expect(text.contains("Integration: ok"))
    }

    @Test func contagensNaOrdemEZerosImpressos() {
        let text = Diagnostics.text(
            appVersion: "dev", osVersion: "x", integration: .notInstalled,
            counts: [:], paths: [], home: "/Users/ana")
        let expected = SessionState.allCases.map { "  \($0.rawValue): 0" }.joined(separator: "\n")
        #expect(text.contains(expected))
    }
}
