# Spec G03 — Integração de hooks: merge aditivo, caminho estável, transparência, status (F02, F03, F16, F17)

Insumos: `04-como-fazer/G03-hooks-integracao.md`, `03-validacao/BACKLOG.md` (F02 M, F03 P, F16 M, F17 P), `00-PLANO.md` (guard rails), código em `main` @ 80768db.

**Verificado nesta spec** (todo o código abaixo aplicado numa cópia do projeto, Swift 6.3.3, tools 6.0, macOS 26.5, Claude Code 2.1.325):
- `swift build`: 0 erros, 0 avisos de concorrência (fecha o item 6 da seção 10 da pesquisa: `[String: Any]` só vive dentro de funções síncronas `nonisolated` do Core e de métodos `@MainActor`; nada não-`Sendable` cruza fronteira). `swift test`: **50 testes passam** (34 atuais + 16 novos).
- Mutação: com o bug do Peep (apagar o grupo inteiro), `grupoMistoPerdeSoONosso` falha. O teste pega a regressão.
- `claudebar-hook install --dry-run` contra o `~/.claude/settings.json` real (só leitura, nada gravado) mostra a migração das 4 entradas legadas (shell form + `--pid $PPID` → exec form + caminho estável), só o bloco `hooks`, e o aviso de reformatação. `uninstall --dry-run` mostra a remoção.
- `echo '{}' | claudebar-hook` e `claudebar-hook bogus` saem com **1** (hoje: 2).
- **Achado novo (fecha o item 5 da seção 10):** cópia do hook com `com.apple.quarantine` **trava no exec** (avaliação do Gatekeeper; morta pelo `alarm` aos 6 s; `spctl --assess` → `rejected`). A mesma cópia sem o atributo sai na hora. Consequência: `copyItem` (que copia xattrs) faria o hook de quem instalou por DMG estourar o timeout em todo evento. A spec copia **só os bytes** (assinatura ad-hoc embutida continua válida: `codesign -v` ok).
- **Achado novo:** `Shell.output` não tem prazo. O teste ponta a ponta do F17 roda na main; com um hook travado (achado acima) o app congelaria. A spec acrescenta `timeout` (testado: `sleep 30` com prazo de 0,5 s volta em ~0,53 s).
- Item 4 da seção 10 (`Bundle.main` dentro do CLI): **contornado**, não testado. O CLI acha o próprio executável com `proc_pidpath(getpid())`, que não depende de bundle. O app usa `Bundle.main.url(forAuxiliaryExecutable:)` (documentado).

## Entregas e arquivos (para o gestor ordenar)

| PR | Entrega | Arquivos | Esforço |
|---|---|---|---|
| **1** | **F02** merge aditivo + CLI `install`/`uninstall` + exit 1 + `getppid()` + cópia estável do binário (parte mínima do F03, sem ela os hooks apontariam para o nada) + `install.sh` sem `jq` + `uninstall.sh` | criar `Sources/ClaudeBarCore/HookInstaller.swift`, `Tests/ClaudeBarTests/HookInstallerTests.swift` (suites `HookMergeTests`, `HookWriteTests`, teste `copiaComPermissao0700…`), `scripts/uninstall.sh`; alterar `Sources/claudebar-hook/main.swift`, `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/ClaudeBar/ProcessProbe.swift`, `scripts/install.sh`, `README.md`, `README.pt-BR.md`, `TODO.md` | 4 h |
| **2** | **F03** detecção de estado (`IntegrationState`, `state(...)`) | alterar `Sources/ClaudeBarCore/HookInstaller.swift`, `Tests/ClaudeBarTests/HookInstallerTests.swift` (testes `estados`, `somenteLeitura`) | 1,5 h |
| **3** | **F16** tela de transparência (`NSAlert` com diff), oferta no 1º uso, item de menu | criar `Sources/ClaudeBar/HookSetup.swift`; alterar `Sources/ClaudeBar/SessionStore.swift` (1 linha), `Sources/ClaudeBar/MenuContent.swift`, `README.md`, `README.pt-BR.md` | 3 h |
| **4** | **F17** "testar integração" ponta a ponta + último evento + dica de pasta não confiada | alterar `Sources/ClaudeBar/HookSetup.swift`, `Sources/ClaudeBar/Shell.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/SessionTerminatorTests.swift` (suite `ShellTimeoutTests`), `README.md`, `README.pt-BR.md` | 2 h |

Ordem e conflitos:
- 1 → 2 → 3 → 4, em sequência (mesmos arquivos).
- **F05 e F07 dependem do PR 1**: acrescentam linhas em `HookInstaller.entries` (F05 precisa de um campo `matcher` no `Entry`, ver "O que NÃO fazer"). A spec G06 diz "`scripts/install.sh` (ou o instalador do F02)": depois do PR 1 é **só** `entries`.
- `main.swift` também é tocado por F05 (`--kind`) e F07 (`error`, payload): rodar depois do PR 1.
- `SessionStore.swift`/`MenuContent.swift` também são tocados por F01, F05, F07, F12, F19, F24: PRs 3 e 4 em sequência com eles.
- G02 (F23): o passo de verificação "sai com 2" vira "sai com 1" depois do PR 1; o texto de README do DMG que manda usar `jq` deixa de valer.

---

## F02 — Merge aditivo em Swift + CLI (PR 1)

### Objetivo
Registrar e remover os hooks do ClaudeBar sem tocar em nada do usuário: hoje o `install.sh` **substitui** o array inteiro de `UserPromptSubmit`/`Stop`/`Notification`/`SessionEnd` (apaga hooks seus nesses eventos), depende de `jq` e usa shell form com `$PPID`. Corrigir junto o bug do `exit(2)`.

### Decisão técnica e por quê
- **`JSONSerialization` no Core**, funções puras (`strip`, `install`, `parse`, `serialize`, `lineDiff`) + duas de IO (`plan`, `apply`). Mesmo código no CLI e no app.
  - Descartado `jq`: dependência externa e não reutilizável no app.
  - Descartado `Codable` com enum `JSONValue`: ~40 linhas a mais e também perde a ordem das chaves.
- **Posse por executável exato**: handler é nosso se o executável (exec form: `command`; shell form legado: 1º token, com ou sem aspas) é o caminho estável **ou** termina em `/ClaudeBar.app/Contents/MacOS/claudebar-hook` (legado, para migrar). Remove-se **o handler**, nunca o grupo (bug do Peep).
  - Descartado `contains("claudebar")`: decidir pela forma do comando apagou hooks alheios no iTerm2.
