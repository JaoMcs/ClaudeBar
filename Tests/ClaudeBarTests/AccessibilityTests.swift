import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

@Suite("VoiceOver e legenda")
struct AccessibilityTests {
    private func linha(_ state: SessionState, kind: WaitKind?) -> SessionRow {
        SessionRow(
            sessionId: "s1",
            name: "my-app",
            cwd: "/tmp/my-app",
            state: state,
            updatedAt: nil,
            message: nil,
            isSubagent: true,
            kind: kind
        )
    }

    /// Sem rótulo o VoiceOver lê só o número. Tem de dizer de quem é, quantas
    /// sessões e o estado.
    @Test func rotuloDaBarraDizAppContagemEEstado() {
        let rotulo = BarState.waiting.accessibilityLabel(openSessions: 2)
        #expect(rotulo.contains("ClaudeBar"))
        #expect(rotulo.contains("2"))
        #expect(rotulo.contains(BarState.waiting.title))
    }

    /// A legenda e o rótulo dependem de cada estado ter um texto próprio.
    @Test func cadaEstadoTemTituloProprio() {
        let titulos = BarState.allCases.map(\.title)
        #expect(titulos.count == 7)
        #expect(titulos.allSatisfy { !$0.isEmpty })
        #expect(Set(titulos).count == BarState.allCases.count)
    }

    /// Emoji no título do item vira ruído falado pelo VoiceOver.
    @MainActor
    @Test func linhaDoMenuSemEmoji() {
        for state in SessionState.allCases {
            for kind in [nil, WaitKind.permission, .question] {
                let texto = MenuContent.label(for: linha(state, kind: kind))
                #expect(!texto.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "\(texto)")
                #expect(texto.contains("my-app"))
            }
        }
    }
}
