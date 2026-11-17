import Foundation
import Testing

@testable import ClaudeBarCore

/// Árvore falsa: `filho → pai`. O que não está aqui não tem pai.
private func tree(_ edges: [Int32: Int32]) -> (Int32) -> Int32? {
    { edges[$0] }
}

@Suite("Subida até o app da sessão")
struct SessionNavigatorTreeTests {
    /// Terminal.app: claude → zsh → login (root) → Terminal.
    @Test func terminalSobeAteOApp() {
        let parent = tree([500: 400, 400: 300, 300: 200, 200: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { $0 == 200 }) == 200)
    }

    /// VS Code/Cursor: o helper do Electron não é `.regular` e fica para trás.
    @Test func helperNaoEOApp() {
        let parent = tree([500: 450, 450: 200, 200: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { $0 == 200 }) == 200)
    }

    /// tmux: claude → servidor tmux → launchd. Sem app: cai no caminho do tmux.
    @Test func tmuxTerminaSemApp() {
        let parent = tree([500: 300, 300: 1])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { _ in false }) == nil)
    }

    @Test func cicloNaoTravaASubida() {
        let parent = tree([500: 400, 400: 500])
        #expect(SessionNavigator.ancestor(of: 500, parent: parent, isApp: { _ in false }) == nil)
    }

    /// Processo de teste tem pai, e PID inexistente não tem.
    @Test func parentPidDeVerdade() {
        #expect(SessionNavigator.parentPID(getpid()) == getppid())
        #expect(SessionNavigator.parentPID(99_999_999) == nil)
    }
}

@Suite("Saídas do tmux")
struct TmuxParsingTests {
    private let panes = "/dev/ttys001\t%0\t$0\n/dev/ttys004\t%7\t$2\n"

    @Test func achaOPanePeloTTY() {
        let found = SessionNavigator.pane(forTTY: "/dev/ttys004", in: panes)
        #expect(found?.pane == "%7")
        #expect(found?.session == "$2")
    }

    /// `ttys00` não pode casar com `ttys001`: comparação exata, não prefixo.
    @Test func ttyParecidoNaoCasa() {
        #expect(SessionNavigator.pane(forTTY: "/dev/ttys00", in: panes) == nil)
    }

    @Test func escolheOClienteUsadoPorUltimo() {
        let clients = "1700000000\t/dev/ttys002\t111\n1700000500\t/dev/ttys009\t222\nlixo\n"
        let client = SessionNavigator.mostRecentClient(in: clients)
        #expect(client?.tty == "/dev/ttys009")
        #expect(client?.pid == 222)
    }

    @Test func semClienteAnexado() {
        #expect(SessionNavigator.mostRecentClient(in: "") == nil)
    }
}
