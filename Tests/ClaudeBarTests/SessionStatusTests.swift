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
