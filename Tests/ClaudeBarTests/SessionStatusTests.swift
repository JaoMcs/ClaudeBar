import ClaudeBarCore
import Foundation
import Testing

@Suite("Arquivo de estado")
struct SessionStatusTests {
    private func decode(_ json: String) throws -> SessionStatus {
        try StatusDirectory.decoder.decode(SessionStatus.self, from: Data(json.utf8))
    }

    /// Arquivo gravado antes do F05 não tem `kind`. Se o decode falhasse,
    /// `readAll` apagaria o estado de todas as sessões na atualização.
    @Test func arquivoAntigoSemKindDecodifica() throws {
        let status = try decode(#"{"sessionId":"s","state":"waiting","cwd":"/tmp","pid":1,"updatedAt":0}"#)
        #expect(status.kind == nil)
        #expect(status.waitKind == nil)
    }

    /// Valor que este app não conhece não derruba o decode: vira genérico.
    @Test func kindDesconhecidoDecodificaComoGenerico() throws {
        let status = try decode(#"{"sessionId":"s","state":"waiting","cwd":"/tmp","pid":1,"updatedAt":0,"kind":"plan"}"#)
        #expect(status.kind == "plan")
        #expect(status.waitKind == nil)
    }

    @Test func kindSobreviveAoEncodeEDecode() throws {
        let original = SessionStatus(sessionId: "s", state: .waiting, cwd: "/tmp", pid: 1, kind: .question)
        let data = try StatusDirectory.encoder.encode(original)
        #expect(try StatusDirectory.decoder.decode(SessionStatus.self, from: data).waitKind == .question)
    }

    /// Sem `kind`, a chave nem é gravada: o arquivo continua igual ao de antes.
    @Test func semKindNaoGravaAChave() throws {
        let data = try StatusDirectory.encoder.encode(
            SessionStatus(sessionId: "s", state: .working, cwd: "/tmp", pid: 1)
        )
        #expect(!String(decoding: data, as: UTF8.self).contains("kind"))
    }
}

@Suite("Agente da sessão")
struct AgentFieldTests {
    @Test func arquivoAntigoSemAgentVaiParaClaude() throws {
        let json = #"{"sessionId":"s","state":"idle","cwd":"/tmp","pid":1,"updatedAt":0}"#
        let status = try StatusDirectory.decoder.decode(SessionStatus.self, from: Data(json.utf8))
        #expect(status.agent == nil)
        #expect(status.agentName == "claude")
    }

    @Test func geminiFazRoundTrip() throws {
        let original = SessionStatus(sessionId: "s", state: .idle, cwd: "/tmp", pid: 1, agent: "gemini")
        let data = try StatusDirectory.encoder.encode(original)
        let back = try StatusDirectory.decoder.decode(SessionStatus.self, from: data)
        #expect(back.agentName == "gemini")
    }

    @Test func semAgentOuClaudeNaoGravaAChave() throws {
        for agent in [nil, "claude"] {
            let data = try StatusDirectory.encoder.encode(
                SessionStatus(sessionId: "s", state: .working, cwd: "/tmp", pid: 1, agent: agent)
            )
            #expect(!String(decoding: data, as: UTF8.self).contains("agent"))
        }
    }

    @Test func valorDesconhecidoDecodifica() throws {
        let data = try StatusDirectory.encoder.encode(
            SessionStatus(sessionId: "s", state: .idle, cwd: "/tmp", pid: 1, agent: "futuro-x")
        )
        #expect(try StatusDirectory.decoder.decode(SessionStatus.self, from: data).agentName == "futuro-x")
    }
}

@Suite("Tipo da espera")
struct WaitKindTests {
    private func status(_ state: SessionState, _ kind: WaitKind? = nil) -> SessionStatus {
        SessionStatus(sessionId: "s", state: state, cwd: "/tmp", pid: 1, kind: kind)
    }

    /// O `permission_prompt` que o `AskUserQuestion` dispara depois não pode
    /// trocar ❓ por ✋.
    @Test func permissaoNaoApagaPerguntaAberta() {
        #expect(status(.waiting, .question).absorbs(.waiting, kind: .permission))
    }

    @Test func soAPermissaoSobreAPerguntaEhAbsorvida() {
        let pergunta = status(.waiting, .question)
        // Resposta, fim do turno, falha e outra pergunta gravam normalmente.
        #expect(!pergunta.absorbs(.working, kind: nil))
        #expect(!pergunta.absorbs(.idle, kind: nil))
        #expect(!pergunta.absorbs(.error, kind: nil))
        #expect(!pergunta.absorbs(.waiting, kind: .question))
        #expect(!pergunta.absorbs(.waiting, kind: nil))
        // Sem pergunta aberta, a permissão entra.
        #expect(!status(.waiting, .permission).absorbs(.waiting, kind: .permission))
        #expect(!status(.waiting).absorbs(.waiting, kind: .permission))
        #expect(!status(.working).absorbs(.waiting, kind: .permission))
    }
}
