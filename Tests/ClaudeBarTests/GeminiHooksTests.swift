import Foundation
import Testing

@testable import ClaudeBarCore

private let binary = "/Users/dev/.claude/claudebar/bin/claudebar-hook"

private func json(_ text: String) throws -> [String: Any] {
    try HookInstaller.parse(Data(text.utf8))
}

private func handlers(_ root: [String: Any], _ event: String) -> [[String: Any]] {
    let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
}

private func allCommands(_ root: [String: Any]) -> [String] {
    GeminiHooks.entries.flatMap { handlers(root, $0.event) }.compactMap { $0["command"] as? String }
}

/// Nunca o `~/.gemini` real: cada teste usa a sua pasta.
private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-gemini-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Hooks do Gemini CLI")
struct GeminiHooksTests {
    @Test func arquivoAusenteGanhaSoOsNossos4() throws {
        let root = GeminiHooks.install(try json(""), binary: binary)
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["BeforeAgent", "AfterAgent", "Notification", "SessionEnd"])
        #expect(handlers(root, "BeforeAgent").first?["command"] as? String
            == "'\(binary)' working --agent gemini")
        #expect(handlers(root, "Notification").first?["command"] as? String
            == "'\(binary)' waiting --kind permission --agent gemini")
    }

    @Test func timeoutEmMilissegundosESessionEndSemTimeout() throws {
        let root = GeminiHooks.install([:], binary: binary)
        for event in ["BeforeAgent", "AfterAgent", "Notification"] {
            #expect(handlers(root, event).first?["timeout"] as? Int == 5000)
            #expect(handlers(root, event).first?["type"] as? String == "command")
        }
        #expect(handlers(root, "SessionEnd").first?["timeout"] == nil)
    }

    /// Nada de variável de shell nem `exit 2` (que bloqueia no Gemini).
    @Test func commandSoTemTextoFixo() throws {
        let commands = allCommands(GeminiHooks.install([:], binary: binary))
        #expect(commands.count == 4)
        for command in commands {
            #expect(!command.contains("$"))
            #expect(!command.contains("exit 2"))
        }
    }

    @Test func preservaHookDoUsuarioNoMesmoEvento() throws {
        let original = try json(#"""
        {"model":"x","hooks":{"AfterAgent":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """#)
        let root = GeminiHooks.install(original, binary: binary)
        #expect(handlers(root, "AfterAgent").map { $0["command"] as? String }
            == ["say done", "'\(binary)' idle --agent gemini"])
        #expect(root["model"] as? String == "x")

        let removed = GeminiHooks.strip(root, binary: binary)
        #expect(NSDictionary(dictionary: removed).isEqual(to: original))
    }

    @Test func idempotenteEReversivel() throws {
        let once = GeminiHooks.install([:], binary: binary)
        let twice = GeminiHooks.install(once, binary: binary)
        #expect(NSDictionary(dictionary: once).isEqual(to: twice))
        #expect(GeminiHooks.strip(twice, binary: binary).isEmpty)
    }

    /// Mesmo executável sem `--agent gemini`, ou outro executável com ele: não é nosso.
    @Test func naoTocaEmHookParecido() throws {
        let original = try json(#"""
        {"hooks":{"BeforeAgent":[{"hooks":[
          {"type":"command","command":"'\#(binary)' working"},
          {"type":"command","command":"'/outro/claudebar-hook' working --agent gemini"},
          {"type":"command","command":"echo '\#(binary)' --agent gemini"}
        ]}]}}
        """#)
        let removed = GeminiHooks.strip(GeminiHooks.install(original, binary: binary), binary: binary)
        #expect(NSDictionary(dictionary: removed).isEqual(to: original))
    }

    @Test func jsonInvalidoNaoViraPlano() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        try Data("[1, 2".utf8).write(to: settings)
        #expect(throws: HookInstallError.invalidSettings) {
            try GeminiHooks.plan(.install, settings: settings, binary: binary, claude: folder.appendingPathComponent("nada.json"))
        }
    }

    @Test func hooksDesligadosNaoMexe() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        try Data(#"{"hooksConfig":{"enabled":false}}"#.utf8).write(to: settings)
        #expect(throws: HookInstallError.hooksDisabled) {
            try GeminiHooks.plan(.install, settings: settings, binary: binary, claude: folder.appendingPathComponent("nada.json"))
        }
    }

    /// Prévia, gravação com backup separado e remoção, tudo numa pasta temporária.
    @Test func planoGravaComBackupERemove() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        let claude = folder.appendingPathComponent("claude.json")
        let backups = folder.appendingPathComponent("backups")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)

        let install = try GeminiHooks.plan(.install, settings: settings, binary: binary, claude: claude)
        #expect(install.hasChanges && install.binaryInUse)
        #expect(install.diff.contains("BeforeAgent") && !install.diff.contains("theme"))
        #expect(try HookInstaller.apply(install, backups: backups) != nil)

        let remove = try GeminiHooks.plan(.uninstall, settings: settings, binary: binary, claude: claude)
        #expect(remove.hasChanges && !remove.binaryInUse)
        try HookInstaller.apply(remove, backups: backups)
        #expect(try json(String(decoding: Data(contentsOf: settings), as: UTF8.self))["hooks"] == nil)
    }

    /// Remover os do Claude não apaga o executável se o Gemini ainda o usa, e vice-versa.
    @Test func executavelFicaEnquantoOutroUsa() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gemini = folder.appendingPathComponent("gemini.json")
        let claude = folder.appendingPathComponent("claude.json")
        try HookInstaller.serialize(GeminiHooks.install([:], binary: binary)).write(to: gemini)
        try HookInstaller.serialize(HookInstaller.install([:], binary: binary)).write(to: claude)

        #expect(try HookInstaller.plan(.uninstall, settings: claude, binary: binary, gemini: gemini).binaryInUse)
        #expect(try GeminiHooks.plan(.uninstall, settings: gemini, binary: binary, claude: claude).binaryInUse)
    }

    @Test func deteccaoDoCLI() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("sem-gemini")
        #expect(!GeminiHooks.cliDetected(candidates: [missing.path], folder: missing))

        let cli = folder.appendingPathComponent("gemini")
        try Data("#!/bin/sh\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        #expect(GeminiHooks.cliDetected(candidates: [cli.path], folder: missing))
        // Só a pasta `~/.gemini` também conta.
        #expect(GeminiHooks.cliDetected(candidates: [], folder: folder))
    }
}
