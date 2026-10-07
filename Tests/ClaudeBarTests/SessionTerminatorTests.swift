import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

private func row(
    pid: Int32? = nil,
    backgroundId: String? = nil,
    isSubagent: Bool = false
) -> SessionRow {
    SessionRow(
        sessionId: "s1",
        name: "projeto",
        cwd: "/Users/dev/projeto",
        state: .working,
        updatedAt: nil,
        message: nil,
        isSubagent: isSubagent,
        pid: pid,
        backgroundId: backgroundId
    )
}

/// Sessão de terminal: o processo lidera o próprio grupo (`pgid == pid`).
private let terminalProbe = ProcessProbe(
    isGroupLeader: { _ in true },
    executablePath: { _ in "/Users/dev/.local/bin/claude" }
)

/// Sessão do app desktop: o processo vive no grupo do `Claude.app`, junto das
/// sessões irmãs. Foi essa topologia que fez um encerramento derrubar várias.
private let desktopProbe = ProcessProbe(
    isGroupLeader: { _ in false },
    executablePath: { _ in
        "/Users/dev/Library/Application Support/Claude/claude-code/2.1.265/claude"
    }
)

@Suite("Sessão do app desktop não é encerrável")
struct DesktopSessionTests {
    /// A regressão: PID de sessão desktop não pode virar sinal, porque ela
    /// compartilha o grupo de processos com o app e com as sessões irmãs.
    @Test func desktopNuncaViraSinal() {
        #expect(SessionTerminator.target(for: row(pid: 35282), probe: desktopProbe) == .hostedByApp)
    }

    @Test func desktopNaoOferecebotaoEExplicaOMotivo() {
        #expect(SessionTerminator.actionTitle(for: row(pid: 35282), probe: desktopProbe) == nil)
        let motivo = SessionTerminator.unavailableReason(for: row(pid: 35282), probe: desktopProbe)
        #expect(motivo?.contains("app desktop") == true)
    }

    @Test func desktopFalhaSemSinalizarNada() {
        guard case .failed(let reason) = SessionTerminator.terminate(row(pid: 35282), probe: desktopProbe) else {
            Issue.record("não deveria ter encerrado")
            return
        }
        #expect(reason.contains("app do Claude"))
    }

    @Test func terminalContinuaEncerravel() {
        #expect(SessionTerminator.target(for: row(pid: 23667), probe: terminalProbe) == .signal(23667))
    }
}

@Suite("Escolha do alvo ao finalizar")
struct SessionTerminatorTests {
    @Test func sessaoDeTerminalUsaSigtermNoPid() {
        #expect(
            SessionTerminator.actionTitle(for: row(pid: 4321), probe: terminalProbe)
                == "Finalizar sessão (kill 4321)"
        )
    }

    /// Entrada de background quase nunca traz `pid` — sem esse caminho a opção
    /// de finalizar ficaria morta justamente para os subagentes.
    @Test func subagenteSemPidCaiNoClaudeStop() {
        let subagente = row(backgroundId: "cccccccc", isSubagent: true)
        #expect(SessionTerminator.target(for: subagente, probe: terminalProbe) == .backgroundStop("cccccccc"))
    }

    /// Subagente vai por `claude stop` mesmo tendo `pid`: é o caminho oficial e
    /// não corre o risco de sinalizar processo hospedado.
    @Test func subagenteComPidAindaUsaClaudeStop() {
        let ambos = row(pid: 99, backgroundId: "abc", isSubagent: true)
        #expect(SessionTerminator.target(for: ambos, probe: terminalProbe) == .backgroundStop("abc"))
    }

    /// `pid: 0` é o que o hook grava quando não recebeu `--pid`: não é processo
    /// nenhum, e sinalizar 0 atingiria o grupo de processos inteiro.
    @Test func pidZeroNaoViraSinal() {
        #expect(SessionTerminator.target(for: row(pid: 0), probe: terminalProbe) == .unavailable)
        #expect(SessionTerminator.actionTitle(for: row(pid: 0), probe: terminalProbe) == nil)
    }

    /// O sistema recicla PID: um estado velho apontando para processo alheio não
    /// pode virar sinal.
    @Test func pidReciclatoParaOutroProcessoNaoViraSinal() {
        let recicladoProbe = ProcessProbe(
            isGroupLeader: { _ in true },
            executablePath: { _ in "/usr/bin/ssh" }
        )
        #expect(SessionTerminator.target(for: row(pid: 4321), probe: recicladoProbe) == .unavailable)
    }

    @Test func processoQueSumiuNaoViraSinal() {
        let mortoProbe = ProcessProbe(isGroupLeader: { _ in true }, executablePath: { _ in nil })
        #expect(SessionTerminator.target(for: row(pid: 4321), probe: mortoProbe) == .unavailable)
    }

    @Test func semPidNemIdNaoOferecemOpcao() {
        #expect(SessionTerminator.target(for: row(), probe: terminalProbe) == .unavailable)
        #expect(SessionTerminator.actionTitle(for: row(), probe: terminalProbe) == nil)
    }
}