- **Exec form** (`command` + `args`, sem shell), caminho gravado já expandido (`$HOME`/`~` não expandem em exec form). `timeout: 5` em todos menos `SessionEnd` (subiria o orçamento de saída de toda sessão). Nunca `onFailure`.
  - Descartado shell form com aspas: reintroduz shell (guard rail). Mínimo passa a ser Claude Code 2.1.139 (README).
- **Sem `--pid $PPID`**: em exec form não expande. O hook usa `getppid()` **só se** `proc_pidpath` do pai contém `claude`; senão grava 0 (= comportamento atual sem pid). Protege o item 1 não confirmado: se o pai direto não for o Claude, nada piora (pid 0 nunca é sinalizado; `SessionTerminator` já confere `proc_pidpath` antes de qualquer `kill`).
- **`exit(1)` em vez de `exit(2)`**: exit 2 bloqueia o prompt (`UserPromptSubmit`) e impede o Claude de parar (`Stop`). 1 é erro que não bloqueia. Também protege o item 3 não confirmado (Claude Code < 2.1.139 que ignore `args` roda o hook sem argumento → sai 1, não bloqueia).
- **Escrita**: resolve symlink antes (`resolvingSymlinksInPath`), `.atomic`, `0600` só em arquivo novo, backup `0600` em `~/.claude/claudebar/backups/settings.json.<yyyyMMdd-HHmmss-SSS>` criado já com a permissão (`createFile(attributes:)`, sem janela `0644`). Milissegundos no nome: `install` + `uninstall` no mesmo segundo não sobrescrevem o backup do original.
- **Corrida com o Claude Code** (`/config`, `/model` gravam o arquivo): `apply` relê e recusa (`changedSinceReview`) se os bytes mudaram desde a prévia. Nunca grava algo diferente do que foi mostrado.
- **Somente leitura** (dotfiles/Nix): `apply` recusa se o arquivo real ou a pasta não são graváveis, mesmo que o `rename` do `.atomic` conseguisse passar por cima de um arquivo `0444`.
- **Diff**: `CollectionDifference` da stdlib sobre `serialize(parse(original))` × `serialize(novo)`, **só do bloco `hooks`**, com contexto. Mostra exatamente o JSON que entra/sai sem ruído de formatação e sem expor o resto do arquivo (`env` pode ter token). Reformatação é avisada à parte (`reformats`).
  - Descartado `/usr/bin/diff -u` via `Process`: um processo a mais para o mesmo resultado.
- **Cópia estável já no PR 1**: `install` registra `~/.claude/claudebar/bin/claudebar-hook`, então o mesmo PR precisa copiar o binário (detalhes no F03). O executável é copiado **antes** do settings ser gravado.
- **CLI trata `install`/`uninstall` antes de ler o stdin** (num terminal, ler o stdin travaria esperando EOF).

### Código

**Criar `Sources/ClaudeBarCore/HookInstaller.swift`** (arquivo completo; `IntegrationState` e `state(...)` são do PR 2 — podem entrar já ou no PR 2, o gestor decide; `installBinary` entra no PR 1):

```swift
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

/// Situação da integração, lida do disco. Cada estado diferente de `ok` e
/// `notInstalled` vira uma **oferta** de reparo — nunca um reparo silencioso.
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

    /// Tudo o que o ClaudeBar registra. F05 e F07 acrescentam linhas aqui.
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

    // MARK: - Executável estável

    /// Copia o hook para o caminho estável trocando o arquivo inteiro. Copiar
    /// por cima de um executável assinado pode derrubá-lo por assinatura (o
    /// kernel guarda cache da assinatura), segundo a Apple: temporário + `rename`.
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

    // MARK: - Detecção

    /// Lê settings e executável e diz em que pé está a integração. Não grava nada.
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
        if let settingsState {
            return isWritable(real) ? settingsState : .readOnlySettings
        }

        guard manager.isExecutableFile(atPath: binary.path) else { return .binaryMissing }
        if let bundledBinary, !manager.contentsEqual(atPath: bundledBinary.path, andPath: binary.path) {
            return .binaryOutdated
        }
        return .ok
    }

    // MARK: - Funções puras sobre o JSON

    /// Um handler é do ClaudeBar se o **executável** for exatamente o nosso
    /// (ou o do bundle, legado). Nada de `contains("claudebar")`: decidir pela
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

    /// `.atomic` cria um arquivo novo ao lado e troca: precisa da pasta
    /// gravável, e o arquivo (se existe) também — senão respeitamos o "só leitura".
    static func isWritable(_ file: URL) -> Bool {
        let manager = FileManager.default
        guard manager.isWritableFile(atPath: file.deletingLastPathComponent().path) else { return false }
        return !manager.fileExists(atPath: file.path) || manager.isWritableFile(atPath: file.path)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
```

**`Sources/ClaudeBarCore/SessionStatus.swift`**: acrescentar no fim (o CLI precisa; hoje esse código está dentro do `ProcessProbe`, no target do app):

```swift
/// Caminho do executável de um processo (`proc_pidpath`), ou `nil` se ele não
/// existe mais. Usado para conferir que um PID ainda é o Claude.
public func processExecutablePath(_ pid: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer[..<Int(length)], as: UTF8.self)
}
```

**`Sources/ClaudeBar/ProcessProbe.swift`**: reusar (acrescentar `import ClaudeBarCore`):

```swift
        executablePath: { processExecutablePath($0) }
```

**`Sources/claudebar-hook/main.swift`** (arquivo completo):

