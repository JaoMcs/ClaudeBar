import Foundation

/// Hooks do ClaudeBar no `~/.gemini/settings.json` do Gemini CLI. Opt-in, só
/// se o CLI existir, com a mesma prévia + backup dos hooks do Claude.
///
/// Doc: https://geminicli.com/docs/hooks/reference/
public enum GeminiHooks {
    public static let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".gemini", isDirectory: true)
    public static let settingsURL = folder.appendingPathComponent("settings.json")

    /// Backups separados dos do Claude: os dois arquivos se chamam `settings.json`.
    public static let backupsURL = HookInstaller.backupsURL.appendingPathComponent("gemini", isDirectory: true)

    /// Onde o Homebrew e o `npm -g` costumam pôr o `gemini`. Sem shell de login.
    public static let candidates = ["/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"]

    static let entries: [(event: String, args: String)] = [
        ("BeforeAgent", "working"),
        ("AfterAgent", "idle"),
        // `notification_type` hoje só tem `ToolPermission`.
        ("Notification", "waiting --kind permission"),
        ("SessionEnd", "end"),
    ]

    public static func cliDetected(
        candidates: [String] = candidates,
        folder: URL = folder,
        manager: FileManager = .default
    ) -> Bool {
        candidates.contains { manager.isExecutableFile(atPath: $0) } || manager.fileExists(atPath: folder.path)
    }

    /// O `command` roda em shell: só texto fixo nosso, caminho entre aspas
    /// simples e nenhuma variável (`$PPID`, `$HOME`).
    static func command(_ args: String, binary: String) -> String {
        "\(HookInstaller.shellQuoted(binary)) \(args) --agent gemini"
    }

    static func isOurs(_ handler: [String: Any], binary: String) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        return command.hasPrefix(HookInstaller.shellQuoted(binary) + " ") && command.contains("--agent gemini")
    }

    static func strip(_ root: [String: Any], binary: String) -> [String: Any] {
        HookInstaller.strip(root) { isOurs($0, binary: binary) }
    }

    /// `strip` + os nossos grupos no fim de cada evento: idempotente.
    static func install(_ root: [String: Any], binary: String) -> [String: Any] {
        var root = strip(root, binary: binary)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var handler: [String: Any] = ["type": "command", "command": command(entry.args, binary: binary)]
            // Milissegundos no Gemini. SessionEnd sem timeout, como no Claude.
            if entry.event != "SessionEnd" { handler["timeout"] = 5000 }
            let groups = hooks[entry.event] as? [[String: Any]] ?? []
            hooks[entry.event] = groups + [["hooks": [handler]]]
        }
        root["hooks"] = hooks
        return root
    }

    /// `hooksConfig.enabled: false` desliga todos os hooks do Gemini: não mexemos nisso.
    static func disabled(_ root: [String: Any]) -> Bool {
        (root["hooksConfig"] as? [String: Any])?["enabled"] as? Bool == false
    }

    /// `action`: `.install` ou `.uninstall` (o resto conta como remover). Diff só de `hooks`.
    public static func plan(
        _ action: HookAction,
        settings: URL = settingsURL,
        binary: String = HookInstaller.stableBinary.path,
        claude: URL = HookInstaller.settingsURL
    ) throws -> HookPlan {
        let real = settings.resolvingSymlinksInPath()
        let bytes = FileManager.default.fileExists(atPath: real.path) ? try Data(contentsOf: real) : Data()
        let root = try HookInstaller.parse(bytes)
        guard !disabled(root) else { throw HookInstallError.hooksDisabled }
        let next = action == .install ? install(root, binary: binary) : strip(root, binary: binary)
        let current = try HookInstaller.serialize(root)
        let updated = try HookInstaller.serialize(next)
        let hooksOnly = { (root: [String: Any]) in root.filter { $0.key == "hooks" } }
        return HookPlan(
            settingsURL: real,
            original: bytes,
            updated: updated,
            diff: HookInstaller.lineDiff(
                from: try HookInstaller.serialize(hooksOnly(root)),
                to: try HookInstaller.serialize(hooksOnly(next))
            ),
            hasChanges: current != updated,
            reformats: !bytes.isEmpty && current != bytes,
            statusLineOriginal: nil,
            binaryInUse: uses(next, binary: binary) || HookInstaller.uses(binary: binary, settings: claude)
        )
    }

    static func uses(_ root: [String: Any], binary: String) -> Bool {
        HookInstaller.handlers(in: root).contains { isOurs($0.handler, binary: binary) }
    }

    /// Só leitura. Arquivo ilegível conta como "usa": na dúvida o executável fica.
    static func uses(binary: String, settings: URL) -> Bool {
        let real = settings.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: real.path) else { return false }
        guard let data = try? Data(contentsOf: real), let root = try? HookInstaller.parse(data) else { return true }
        return uses(root, binary: binary)
    }
}
