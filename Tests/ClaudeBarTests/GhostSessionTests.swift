import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

/// Pasta temporária com um arquivo por status, gravado como o hook grava.
private func directory(with statuses: [SessionStatus], fileName: ((SessionStatus) -> String)? = nil) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("claudebar-teste-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for status in statuses {
        let name = fileName?(status) ?? "\(status.sessionId).json"
        try StatusDirectory.encoder.encode(status).write(to: dir.appendingPathComponent(name))
    }
    return dir
}

private func files(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

/// Sessão gravada há 1 min pelo PID 4321.
private let gravada = SessionStatus(
    sessionId: "s1", state: .idle, cwd: "/Users/dev/app", pid: 4321,
    updatedAt: Date(timeIntervalSinceNow: -60)
)

private func probe(
    exists: Bool = true,
    path: String? = "/Users/dev/.local/share/claude/versions/2.1.325",
    start: Date? = Date(timeIntervalSinceNow: -3600)
) -> ProcessProbe {
    ProcessProbe(
        isGroupLeader: { _ in true },
        executablePath: { _ in path },
        exists: { _ in exists },
        startTime: { _ in start }
    )
}

@Suite("Sessões fantasmas: o que sai do disco")
struct GhostFileTests {
    @Test func processoMortoApagaOArquivo() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(exists: false).isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }

    @Test func pidRecicladoPorOutroProgramaApaga() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(path: "/usr/sbin/cron").isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }

    /// Outro `claude` herdou o PID: ele nasceu depois de o arquivo ser gravado.
    @Test func pidRecicladoPorOutroClaudeApaga() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        let depois = probe(start: Date())
        #expect(StatusDirectory.readAll(in: dir, isAlive: depois.isAlive).isEmpty)
    }

    @Test func claudeQueNasceuAntesDaGravacaoFica() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe().isAlive).map(\.sessionId) == ["s1"])
        #expect(files(in: dir) == ["s1.json"])
    }

    /// Sem caminho nem horário (outro usuário, corrida com a saída): sem prova
    /// de morte, o arquivo fica.
    @Test func semInformacaoMantem() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(path: nil, start: nil).isAlive).count == 1)
    }

    @Test func sessaoDoAppDesktopFica() throws {
        let dir = try directory(with: [gravada])
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktop = probe(path: "/Users/dev/Library/Application Support/Claude/claude-code/2.1.325/claude.app/Contents/MacOS/claude")
        #expect(StatusDirectory.readAll(in: dir, isAlive: desktop.isAlive).count == 1)
    }

    /// `pid 0` não tem processo para conferir: não sai do disco. Quem tira da
    /// lista é o cruzamento com o CLI.
    @Test func pidZeroNaoEhApagado() throws {
        let semPid = SessionStatus(sessionId: "s0", state: .working, cwd: "/x", pid: 0)
        let dir = try directory(with: [semPid])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(exists: false).isAlive).count == 1)
    }

    @Test(arguments: [
        ("unknown", "unknown.json"),
        ("", "unknown.json"),
        ("s1", "outro.json"),
    ])
    func arquivoQueNaoEhDeSessaoNenhumaApaga(sessionId: String, arquivo: String) throws {
        let status = SessionStatus(sessionId: sessionId, state: .idle, cwd: "/x", pid: 4321)
        let dir = try directory(with: [status]) { _ in arquivo }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe().isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }
}

@Suite("Sessões fantasmas: o que sai da lista")
struct GhostMergeTests {
    private let semPid = SessionStatus(sessionId: "s0", state: .working, cwd: "/x", pid: 0)

    @Test func pidZeroSomeQuandoOCliRespondeuSemEla() {
        #expect(SessionMerge.rows(agents: [], statuses: [semPid]).isEmpty)
    }

    @Test func pidZeroApareceSeOCliNaoRespondeu() {
        #expect(SessionMerge.rows(agents: nil, statuses: [semPid]).count == 1)
    }

    /// `/clear` troca o `sessionId` no mesmo processo. Se o `SessionEnd` falhar,
    /// o arquivo antigo fica com PID vivo e caminho `claude` — só o CLI desempata.
    @Test func sobraDeClearSomeQuandoOCliListaOPidComOutroId() throws {
        let json = """
        [{"pid":4321,"cwd":"/x","kind":"interactive","sessionId":"novo","status":"idle"}]
        """
        let agents = try JSONDecoder().decode([AgentSession].self, from: Data(json.utf8))
        let rows = SessionMerge.rows(agents: agents, statuses: [gravada])
        #expect(rows.map(\.sessionId) == ["novo"])
    }
}

@Suite("Sessões fantasmas: processo de verdade")
struct GhostLiveTests {
    /// Ponta a ponta com `ProcessProbe.live`, menos o caminho: `/bin/sleep` não
    /// é `claude` e seria apagado vivo, o que não testaria a morte.
    @Test func processoQueMorreSaiDoDisco() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let antes = Date()
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let pid = process.processIdentifier
        var real = ProcessProbe.live
        real.executablePath = { _ in "/bin/claude" }

        let inicio = try #require(ProcessProbe.live.startTime(pid))
        #expect(abs(inicio.timeIntervalSince(antes)) < 2)

        let status = SessionStatus(sessionId: "vivo", state: .working, cwd: "/tmp", pid: pid)
        let dir = try directory(with: [status])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusDirectory.readAll(in: dir, isAlive: real.isAlive).count == 1)

        kill(pid, SIGKILL)
        process.waitUntilExit()
        #expect(ProcessProbe.live.exists(pid) == false)
        #expect(StatusDirectory.readAll(in: dir, isAlive: real.isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }
}
