import AppKit
import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

@Suite("Avisos sonoros")
struct AlertTests {
    @Test func osDoisAvisosTocamSonsDiferentes() {
        #expect(Alert.finished.soundName != Alert.waiting.soundName)
    }

    @Test func osTresAvisosTocamSonsDiferentes() {
        let sons = [Alert.finished, .waiting, .failed].map(\.soundName)
        #expect(Set(sons).count == 3)
    }

    /// "Esperando você" toca a 75% do volume principal, como pedido.
    @Test func esperandoTocaMaisBaixo() {
        #expect(Alert.waiting.volume == 0.75)
        #expect(Alert.finished.volume == 1)
        #expect(Alert.waiting.volume < Alert.finished.volume)
    }

    /// Nome errado dá `NSSound` nulo e o aviso sai calado — vale checar que os
    /// sons existem mesmo neste macOS.
    @Test func osDoisSonsExistemNoSistema() throws {
        for alert in [Alert.finished, .waiting, .permission, .question, .failed] {
            #expect(NSSound(named: alert.soundName) != nil, "som ausente: \(alert.soundName)")
            let arquivo = "/System/Library/Sounds/\(alert.soundName).aiff"
            #expect(FileManager.default.fileExists(atPath: arquivo))
        }
    }

    /// Dá para saber de ouvido se é pergunta ou permissão.
    @Test func perguntaTemSomProprio() {
        let sons = [Alert.finished, .permission, .question, .failed].map(\.soundName)
        #expect(Set(sons).count == 4)
        #expect(Alert.permission.soundName == Alert.waiting.soundName)
        #expect(Alert.question.volume == 0.75)
        #expect(Alert.permission.volume == 0.75)
    }

    @Test func tipoDaEsperaEscolheOAviso() {
        #expect(Alert(waiting: .permission) == .permission)
        #expect(Alert(waiting: .question) == .question)
        #expect(Alert(waiting: nil) == .waiting)
        #expect(Alert.permission.title == "Claude pede permissão")
        #expect(Alert.question.title == "Claude fez uma pergunta")
    }

    @Test func cadaAvisoTemSeuTitulo() {
        #expect(Alert.finished.title == "Claude terminou")
        #expect(Alert.waiting.title.contains("esperando"))
        #expect(Alert.failed.title.contains("falhou"))
    }

    /// Toggle "Notificações" desligado não pode tocar som (F01).
    @MainActor @Test func desligadoNaoTocaSom() throws {
        let suite = "claudebar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var tocados: [Alert] = []
        let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
        notifier.setEnabled(false)

        notifier.post(.finished, body: "projeto")
        notifier.post(.waiting, body: "Claude needs your permission to use Bash")

        #expect(tocados.isEmpty)
    }
}
