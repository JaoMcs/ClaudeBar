import Foundation
import Testing

@testable import ClaudeBarCore

private let binary = "/Users/dev/.claude/claudebar/bin/claudebar-hook"

@Suite("Configuração do Codex CLI")
struct CodexConfigTests {
    @Test func cliDetectedUsaCaminhosInjetados() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bin = dir.appendingPathComponent("codex")
        #expect(!CodexConfig.cliDetected(paths: [bin.path]))

        try Data("#!/bin/sh\n".utf8).write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        #expect(CodexConfig.cliDetected(paths: [bin.path]))
    }

    @Test func snippetSemVariavelDeShell() {
        let toml = CodexConfig.snippet(binary: binary)
        #expect(!toml.contains("$"))
        #expect(toml == "notify = [\"\(binary)\", \"idle\", \"--agent\", \"codex\"]")
    }

    @Test func isConfiguredVerdadeiroFalsoEComentario() {
        let toml = CodexConfig.snippet(binary: binary)
        #expect(CodexConfig.isConfigured(configText: toml, binary: binary))
        #expect(CodexConfig.isConfigured(configText: "model = \"o3\"\n\(toml)\n", binary: binary))
        #expect(!CodexConfig.isConfigured(configText: "# \(toml)\n", binary: binary))
        #expect(!CodexConfig.isConfigured(configText: "notify = [\"/other/hook\", \"idle\"]\n", binary: binary))
        #expect(!CodexConfig.isConfigured(configText: "", binary: binary))
    }

    @Test func parsePayloadExemploDaDocumentacao() throws {
        // Exemplo do payload `agent-turn-complete` passado no último argumento pelo Codex.
        let json = #"""
        {"type":"agent-turn-complete","thread-id":"b5f6c1c2-1111-2222-3333-444455556666","turn-id":"12345","cwd":"/tmp/meu-projeto","input-messages":["teste"],"last-assistant-message":"Pronto"}
        """#
        let data = try #require(CodexConfig.payloadData(from: ["claudebar-hook", "idle", "--agent", "codex", json]))
        let payload = try #require(CodexConfig.parsePayload(data))
        #expect(payload.type == "agent-turn-complete")
        #expect(payload.resolvedSessionId == "b5f6c1c2-1111-2222-3333-444455556666")
        #expect(payload.cwd == "/tmp/meu-projeto")
    }

    @Test func payloadDataIgnoraQuandoUltimoArgumentoNaoEhJson() {
        #expect(CodexConfig.payloadData(from: ["claudebar-hook", "idle", "--agent", "codex"]) == nil)
    }
}
