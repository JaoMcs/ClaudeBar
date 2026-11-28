import ClaudeBarCore
import Foundation

// CLI chamado pelos hooks do Claude Code. Lê o payload JSON no stdin e grava
// o estado da sessão em ~/.claude/claudebar/<session_id>.json.
//
// Uso: claudebar-hook <working|idle|waiting|error|end> [--kind <permission|question>] [--if-waiting] [--pid <pid do claude>] [--agent <nome>]
//      claudebar-hook install|uninstall [--statusline|--gemini] [--dry-run]
//      claudebar-hook status [--json]   uma sessão por linha: estado<TAB>projeto<TAB>pasta
//      claudebar-hook next              traz para a frente a sessão que espera há mais tempo
//      claudebar-hook statusline        comando do `statusLine` do Claude Code (limites de uso)

/// Campos do payload que os hooks do Claude Code entregam no stdin.
private struct HookPayload: Decodable {
    let sessionId: String?
    let cwd: String?
    let message: String?
    /// Só no `StopFailure`: código do erro da API (`rate_limit`, `overloaded`…).
    /// `String`, não enum: código novo não pode derrubar o decode.
    let error: String?
    /// Só no `StopFailure`, opcional: detalhe técnico (`429 Too Many Requests`).
    let errorDetails: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case message
        case error
        case errorDetails = "error_details"
    }
}

/// O que mostrar quando a resposta falhou. `last_assistant_message` fica de
/// fora de propósito: no `Stop` ele é a resposta do Claude, e o app não lê
/// conversa.
private func errorSummary(_ payload: HookPayload?) -> String? {
    let parts = [payload?.error, payload?.errorDetails].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " — ")
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("claudebar-hook: \(message)\n".utf8))
    // 1, nunca 2: no Claude Code, exit 2 bloqueia o prompt (UserPromptSubmit)
    // e impede o Claude de parar (Stop). 1 é erro que não bloqueia nada.
    exit(1)
}

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func parsePID(_ arguments: [String]) -> Int32 {
    if let pid = value(after: "--pid", in: arguments).flatMap({ Int32($0) }) { return pid }
    // Outro agente (Gemini): sem pid. A sessão vive pelos hooks (`end`) e pela
    // regra de sessões fantasmas.
    if let agent = value(after: "--agent", in: arguments), agent != "claude" { return 0 }
    // Exec form (sem shell) não tem `$PPID`: o pai direto deve ser o Claude
    // Code. Só aceita se for mesmo um `claude`; senão 0 = "sem pid", como antes.
    let parent = getppid()
    let isClaude = processExecutablePath(parent)?.lowercased().contains("claude") == true
    return isClaude ? parent : 0
}

/// `install`/`uninstall`: mostra o diff e, sem `--dry-run`, grava com backup.
private func manage(_ action: HookAction, gemini: Bool = false, dryRun: Bool) {
    do {
        if gemini, action == .install, !GeminiHooks.cliDetected() { fail("Gemini CLI não encontrado") }
        let plan = try gemini ? GeminiHooks.plan(action) : HookInstaller.plan(action)
        print(plan.hasChanges ? plan.diff : "Nada a mudar em \(plan.settingsURL.path).")
        if plan.hasChanges, plan.reformats {
            print("\nO arquivo será reformatado (ordem das chaves); fora de \"hooks\" e \"statusLine\" o conteúdo não muda.")
        }
        guard !dryRun else { return }

        if action == .install || action == .installStatusLine {
            // O próprio executável que está rodando vira a cópia estável.
            guard let me = processExecutablePath(getpid()) else { fail("executável não encontrado") }
            try HookInstaller.installBinary(from: URL(fileURLWithPath: me))
        }
        if plan.hasChanges, let backup = try HookInstaller.apply(plan, backups: gemini ? GeminiHooks.backupsURL : HookInstaller.backupsURL) {
            print("Backup: \(backup.path)")
        }
        // Se o statusline ou os hooks ainda o chamam, o executável fica.
        if action == .uninstall || action == .uninstallStatusLine, !plan.binaryInUse {
            try? FileManager.default.removeItem(at: HookInstaller.stableBinary)
        }
    } catch {
        fail(error.localizedDescription)
    }
}

