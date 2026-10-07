import ClaudeBarCore
import Foundation

// CLI chamado pelos hooks do Claude Code. Lê o payload JSON no stdin e grava
// o estado da sessão em ~/.claude/claudebar/<session_id>.json.
//
// Uso: claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>]

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
    exit(2)
}

private func parsePID(_ arguments: [String]) -> Int32 {
    guard let index = arguments.firstIndex(of: "--pid"),
          arguments.indices.contains(index + 1),
          let pid = Int32(arguments[index + 1])
    else { return 0 }
    return pid
}

private func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        fail("informe o estado (working|idle|waiting|end)")
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