```swift
import ClaudeBarCore
import Foundation

// CLI chamado pelos hooks do Claude Code. Lê o payload JSON no stdin e grava
// o estado da sessão em ~/.claude/claudebar/<session_id>.json.
//
// Uso: claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>]
//      claudebar-hook install|uninstall [--dry-run]

/// Campos do payload que os hooks do Claude Code entregam no stdin.
private struct HookPayload: Decodable {
    let sessionId: String?
    let cwd: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case message
    }
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("claudebar-hook: \(message)\n".utf8))
    // 1, nunca 2: no Claude Code, exit 2 bloqueia o prompt (UserPromptSubmit)
    // e impede o Claude de parar (Stop). 1 é erro que não bloqueia nada.
    exit(1)
}

private func parsePID(_ arguments: [String]) -> Int32 {
    if let index = arguments.firstIndex(of: "--pid"),
       arguments.indices.contains(index + 1),
       let pid = Int32(arguments[index + 1]) {
        return pid
    }
    // Exec form (sem shell) não tem `$PPID`: o pai direto deve ser o Claude
    // Code. Só aceita se for mesmo um `claude`; senão 0 = "sem pid", como antes.
    let parent = getppid()
    let isClaude = processExecutablePath(parent)?.lowercased().contains("claude") == true
    return isClaude ? parent : 0
}

/// `install`/`uninstall`: mostra o diff e, sem `--dry-run`, grava com backup.
private func manage(_ action: HookAction, dryRun: Bool) {
    do {
        let plan = try HookInstaller.plan(action)
        print(plan.hasChanges ? plan.diff : "Nada a mudar em \(plan.settingsURL.path).")
        if plan.hasChanges, plan.reformats {
            print("\nO arquivo será reformatado (ordem das chaves); fora de \"hooks\" o conteúdo não muda.")
        }
        guard !dryRun else { return }

        if action == .install {
            // O próprio executável que está rodando vira a cópia estável.
            guard let me = processExecutablePath(getpid()) else { fail("executável não encontrado") }
            try HookInstaller.installBinary(from: URL(fileURLWithPath: me))
        }
        if plan.hasChanges, let backup = try HookInstaller.apply(plan) {
            print("Backup: \(backup.path)")
        }
        if action == .uninstall {
            try? FileManager.default.removeItem(at: HookInstaller.stableBinary)
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        fail("informe o estado (working|idle|waiting|end) ou install|uninstall")
    }

    // Antes de ler o stdin: num terminal, ler o stdin travaria esperando EOF.
    switch command {
    case "install": return manage(.install, dryRun: arguments.contains("--dry-run"))
    case "uninstall": return manage(.uninstall, dryRun: arguments.contains("--dry-run"))
    default: break
    }

    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    let payload = try? StatusDirectory.decoder.decode(HookPayload.self, from: stdinData)
    let sessionId = payload?.sessionId
        ?? ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"]
        ?? "unknown"

    if command == "end" {
        StatusDirectory.remove(sessionId: sessionId)
        return
    }

    guard let state = SessionState(rawValue: command) else {
        fail("estado inválido \"\(command)\"")
    }

    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: payload?.cwd ?? FileManager.default.currentDirectoryPath,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: payload?.message.map { String($0.prefix(200)) }
    )

    do {
        try StatusDirectory.write(status)
    } catch {
        // Um hook nunca deve derrubar a sessão do Claude: só registra e sai bem.
        FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
    }
}

run()
```

### Testes
`Tests/ClaudeBarTests/HookInstallerTests.swift` (arquivo completo; no PR 1 entram `HookMergeTests`, `HookWriteTests` e `copiaComPermissao0700ESubstituiInteiro`; `estados` e `somenteLeitura` vão no PR 2). Usa pastas temporárias: `NSHomeDirectory()` ignora `$HOME`, então nenhum teste pode usar os caminhos padrão.

```swift
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
}

@Suite("Prévia e escrita do settings.json")
struct HookWriteTests {
    @Test func gravaPeloSymlinkComBackup() throws {
        let folder = try tempFolder()
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
        let settings = folder.appendingPathComponent("settings.json")
        try Data(#"{ "model" : "opus" }"#.utf8).write(to: settings)
        let plan = try HookInstaller.plan(.uninstall, settings: settings, binary: binary)
        #expect(!plan.hasChanges)
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
        #expect(try state(#"{"disableAllHooks": true}"#) == .hooksDisabled)
        #expect(try state("{") == .invalidSettings)
    }

    /// Settings gerado (dotfiles/Nix): só leitura vira estado próprio, e a
    /// escrita é recusada mesmo com a pasta gravável.
    @Test func somenteLeitura() throws {
        let f = try fixture(settings: "{}")
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: f.settings.path)
        #expect(HookInstaller.state(bundledBinary: f.bundled, settings: f.settings, binary: f.stable) == .readOnlySettings)

        let plan = try HookInstaller.plan(.install, settings: f.settings, binary: f.stable.path)
        #expect(throws: HookInstallError.readOnly) { try HookInstaller.apply(plan, backups: f.stable) }
    }
}
```

O `exit(1)` não tem teste automatizado (exigiria localizar o executável buildado a partir do teste, frágil). Fica na verificação manual.

### Scripts

**`scripts/install.sh`** (completo):

```bash
#!/bin/bash
# Instala o ClaudeBar em ~/Applications e registra os hooks no
# ~/.claude/settings.json pelo próprio claudebar-hook: mostra a prévia, mexe só
# nas entradas do ClaudeBar e guarda backup em ~/.claude/claudebar/backups.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications"
APP="$APP_DIR/ClaudeBar.app"
HOOK="$APP/Contents/MacOS/claudebar-hook"

./scripts/build-app.sh

echo "==> Instalando em $APP"
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R build/ClaudeBar.app "$APP"

echo "==> Prévia das mudanças no ~/.claude/settings.json"
"$HOOK" install --dry-run
read -r -p "Aplicar? [s/N] " resposta
if [[ "$resposta" =~ ^[sS]$ ]]; then
  "$HOOK" install
else
  echo "Hooks não registrados. Dá para registrar depois pelo menu do app."
fi

echo "==> Abrindo o app"
open "$APP"

echo
echo "Pronto. O ícone está na barra de menu."
echo "O Claude Code recarrega o settings.json sozinho: sessões abertas já usam os hooks."
```

**Criar `scripts/uninstall.sh`** (`chmod +x`):

```bash
#!/bin/bash
# Remove o ClaudeBar: tira só as entradas dele do settings.json (com backup),
# fecha o app e apaga o bundle. Estado e backups ficam em ~/.claude/claudebar.
set -euo pipefail

HOOK="$HOME/.claude/claudebar/bin/claudebar-hook"
[[ -x "$HOOK" ]] || HOOK="$HOME/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook"

"$HOOK" uninstall
pkill -x ClaudeBar || true
rm -rf "$HOME/Applications/ClaudeBar.app"

echo "Removido. Backups do settings.json em ~/.claude/claudebar/backups (apague à mão se quiser)."
```

