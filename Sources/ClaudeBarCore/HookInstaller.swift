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

/// O que vai ser gravado, montado antes de qualquer escrita para você ver.
public struct HookPlan: Sendable {
    /// Arquivo de verdade, com symlink resolvido: é ele que será reescrito.
    public let settingsURL: URL
    /// Bytes lidos ao montar a prévia. `apply` recusa se o arquivo mudou.
    let original: Data
    let updated: Data
    /// Só o bloco `hooks`, linha a linha com `+`/`-`. O resto do arquivo
    /// (que pode ter `env` com token) não aparece.
    public let diff: String
    public let hasChanges: Bool
    /// O arquivo vai ser reformatado (ordem das chaves, espaços).
    public let reformats: Bool
}

/// Em que pé está a integração. Tudo que não é `ok`/`notInstalled` vira oferta
/// de reparo no app; a detecção em si nunca grava nada.
public enum IntegrationState: Equatable, Sendable {
    case notInstalled
    case ok
    /// Hooks registrados, mas a cópia estável do executável sumiu.
    case binaryMissing
    /// A cópia estável difere do executável deste `.app` (o app foi atualizado).
    case binaryOutdated
    /// Faltam entradas, ou sobram entradas de outra versão.
    case hooksOutdated
    /// Entradas do `install.sh` antigo: shell form, caminho dentro do bundle.
    case legacyHooks
    case invalidSettings
    /// Precisa gravar, mas o arquivo (já sem symlink) não é gravável.
    case readOnlySettings
    /// `disableAllHooks: true` no settings do usuário. Não mexemos nisso.
    case hooksDisabled
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

    // MARK: - Prévia e escrita

    public static func plan(
        _ action: HookAction,
        settings: URL = settingsURL,
        binary: String = stableBinary.path
    ) throws -> HookPlan {
        // Settings em dotfiles costuma ser symlink: gravar `.atomic` no link
        // trocaria o link por um arquivo comum e o repositório pararia de mudar.
        let real = settings.resolvingSymlinksInPath()
        let original = FileManager.default.fileExists(atPath: real.path) ? try Data(contentsOf: real) : Data()
        let root = try parse(original)
        let next = action == .install ? install(root, binary: binary) : strip(root, binary: binary)

        let current = try serialize(root)
        let updated = try serialize(next)
        return HookPlan(
            settingsURL: real,
            original: original,
            updated: updated,
            diff: lineDiff(from: try serialize(hooksOnly(root)), to: try serialize(hooksOnly(next))),
            hasChanges: current != updated,
            reformats: !original.isEmpty && current != original
        )
    }

    /// Grava exatamente o que a prévia mostrou. Devolve o backup, se havia arquivo.
    @discardableResult
    public static func apply(_ plan: HookPlan, backups: URL = backupsURL) throws -> URL? {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: plan.settingsURL.path)
        let now = exists ? try Data(contentsOf: plan.settingsURL) : Data()
        // O Claude Code também grava esse arquivo (`/config`, `/model`): se ele
        // mudou desde a prévia, gravar agora apagaria a mudança dele.
        guard now == plan.original else { throw HookInstallError.changedSinceReview }
        // Sem `~/.claude` ainda, a pasta ausente cairia em "somente leitura".
        if !exists {
            try manager.createDirectory(
                at: plan.settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard isWritable(plan.settingsURL) else { throw HookInstallError.readOnly }

        var backup: URL?
        if exists {
            try manager.createDirectory(
                at: backups,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = backups.appendingPathComponent("settings.json.\(timestamp())")
            // O settings pode ter `env` com token: o backup já nasce `0600`.
            guard manager.createFile(atPath: url.path, contents: now, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            backup = url
        }

        try plan.updated.write(to: plan.settingsURL, options: .atomic)
        if !exists {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.settingsURL.path)
        }
        return backup
    }

    /// JSON para colar à mão quando o settings é gerado por outra ferramenta.
    public static func snippet(binary: String = stableBinary.path) -> String {
        let data = (try? serialize(install([:], binary: binary))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Detecção

    /// Só leitura. `contentsEqual` lê os dois executáveis: chamar no launch,
    /// depois de uma ação e no "Atualizar", não a cada render.
    public static func state(
        bundledBinary: URL?,
        settings: URL = settingsURL,
        binary: URL = stableBinary
    ) -> IntegrationState {
        let manager = FileManager.default
        let real = settings.resolvingSymlinksInPath()
        let data = manager.fileExists(atPath: real.path) ? try? Data(contentsOf: real) : Data()
        guard let data, let root = try? parse(data) else { return .invalidSettings }
        if root["disableAllHooks"] as? Bool == true { return .hooksDisabled }

        let ours = handlers(in: root).filter { isOurs($0.handler, binary: binary.path) }
        let current = ours.filter { $0.handler["args"] != nil && $0.handler["command"] as? String == binary.path }
        let complete = current.count == entries.count && entries.allSatisfy { entry in
            current.contains { $0.event == entry.event && $0.handler["args"] as? [String] == entry.args }
        }
        let settingsState: IntegrationState? =
            if ours.isEmpty { .notInstalled }
            else if current.count != ours.count { .legacyHooks }
            else if !complete { .hooksOutdated }
            else { nil }
        // `readOnlySettings` só quando há algo a gravar.
        if let settingsState {
            return isWritable(real) ? settingsState : .readOnlySettings
        }
        guard manager.isExecutableFile(atPath: binary.path) else { return .binaryMissing }
        if let bundledBinary, !manager.contentsEqual(atPath: bundledBinary.path, andPath: binary.path) {
            return .binaryOutdated
        }
        return .ok
    }

    // MARK: - Executável estável

    /// Copia o hook para o caminho estável trocando o arquivo inteiro. Copiar
    /// por cima de um executável assinado pode derrubá-lo por assinatura (o
    /// kernel guarda cache da assinatura): temporário + `rename`.
    ///
    /// Copia só os bytes (a assinatura vai junto, embutida), não os atributos
    /// estendidos: uma cópia com `com.apple.quarantine` do DMG fica parada na
    /// avaliação do Gatekeeper a cada execução, e o hook estoura o timeout.
    public static func installBinary(from source: URL, to destination: URL = stableBinary) throws {
        let manager = FileManager.default
        guard !manager.contentsEqual(atPath: source.path, andPath: destination.path) else { return }

        let folder = destination.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temp = folder.appendingPathComponent(".claudebar-hook.\(UUID().uuidString)")
        guard manager.createFile(atPath: temp.path, contents: try Data(contentsOf: source), attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        guard rename(temp.path, destination.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

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

    /// Gravar `.atomic` troca o arquivo pela pasta, então a pasta também precisa
    /// ser gravável; um arquivo `0444` (gerado por outra ferramenta) é recusado.
    static func isWritable(_ file: URL) -> Bool {
        let manager = FileManager.default
        guard manager.isWritableFile(atPath: file.deletingLastPathComponent().path) else { return false }
        return !manager.fileExists(atPath: file.path) || manager.isWritableFile(atPath: file.path)
    }

    /// Com milissegundos: duas gravações no mesmo segundo não sobrescrevem o backup.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
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
