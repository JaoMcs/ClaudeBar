import Foundation
import Testing

@testable import ClaudeBarCore

private let binary = "/Users/dev/.claude/claudebar/bin/claudebar-hook"
private let legacy = "/Users/dev/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook"

private func json(_ text: String) throws -> [String: Any] {
    try HookInstaller.parse(Data(text.utf8))
}

private func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    NSDictionary(dictionary: a).isEqual(to: b)
}

private func handlers(_ root: [String: Any], _ event: String) -> [[String: Any]] {
    let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
}

@Suite("Merge aditivo dos hooks")
struct HookMergeTests {
    @Test func arquivoAusenteGanhaSoOsNossos() throws {
        let root = HookInstaller.install(try json(""), binary: binary)
        #expect(handlers(root, "Stop").count == 1)
        #expect(handlers(root, "Stop").first?["args"] as? [String] == ["idle"])
        #expect(handlers(root, "Stop").first?["command"] as? String == binary)
    }

    /// Exec form, SessionEnd sem timeout, nunca `onFailure`.
    @Test func formatoDoHandler() throws {
        let root = HookInstaller.install([:], binary: binary)
        for event in ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"] {
            let handler = try #require(handlers(root, event).first)
            #expect(handler["args"] != nil, "\(event) sem args = shell form")
            #expect(handler["onFailure"] == nil)
        }
        #expect(handlers(root, "SessionEnd").first?["timeout"] == nil)
        #expect(handlers(root, "Stop").first?["timeout"] as? Int == 5)
    }

    @Test func preservaHookDoUsuarioNoMesmoEvento() throws {
        let original = try json(#"""
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}]}}
        """#)
        let root = HookInstaller.install(original, binary: binary)
        #expect(handlers(root, "Stop").map { $0["command"] as? String } == ["say pronto", binary])
        #expect(root["model"] as? String == "opus")
    }

    /// O bug do Peep: remover o grupo inteiro apagaria o `say` que divide o grupo.
    @Test func grupoMistoPerdeSoONosso() throws {
        let original = try json(#"""
        {"hooks":{"Stop":[{"hooks":[
          {"type":"command","command":"say pronto"},
          {"type":"command","command":"\#(legacy) idle --pid $PPID"}
        ]}]}}
        """#)
        let root = HookInstaller.strip(original, binary: binary)
        #expect(handlers(root, "Stop").map { $0["command"] as? String } == ["say pronto"])
    }

    @Test func migraEntradaLegadaDoInstallSh() throws {
        let original = try json(#"""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(legacy) idle --pid $PPID"}]}]}}
        """#)
        let root = HookInstaller.install(original, binary: binary)
        #expect(handlers(root, "Stop").count == 1)
        #expect(handlers(root, "Stop").first?["command"] as? String == binary)
    }

    @Test func naoTocaEmHookParecido() throws {
        let parecidos = [
            "/opt/tools/claudebar-hook-wrapper idle",
            "echo claudebar-hook",
            "\"/Users/dev/outro/claudebar-hook\" idle",
        ]
        for command in parecidos {
            #expect(!HookInstaller.isOurs(["type": "command", "command": command], binary: binary), "\(command)")
        }
        #expect(HookInstaller.isOurs(["command": "\"\(legacy)\" idle"], binary: binary))
    }

    @Test func idempotenteEReversivel() throws {
        let original = try json(#"""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}],"PreToolUse":[]}}
        """#)
        let once = HookInstaller.install(original, binary: binary)
        #expect(same(HookInstaller.install(once, binary: binary), once))
        #expect(same(HookInstaller.strip(once, binary: binary), original))
        #expect(same(HookInstaller.strip([:], binary: binary), [:]))
    }

    @Test func jsonInvalidoNaoViraPlano() throws {
        for text in ["{", "[1, 2]", #"{"hooks": []}"#, #"{"hooks": {"Stop": {}}}"#] {
            #expect(throws: HookInstallError.invalidSettings) { try json(text) }
        }
    }

    /// Uma linha trocada vira remoção seguida de inserção, com contexto em volta.
    @Test func diffPorLinha() {
        let diff = HookInstaller.lineDiff(from: Data("a\nb\nc".utf8), to: Data("a\nx\nc".utf8))
        #expect(diff == "  a\n- b\n+ x\n  c")
    }
}
