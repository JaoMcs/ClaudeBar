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

/// Pasta temporária própria: `NSHomeDirectory()` ignora `$HOME`, então nada
/// aqui pode usar os caminhos padrão.
private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
        for event in ["UserPromptSubmit", "Stop", "StopFailure", "Notification", "SessionEnd"] {
            let handler = try #require(handlers(root, event).first)
            #expect(handler["args"] != nil, "\(event) sem args = shell form")
            #expect(handler["onFailure"] == nil)
        }
        #expect(handlers(root, "SessionEnd").first?["timeout"] == nil)
        #expect(handlers(root, "Stop").first?["timeout"] as? Int == 5)
        #expect(handlers(root, "StopFailure").first?["timeout"] as? Int == 5)
        #expect(handlers(root, "StopFailure").first?["args"] as? [String] == ["error"])
        #expect(handlers(root, "Notification").allSatisfy { $0["timeout"] as? Int == 5 })
        // Sem `compact` no matcher: ele roda no meio do turno.
        let start = try #require(((root["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])?.first)
        #expect(start["matcher"] as? String == "startup|resume|clear")
        #expect(handlers(root, "SessionStart").first?["args"] as? [String] == ["idle"])
        #expect(handlers(root, "SessionStart").first?["timeout"] as? Int == 5)
    }

    /// `idle_prompt`, `auth_success`… não viram "esperando": só os dois matchers.
    @Test func notificationTemDoisMatchers() throws {
        let hooks = try #require(HookInstaller.install([:], binary: binary)["hooks"] as? [String: Any])
        let groups = try #require(hooks["Notification"] as? [[String: Any]])
        let pairs = groups.map { group in
            (group["matcher"] as? String, (group["hooks"] as? [[String: Any]])?.first?["args"] as? [String])
        }
        #expect(groups.count == 2)
        #expect(pairs.allSatisfy { $0.0 != nil })
        #expect(pairs.contains { $0 == ("permission_prompt", ["waiting", "--kind", "permission"]) })
        #expect(pairs.contains { $0 == ("elicitation_dialog|elicitation_url_dialog", ["waiting", "--kind", "question"]) })
    }

    @Test func preservaHookDoUsuarioNoMesmoEvento() throws {
        let original = try json(#"""
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}]}}
        """#)
        let root = HookInstaller.install(original, binary: binary)
        #expect(handlers(root, "Stop").map { $0["command"] as? String } == ["say pronto", binary])
        #expect(root["model"] as? String == "opus")
    }

    /// H0: o nosso `PostToolUse` entra depois do seu, sem matcher, e não duplica.
    @Test func postToolUseDoUsuarioFica() throws {
        let original = try json(#"""
        {"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"prettier --write"}]}]}}
        """#)
        let root = HookInstaller.install(original, binary: binary)
        #expect(handlers(root, "PostToolUse").map { $0["command"] as? String } == ["prettier --write", binary])
        for event in ["PostToolUse", "PostToolUseFailure"] {
            let ours = try #require(handlers(root, event).last)
            #expect(ours["args"] as? [String] == ["working", "--if-waiting"])
            #expect(ours["timeout"] as? Int == 5)
        }
        let groups = try #require((root["hooks"] as? [String: Any])?["PostToolUseFailure"] as? [[String: Any]])
        #expect(groups.count == 1 && groups[0]["matcher"] == nil)
        #expect(same(HookInstaller.install(root, binary: binary), root))
    }

    /// F24: o nosso `PreToolUse` só casa com `AskUserQuestion` e entra ao lado
    /// do seu. Nenhum `PostToolUse` com esse matcher: o `--if-waiting` já cobre.
    @Test func preToolUseDoUsuarioFica() throws {
        let original = try json(#"""
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./guard.sh"}]}]}}
        """#)
        let root = HookInstaller.install(original, binary: binary)
        #expect(handlers(root, "PreToolUse").map { $0["command"] as? String } == ["./guard.sh", binary])
        let hooks = try #require(root["hooks"] as? [String: Any])
        let groups = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(groups.map { $0["matcher"] as? String } == ["Bash", "AskUserQuestion"])
        #expect(handlers(root, "PreToolUse").last?["args"] as? [String] == ["waiting", "--kind", "question"])
        let post = try #require(hooks["PostToolUse"] as? [[String: Any]])
        #expect(post.allSatisfy { $0["matcher"] == nil })
        #expect(same(HookInstaller.install(root, binary: binary), root))
        #expect(same(HookInstaller.strip(root, binary: binary), original))
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
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}],"PreCompact":[]}}
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

@Suite("Prévia e escrita do settings.json")
struct HookWriteTests {
    @Test func gravaPeloSymlinkComBackup() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("dotfiles-settings.json")
        let link = folder.appendingPathComponent("settings.json")
        let backups = folder.appendingPathComponent("backups")
        try Data(#"{"model":"opus"}"#.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let plan = try HookInstaller.plan(.install, settings: link, binary: binary)
        #expect(plan.hasChanges)
        #expect(plan.diff.contains("+ "))
        #expect(!plan.diff.contains("opus"), "o diff mostra só o bloco hooks")
        let backup = try #require(try HookInstaller.apply(plan, backups: backups))

        // O link continua link, e quem mudou foi o arquivo de verdade.
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(handlers(try json(String(decoding: Data(contentsOf: real), as: UTF8.self)), "Stop").count == 1)

        let mode = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try Data(contentsOf: backup) == Data(#"{"model":"opus"}"#.utf8))
    }

    @Test func recusaSeMudouDepoisDaPrevia() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: settings)
        let plan = try HookInstaller.plan(.install, settings: settings, binary: binary)
        try Data(#"{"model":"sonnet"}"#.utf8).write(to: settings)

        #expect(throws: HookInstallError.changedSinceReview) {
            try HookInstaller.apply(plan, backups: folder)
        }
        #expect(try Data(contentsOf: settings) == Data(#"{"model":"sonnet"}"#.utf8))
    }

    @Test func removerSemNadaNossoNaoMuda() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        try Data(#"{ "model" : "opus" }"#.utf8).write(to: settings)
        let plan = try HookInstaller.plan(.uninstall, settings: settings, binary: binary)
        #expect(!plan.hasChanges)
    }

    /// Arquivo `0444` numa pasta gravável: recusa e não deixa backup.
    @Test func arquivoSomenteLeituraRecusa() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        let backups = folder.appendingPathComponent("backups")
        try Data("{}".utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: settings.path)
        let plan = try HookInstaller.plan(.install, settings: settings, binary: binary)

        #expect(throws: HookInstallError.readOnly) {
            try HookInstaller.apply(plan, backups: backups)
        }
        #expect(!FileManager.default.fileExists(atPath: backups.path))
        #expect(try Data(contentsOf: settings) == Data("{}".utf8))
    }

    /// Sem `~/.claude` ainda: a pasta nasce `0700` em vez de cair em "somente leitura".
    @Test func criaPastaQueNaoExiste() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("novo/settings.json")
        let plan = try HookInstaller.plan(.install, settings: settings, binary: binary)
        #expect(try HookInstaller.apply(plan, backups: folder) == nil)

        let manager = FileManager.default
        #expect(try manager.attributesOfItem(atPath: settings.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
        #expect(try manager.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int == 0o600)
    }
}

@Suite("Executável estável e detecção")
struct HookStateTests {
    /// Monta settings + executáveis numa pasta temporária.
    private func fixture(settings: String) throws -> (settings: URL, bundled: URL, stable: URL) {
        let folder = try tempFolder()
        let bundled = folder.appendingPathComponent("bundle-hook")
        try Data("v1".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
        let stable = folder.appendingPathComponent("bin/claudebar-hook")
        let file = folder.appendingPathComponent("settings.json")
        try Data(settings.utf8).write(to: file)
        return (file, bundled, stable)
    }

    @Test func copiaComPermissao0700ESubstituiInteiro() throws {
        let f = try fixture(settings: "{}")
        defer { try? FileManager.default.removeItem(at: f.settings.deletingLastPathComponent()) }
        let quarentena = Array("0081;00000000;Safari;".utf8)
        #expect(setxattr(f.bundled.path, "com.apple.quarantine", quarentena, quarentena.count, 0, 0) == 0)
        try HookInstaller.installBinary(from: f.bundled, to: f.stable)
        #expect(FileManager.default.contentsEqual(atPath: f.bundled.path, andPath: f.stable.path))
        // A quarentena do DMG não vai junto: com ela o exec trava no Gatekeeper.
        #expect(getxattr(f.stable.path, "com.apple.quarantine", nil, 0, 0, 0) == -1)
        let mode = try FileManager.default.attributesOfItem(atPath: f.stable.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)

        // Versão nova: troca por rename, inode novo.
        let before = try FileManager.default.attributesOfItem(atPath: f.stable.path)[.systemFileNumber] as? Int
        try Data("v2".utf8).write(to: f.bundled)
        try HookInstaller.installBinary(from: f.bundled, to: f.stable)
        let after = try FileManager.default.attributesOfItem(atPath: f.stable.path)[.systemFileNumber] as? Int
        #expect(before != after)
        #expect(try Data(contentsOf: f.stable) == Data("v2".utf8))
    }

    @Test func estados() throws {
        let f = try fixture(settings: "{}")
        defer { try? FileManager.default.removeItem(at: f.settings.deletingLastPathComponent()) }
        func state(_ settings: String) throws -> IntegrationState {
            try Data(settings.utf8).write(to: f.settings)
            return HookInstaller.state(bundledBinary: f.bundled, settings: f.settings, binary: f.stable)
        }
        let installed = String(decoding: try HookInstaller.serialize(HookInstaller.install([:], binary: f.stable.path)), as: UTF8.self)

        #expect(try state("{}") == .notInstalled)
        #expect(try state(installed) == .binaryMissing)
        try HookInstaller.installBinary(from: f.bundled, to: f.stable)
        #expect(try state(installed) == .ok)
        try Data("v2".utf8).write(to: f.bundled)
        #expect(try state(installed) == .binaryOutdated)

        #expect(try state(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(legacy) idle"}]}]}}"#) == .legacyHooks)
        #expect(try state(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(f.stable.path)","args":["idle"]}]}]}}"#) == .hooksOutdated)
        // Instalação de T05: um `Notification` sem matcher. Reinstalar conserta.
        var hooks = try #require(HookInstaller.install([:], binary: f.stable.path)["hooks"] as? [String: Any])
        hooks["Notification"] = [["hooks": [["type": "command", "command": f.stable.path, "args": ["waiting"]]]]]
        let semMatcher = String(decoding: try HookInstaller.serialize(["hooks": hooks]), as: UTF8.self)
        #expect(try state(semMatcher) == .hooksOutdated)
        let reinstalado = try HookInstaller.install(HookInstaller.parse(Data(semMatcher.utf8)), binary: f.stable.path)
        #expect(try state(String(decoding: HookInstaller.serialize(reinstalado), as: UTF8.self)) == .binaryOutdated)

        #expect(try state(#"{"disableAllHooks": true}"#) == .hooksDisabled)
        #expect(try state("{") == .invalidSettings)

        // Sem `~/.claude` ainda: não instalado, não somente leitura.
        let missing = f.settings.deletingLastPathComponent().appendingPathComponent("nao-existe/settings.json")
        #expect(HookInstaller.state(bundledBinary: f.bundled, settings: missing, binary: f.stable) == .notInstalled)
    }

    /// Quem instalou com o matcher antigo (`elicitation_dialog`) vê "desatualizado";
    /// reinstalar troca o matcher sem duplicar o grupo, e a segunda vez é `.ok`.
    @Test func matcherAntigoMigraSemDuplicar() throws {
        let f = try fixture(settings: "{}")
        defer { try? FileManager.default.removeItem(at: f.settings.deletingLastPathComponent()) }
        try HookInstaller.installBinary(from: f.bundled, to: f.stable)
        let novo = String(decoding: try HookInstaller.serialize(HookInstaller.install([:], binary: f.stable.path)), as: UTF8.self)
        let antigo = novo.replacingOccurrences(of: "elicitation_dialog|elicitation_url_dialog", with: "elicitation_dialog")
        #expect(antigo != novo)
        try Data(antigo.utf8).write(to: f.settings)
        #expect(HookInstaller.state(bundledBinary: f.bundled, settings: f.settings, binary: f.stable) == .hooksOutdated)

        let migrado = HookInstaller.install(try HookInstaller.parse(Data(antigo.utf8)), binary: f.stable.path)
        let groups = try #require((migrado["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]])
        #expect(groups.count == 2)
        #expect(groups.filter { $0["matcher"] as? String == "elicitation_dialog|elicitation_url_dialog" }.count == 1)
        try HookInstaller.serialize(migrado).write(to: f.settings)
        #expect(HookInstaller.state(bundledBinary: f.bundled, settings: f.settings, binary: f.stable) == .ok)
    }

    /// Settings gerado (dotfiles/Nix): só leitura vira estado próprio, e a
    /// escrita é recusada mesmo com a pasta gravável.
    @Test func somenteLeitura() throws {
        let f = try fixture(settings: "{}")
        defer { try? FileManager.default.removeItem(at: f.settings.deletingLastPathComponent()) }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: f.settings.path)
        #expect(HookInstaller.state(bundledBinary: f.bundled, settings: f.settings, binary: f.stable) == .readOnlySettings)

        let plan = try HookInstaller.plan(.install, settings: f.settings, binary: f.stable.path)
        #expect(throws: HookInstallError.readOnly) { try HookInstaller.apply(plan, backups: f.stable) }
    }
}
