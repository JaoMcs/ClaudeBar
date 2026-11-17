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

    /// Os três avisos de espera ficam na tela; "terminou" e "falhou" somem (F12).
    @Test func avisosDeEsperaFicam() {
        for alert in [Alert.waiting, .permission, .question] {
            #expect(alert.staysUntilAnswered)
        }
        for alert in [Alert.finished, .failed] {
            #expect(!alert.staysUntilAnswered)
        }
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

@Suite("Canto do popup")
struct PopupCornerTests {
    /// `visibleFrame` de uma tela 1440x900, já sem a barra de menu.
    private let tela = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let tamanho = NSSize(width: 320, height: 80)

    private func origem(mouse: NSPoint, tela: NSRect? = nil) -> NSPoint {
        StatusHUD.origin(for: tamanho, in: tela ?? self.tela, avoiding: mouse, margin: 16)
    }

    @Test func cursorLongeFicaNoSuperiorDireito() {
        #expect(origem(mouse: NSPoint(x: 700, y: 400)) == NSPoint(x: 1104, y: 779))
    }

    @Test func cursorNoSuperiorDireitoVaiParaBaixo() {
        #expect(origem(mouse: NSPoint(x: 1300, y: 820)) == NSPoint(x: 1104, y: 16))
    }

    /// Encostado na borda do popup também conta: a margem faz parte da área.
    @Test func cursorNaMargemTambemEvita() {
        #expect(origem(mouse: NSPoint(x: 1100, y: 870)) == NSPoint(x: 1104, y: 16))
    }

    /// Tela tão baixa que os dois cantos da direita pegam o cursor.
    @Test func semSaidaNaDireitaVaiParaEsquerda() {
        let baixa = NSRect(x: 0, y: 0, width: 1440, height: 150)
        #expect(origem(mouse: NSPoint(x: 1300, y: 75), tela: baixa) == NSPoint(x: 16, y: 54))
    }

    /// Segundo monitor à esquerda: coordenadas negativas, mesma regra.
    @Test func telaComOrigemNegativa() {
        let esquerda = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        #expect(origem(mouse: NSPoint(x: -100, y: 1000), tela: esquerda) == NSPoint(x: -336, y: 16))
    }
}
