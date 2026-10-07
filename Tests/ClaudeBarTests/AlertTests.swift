import AppKit
import Foundation
import Testing

@testable import ClaudeBar

@Suite("Avisos sonoros")
struct AlertTests {
    @Test func osDoisAvisosTocamSonsDiferentes() {
        #expect(Alert.finished.soundName != Alert.waiting.soundName)
    }

    /// "Esperando você" toca a 75% do volume principal, como pedido.
    @Test func esperandoTocaMaisBaixo() {
        #expect(Alert.waiting.volume == 0.75)
        #expect(Alert.finished.volume == 1)
        #expect(Alert.waiting.volume < Alert.finished.volume)
    }

    /// Nome errado dá `NSSound` nulo e o aviso sai calado — vale checar que os
    /// dois sons existem mesmo neste macOS.
    @Test func osDoisSonsExistemNoSistema() throws {
        for alert in [Alert.finished, Alert.waiting] {
            #expect(NSSound(named: alert.soundName) != nil, "som ausente: \(alert.soundName)")
            let arquivo = "/System/Library/Sounds/\(alert.soundName).aiff"
            #expect(FileManager.default.fileExists(atPath: arquivo))
        }
    }

    @Test func cadaAvisoTemSeuTitulo() {
        #expect(Alert.finished.title == "Claude terminou")
        #expect(Alert.waiting.title.contains("esperando"))
    }
}
