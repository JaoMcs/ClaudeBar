@testable import ClaudeBar
@testable import ClaudeBarCore
import Foundation
import Testing

/// Recorte do exemplo oficial do stdin do statusline (code.claude.com/docs/en/statusline).
private let statusLineJSON = """
{
  "session_id": "abc",
  "transcript_path": "/Users/dev/.claude/projects/x.jsonl",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
"""

@Suite("Limites do statusline")
struct RateLimitsTests {
    @Test func decodificaOExemploOficial() throws {
        let now = Date(timeIntervalSince1970: 1_738_400_000)
        let limits = try #require(RateLimits.fromStatusLine(Data(statusLineJSON.utf8), now: now))
        #expect(limits.fiveHour == RateWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)))
        #expect(limits.sevenDay?.usedPercentage == 41.2)
        #expect(limits.updatedAt == now)
    }

    /// Chave de API ou sessão antes da 1ª resposta: não grava nada, para não
    /// apagar o dado bom de outra sessão.
    @Test(arguments: [#"{"session_id":"abc"}"#, #"{"rate_limits":{}}"#, #"{"rate_limits":null}"#, "lixo"])
    func semCampoNaoGrava(json: String) {
        #expect(RateLimits.fromStatusLine(Data(json.utf8)) == nil)
    }

    @Test func umaJanelaSo() throws {
        let json = #"{"rate_limits":{"seven_day":{"used_percentage":12,"resets_at":1738857600}}}"#
        let limits = try #require(RateLimits.fromStatusLine(Data(json.utf8)))
        #expect(limits.fiveHour == nil)
        #expect(limits.sevenDay?.displayPercent == 12)
    }

    @Test func percentualPresoEntre0e100() {
        let reset = Date()
        #expect(RateWindow(usedPercentage: 104.7, resetsAt: reset).displayPercent == 100)
        #expect(RateWindow(usedPercentage: -1, resetsAt: reset).displayPercent == 0)
        #expect(RateWindow(usedPercentage: 23.5, resetsAt: reset).displayPercent == 24)
    }

    @Test func resumoDoRodape() {
        let now = Date(timeIntervalSince1970: 1_000)
        let limits = RateLimits(
            fiveHour: RateWindow(usedPercentage: 23.4, resetsAt: Date(timeIntervalSince1970: 500)),
            sevenDay: RateWindow(usedPercentage: 41.2, resetsAt: Date(timeIntervalSince1970: 2_000))
        )
        // 5 h já renovou: "–", nunca 0% nem o número velho.
        #expect(limits.summary(now: now) == "5h – · sem 41%")
        #expect(RateLimits().summary(now: now) == "5h – · sem –")
    }

    /// O rodapé atualiza a cada poucos segundos; regravar sem mudança acordaria
    /// o app à toa.
    @Test func soRegravaQuandoMuda() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = RateWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 20_000))
        let novo = RateLimits(fiveHour: window, updatedAt: now)
        #expect(novo.needsWrite(over: nil, now: now))
        #expect(!novo.needsWrite(over: RateLimits(fiveHour: window, updatedAt: now - 10), now: now))
        #expect(novo.needsWrite(over: RateLimits(fiveHour: window, updatedAt: now - 61), now: now))
        let outro = RateWindow(usedPercentage: 24, resetsAt: window.resetsAt)
        #expect(novo.needsWrite(over: RateLimits(fiveHour: outro, updatedAt: now - 10), now: now))
    }

    /// `readAll` apagava todo `*.json` que não fosse sessão.
    @Test func readAllNaoApagaOsArquivosDoStatusline() {
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.limitsURL))
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.originalStatusLineURL))
        #expect(StatusDirectory.isSessionFile(StatusDirectory.fileURL(sessionId: "abc")))
    }
}

/// Em série: cada teste prende uma thread do pool esperando o filho, e o
/// runner de CI tem só 3 vCPU.
@Suite("Encadeamento do statusline", .serialized)
struct StatusLineChainTests {
    @Test func repassaStdinEDevolveStdout() throws {
        let input = Data(String(repeating: "x", count: 200_000).utf8) // maior que o buffer do pipe
        let result = try #require(StatusLineChain.run(command: "cat", input: input, timeout: 5))
        #expect(result.output == input)
        #expect(result.status == 0)
    }

    @Test func repassaCodigoDeSaida() throws {
        let result = try #require(StatusLineChain.run(command: "echo oi; exit 3", input: Data(), timeout: 5))
        #expect(String(decoding: result.output, as: UTF8.self) == "oi\n")
        #expect(result.status == 3)
    }

    /// Filho que nem lê o stdin não pode derrubar o hook com SIGPIPE.
    @Test func filhoQueIgnoraStdin() throws {
        let input = Data(count: 1_000_000)
        let result = try #require(StatusLineChain.run(command: "echo ok", input: input, timeout: 5))
        #expect(result.status == 0)
    }

