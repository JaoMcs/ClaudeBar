import Foundation
import Testing

@testable import ClaudeBar

@Suite("Abrir pasta do projeto")
@MainActor
struct OpenFolderTests {
    /// Abrir um `.app` executaria o app: só pasta comum pode passar.
    @Test func soAbrePastaDeVerdade() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = base.appendingPathComponent("Foo.app", isDirectory: true)
        let file = base.appendingPathComponent("arquivo.txt")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? manager.removeItem(at: base) }

        #expect(SessionStore.isOpenableFolder(base.path))
        #expect(!SessionStore.isOpenableFolder(app.path))
        #expect(!SessionStore.isOpenableFolder(file.path))
        #expect(!SessionStore.isOpenableFolder(base.appendingPathComponent("sumiu").path))
        #expect(!SessionStore.isOpenableFolder("relativo/pasta"))
    }
}
