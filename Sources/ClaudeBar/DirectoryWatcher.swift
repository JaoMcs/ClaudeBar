import Foundation

/// Observa um diretório e avisa quando qualquer arquivo dentro dele muda.
///
/// Usa `DispatchSource` em cima de um file descriptor: reage em milissegundos,
/// sem ficar varrendo o disco em loop.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, queue: DispatchQueue = .main, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