### README (`README.md` e `README.pt-BR.md`)
- Requirements: tirar `jq`; acrescentar "Claude Code 2.1.139 or later (hooks use exec form, `args`)".
- Installation: o script mostra o diff e pergunta; só as entradas do ClaudeBar mudam, hooks seus nos mesmos eventos ficam; backup em `~/.claude/claudebar/backups/` (`0600`); o arquivo é reformatado (ordem das chaves). Trocar "Hooks only apply to new sessions" por "Claude Code reloads `settings.json`, so open sessions pick the hooks up (folders must be trusted)". Tirar "`~/.claude/settings.json` must already exist" (o merge cria).
- Hook CLI usage: `claudebar-hook <working|idle|waiting|end> [--pid <pid>]` e `claudebar-hook install|uninstall [--dry-run]`. Explicar o fallback para `getppid()` e o exit 1.
- "How it works": o hook mora em `~/.claude/claudebar/bin/claudebar-hook` (cópia do bundle).
- Uninstall: `./scripts/uninstall.sh` (ou `~/.claude/claudebar/bin/claudebar-hook uninstall`).
- Security: backups `0600`; "no jq"; exec form = sem shell também nos hooks.
- Project structure: `HookInstaller.swift`, `scripts/uninstall.sh`.
- `TODO.md`: marcar o item de housekeeping "Merge instead".

### Verificação manual
1. `swift build && swift test` verdes; `./scripts/build-app.sh`.
2. `cp ~/.claude/settings.json /tmp/settings.antes.json` (backup próprio do teste).
3. `build/ClaudeBar.app/Contents/MacOS/claudebar-hook install --dry-run`: diff só do bloco `hooks`, nada gravado (`shasum` do settings igual).
4. Acrescentar à mão um `{"type":"command","command":"say pronto"}` no mesmo grupo do `Stop`; rodar `install`. O `say` continua; os 4 handlers viram exec form apontando para `~/.claude/claudebar/bin/claudebar-hook`; backup novo `0600` em `~/.claude/claudebar/backups/`; `ls -l ~/.claude/claudebar/bin` → `-rwx------`.
5. Rodar `install` de novo: "Nada a mudar".
6. Abrir uma sessão do Claude Code **já aberta antes** e mandar um prompt: o arquivo `~/.claude/claudebar/<id>.json` aparece com `"state" : "working"` e `pid` igual a `pgrep -x claude` daquela sessão (fecha o item 1 da seção 10; se `pid` vier 0, registrar no PR e seguir: o comportamento é o de hoje sem pid).
7. `echo '{}' | ~/.claude/claudebar/bin/claudebar-hook; echo $?` → `1`.
8. Settings como symlink: `mv ~/.claude/settings.json ~/dotfiles-settings.json && ln -s ~/dotfiles-settings.json ~/.claude/settings.json`; `install`: o link continua link. Desfazer.
9. `uninstall`: só os 4 handlers somem; `say` fica; `bin/claudebar-hook` some.
10. Restaurar `/tmp/settings.antes.json` se algo der errado.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Apagar hook do usuário | Posse por executável exato, remoção por handler; testes `grupoMisto…`, `naoTocaEmHookParecido`, mutação verificada |
| JSON inválido do usuário vira `{}` | `parse` lança `invalidSettings` para não-objeto e `hooks` malformado; arquivo ilegível lança (não vira vazio) |
| Reformatação assusta | Diff semântico só de `hooks` + aviso explícito + backup |
| Corrida com `/config`, `/model` | `changedSinceReview` em `apply`. Residual de ms entre reler e `rename`: aceito |
| Symlink de dotfiles virar arquivo | `resolvingSymlinksInPath()` + teste `gravaPeloSymlinkComBackup` |
| Claude Code < 2.1.139 ignora `args` (não confirmado) | `exit(1)` não bloqueia; README declara o mínimo. Se o gestor quiser cobrir versões antigas: adiar, não reintroduzir shell |
| `getppid()` não ser o Claude (não confirmado) | Só aceito se `proc_pidpath` contém `claude`; senão 0 |
| `~` em exec form (não confirmado) | Irrelevante: grava caminho absoluto expandido |
| `CLAUDE_CONFIG_DIR` (F44) | `settingsURL` é o único lugar com o caminho; F44 troca ali |

### Critérios de aceite
- [ ] `swift build` sem avisos; `swift test` ≥ 48 testes, todos verdes (PR 1).
- [ ] `install` em settings com hook do usuário no mesmo grupo preserva o hook do usuário (teste + passo manual 4).
- [ ] `install` duas vezes = mesmo arquivo; `strip(install(x)) == strip(x)` (teste).
- [ ] Handlers gravados têm `args`, nenhum tem `onFailure`, `SessionEnd` sem `timeout` (teste).
- [ ] Settings inválido: nada gravado, saída com mensagem e exit 1.
- [ ] Backup `0600` antes de toda escrita em arquivo existente.
- [ ] `claudebar-hook` sem argumento ou com estado inválido sai com 1.
- [ ] `install.sh` não chama `jq`; `grep -n jq scripts/` vazio.
- [ ] README sem "new sessions" e sem `jq`.

### O que NÃO fazer
- Não remover o grupo inteiro; não usar `contains`.
- Não pôr `onFailure`, `async`, `timeout` no `SessionEnd`, nem matcher em `Stop`/`UserPromptSubmit`.
- Não acrescentar o campo `matcher` agora: entra no F05 (`Entry(event:matcher:args:)` + `group["matcher"] = …` em `install`, e a comparação em `state`).
- Não manter backup ao lado do `settings.json` nem limitar número de backups (ponytail: quando alguém reclamar).
- Não criar `claudebar-hook status` (é o F26).

---

## F03 — Executável em caminho estável + detecção (PRs 1 e 2)

### Objetivo
Os hooks apontam para `~/.claude/claudebar/bin/claudebar-hook`, que sobrevive a mover/renomear/apagar o `.app`. Na abertura o app detecta binário ausente/desatualizado, hooks faltando/legados, settings inválido/somente leitura/hooks desligados, e **oferece** reparo (F16). Nunca repara em silêncio.

### Decisão técnica e por quê
- **Cópia por temporário + `rename(2)`** (`installBinary`). A Apple: modificar no lugar dessincroniza o cache de assinatura do kernel.
  - Descartado `cp`/`copyItem` por cima: o caso que a Apple descreve.
  - Descartado symlink → bundle (iTerm2): pendura se o app sair do lugar, que é o bug que o F03 mata.
