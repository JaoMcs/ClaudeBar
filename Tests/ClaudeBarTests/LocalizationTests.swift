import Foundation
import Testing

@testable import ClaudeBar

/// No `swift test` o `Bundle.main` é o runner, sem `.lproj`: as tabelas são
/// lidas direto de `Resources/`, que é o que o `build-app.sh` copia.
private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources")

private func table(_ language: String) throws -> [String: String] {
    let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: String])
}

/// `%@`, `%lld`, `%d`… na ordem em que aparecem.
private func specifiers(_ text: String) -> [String] {
    text.matches(of: /%(@|l{0,2}d)/).map { String($0.output.0) }
}

@Suite("Tradução")
struct LocalizationTests {
    /// Pega o erro comum de quem traduz à mão: marcador trocado, esquecido ou valor vazio.
    @Test func tabelaEmPortuguesTemOsMesmosMarcadoresDaChave() throws {
        let pt = try table("pt-BR")
        #expect(!pt.isEmpty)
        for (key, value) in pt {
            #expect(specifiers(key) == specifiers(value), "\(key)")
            #expect(!value.isEmpty, "\(key)")
        }
    }

    /// Em inglês a chave já é o texto; a tabela só precisa existir e ser válida.
    @Test func tabelaEmInglesEhValida() throws {
        _ = try table("en")
    }

    /// Os textos que o código monta sozinho têm tradução — sem ela, o menu
    /// misturaria inglês no meio do português.
    @MainActor
    @Test func textosDosEstadosEAvisosTemTraducao() throws {
        let pt = try table("pt-BR")
        let alerts: [Alert] = [.finished, .waiting, .permission, .question, .failed]
        for titulo in BarState.allCases.map(\.title) + alerts.map(\.title) {
            #expect(pt[titulo] != nil, "sem tradução: \(titulo)")
        }
    }
}
