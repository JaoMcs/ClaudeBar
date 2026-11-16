import ClaudeBarCore
import Foundation

// CLI chamado pelos hooks do Claude Code. Lê o payload JSON no stdin e grava
// o estado da sessão em ~/.claude/claudebar/<session_id>.json.
//
// Uso: claudebar-hook <working|idle|waiting|end> [--kind <permission|question>] [--pid <pid do claude>]
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

    // O tipo vem do argumento que o instalador escreveu (um matcher por tipo),
    // não do payload: `notification_type` já faltou em versão antiga.
    let kind = state == .waiting
        ? value(after: "--kind", in: arguments).flatMap(WaitKind.init(rawValue:))
        : nil

    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: payload?.cwd ?? FileManager.default.currentDirectoryPath,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: payload?.message.map { String($0.prefix(200)) },
        kind: kind
    )

    do {
        try StatusDirectory.write(status)
    } catch {
        // Um hook nunca deve derrubar a sessão do Claude: só registra e sai bem.
        FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
    }
}

run()