/// Statusline: guarda os limites de uso e devolve o statusline que o usuário já
/// tinha. Nunca falha por culpa própria — o pior caso é o rodapé sem texto.
private func statusLine(_ stdinData: Data) -> Never {
    // Grava antes de rodar o original: se o Claude Code cancelar este processo
    // no meio, o dado já está salvo. Só regrava se mudou (ver `needsWrite`).
    let limits = RateLimits.fromStatusLine(stdinData)
    if let limits, limits.needsWrite(over: StatusDirectory.readLimits()) {
        do {
            try StatusDirectory.writeLimits(limits)
        } catch {
            FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
        }
    }

    let isReentry = ProcessInfo.processInfo.environment[StatusLineChain.reentryVariable] != nil
    if !isReentry,
       let command = StatusLineChain.originalCommand(),
       // 5 s: a doc não fixa limite e o Claude Code cancela o script na
       // próxima atualização; mais que isso já é rodapé travado.
       let result = StatusLineChain.run(command: command, input: stdinData, timeout: 5) {
        FileHandle.standardOutput.write(result.output)
        exit(result.status)
    }

    // Sem statusline anterior (ou ele falhou em rodar): uma linha curta em vez
    // de vazio, porque com statusline configurado o Claude Code esconde as
    // dicas do rodapé.
    let shown = limits ?? StatusDirectory.readLimits() ?? RateLimits()
    print(shown.summary())
    exit(0)
}

/// Sem `ProcessProbe` (é do app): só apaga arquivo de processo que não existe mais.
private func readSessions() -> [SessionStatus] {
    StatusDirectory.readAll { $0.pid <= 0 || kill($0.pid, 0) == 0 || errno != ESRCH }
}

/// `status`: para a barra do tmux, scripts e leitor de tela. `--json` sai no
/// formato dos arquivos de estado.
private func printStatus(json: Bool) {
    let sessions = readSessions()
    if json {
        let data = (try? StatusDirectory.encoder.encode(sessions)) ?? Data("[]".utf8)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        return
    }
    for session in sessions {
        print("\(session.state.rawValue)\t\(session.projectName)\t\(session.cwd)")
    }
}

/// `next`: leva você à sessão que espera há mais tempo. Sai 1 se não houver.
@MainActor
private func goToNextWaiting() async -> Int32 {
    let waiting = SessionNavigator.nextWaiting(in: readSessions())
    guard let waiting else { fail("nenhuma sessão esperando você") }
    // `app(for:)` é síncrono e pede para ficar fora da main actor; aqui tudo
    // bem: é um CLI de vida curta, sem interface para travar.
    guard let app = SessionNavigator.app(for: waiting.pid), await SessionNavigator.bringToFront(app) else {
        fail("não achei o app de \(waiting.projectName) (\(waiting.cwd))")
    }
    print(waiting.projectName)
    return 0
}

