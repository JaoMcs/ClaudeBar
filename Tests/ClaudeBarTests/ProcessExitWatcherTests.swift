import Foundation
import Testing

@testable import ClaudeBar

@Suite("Aviso de saída de processo")
struct ProcessExitWatcherTests {
    private func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    @Test func avisaQuandoOProcessoMorre() throws {
        let process = try sleeper()
        defer { if process.isRunning { process.terminate() } }
        let avisou = DispatchSemaphore(value: 0)
        let watcher = ProcessExitWatcher(queue: .global()) { avisou.signal() }
        watcher.watch([process.processIdentifier])

        kill(process.processIdentifier, SIGKILL)
        #expect(avisou.wait(timeout: .now() + 2) == .success)
    }

    /// PID que saiu da lista não avisa mais: a fonte foi cancelada.
    @Test func pidRemovidoNaoAvisa() throws {
        let process = try sleeper()
        defer { if process.isRunning { process.terminate() } }
        let avisou = DispatchSemaphore(value: 0)
        let watcher = ProcessExitWatcher(queue: .global()) { avisou.signal() }
        watcher.watch([process.processIdentifier])
        watcher.watch([])

        kill(process.processIdentifier, SIGKILL)
        #expect(avisou.wait(timeout: .now() + 0.5) == .timedOut)
    }

    /// A doc não diz o que acontece com PID que morreu antes de a fonte nascer.
    /// Medido: o libdispatch avisa na hora — a sessão não fica presa até o polling.
    @Test func pidJaMortoAvisaAoObservar() throws {
        let process = try sleeper()
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        let avisou = DispatchSemaphore(value: 0)
        // Fila serial própria: a global some quando outros testes prendem as
        // poucas threads do pool no runner de CI.
        let watcher = ProcessExitWatcher(queue: DispatchQueue(label: "teste")) { avisou.signal() }
        watcher.watch([process.processIdentifier])
        #expect(avisou.wait(timeout: .now() + 2) == .success)
    }
}