- **Só os bytes, sem xattrs** (`createFile(contents:)`, não `copyItem`). Verificado aqui: cópia com `com.apple.quarantine` trava no exec. O binário já foi aceito pelo usuário ao abrir o `.app` que o contém; não se remove quarentena de nada que o usuário não abriu. Com F28 (Developer ID + notarização) a questão some. **Ponto para o revisor**: a pesquisa dizia "não remover o xattr por conta própria"; a spec não remove xattr de arquivo existente, só não o copia para a cópia que o próprio app cria — e sem isso o F03 quebra para todo usuário de DMG.
- **"Desatualizado" = `FileManager.contentsEqual(atPath:andPath:)`** (Foundation, 170 KB). Sem hash nem versão embutida.
- **Estados como enum plano no Core**, função `state(bundledBinary:settings:binary:)` que só lê. Nomes em inglês como o resto do código; equivalência com a pesquisa: `naoInstalado`=`notInstalled`, `binarioAusente`=`binaryMissing`, `binarioDesatualizado`=`binaryOutdated`, `hooksFaltando`=`hooksOutdated` (cobre também entradas sobrando de outra versão, ex.: depois do F05), `hooksLegado`=`legacyHooks`, `settingsInvalido`=`invalidSettings`, `settingsSomenteLeitura`=`readOnlySettings`, `hooksDesligados`=`hooksDisabled`.
- `readOnlySettings` só aparece quando é **preciso** gravar (não instalado, legado, faltando). Binário desatualizado não precisa tocar no settings.
- `disableAllHooks` só no settings do usuário; o de projeto e `allowManagedHooksOnly` não são visíveis daqui (o F17 manda conferir `/hooks`).
- Origem do binário: no CLI `proc_pidpath(getpid())`; no app `Bundle.main.url(forAuxiliaryExecutable: "claudebar-hook")`. Elimina a dúvida do `Bundle.main` dentro do CLI.

### Código
Já incluído no `HookInstaller.swift` acima: `IntegrationState`, `installBinary(from:to:)`, `state(bundledBinary:settings:binary:)`, `isWritable`. Uso no CLI: `manage(.install)` em `main.swift`. Uso no app: `HookSetup` (F16).

### Testes
`copiaComPermissao0700ESubstituiInteiro` (PR 1): `0700`, inode novo na troca, quarentena da origem não vai para a cópia. `estados` e `somenteLeitura` (PR 2): todos os estados a partir de settings/binários numa pasta temporária.

### Scripts/README
README: seção "Moving or updating the app" — o hook é uma cópia; depois de atualizar o app, o menu oferece atualizar a cópia. `uninstall` apaga `bin/`.

### Verificação manual
1. Com o PR 1 instalado: `mv ~/Applications/ClaudeBar.app /tmp/` e mandar um prompt numa sessão: o arquivo de estado ainda é gravado. Voltar o app.
2. `xattr -l ~/.claude/claudebar/bin/claudebar-hook`: sem `com.apple.quarantine`.
3. Recompilar com uma mudança trivial no hook e trocar o `.app`: o PR 3 deve oferecer "executável de outra versão".
4. `chmod 444 ~/.claude/settings.json` com hooks legados → estado `readOnlySettings`; `chmod 600` de volta.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Quarentena trava o hook (confirmado aqui) | Copiar bytes sem xattrs + teste; F17 detecta o resto com timeout |
| Binário removido por limpeza do usuário | `binaryMissing` → oferta |
| Oferta a cada abertura | F16 lembra o último estado oferecido em `UserDefaults` e limpa ao voltar a `ok` |
| `contentsEqual` em cada render do menu | `state` só é recalculado no launch, depois de ações e no "Atualizar" |

### Critérios de aceite
- [ ] Hooks registrados nunca apontam para dentro do bundle.
- [ ] A cópia tem `0700`, mesmo conteúdo do bundle, sem quarentena; trocada por `rename`.
- [ ] `state` devolve os 9 estados nos testes; não grava nada.
- [ ] Nenhum caminho do app grava settings ou binário sem clique (grep: `installBinary`/`apply` só em `HookSetup.review`/`copySnippet` e no CLI).

### O que NÃO fazer
- Não atualizar o binário sozinho a cada versão (decisão pendente: "oferece" do backlog; se o usuário preferir automático só para o binário, vai para `PENDENCIAS`).
- Não `xattr -d` em arquivo nenhum; não `copyItem`.
- Não embutir versão no binário só para comparar.

---

## F16 — Tela de transparência (PR 3)

### Objetivo
Antes de gravar, o usuário vê o arquivo, o diff exato do bloco `hooks`, onde fica o backup, e decide: Instalar / Remover / Pular. No 1º uso a mesma tela aparece sozinha uma vez; "Pular" não grava nada.

### Decisão técnica e por quê
- **`NSAlert` com `accessoryView`** (`NSTextView.scrollableTextView()`, monoespaçado, só leitura, selecionável, rótulo de acessibilidade) + `activate(ignoringOtherApps:)` + `runModal()`, o padrão que já funciona em `SessionStore.confirmTermination`.
  - Descartada janela SwiftUI (`Window`/`openWindow`): em app `.accessory` abre atrás (relatos de fórum, não confirmado) e exige trocar activation policy. Só se a tela crescer.
  - Descartado `showsSuppressionButton`: não serve para consentimento.
- **Um alerta só** (não "Ver o que será alterado…" + outro): menos cliques, mesmo consentimento.
- **Oferta uma vez por estado** (`UserDefaults`, chave `hookSetupOfferedState`), limpa ao voltar a `.ok` — senão a próxima atualização do app (binário desatualizado) nunca seria oferecida.
- **Oferta fora do `init`**: `HookSetup` nasce dentro do `SessionStore`, que nasce no `init` do `App`, antes do `finishLaunching`. O `Task { @MainActor in … }` roda quando a run loop principal começa, depois do launch. (Inferência a confirmar na verificação manual 1; se o alerta aparecer antes do ícone ou não aparecer, trocar por observar `NSApplication.didFinishLaunchingNotification`.)
- **`changedSinceReview` → mostra a prévia nova** (nunca grava às cegas).
- **Somente leitura**: botão "Copiar JSON dos hooks" (copia o binário e põe `snippet()` no pasteboard). Não tenta contornar.
- `HookSetup` é `@MainActor @Observable`, dono do `state`, exposto como `store.hookSetup` (mesmo padrão do `notifier`).

### Código

**Criar `Sources/ClaudeBar/HookSetup.swift`** (no PR 3, sem `selfTest`/`check`, que são do F17):

