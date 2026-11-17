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

    /// Suíte de `UserDefaults` descartável: nunca `.standard` em teste.
    private func scratchDefaults() throws -> (UserDefaults, String) {
        let suite = "claudebar.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// Toggle "Notificações" desligado não pode tocar som (F01).
    @MainActor @Test func desligadoNaoTocaSom() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var tocados: [Alert] = []
        let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
        notifier.setEnabled(false)

        notifier.post(.finished, body: "projeto")
        notifier.post(.waiting, body: "Claude needs your permission to use Bash")

        #expect(tocados.isEmpty)
    }

    /// "Avisar quando terminar" desligado nos Ajustes cala esse aviso, som
    /// incluído, com o toggle geral ligado (F15).
    @MainActor @Test func tipoDesligadoNosAjustesNaoAvisa() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var tocados: [Alert] = []
        let notifier = Notifier(defaults: defaults, playSound: { tocados.append($0) })
        notifier.setEnabled(true)
        defaults.set(true, forKey: Notifier.soundEnabledKey)
        defaults.set(false, forKey: Alert.finished.enabledKey)

        notifier.post(.finished, body: "projeto")

        #expect(tocados.isEmpty)
    }

    /// Som escolhido nos Ajustes vale no próximo aviso; som desligado = nenhum
    /// nome. Lido na hora, sem reiniciar o `Notifier` (F15).
    @MainActor @Test func somVemDosAjustes() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let notifier = Notifier(defaults: defaults, playSound: { _ in })
        defaults.set(true, forKey: Notifier.soundEnabledKey)
        #expect(notifier.soundName(for: .finished) == "Glass")

        defaults.set("Ping", forKey: Alert.finished.soundKey)
        #expect(notifier.soundName(for: .finished) == "Ping")
        #expect(notifier.soundName(for: .waiting) == "Submarine")
        #expect(notifier.soundName(for: .question) == "Purr")
        #expect(notifier.soundName(for: .failed) == "Basso")

        defaults.set(false, forKey: Notifier.soundEnabledKey)
        #expect(notifier.soundName(for: .finished) == nil)
    }

    /// A lista do Picker tem os quatro padrões, sem extensão (F15).
    @MainActor @Test func listaDeSonsTemOsPadroes() {
        for som in ["Glass", "Submarine", "Purr", "Basso"] {
            #expect(Notifier.systemSounds.contains(som), "som ausente: \(som)")
        }
        #expect(!Notifier.systemSounds.contains { $0.hasSuffix(".aiff") })
    }

    /// Minutos do lembrete abaixo de 1 viram 1: nada de lembrete no mesmo merge (F13).
    @MainActor @Test func minutosInvalidosViramUm() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let notifier = Notifier(defaults: defaults, playSound: { _ in })
        #expect(notifier.isReminderEnabled)
        #expect(notifier.reminderMinutes == 5)
        defaults.set(0, forKey: Notifier.reminderMinutesKey)
        #expect(notifier.reminderMinutes == 1)
    }

    /// Permissão e pergunta são espera: um toggle só para os três (F15).
    @MainActor @Test func permissaoEEsperaDividemOToggle() {
        #expect(Alert.permission.enabledKey == Alert.waiting.enabledKey)
        #expect(Alert.question.enabledKey == Alert.waiting.enabledKey)
        #expect(Alert.permission.soundKey == Alert.waiting.soundKey)
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