@Suite("Topologia real de processo")
struct ProcessProbeTests {
    /// Lado "terminal": `Process` no macOS já coloca o filho num grupo próprio,
    /// então ele é líder — exatamente como a sessão de terminal do Claude.
    @Test func liveReconheceLiderDeGrupo() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        let pid = process.processIdentifier
        #expect(getpgid(pid) == pid)
        #expect(ProcessProbe.live.isGroupLeader(pid) == true)
        #expect(ProcessProbe.live.executablePath(pid) == "/bin/sleep")
    }

    /// Lado "app desktop": um neto herda o grupo do `sh` que o criou, então não
    /// é líder. É a mesma topologia da sessão hospedada pelo Claude.app — e é
    /// por isso que ela precisa ser reconhecida e poupada.
    @Test func liveReconheceProcessoHospedadoEmGrupoAlheio() throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 30 & wait"]
        try shell.run()
        defer { shell.terminate() }

        // Espera o neto aparecer.
        var neto: Int32?
        for _ in 0..<50 where neto == nil {
            let saida = Shell.output(
                of: URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-P", "\(shell.processIdentifier)"]
            )
            neto = saida?.split(separator: "\n").first.flatMap { Int32($0) }
            if neto == nil { usleep(20_000) }
        }

        let pid = try #require(neto, "o neto do shell não apareceu")
        defer { kill(pid, SIGTERM) }

        #expect(getpgid(pid) == shell.processIdentifier)
        #expect(ProcessProbe.live.isGroupLeader(pid) == false)
    }

    @Test func liveReconheceOProprioProcessoDeTeste() {
        let meu = getpid()
        #expect(ProcessProbe.live.isGroupLeader(meu) == (getpgid(meu) == meu))
        #expect(ProcessProbe.live.executablePath(meu)?.isEmpty == false)
    }
}

@Suite("Encerramento de verdade")
struct TerminationEffectTests {
    /// Sobe um processo real, encerra pelo mesmo caminho que o menu usa e checa
    /// que ele morreu. O `probe` descreve a topologia de terminal, já que um
    /// filho de `Process` herda o grupo do processo de teste.
    @Test func sigtermDerrubaOProcesso() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["300"]
        try process.run()

        let alvo = SessionRow(
            sessionId: "teste-\(UUID().uuidString)",
            name: "sleep de teste",
            cwd: "/tmp",
            state: .working,
            updatedAt: nil,
            message: nil,
            isSubagent: false,
            pid: process.processIdentifier
        )
        let probe = ProcessProbe(isGroupLeader: { _ in true }, executablePath: { _ in "/bin/claude" })

        #expect(kill(process.processIdentifier, 0) == 0)

        guard case .terminated = SessionTerminator.terminate(alvo, probe: probe) else {
            Issue.record("o encerramento não foi bem-sucedido")
            return
        }

        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
    }

    /// Um único `SIGTERM` não pode alcançar processo irmão — o oposto do que
    /// acontece quando se sinaliza um grupo compartilhado.
    @Test func encerrarUmNaoDerrubaOIrmao() throws {
        func sleeper() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["300"]
            try process.run()
            return process
        }

        let alvo = try sleeper()
        let irmao = try sleeper()
        defer { irmao.terminate() }

        let probe = ProcessProbe(isGroupLeader: { _ in true }, executablePath: { _ in "/bin/claude" })
        let linha = SessionRow(
            sessionId: "teste-\(UUID().uuidString)",
            name: "alvo",
            cwd: "/tmp",
            state: .working,
            updatedAt: nil,
            message: nil,
            isSubagent: false,
            pid: alvo.processIdentifier
        )

        guard case .terminated = SessionTerminator.terminate(linha, probe: probe) else {
            Issue.record("o encerramento não foi bem-sucedido")
            return
        }

        alvo.waitUntilExit()
        #expect(irmao.isRunning)
        #expect(kill(irmao.processIdentifier, 0) == 0)
    }

    @Test func alvoInexistenteFalhaSemDerrubarNada() {
        let probe = ProcessProbe(isGroupLeader: { _ in true }, executablePath: { _ in "/bin/claude" })
        let fantasma = SessionRow(
            sessionId: "teste-fantasma",
            name: "fantasma",
            cwd: "/tmp",
            state: .working,
            updatedAt: nil,
            message: nil,
            isSubagent: false,
            pid: 999_998
        )

        guard case .failed(let reason) = SessionTerminator.terminate(fantasma, probe: probe) else {
            Issue.record("deveria ter falhado")
            return
        }
        #expect(reason.contains("999998"))
    }
}

@Suite("Origem do PID no cruzamento")
struct TerminationMergeTests {
    @Test func pidDoCliEntraNaLinha() throws {
        let json = """
        [{"pid":4321,"cwd":"/x","kind":"interactive","sessionId":"s1","status":"idle"}]
        """
        let agents = try JSONDecoder().decode([AgentSession].self, from: Data(json.utf8))
        let rows = SessionMerge.rows(agents: agents, statuses: [])
        #expect(rows[0].pid == 4321)
    }

    /// Sessão que o CLI não listou ainda usa o PID que o hook gravou.
    @Test func pidDoHookServeDeReserva() {
        let status = SessionStatus(sessionId: "s2", state: .working, cwd: "/y", pid: 777)
        let rows = SessionMerge.rows(agents: [], statuses: [status])
        #expect(SessionTerminator.target(for: rows[0], probe: terminalProbe) == .signal(777))
    }

    @Test func subagenteCarregaOIdCurtoDoBackground() throws {
        let json = """
        [{"id":"cccccccc","cwd":"/z","kind":"background","sessionId":"cccccccc-0000","state":"running"}]
        """
        let agents = try JSONDecoder().decode([AgentSession].self, from: Data(json.utf8))
        let rows = SessionMerge.rows(agents: agents, statuses: [])
        #expect(rows[0].backgroundId == "cccccccc")
        #expect(SessionTerminator.target(for: rows[0], probe: terminalProbe) == .backgroundStop("cccccccc"))
    }
}