```swift
import AppKit
import ClaudeBarCore
import Observation

/// A integração com o Claude Code vista pelo app: detecta o estado, mostra o
/// diff exato e só grava com o seu clique. Nunca repara em silêncio.
@MainActor
@Observable
final class HookSetup {
    private(set) var state: IntegrationState = .notInstalled
    private let defaults = UserDefaults.standard

    /// Último estado já oferecido no launch: oferecer de novo só se mudar.
    private static let offeredKey = "hookSetupOfferedState"

    /// O hook que veio neste `.app`. No `swift run`, o executável ao lado.
    private let bundledBinary = Bundle.main.url(forAuxiliaryExecutable: "claudebar-hook")

    init() {
        refresh()
        // Fora do init: o `SessionStore` nasce antes do app terminar de
        // abrir, e um alerta modal ali apareceria cedo demais.
        Task { @MainActor in self.offerIfNeeded() }
    }

    var menuTitle: String {
        switch state {
        case .ok: "Integração com o Claude Code: ok"
        case .notInstalled: "Integração: hooks não instalados"
        default: "⚠︎ Integração precisa de atenção"
        }
    }

    var summary: String {
        switch state {
        case .ok: "Hooks registrados e executável em dia"
        case .notInstalled: "Sem hooks, o app só vê as sessões de 5 em 5 s"
        case .binaryMissing: "O executável do hook sumiu de ~/.claude/claudebar/bin"
        case .binaryOutdated: "O executável do hook é de outra versão do app"
        case .hooksOutdated: "Faltam hooks do ClaudeBar no settings.json"
        case .legacyHooks: "Hooks no formato antigo (caminho dentro do .app)"
        case .invalidSettings: "O settings.json não é um JSON válido — nada será alterado"
        case .readOnlySettings: "O settings.json é somente leitura: cole o JSON na ferramenta que o gera"
        case .hooksDisabled: "disableAllHooks está ligado no seu settings.json"
        }
    }

    var canRemove: Bool {
        ![.notInstalled, .invalidSettings, .readOnlySettings].contains(state)
    }

    func refresh() {
        state = HookInstaller.state(bundledBinary: bundledBinary)
        // Voltou ao normal: a próxima quebra (ex.: atualização do app) pode ser oferecida.
        if state == .ok {
            defaults.removeObject(forKey: Self.offeredKey)
        }
    }

    /// Oferece instalar ou reparar uma vez por estado novo. "Pular" não grava nada.
    private func offerIfNeeded() {
        let offerable: [IntegrationState] = [.notInstalled, .binaryMissing, .binaryOutdated, .hooksOutdated, .legacyHooks]
        let key = "\(state)"
        guard offerable.contains(state), defaults.string(forKey: Self.offeredKey) != key else { return }
        defaults.set(key, forKey: Self.offeredKey)
        review(.install, cancelTitle: "Pular")
    }

    /// Mostra exatamente o que muda e grava só se você clicar na ação.
    func review(_ action: HookAction, cancelTitle: String = "Cancelar") {
        let plan: HookPlan
        do {
            plan = try HookInstaller.plan(action)
        } catch {
            return report(title: "Não foi possível ler o settings.json", message: error.localizedDescription)
        }

        let stable = HookInstaller.stableBinary
        if action == .install, bundledBinary == nil, !FileManager.default.isExecutableFile(atPath: stable.path) {
            return report(title: "Executável do hook não encontrado", message: "Abra o ClaudeBar a partir do .app.")
        }
        let copiesBinary = action == .install && bundledBinary.map {
            !FileManager.default.contentsEqual(atPath: $0.path, andPath: stable.path)
        } == true

        guard plan.hasChanges || copiesBinary else {
            return report(title: "Nada a mudar", message: plan.settingsURL.path)
        }

        let alert = NSAlert()
        alert.messageText = action == .install
            ? "Registrar os hooks do ClaudeBar no Claude Code?"
            : "Remover os hooks do ClaudeBar?"
        var info: [String] = []
        if plan.hasChanges {
            info.append("Arquivo: \(plan.settingsURL.path)")
            info.append("Backup antes de gravar, em \(HookInstaller.backupsURL.path)")
            if plan.reformats {
                info.append("O arquivo será reformatado (ordem das chaves); fora de \"hooks\" o conteúdo não muda.")
            }
            alert.accessoryView = codeView(plan.diff)
        }
        if copiesBinary {
            info.append("Copia o executável do hook para \(stable.path).")
        }
        info.append("Só as entradas do ClaudeBar mudam; hooks seus ficam como estão. O Claude Code aplica sem reiniciar.")
        alert.informativeText = info.joined(separator: "\n\n")
        alert.addButton(withTitle: action == .install ? "Instalar" : "Remover")
        alert.addButton(withTitle: cancelTitle)

        // O app é accessory: sem ativar, o alerta nasce atrás das outras janelas.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            // Executável antes do settings: hook registrado nunca aponta para o nada.
            if action == .install, let bundledBinary {
                try HookInstaller.installBinary(from: bundledBinary)
            }
            if plan.hasChanges {
                try HookInstaller.apply(plan)
            }
            if action == .uninstall {
                try? FileManager.default.removeItem(at: stable)
            }
        } catch HookInstallError.changedSinceReview {
            // Mudou enquanto você lia: mostra a prévia nova, nunca grava às cegas.
            return review(action, cancelTitle: cancelTitle)
        } catch {
            report(title: "Não foi possível gravar", message: error.localizedDescription)
        }
        refresh()
    }

    /// Settings somente leitura: copia o executável e entrega o JSON para colar.
    func copySnippet() {
        if let bundledBinary {
            try? HookInstaller.installBinary(from: bundledBinary)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HookInstaller.snippet(), forType: .string)
        refresh()
    }

    /// Texto monoespaçado, só leitura e selecionável, dentro do alerta.
    private func codeView(_ text: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 560, height: 260)
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.string = text
            textView.setAccessibilityLabel("Alterações no settings.json")
        }
        return scroll
    }

    private func report(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

**`Sources/ClaudeBar/SessionStore.swift`**:

```swift
    let notifier = Notifier()
    /// Integração com o Claude Code (hooks + executável estável).
    let hookSetup = HookSetup()
```

**`Sources/ClaudeBar/MenuContent.swift`**: antes de "Atualizar", `integrationMenu`; no "Atualizar", `store.hookSetup.refresh()`:

```swift
        Divider()

        integrationMenu

        Button("Atualizar") {
            store.refreshAgents()
            store.hookSetup.refresh()
        }