private func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        fail("informe o estado (working|idle|waiting|error|end) ou install|uninstall|status|next|statusline")
    }

    // Antes de ler o stdin: num terminal, ler o stdin travaria esperando EOF.
    switch command {
    // `--statusline` é opt-in próprio: mexe só no `statusLine`, nunca nos hooks.
    // `--gemini` mexe só no `~/.gemini/settings.json`.
    case "install":
        let action: HookAction = arguments.contains("--statusline") ? .installStatusLine : .install
        return manage(action, gemini: arguments.contains("--gemini"), dryRun: arguments.contains("--dry-run"))
    case "uninstall":
        let action: HookAction = arguments.contains("--statusline") ? .uninstallStatusLine : .uninstall
        return manage(action, gemini: arguments.contains("--gemini"), dryRun: arguments.contains("--dry-run"))
    case "status": return printStatus(json: arguments.contains("--json"))
    default: break
    }

    let agent = value(after: "--agent", in: arguments)
    // Codex `notify` passa o JSON como último argumento (argv), não no stdin;
    // ler stdin sem EOF travaria quando chamado por ele.
    if agent == "codex" {
        // Sem JSON no argv: sai já (fail-open) em vez de cair no stdin.
        guard let argData = CodexConfig.payloadData(from: arguments) else {
            FileHandle.standardError.write(Data("claudebar-hook: --agent codex sem payload JSON no argumento\n".utf8))
            return
        }
        let codex = CodexConfig.parsePayload(argData)
        guard let sessionId = codex?.resolvedSessionId, !sessionId.isEmpty else { return }
        handleSessionEvent(command: command, sessionId: sessionId, cwd: codex?.cwd, message: nil, errorText: nil, arguments: arguments)
        return
    }

    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    if command == "statusline" {
        statusLine(stdinData)
    }
    let payload = try? StatusDirectory.decoder.decode(HookPayload.self, from: stdinData)
    // Sem `session_id` não há de quem gravar o estado. Sai bem, sem arquivo: um
    // `unknown.json` juntaria sessões diferentes num só fantasma.
    guard let sessionId = payload?.sessionId, !sessionId.isEmpty else { return }
    handleSessionEvent(
        command: command,
        sessionId: sessionId,
        cwd: payload?.cwd,
        message: payload?.message,
        errorText: errorSummary(payload),
        arguments: arguments
    )
}

private func handleSessionEvent(
    command: String,
    sessionId: String,
    cwd: String?,
    message: String?,
    errorText: String?,
    arguments: [String]
) {
    if command == "end" {
        StatusDirectory.remove(sessionId: sessionId)
        return
    }

    guard let state = SessionState(rawValue: command) else {
        fail("estado inválido \"\(command)\"")
    }

    // `PostToolUse` roda a cada ferramenta. Só interessa quando ela tira a sessão
    // de "esperando" (permissão aprovada); no resto do turno o arquivo já diz
    // `working`, e regravar só mexeria no `updatedAt` e acordaria o app à toa.
    // Arquivo ausente ou ilegível: não grava (o `Stop` acerta o estado depois).
    if arguments.contains("--if-waiting") {
        let current = (try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)))
            .flatMap { try? StatusDirectory.decoder.decode(SessionStatus.self, from: $0) }
        guard current?.state == .waiting else { return }
    }

    // O tipo vem do argumento que o instalador escreveu (um matcher por tipo),
    // não do payload: `notification_type` já faltou em versão antiga.
    let kind = state == .waiting
        ? value(after: "--kind", in: arguments).flatMap(WaitKind.init(rawValue:))
        : nil

    // Pergunta aberta vence a "permissão" que o AskUserQuestion dispara depois.
    // Sem arquivo ou arquivo ilegível: grava normalmente.
    if let data = try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)),
       let current = try? StatusDirectory.decoder.decode(SessionStatus.self, from: data),
       current.absorbs(state, kind: kind) {
        return
    }

    let text = state == .error ? errorText : message

    let cwd = cwd ?? FileManager.default.currentDirectoryPath
    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: cwd,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: text.map { String($0.prefix(200)) },
        kind: kind,
        // Lida aqui, e não no app: o hook roda no terminal, que já tem acesso à
        // pasta do projeto. Qualquer falha vira `nil`, nunca erro.
        branch: GitHead.branch(at: cwd),
        agent: value(after: "--agent", in: arguments)
    )

    do {
        try StatusDirectory.write(status)
    } catch {
        // Um hook nunca deve derrubar a sessão do Claude: só registra e sai bem.
        FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
    }
}

// `status` e `next` são digitados por você: o stdin é o terminal e nunca chega
// EOF. Por isso são tratados antes de `run()` ler o stdin inteiro. O `next`
// fica aqui porque precisa de `await` (o top-level é `@MainActor`).
if CommandLine.arguments.dropFirst().first == "next" {
    exit(await goToNextWaiting())
}
run()
