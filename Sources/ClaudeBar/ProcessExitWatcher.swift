import Foundation

/// Avisa quando algum dos processos observados termina — inclusive por
/// `kill -9`, crash ou terminal fechado, quando nenhum hook roda.
///
/// O aviso só pede um recálculo: quem decide se a sessão morreu é
/// `ProcessProbe.isAlive`, no `merge()`.
final class ProcessExitWatcher {
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private let queue: DispatchQueue
    private let onExit: @Sendable () -> Void

    init(queue: DispatchQueue = .main, onExit: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onExit = onExit
    }

    /// Passa a observar exatamente estes PIDs: cria fonte para quem entrou e
    /// cancela a de quem saiu. `pid <= 0` é ignorado.
    func watch(_ pids: Set<Int32>) {
        for (pid, source) in sources where !pids.contains(pid) {
            source.cancel()
            sources[pid] = nil
        }
        for pid in pids where pid > 0 && sources[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler(handler: onExit)
            source.resume()
            sources[pid] = source
        }
    }

    deinit {
        sources.values.forEach { $0.cancel() }
    }
}
