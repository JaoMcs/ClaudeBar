import ClaudeBarCore
import Foundation

// CLI chamado pelos hooks do Claude Code. Lê o payload JSON no stdin e grava
// o estado da sessão em ~/.claude/claudebar/<session_id>.json.
//
// Uso: claudebar-hook <working|idle|waiting|error|end> [--kind <permission|question>] [--if-waiting] [--pid <pid do claude>]
//      claudebar-hook install|uninstall [--dry-run]
//      claudebar-hook status [--json]   uma sessão por linha: estado<TAB>projeto<TAB>pasta
//      claudebar-hook next              traz para a frente a sessão que espera há mais tempo

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
    let waiting = readSessions()
        .filter { $0.state == .waiting && $0.pid > 0 }
        .min { $0.updatedAt < $1.updatedAt }
    guard let waiting else { print("nenhuma sessão esperando você"); return 1 }
    guard let app = SessionNavigator.app(for: waiting.pid), await SessionNavigator.bringToFront(app) else {
        print("não achei o app de \(waiting.projectName) (\(waiting.cwd))")
        return 1
    }
    print(waiting.projectName)
    return 0
}

private func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        fail("informe o estado (working|idle|waiting|error|end) ou install|uninstall|status|next")
    }

    // Antes de ler o stdin: num terminal, ler o stdin travaria esperando EOF.
    switch command {
    case "install": return manage(.install, dryRun: arguments.contains("--dry-run"))
    case "uninstall": return manage(.uninstall, dryRun: arguments.contains("--dry-run"))
    case "status": return printStatus(json: arguments.contains("--json"))
    default: break
    }

    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    let payload = try? StatusDirectory.decoder.decode(HookPayload.self, from: stdinData)
    // Sem `session_id` não há de quem gravar o estado. Sai bem, sem arquivo: um
    // `unknown.json` juntaria sessões diferentes num só fantasma.
    guard let sessionId = payload?.sessionId, !sessionId.isEmpty else { return }

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

    let text = state == .error ? errorSummary(payload) : payload?.message

    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: payload?.cwd ?? FileManager.default.currentDirectoryPath,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: text.map { String($0.prefix(200)) },
        kind: kind
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