```

```swift
    /// Status da integração (F17) e as ações do F16. Nada grava sem o alerta.
    @ViewBuilder private var integrationMenu: some View {
        let setup = store.hookSetup
        Menu(setup.menuTitle) {
            Text(setup.summary)

            Divider()

            switch setup.state {
            case .readOnlySettings:
                Button("Copiar JSON dos hooks") { setup.copySnippet() }
            case .invalidSettings, .hooksDisabled:
                EmptyView()
            default:
                Button(setup.state == .ok ? "Reinstalar hooks…" : "Instalar hooks…") {
                    setup.review(.install)
                }
            }

            if setup.canRemove {
                Button("Remover hooks…") { setup.review(.uninstall) }
            }
            // PR 4 acrescenta aqui: Divider() + "Testar integração".
        }
    }
```

### Testes
A UI (`NSAlert`) não tem teste automatizado; toda a lógica que ela mostra/grava está no Core e já é testada (diff, plano, escrita, estados). **Não instanciar `HookSetup` nem `SessionStore` em teste** (o `init` abre alerta modal).

### README
Seção "Integração com o Claude Code" no menu: o que cada item faz, que nada é gravado sem o alerta, e que "Pular" não pergunta de novo enquanto o estado não mudar.

### Verificação manual
1. Sair do ClaudeBar instalado. Com `defaults delete com.joaomarcos.claudebar hookSetupOfferedState` e hooks removidos (`claudebar-hook uninstall`), abrir o `.app` buildado: aparece **na frente** o alerta com o diff, caminho do arquivo e do backup, botões Instalar/Pular.
2. "Pular": `shasum ~/.claude/settings.json` igual ao de antes; reabrir o app: não pergunta de novo; o menu mostra "Integração: hooks não instalados".
3. Menu → "Instalar hooks…" → Instalar: settings atualizado, backup criado, título vira "…: ok".
4. VoiceOver (⌘F5) no alerta: lê o rótulo "Alterações no settings.json" e o conteúdo.
5. Com o alerta aberto, rodar `/model` numa sessão do Claude (grava o settings) e clicar Instalar: aparece a prévia nova, não grava a antiga.
6. Settings `chmod 444`: menu oferece "Copiar JSON dos hooks"; colar num editor dá um JSON válido com os 4 eventos.
7. Hooks legados do `install.sh` antigo (estado da máquina de hoje): abrir o app oferece a migração com o diff `-`/`+` mostrado no topo desta spec.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Alerta atrás das janelas | `activate(ignoringOtherApps:)` (padrão já provado no app) |
| Alerta cedo demais no launch (inferência) | Verificação 1; plano B: `didFinishLaunchingNotification` |
| Diff grande | Só o bloco `hooks`, com scroll (560×260) |
| Usuário clica sem ler | Texto diz que só entradas do ClaudeBar mudam + backup + `uninstall` desfaz |

### Critérios de aceite
- [ ] Nenhuma escrita sem clique em "Instalar"/"Remover"/"Copiar JSON".
- [ ] "Pular" não grava e não reaparece até o estado mudar.
- [ ] O alerta mostra arquivo real (symlink resolvido), diff, pasta do backup e o aviso de reformatação quando houver.
- [ ] Estado `.ok` volta a permitir oferta futura.

### O que NÃO fazer
- Nada de janela SwiftUI/Settings scene, tour de boas-vindas ou trocar activation policy.
- Não reparar no launch; não alertar a cada abertura.
- Não mostrar o settings inteiro (pode ter token em `env`).

---

## F17 — "Tudo ok" + testar integração (PR 4)

### Objetivo
Um clique responde "por que o ícone não muda?": hooks registrados, executável presente e igual ao do app, o hook realmente roda e grava, último evento recebido, e dica de pasta não confiada / `disableAllHooks`. Termina com o popup de exemplo (o "testar alerta" que já existe).

### Decisão técnica e por quê
- **Teste ponta a ponta de verdade**: roda o executável estável via `Process` (sem shell, `Shell.output`), payload no stdin como o Claude Code entrega, `--pid 0`, sessão `claudebar-selftest`; confere o arquivo; `end` apaga. Pega quarentena, assinatura quebrada, permissão.
- **`Shell.output` ganha `input` e `timeout`**: sem prazo, um hook travado (quarentena, confirmado aqui) congelaria a main. `kill(pid, SIGTERM)` agendado num `DispatchWorkItem` que só captura o `pid` (`Sendable`, sem aviso no Swift 6), cancelado no `defer`. `F_SETNOSIGPIPE` no stdin: filho que morre cedo não derruba o app com `SIGPIPE`.
  - Descartado rodar em background: a ação é disparada por clique e termina em `runModal`; 2 × 3 s no pior caso é aceitável.
- **Último evento** = maior `updatedAt` de `StatusDirectory.readAll()` (sem o selftest). Sem evento e com sessões abertas → dica de **workspace trust** (confirmado na doc) e `disableAllHooks`/`/hooks`.
- Relatório em `NSAlert` com ✓/✗ (texto, não só cor).

### Código

**`Sources/ClaudeBar/Shell.swift`** (completo):

```swift
import Foundation

