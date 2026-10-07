import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

/// Recorte real de `claude agents --json`: duas sessões interativas (uma ociosa,
/// uma ocupada — que omite `status`) e um agente background, que traz `id` e
/// `state` em vez de `status` e **não traz `pid`**.
private let agentsJSON = """
[
  {
    "pid": 94713,
    "cwd": "/Users/dev/my-app",
    "kind": "interactive",
    "startedAt": 1788885326219,
    "sessionId": "aaaaaaaa-0000-0000-0000-000000000000",
    "name": "my-app-4d",
    "status": "idle"
  },
  {
    "pid": 23864,
    "cwd": "/Users/dev/code",
    "kind": "interactive",
    "startedAt": 1788895284614,
    "sessionId": "bbbbbbbb-0000-0000-0000-000000000000",
    "name": "code-00"
  },
  {
    "id": "cccccccc",
    "cwd": "/Users/dev/pessoal",
    "kind": "background",
    "startedAt": 1786646454723,
    "sessionId": "cccccccc-0000-0000-0000-000000000000",
    "name": "Planejar caminhos para cidadania europeia",
    "state": "running"
  }
]
"""

private func decodeAgents() throws -> [AgentSession] {
    try JSONDecoder().decode([AgentSession].self, from: Data(agentsJSON.utf8))
}

@Suite("Decode do agents --json")
struct AgentSessionTests {
    /// Entrada background não tem `pid`. Se o campo fosse obrigatório, o decode
    /// do array inteiro falharia e o app perderia todas as sessões de uma vez.
    @Test func decodificaArrayMistoSemPerderEntradas() throws {
        let agents = try decodeAgents()
        #expect(agents.count == 3)
        #expect(agents[2].pid == nil)
    }

    @Test func somenteBackgroundEhSubagente() throws {
        let agents = try decodeAgents()
        #expect(agents.map(\.isSubagent) == [false, false, true])
    }

    @Test func statusAusenteSignificaProcessando() throws {
        let agents = try decodeAgents()
        #expect(agents[0].sessionState == .idle)
        #expect(agents[1].sessionState == .working)
    }

    @Test func backgroundUsaOCampoState() throws {
        let agents = try decodeAgents()
        #expect(agents[2].sessionState == .working)
        #expect(agents[2].identifier == "cccccccc-0000-0000-0000-000000000000")
    }
}

@Suite("Cruzamento das duas origens")
struct SessionMergeTests {
    private func hook(
        _ sessionId: String,
        _ state: SessionState,
        cwd: String = "/Users/dev/code"
    ) -> SessionStatus {
        SessionStatus(sessionId: sessionId, state: state, cwd: cwd, pid: 1, updatedAt: Date())
    }

    @Test func subagenteNaoContaNoNumeroDaBarra() throws {
        let rows = SessionMerge.rows(agents: try decodeAgents(), statuses: [])
        #expect(rows.count == 3)
        #expect(SessionMerge.openSessionCount(rows: rows) == 2)
    }

    @Test func subagenteNaoMudaOIcone() throws {
        let agents = try decodeAgents()
        // O background está `running` e a única interativa restante está ociosa
        // e já vista: o ícone tem de ficar parado, não em "processando".
        let rows = SessionMerge.rows(agents: agents, statuses: [])
        let vistas = Set(rows.filter { !$0.isSubagent }.map(\.sessionId))
        #expect(SessionMerge.barState(rows: rows, acknowledged: vistas) == .working)

        let semInterativaOcupada = rows.filter { $0.isSubagent || $0.state == .idle }
        #expect(SessionMerge.barState(rows: semInterativaOcupada, acknowledged: vistas) == .idle)
    }

    @Test func subagenteApareceNaListaEVemPorUltimo() throws {
        let rows = SessionMerge.rows(agents: try decodeAgents(), statuses: [])
        #expect(rows.last?.isSubagent == true)
        #expect(rows.dropLast().allSatisfy { !$0.isSubagent })
    }

    @Test func hookVenceOCliNoEstadoDaSessao() throws {
        let ocupadaSegundoCli = "aaaaaaaa-0000-0000-0000-000000000000"
        let rows = SessionMerge.rows(
            agents: try decodeAgents(),
            statuses: [hook(ocupadaSegundoCli, .waiting)]
        )
        let row = try #require(rows.first { $0.sessionId == ocupadaSegundoCli })
        #expect(row.state == .waiting)
        // O nome continua vindo do CLI, que é quem sabe nomear a sessão.
        #expect(row.name == "my-app-4d")
    }

    @Test func sessaoConhecidaSoPelosHooksNaoEhPerdida() throws {
        let rows = SessionMerge.rows(agents: [], statuses: [hook("orfa", .idle)])
        #expect(rows.count == 1)
        #expect(rows[0].isSubagent == false)
        #expect(SessionMerge.openSessionCount(rows: rows) == 1)
    }

    @Test func pendenciaNaoVistaAcendeOIcone() throws {
        let rows = SessionMerge.rows(agents: [], statuses: [hook("s1", .idle)])
        #expect(SessionMerge.barState(rows: rows, acknowledged: []) == .done)
        #expect(SessionMerge.barState(rows: rows, acknowledged: ["s1"]) == .idle)
    }
}