    @Test func estouraOTimeout() {
        let start = Date()
        #expect(StatusLineChain.run(command: "sleep 10", input: Data(), timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func originalComONossoComandoNaoEncadeia() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("statusline-original.json")

        try Data(#"{"type":"command","command":"~/bin/minha-linha.sh","padding":2}"#.utf8).write(to: file)
        #expect(StatusLineChain.originalCommand(at: file) == "~/bin/minha-linha.sh")

        try Data(#"{"type":"command","command":"/x/claudebar-hook statusline"}"#.utf8).write(to: file)
        #expect(StatusLineChain.originalCommand(at: file) == nil)

        #expect(StatusLineChain.originalCommand(at: dir.appendingPathComponent("nao-existe.json")) == nil)
    }

    @MainActor @Test func menuSemDadoDizIndisponivel() {
        #expect(MenuContent.limitLines(nil, now: Date()) == ["Limites de uso: indisponível"])
        let lines = MenuContent.limitLines(RateLimits(updatedAt: Date()), now: Date())
        #expect(lines[0] == "Limite 5 h: indisponível")
        #expect(lines[1] == "Semanal: indisponível")
        #expect(!lines.contains { $0.contains("0%") })
    }

    @MainActor @Test func menuJanelaRenovada() {
        let now = Date()
        let limits = RateLimits(fiveHour: RateWindow(usedPercentage: 90, resetsAt: now.addingTimeInterval(-60)))
        #expect(MenuContent.limitLines(limits, now: now)[0] == "Limite 5 h: renovado, aguardando dado novo")
    }
}

@Suite("Instalação do statusline")
struct StatusLineInstallTests {
    private let hook = "'/Users/dev/.claude/claudebar/bin/claudebar-hook' statusline"

    @Test func semStatuslineAnterior() {
        let (settings, original) = StatusLineInstall.install(["model": "opus"], hookCommand: hook)
        #expect((settings["statusLine"] as? [String: Any])?["command"] as? String == hook)
        #expect(settings["model"] as? String == "opus")
        guard case .remove = original else { Issue.record("esperava .remove"); return }
    }

    @Test func guardaOOriginalEMantemPadding() {
        let old: [String: Any] = ["type": "command", "command": "~/linha.sh", "padding": 2]
        let (settings, original) = StatusLineInstall.install(["statusLine": old], hookCommand: hook)
        #expect((settings["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
        guard case .save(let saved) = original else { Issue.record("esperava .save"); return }
        #expect(saved["command"] as? String == "~/linha.sh")
    }

    /// Reinstalar não pode guardar o nosso como original (o hook chamaria a si mesmo).
    @Test func reinstalarMantemOOriginal() {
        let (once, _) = StatusLineInstall.install([:], hookCommand: hook)
        let (_, original) = StatusLineInstall.install(once, hookCommand: hook)
        guard case .keep = original else { Issue.record("esperava .keep"); return }
    }

    @Test func removerRestauraOuRespeitaTroca() {
        let old: [String: Any] = ["type": "command", "command": "~/linha.sh"]
        let (installed, _) = StatusLineInstall.install(["statusLine": old], hookCommand: hook)
        let restored = StatusLineInstall.uninstall(installed, original: old)
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "~/linha.sh")

        let semAnterior = StatusLineInstall.uninstall(StatusLineInstall.install([:], hookCommand: hook).settings, original: nil)
        #expect(semAnterior["statusLine"] == nil)

        // Usuário trocou o statusline depois de instalar: a escolha dele fica.
        let trocado: [String: Any] = ["statusLine": ["type": "command", "command": "outro.sh"]]
        #expect((StatusLineInstall.uninstall(trocado, original: old)["statusLine"] as? [String: Any])?["command"] as? String == "outro.sh")
    }

    /// Ida e volta pelo instalador, em pasta temporária: nada toca no `~/.claude` real.
    @Test func idaEVoltaDoStatusline() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("claudebar-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        let backups = folder.appendingPathComponent("backups")
        let original = folder.appendingPathComponent("state/statusline-original.json")
        let binary = folder.appendingPathComponent("bin/claudebar-hook").path
        try Data(#"{"statusLine":{"type":"command","command":"~/x.sh","padding":2}}"#.utf8).write(to: settings)
        func statusLine() throws -> NSDictionary? {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
            return (root?["statusLine"] as? [String: Any]).map { NSDictionary(dictionary: $0) }
        }
        let before = try statusLine()

        let install = try HookInstaller.plan(.installStatusLine, settings: settings, binary: binary, original: original)
        #expect(install.diff.contains("statusline"))
        try HookInstaller.apply(install, backups: backups, original: original)
        #expect(try statusLine()?["command"] as? String == HookInstaller.shellQuoted(binary) + " statusline")
        #expect(try statusLine()?["padding"] as? Int == 2)
        let mode = try manager.attributesOfItem(atPath: original.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: original)) as? [String: Any]
        #expect(saved.map { NSDictionary(dictionary: $0) } == before)

        // Instalar de novo: nada a mudar, e o original fica intacto.
        let again = try HookInstaller.plan(.installStatusLine, settings: settings, binary: binary, original: original)
        #expect(!again.hasChanges)

        let uninstall = try HookInstaller.plan(.uninstallStatusLine, settings: settings, binary: binary, original: original)
        try HookInstaller.apply(uninstall, backups: backups, original: original)
        #expect(try statusLine() == before)
        #expect(!manager.fileExists(atPath: original.path))
    }

    @Test func shellQuoted() {
        #expect(HookInstaller.shellQuoted("/Users/a b/it's") == #"'/Users/a b/it'\''s'"#)
    }
}