/// Execução de processo sem shell: argumentos vão separados, então não há
/// interpolação e não há injeção.
enum Shell {
    /// `input` vai para o stdin, como o Claude Code entrega o payload ao hook.
    /// `timeout` encerra o filho que travar (ex.: cópia em quarentena parada
    /// na avaliação do Gatekeeper), em vez de travar quem chamou.
    static func output(
        of url: URL,
        arguments: [String],
        input: Data? = nil,
        timeout: TimeInterval? = nil
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        let stdin = Pipe()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if input != nil {
            process.standardInput = stdin
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let deadline = DispatchWorkItem { _ = kill(pid, SIGTERM) }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        }
        defer { deadline.cancel() }

        if let input {
            let handle = stdin.fileHandleForWriting
            // Filho que morreu cedo (ex.: barrado pelo Gatekeeper) não pode
            // derrubar o app com SIGPIPE: vira só um erro de escrita, ignorado.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? handle.write(contentsOf: input)
            try? handle.close()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**`Sources/ClaudeBar/HookSetup.swift`**: acrescentar:

```swift
    /// Prova ponta a ponta: roda o hook instalado como o Claude Code rodaria
    /// (sem shell, payload no stdin) e confere o arquivo que ele grava.
    func selfTest(openSessions: Int) {
        refresh()
        let manager = FileManager.default
        let hook = HookInstaller.stableBinary
        let id = "claudebar-selftest"
        let payload = Data(#"{"session_id":"\#(id)","cwd":"/"}"#.utf8)

        // `--pid 0`: sem pid, o arquivo de teste não depende de processo vivo.
        let ran = Shell.output(of: hook, arguments: ["waiting", "--pid", "0"], input: payload, timeout: 3) != nil
        let wrote = manager.fileExists(atPath: StatusDirectory.fileURL(sessionId: id).path)
        _ = Shell.output(of: hook, arguments: ["end"], input: payload, timeout: 3)

        var lines = [
            check(state != .notInstalled && state != .legacyHooks && state != .hooksOutdated, "Hooks registrados no settings.json"),
            check(manager.isExecutableFile(atPath: hook.path), "Executável em \(hook.path)"),
            check(state != .binaryOutdated, "Executável igual ao deste app"),
            check(ran && wrote, "O hook rodou e gravou o estado"),
        ]
        if state == .hooksDisabled {
            lines.append("⚠︎ disableAllHooks está ligado: o Claude Code não roda nenhum hook.")
        }

        let lastEvent = StatusDirectory.readAll().filter { $0.sessionId != id }.map(\.updatedAt).max()
        if let lastEvent {
            lines.append("Último evento recebido: \(lastEvent.formatted(.relative(presentation: .named)))")
        } else if openSessions > 0 {
            lines.append("""
            ⚠︎ Há sessões abertas e nenhum evento chegou. A pasta já foi aceita no \
            diálogo de confiança do Claude Code? Antes disso ele retém os hooks. \
            Confira também `disableAllHooks` e o `/hooks` dentro do Claude Code.
            """)
        }

        report(title: "Teste da integração", message: lines.joined(separator: "\n"))
    }

    private func check(_ passed: Bool, _ text: String) -> String {
        "\(passed ? "✓" : "✗") \(text)"
    }
```

**`Sources/ClaudeBar/MenuContent.swift`**: no fim do `integrationMenu`:

```swift
            Divider()

            Button("Testar integração") {
                setup.selfTest(openSessions: store.openSessionCount)
                store.notifier.showSample()
            }
```

### Testes
`Tests/ClaudeBarTests/SessionTerminatorTests.swift` (onde já se testa processo real), nova suite:

```swift
@Suite("Shell com prazo")
struct ShellTimeoutTests {
    /// Filho travado não pode travar o app: o teste da integração roda na main.
    @Test func filhoTravadoEhEncerrado() {
        let inicio = Date()
        #expect(Shell.output(of: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(inicio) < 5)
    }

    @Test func stdinChegaAoFilho() {
        let saida = Shell.output(of: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("oi".utf8), timeout: 5)
        #expect(saida == "oi")
    }
}
```

`selfTest` em si não tem teste automatizado (escreveria em `~/.claude/claudebar` real, porque `NSHomeDirectory()` ignora `$HOME`).

### README
Menu → "Testar integração": o que é checado; o que não dá para ver daqui (`disableAllHooks` em settings de projeto, `allowManagedHooksOnly`): conferir `/hooks` no Claude Code; pasta precisa estar confiada.

### Verificação manual
1. Com tudo instalado: "Testar integração" → 4 ✓, "Último evento recebido: há X", depois o popup de exemplo. `ls ~/.claude/claudebar/claudebar-selftest.json` não existe.
2. `rm ~/.claude/claudebar/bin/claudebar-hook` → ✗ no executável e no "rodou e gravou"; o app não trava.
3. `xattr -w com.apple.quarantine "0081;00000000;Safari;" ~/.claude/claudebar/bin/claudebar-hook` → o teste volta em ~3 s com ✗ (o app não congela). Reparar pelo menu (reinstalar copia os bytes sem a quarentena).
4. Abrir o Claude Code numa pasta nova sem aceitar o diálogo de confiança, sem nenhuma outra sessão com hook: aparece a dica de pasta não confiada.
5. `"disableAllHooks": true` no settings → linha de aviso; tirar.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Hook travado congela o app | `timeout: 3` + teste |
| Linha `claudebar-selftest` piscando no menu | Vive milissegundos; `end` logo em seguida; `--pid 0` |
| Falso "nenhum evento" (sessões acabaram de abrir) | Texto é pergunta/dica, não erro |
| `SIGPIPE` se o filho morre antes do stdin | `F_SETNOSIGPIPE` |

### Critérios de aceite
- [ ] "Testar integração" nunca bloqueia o app por mais de ~6 s.
- [ ] Mostra ✓/✗ para: hooks registrados, executável presente, executável igual ao do app, hook rodou e gravou.
- [ ] Sem evento + sessões abertas → dica de workspace trust e `disableAllHooks`.
- [ ] Nenhum arquivo `claudebar-selftest.json` sobra.
- [ ] `swift test` com os 2 testes novos do `Shell`.

### O que NÃO fazer
- Não ler `~/.claude/debug/*.txt` nem transcript (guard rail: não ler conversas).
- Não chamar `claude` nem rede para testar.
- Não tentar ler settings de projeto/managed.

---

## Não confirmado — como a implementação se protege

| Item (seção 10 da pesquisa) | Situação nesta spec |
|---|---|
| 1. Pai direto em exec form é o `claude` | Protegido: `getppid()` só se `proc_pidpath` contém `claude`, senão 0. Confirmar na verificação manual 6 do F02 |
| 2. `~` em exec form | Irrelevante: caminho absoluto gravado |
| 3. Claude Code < 2.1.139 com `args` | Protegido: `exit(1)` não bloqueia; README declara mínimo. Não testado |
| 4. `Bundle.main` no CLI | Contornado: CLI usa `proc_pidpath(getpid())` |
| 5. Quarentena de DMG | **Confirmado aqui que trava**; mitigado copiando só bytes + timeout no F17. Revalidar com o DMG do F23 |
| 6. Aviso Swift 6 com `[String: Any]` | **Confirmado: nenhum aviso** |
| 7. Código de claude-status-bar, Clabar, nudgy, Meanwhile | Não usado como base; nada depende dele |
| 8. Janela SwiftUI atrás em `.accessory` | Evitado: `NSAlert` |
| Novo: `Task` no `init` roda depois do launch | Inferência; verificação manual 1 do F16, com plano B |

> **Nota do usuário:** `activate(ignoringOtherApps:)` vai ser descontinuada numa versão futura do macOS. Não usar em código novo (ver TODO.md, "Deprecated APIs"). Pesquisar a substituta depois.
