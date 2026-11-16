import Foundation

public enum HookAction: Sendable {
    case install
    case uninstall
}

public enum HookInstallError: Error, Equatable, LocalizedError {
    /// O arquivo existe e não é um objeto JSON no formato esperado: não se grava nada.
    case invalidSettings
    /// Gerado por outra ferramenta (dotfiles, Nix) ou sem permissão de escrita.
    case readOnly
    /// O arquivo mudou entre a prévia e o clique (o próprio Claude Code grava nele).
    case changedSinceReview

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "o settings.json não é um JSON válido; nada foi alterado"
        case .readOnly: "o settings.json é somente leitura; copie o JSON e cole na ferramenta que o gera"
        case .changedSinceReview: "o settings.json mudou depois da prévia; nada foi alterado"
        }
    }
}

/// Registro dos hooks do ClaudeBar no `~/.claude/settings.json`.
///
/// Só mexe nos handlers cujo executável é o do ClaudeBar — nunca no grupo
/// inteiro, nunca em hook seu. O app e o `claudebar-hook install` passam
/// pelas mesmas funções.
public enum HookInstaller {
    public static let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("settings.json")

    /// Cópia estável do hook: sobrevive a mover, renomear ou apagar o `.app`.
    public static let stableBinary = StatusDirectory.url
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("claudebar-hook")

    public static let backupsURL = StatusDirectory.url
        .appendingPathComponent("backups", isDirectory: true)

    /// O que o `install.sh` antigo gravava: o hook dentro do bundle.
    static let legacySuffix = "/ClaudeBar.app/Contents/MacOS/claudebar-hook"

    struct Entry {
        let event: String
        let args: [String]
    }

    /// Tudo o que o ClaudeBar registra. F05, H0, F07, F08, F24 acrescentam linhas aqui.
    static let entries = [
        Entry(event: "UserPromptSubmit", args: ["working"]),
        Entry(event: "Stop", args: ["idle"]),
        Entry(event: "Notification", args: ["waiting"]),
        Entry(event: "SessionEnd", args: ["end"]),
    ]

    // MARK: - Funções puras sobre o JSON

    /// Um handler é do ClaudeBar se o **executável** for exatamente o nosso
    /// (ou o do bundle, legado). Nada de busca por substring: decidir pela
    /// forma do comando já apagou hook alheio em outro app.
    static func isOurs(_ handler: [String: Any], binary: String) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        let executable: String =
            if handler["args"] != nil { command } // exec form: `command` é só o executável
            else if command.hasPrefix("\"") { String(command.dropFirst().prefix { $0 != "\"" }) }
            else { String(command.prefix { $0 != " " }) }
        return executable == binary || executable.hasSuffix(legacySuffix)
    }

    /// Tira só os nossos handlers. Grupo que fica vazio sai, evento vazio sai;
    /// o que é seu fica igual, inclusive no mesmo grupo.
    static func strip(_ root: [String: Any], binary: String) -> [String: Any] {
        guard let hooks = root["hooks"] as? [String: Any] else { return root }
        var kept = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let remaining: [[String: Any]] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !isOurs($0, binary: binary) }
                if others.count == handlers.count { return group }
                if others.isEmpty { return nil }
                var group = group
                group["hooks"] = others
                return group
            }
            kept[event] = remaining.isEmpty && !groups.isEmpty ? nil : remaining
        }
        var root = root
        root["hooks"] = kept.isEmpty && !hooks.isEmpty ? nil : kept
        return root
    }

    /// `strip` + os nossos grupos no fim de cada evento. Reinstalar é idempotente
    /// e migra as entradas legadas.
    static func install(_ root: [String: Any], binary: String) -> [String: Any] {
        var root = strip(root, binary: binary)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var handler: [String: Any] = ["type": "command", "command": binary, "args": entry.args]
            // SessionEnd fica sem `timeout`: o orçamento de saída de *toda*
            // sessão sobe até o maior timeout configurado nele.
            // E nunca `onFailure`: o indicador não pode bloquear o prompt.
            if entry.event != "SessionEnd" { handler["timeout"] = 5 }
            let groups = hooks[entry.event] as? [[String: Any]] ?? []
            hooks[entry.event] = groups + [["hooks": [handler]]]
        }
        root["hooks"] = hooks
        return root
    }

    /// `[:]` para arquivo ausente ou em branco. Erro se não for objeto JSON ou
    /// se `hooks` tiver formato inesperado — nesses casos não se grava nada.
    static func parse(_ data: Data) throws -> [String: Any] {
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallError.invalidSettings
        }
        if let hooks = root["hooks"] {
            guard let events = hooks as? [String: Any],
                  events.values.allSatisfy({ $0 is [[String: Any]] })
            else { throw HookInstallError.invalidSettings }
        }
        return root
    }

    static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    /// Diff por linha com `CollectionDifference` (stdlib), na ordem do arquivo.
    static func lineDiff(from old: Data, to new: Data) -> String {
        let before = String(decoding: old, as: UTF8.self).components(separatedBy: "\n")
        let after = String(decoding: new, as: UTF8.self).components(separatedBy: "\n")
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in after.difference(from: before) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var lines: [String] = []
        var old = 0
        var new = 0
        while old < before.count || new < after.count {
            if removed.contains(old) {
                lines.append("- \(before[old])")
                old += 1
            } else if inserted.contains(new) {
                lines.append("+ \(after[new])")
                new += 1
            } else {
                if new < after.count, !after[new].isEmpty { lines.append("  \(after[new])") }
                old += 1
                new += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func hooksOnly(_ root: [String: Any]) -> [String: Any] {
        root["hooks"].map { ["hooks": $0] } ?? [:]
    }

    private static func handlers(in root: [String: Any]) -> [(event: String, handler: [String: Any])] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return hooks.flatMap { event, value in
            (value as? [[String: Any]] ?? [])
                .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                .map { (event: event, handler: $0) }
        }
    }
}
