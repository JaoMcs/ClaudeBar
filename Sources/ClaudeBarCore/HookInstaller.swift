import Foundation

public enum HookAction: Sendable {
    case install
    case uninstall
    /// `statusLine` do ClaudeBar (limites de uso). Opt-in próprio, separado dos hooks.
    case installStatusLine
    case uninstallStatusLine
}

public enum HookInstallError: Error, Equatable, LocalizedError {
    /// O arquivo existe e não é um objeto JSON no formato esperado: não se grava nada.
    case invalidSettings
    /// Gerado por outra ferramenta (dotfiles, Nix) ou sem permissão de escrita.
    case readOnly
    /// O arquivo mudou entre a prévia e o clique (o próprio Claude Code grava nele).
    case changedSinceReview
    /// `hooksConfig.enabled: false` no settings do Gemini. Não mexemos nisso.
    case hooksDisabled

    /// No app acha a tradução no `Bundle.main`; no CLI (stderr) fica em inglês.
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: String(localized: "settings.json is not valid JSON; nothing was changed")
        case .readOnly: String(localized: "settings.json is read-only; copy the JSON and paste it into the tool that generates it")
        case .changedSinceReview: String(localized: "settings.json changed after the preview; nothing was changed")
        case .hooksDisabled: String(localized: "Hooks are turned off in settings.json (hooksConfig.enabled); nothing was changed")
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
    /// Só `hooks` e `statusLine`, linha a linha com `+`/`-`. O resto do arquivo
    /// (que pode ter `env` com token) não aparece.
    public let diff: String
    public let hasChanges: Bool
    /// O arquivo vai ser reformatado (ordem das chaves, espaços).
    public let reformats: Bool
    /// Ações de statusline: o que fazer com `statusline-original.json`.
    /// `.save` grava antes do settings; `.remove` apaga depois.
    public let statusLineOriginal: StatusLineInstall.Original?
    /// Depois de gravar, o `statusLine` ou algum hook ainda chama o executável
    /// estável: remover um dos dois não pode apagá-lo. Sem nenhum, ele sai.
    public let binaryInUse: Bool
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
        /// `matcher` do grupo. `var` para entrar no init memberwise com padrão.
        var matcher: String? = nil
        let args: [String]
    }

    /// Tudo o que o ClaudeBar registra. F05, H0, F07, F08, F24 acrescentam linhas aqui.
    static let entries = [
        // Sessão aberta e ainda sem prompt aparece na hora. Sem `compact`: ele
        // acontece no meio do turno, e `idle` ali seria um "terminou" falso.
        Entry(event: "SessionStart", matcher: "startup|resume|clear", args: ["idle"]),
        Entry(event: "UserPromptSubmit", args: ["working"]),
        Entry(event: "Stop", args: ["idle"]),
        // Turno que acabou por erro de API: o `Stop` não roda nesse caso.
        Entry(event: "StopFailure", args: ["error"]),
        // Só o que de fato espera você. `idle_prompt`, `auth_success`, `quota_*`
        // nem chamam o binário.
        Entry(event: "Notification", matcher: "permission_prompt", args: ["waiting", "--kind", "permission"]),
        // Formulário (`elicitation_dialog`) e pedido de abrir URL (`elicitation_url_dialog`) são a mesma pergunta.
        Entry(event: "Notification", matcher: "elicitation_dialog|elicitation_url_dialog", args: ["waiting", "--kind", "question"]),
        // Pergunta do Claude aparece na hora, sem esperar o `Notification`. Só
        // o fato de ter perguntado: o `tool_input` (o texto) não é lido.
        Entry(event: "PreToolUse", matcher: "AskUserQuestion", args: ["waiting", "--kind", "question"]),
        // Permissão aprovada (ou ferramenta que falhou) tira a sessão de
        // "esperando". Sem matcher: qualquer ferramenta pode ter pedido permissão.
        Entry(event: "PostToolUse", args: ["working", "--if-waiting"]),
        Entry(event: "PostToolUseFailure", args: ["working", "--if-waiting"]),
        Entry(event: "SessionEnd", args: ["end"]),
    ]

    // MARK: - Prévia e escrita

    public static func plan(
        _ action: HookAction,
        settings: URL = settingsURL,
        binary: String = stableBinary.path,
        original: URL = StatusDirectory.originalStatusLineURL,
        gemini: URL = GeminiHooks.settingsURL
    ) throws -> HookPlan {
        // Settings em dotfiles costuma ser symlink: gravar `.atomic` no link
        // trocaria o link por um arquivo comum e o repositório pararia de mudar.
        let real = settings.resolvingSymlinksInPath()
        let bytes = FileManager.default.fileExists(atPath: real.path) ? try Data(contentsOf: real) : Data()
        let root = try parse(bytes)
        let next: [String: Any]
        var statusLineOriginal: StatusLineInstall.Original?
        switch action {
        case .install: next = install(root, binary: binary)
        case .uninstall: next = strip(root, binary: binary)
        case .installStatusLine:
            let result = StatusLineInstall.install(root, hookCommand: shellQuoted(binary) + " statusline")
            next = result.settings
            statusLineOriginal = result.original
        case .uninstallStatusLine:
            // Pode faltar (não havia statusline): aí a chave sai.
            let saved = (try? Data(contentsOf: original))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            next = StatusLineInstall.uninstall(root, original: saved)
            statusLineOriginal = .remove
        }

        let current = try serialize(root)
        let updated = try serialize(next)
        return HookPlan(
            settingsURL: real,
            original: bytes,
            updated: updated,
            diff: lineDiff(from: try serialize(relevantKeys(root)), to: try serialize(relevantKeys(next))),
            hasChanges: current != updated,
            reformats: !bytes.isEmpty && current != bytes,
            statusLineOriginal: statusLineOriginal,
            binaryInUse: uses(next, binary: binary) || GeminiHooks.uses(binary: binary, settings: gemini)
        )
    }

    /// O `statusLine` ou algum hook deste settings chama o executável.
    static func uses(_ root: [String: Any], binary: String) -> Bool {
        StatusLineInstall.isOurs(root["statusLine"]) || handlers(in: root).contains { isOurs($0.handler, binary: binary) }
    }

    /// Só leitura, para o plano do Gemini saber se o Claude ainda usa o executável.
    /// Arquivo ilegível conta como "usa": na dúvida o executável fica.
    static func uses(binary: String, settings: URL) -> Bool {
        let real = settings.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: real.path) else { return false }
        guard let data = try? Data(contentsOf: real), let root = try? parse(data) else { return true }
        return uses(root, binary: binary)
    }

    /// Grava exatamente o que a prévia mostrou. Devolve o backup, se havia arquivo.
    @discardableResult
    public static func apply(
        _ plan: HookPlan,
        backups: URL = backupsURL,
        original: URL = StatusDirectory.originalStatusLineURL
    ) throws -> URL? {
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

        // Original antes do settings: se a escrita do settings falhar, ele
        // continua com o statusline do usuário e o arquivo extra é inofensivo.
        if case .save(let object) = plan.statusLineOriginal {
            try manager.createDirectory(
                at: original.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Já nasce `0600`, como o backup: nenhum instante com a permissão do umask.
            guard manager.createFile(atPath: original.path, contents: try serialize(object), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        try plan.updated.write(to: plan.settingsURL, options: .atomic)
        if !exists {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.settingsURL.path)
        }
        // Depois do settings: até aqui o hook ainda podia precisar do original.
        if case .remove = plan.statusLineOriginal {
            try? manager.removeItem(at: original)
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
            current.contains {
                $0.event == entry.event && $0.matcher == entry.matcher && $0.handler["args"] as? [String] == entry.args
            }
        }
        let settingsState: IntegrationState? =
            if ours.isEmpty { .notInstalled }
            else if current.count != ours.count { .legacyHooks }
            else if !complete { .hooksOutdated }
            else { nil }
        // `readOnlySettings` só quando há algo a gravar. Sem `~/.claude` ainda,
        // `apply` cria a pasta: não é somente leitura.
        if let settingsState {
            let folderMissing = !manager.fileExists(atPath: real.deletingLastPathComponent().path)
            return folderMissing || isWritable(real) ? settingsState : .readOnlySettings
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
        strip(root) { isOurs($0, binary: binary) }
    }

    /// `strip` com o critério de "nosso" de fora: o Gemini reconhece pelo `command`.
    static func strip(_ root: [String: Any], where isOurs: ([String: Any]) -> Bool) -> [String: Any] {
        guard let hooks = root["hooks"] as? [String: Any] else { return root }
        var kept = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let remaining: [[String: Any]] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !isOurs($0) }
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
            var group: [String: Any] = ["hooks": [handler]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            let groups = hooks[entry.event] as? [[String: Any]] ?? []
            hooks[entry.event] = groups + [group]
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

    /// Só o que o ClaudeBar mexe: o resto do settings pode ter token em `env`.
    private static func relevantKeys(_ root: [String: Any]) -> [String: Any] {
        root.filter { $0.key == "hooks" || $0.key == "statusLine" }
    }

    /// O `statusLine.command` roda em shell: o caminho vai entre aspas simples.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func handlers(in root: [String: Any]) -> [(event: String, matcher: String?, handler: [String: Any])] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return hooks.flatMap { event, value in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .map { (event: event, matcher: group["matcher"] as? String, handler: $0) }
            }
        }
    }
}
