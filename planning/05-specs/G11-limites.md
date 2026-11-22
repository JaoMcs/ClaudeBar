# Spec G11 — Limites 5 h e semanal sem rede (F22)

Insumos: `04-como-fazer/G11-limites.md`, `03-validacao/BACKLOG.md` (F22: M, depende de F02 e F16), `00-PLANO.md` (guard rails), código em `main` @ f943cc4.

**Protótipo validado.** Todo o código Swift abaixo foi aplicado numa cópia do repositório (scratchpad, descartável) e passou em `swift build` (Swift 6.3.3, modo Swift 6, **zero warnings**) e em `swift test` (51 testes: os 30 existentes + 21 novos). O ponto "variáveis globais de top-level dão erro de `Sendable`" da pesquisa não se aplica, porque nada novo fica em top-level: tudo roda dentro de funções, como o `run()` atual.

Dividido em três entregas, e cada uma vira um PR:

| Id | Entrega | Depende de | Arquivos | Esforço |
|---|---|---|---|---|
| **F22.1** | Core + subcomando `claudebar-hook statusline` (grava `limits.json`, encadeia o original, timeout, fail-open) + correção do `readAll` | — | novo `Sources/ClaudeBarCore/RateLimits.swift`, novo `Sources/ClaudeBarCore/StatusLineChain.swift`, `Sources/ClaudeBarCore/StatusDirectory.swift`, `Sources/claudebar-hook/main.swift`, novo `Tests/ClaudeBarTests/RateLimitsTests.swift`, `README.md`, `README.pt-BR.md` | 2,5 h |
| **F22.2** | Seção de limites no menu | F22.1 | `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/RateLimitsTests.swift` | 1 h |
| **F22.3** | Instalar e remover o `statusLine` (opt-in separado no F16, backup do original) | F22.1, F02, F16 (F03 recomendado) | novo `Sources/ClaudeBarCore/StatusLineInstall.swift`, o instalador do F02 (arquivo que o F02 criar), a tela do F16, `Tests/ClaudeBarTests/RateLimitsTests.swift`, `README.md`, `README.pt-BR.md` | 2 h |

Ordem recomendada para o gestor:
- **F22.1 e F22.2 não esperam F02/F16.** Sem instalação, o hook só roda se alguém editar o `settings.json` à mão (ver verificação manual). Os dois podem entrar cedo.
- **F22.3 depois de F02, F03 e F16.** Ele usa a leitura, o backup e a escrita do `settings.json` que o F02 cria, e o caminho estável do hook do F03.
- Conflitos de arquivo: `main.swift` também é tocado por F02 (`install|uninstall`), F05, F07 e F26. `MenuContent.swift` e `SessionStore.swift` também são tocados por F05, F07, F12, F19, F20 e F24. `StatusDirectory.swift` pode ser tocado por F03 e F26. Esses PRs rodam em sequência, não em paralelo.
- F31 (alerta perto do limite), F32 e F43 reaproveitam `RateLimits`/`limits.json` e ficam para depois.

---

## F22.1 — Core e subcomando `statusline`

### Objetivo
Toda vez que o Claude Code atualiza o rodapé, o `claudebar-hook statusline` grava `rate_limits.five_hour` e `rate_limits.seven_day` em `~/.claude/claudebar/limits.json` (atômico, 0600) e devolve exatamente o que o statusline anterior do usuário devolveria. Sem rede, sem OAuth, sem Keychain, sem ler conversa.

### Decisão técnica e por quê
- **Um tipo só, `RateLimits`, para o payload e para o arquivo.** O `limits.json` usa os mesmos nomes do payload oficial (`five_hour`, `seven_day`, `used_percentage`, `resets_at`) e acrescenta só o `updated_at`, que é opcional (vem `nil` do Claude Code, e o hook preenche). Um `Codable` decodifica os dois, e o `StatusDirectory.decoder` (`.secondsSince1970`) já bate com "Unix epoch seconds".
  - Descartada: dois tipos (payload e arquivo) com conversão. Seria código a mais para os mesmos campos.
- **Decode tolerante por omissão.** A struct de entrada só declara `rate_limits`, então `transcript_path`, `cost`, `spend_limit` e qualquer campo novo são ignorados. Janela ausente vira `nil`. Se o JSON vier inválido, se faltar o campo ou se nenhuma janela vier, **não se grava nada**: uma sessão com chave de API ou recém-aberta não apaga o dado bom de outra sessão.
  - Janela malformada (por exemplo, `used_percentage: null`) derruba o decode inteiro e também não grava. É o lado seguro: dado velho com idade visível é melhor que dado errado.
- **`readAll` ignora os dois arquivos novos.** Hoje ele apaga todo `*.json` que não decodifica como sessão. A pesquisa só citou o `limits.json`, mas o `statusline-original.json` (F22.3) mora no mesmo diretório e seria apagado também. Por isso entra uma função `isSessionFile`, que deixa a regra testável.
  - Descartada: extensão diferente (`limits.data`). O backlog fixa o nome `limits.json`, e um JSON com extensão `.json` é mais fácil de inspecionar.
  - Descartada: subdiretório. Seria preciso um segundo watcher ou um watcher recursivo.
- **Encadear com `/bin/sh -c <comando>`, com o comando como um argumento só.** O comando é texto que o usuário escreveu nos próprios settings, e o ClaudeBar não monta shell nenhum. É o mesmo que o Claude Code faz ("runs in a shell").
  - Descartada: passar o comando original como argumento do nosso `command`. Isso exigiria quoting de shell feito por nós, e o guard rail proíbe.
  - Descartada: substituir o statusline sem encadear. O usuário perderia a linha dele.
- **stdin e stdout em paralelo, com um prazo único para o EOF e para a saída do processo** (`DispatchGroup.wait(timeout:)`). Escrever tudo antes de ler trava quando o payload passa do buffer do pipe (o teste usa 200 KB).
- **Timeout de 5 s** (escolha nossa, a doc não fixa). Se estourar, o filho recebe SIGTERM, e o hook imprime o resumo dele e sai com 0.
- **`signal(SIGPIPE, SIG_IGN)`.** Um original que sai sem ler o stdin (por exemplo, `echo oi`) mataria o hook com SIGPIPE quando ele tentasse escrever no pipe. Com o sinal ignorado, o `write` só lança erro. Isso tem teste.
- **Gravar `limits.json` antes de rodar o filho.** Se o Claude Code cancelar o script no meio (o sinal não está documentado), o dado já foi salvo.
- **Variável `CLAUDEBAR_STATUSLINE=1` no ambiente do filho.** Se, por algum caminho, o "original" for o próprio hook, a segunda chamada não encadeia de novo. Junto com o filtro `!command.contains("claudebar-hook")` no `originalCommand`, isso fecha o laço infinito (fork bomb lenta) por dois lados.
- **Código de saída do original é repassado.** Se o script do usuário sai com código diferente de zero, o rodapé fica em branco, como já ficava sem o ClaudeBar. Erro nosso (arquivo do original ausente ou inválido, `Process.run` falhou, timeout) nunca dá código diferente de zero: o hook imprime o próprio resumo e sai com 0.
- **Sem statusline anterior: imprimir `5h 23% · sem 41%`.** Com statusline configurado, o Claude Code esconde as dicas do rodapé, e uma linha vazia seria pior. Janela ausente ou já renovada vira `–`, nunca 0%. Se o payload não trouxe o campo, o hook usa o último `limits.json` e, sem ele, imprime `5h – · sem –`.
  - Descartada: ANSI/cores. Seria código a mais, e texto puro funciona em qualquer terminal e no VoiceOver.

### Arquivos e código

**`Sources/ClaudeBarCore/RateLimits.swift`** (novo):
```swift
import Foundation

/// Uma janela de limite de uso (5 h ou semanal), como vem no stdin do statusline.
public struct RateWindow: Codable, Sendable, Equatable {
    /// De 0 a 100, decimal. Já veio acima de 100 em versões antigas do CLI.
    public let usedPercentage: Double
    public let resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// Percentual inteiro para exibir, preso entre 0 e 100.
    public var displayPercent: Int {
        Int(min(max(usedPercentage, 0), 100).rounded())
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

/// Limites da conta. Mesmo formato do `rate_limits` do statusline, mais a hora
/// em que o hook gravou — o app mostra a idade do dado.
public struct RateLimits: Codable, Sendable, Equatable {
    public var fiveHour: RateWindow?
    public var sevenDay: RateWindow?
    /// `nil` no payload do Claude Code; o hook preenche antes de gravar.
    public var updatedAt: Date?

    public init(fiveHour: RateWindow? = nil, sevenDay: RateWindow? = nil, updatedAt: Date? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case updatedAt = "updated_at"
    }

    /// Extrai os limites do JSON que o Claude Code manda ao statusline.
    ///
    /// `nil` quando o campo não vem (chave de API, sessão antes da 1ª resposta)
    /// ou vem sem nenhuma janela: nesses casos não se grava nada, para não
    /// apagar o dado bom que outra sessão gravou.
    public static func fromStatusLine(_ data: Data, now: Date = Date()) -> RateLimits? {
        struct Input: Decodable {
            let rateLimits: RateLimits?
            enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
        }
        guard var limits = (try? StatusDirectory.decoder.decode(Input.self, from: data))?.rateLimits,
              limits.fiveHour != nil || limits.sevenDay != nil
        else { return nil }
        limits.updatedAt = now
        return limits
    }

    /// Linha curta impressa no rodapé do Claude Code quando não havia statusline
    /// antes. Janela ausente ou já renovada vira "–", nunca 0%.
    public func summary(now: Date = Date()) -> String {
        func text(_ window: RateWindow?) -> String {
            guard let window, window.resetsAt > now else { return "–" }
            return "\(window.displayPercent)%"
        }
        return "5h \(text(fiveHour)) · sem \(text(sevenDay))"
    }
}
```

**`Sources/ClaudeBarCore/StatusLineChain.swift`** (novo):
```swift
import Foundation

/// Roda o statusline que o usuário já tinha, para o ClaudeBar entrar no meio
/// sem tomar o lugar dele.
public enum StatusLineChain {
    /// Variável que o hook põe no ambiente do filho: se o "comando original"
    /// for o próprio hook, a segunda chamada não encadeia de novo (sem laço).
    public static let reentryVariable = "CLAUDEBAR_STATUSLINE"

    /// Lê o `statusLine` original salvo na instalação. Só `type: "command"` com
    /// comando não vazio conta; qualquer outra coisa é "não havia statusline".
    public static func originalCommand(at url: URL = StatusDirectory.originalStatusLineURL) -> String? {
        struct Original: Decodable {
            let type: String?
            let command: String?
        }
        guard let data = try? Data(contentsOf: url),
              let original = try? JSONDecoder().decode(Original.self, from: data),
              original.type == nil || original.type == "command",
              let command = original.command,
              !command.trimmingCharacters(in: .whitespaces).isEmpty,
              !command.contains("claudebar-hook")
        else { return nil }
        return command
    }

    /// Roda `command` em `/bin/sh -c`, entregando `input` no stdin.
    ///
    /// O comando é texto que o próprio usuário escreveu nos settings dele e vai
    /// como **um** argumento: o ClaudeBar não monta shell. Devolve o stdout e o
    /// código de saída do filho, ou `nil` se não deu para rodar ou estourou o
    /// `timeout` (aí o filho recebe SIGTERM).
    public static func run(
        command: String,
        input: Data,
        timeout: TimeInterval
    ) -> (output: Data, status: Int32)? {
        // Filho que sai sem ler o stdin faria o `write` abaixo matar o hook
        // com SIGPIPE. Ignorado, o `write` só lança erro.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        var environment = ProcessInfo.processInfo.environment
        environment[reentryVariable] = "1"
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        // stderr do filho segue para o nosso: aparece no `claude --debug`.
        process.standardError = FileHandle.standardError

        // Espera duas coisas: o EOF do stdout e o fim do processo, ambos dentro
        // do mesmo prazo.
        let done = DispatchGroup()
        done.enter()
        process.terminationHandler = { _ in done.leave() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // stdin e stdout em paralelo: o pipe tem buffer finito, e escrever tudo
        // antes de ler trava se o filho imprimir muito antes de ler o resto.
        let writer = stdin.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

        let output = OutputBox()
        let reader = stdout.fileHandleForReading
        done.enter()
        DispatchQueue.global().async {
            output.data = reader.readDataToEndOfFile()
            done.leave()
        }

        // ponytail: neto que herdou o stdout (`cmd &`) segura o EOF; o timeout
        // cobre, mas ele pode sobrar vivo. Grupo de processos se isso aparecer.
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return (output.data, process.terminationStatus)
    }
}

/// O `DispatchGroup` ordena a escrita (leitor) antes da leitura (quem espera).
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
```
Por que fica no Core e não no `main.swift`: o target de testes não depende do executável `claudebar-hook`, e o encadeamento é a parte que mais precisa de teste.

**`Sources/ClaudeBarCore/StatusDirectory.swift`**: dois caminhos, o filtro e a escrita atômica extraída para reuso. O padrão 0700/0600 continua idêntico.
```swift
    /// Últimos limites de uso, gravados pelo `claudebar-hook statusline`.
    public static let limitsURL = url.appendingPathComponent("limits.json")
    /// `statusLine` que o usuário tinha antes da instalação, encadeado pelo hook.
    public static let originalStatusLineURL = url.appendingPathComponent("statusline-original.json")

    /// `readAll` apaga todo `*.json` que não decodifica como sessão: estes dois
    /// moram no mesmo diretório e precisam ficar de fora.
    static func isSessionFile(_ file: URL) -> Bool {
        file.pathExtension == "json"
            && file.lastPathComponent != limitsURL.lastPathComponent
            && file.lastPathComponent != originalStatusLineURL.lastPathComponent
    }
```
```swift
    /// Grava de forma atômica, para o app nunca ler um JSON pela metade.
    public static func write(_ status: SessionStatus) throws {
        try writeAtomically(encoder.encode(status), to: fileURL(sessionId: status.sessionId))
    }

    public static func writeLimits(_ limits: RateLimits) throws {
        try writeAtomically(encoder.encode(limits), to: limitsURL)
    }

    /// `nil` sem arquivo ou com arquivo inválido: o menu mostra "indisponível".
    public static func readLimits() -> RateLimits? {
        guard let data = try? Data(contentsOf: limitsURL) else { return nil }
        return try? decoder.decode(RateLimits.self, from: data)
    }

    private static func writeAtomically(_ data: Data, to file: URL) throws {
        try createIfNeeded()
        try data.write(to: file, options: .atomic)
        // A escrita atômica cria o arquivo novo pelo umask; reforçamos depois.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
```
Em `readAll()`, troque `.filter { $0.pathExtension == "json" }` por `.filter(isSessionFile)`.

**`Sources/claudebar-hook/main.swift`**: uma função nova e um desvio logo depois de ler o stdin, **antes** do `HookPayload` e do `SessionState(rawValue:)`.
```swift
// Uso: claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>]
//      claudebar-hook statusline   (comando do `statusLine` do Claude Code)
```
```swift
/// Statusline: guarda os limites de uso e devolve o statusline que o usuário já
/// tinha. Nunca falha por culpa própria — o pior caso é o rodapé sem texto.
private func statusLine(_ stdinData: Data) -> Never {
    // Grava antes de rodar o original: se o Claude Code cancelar este processo
    // no meio, o dado já está salvo.
    let limits = RateLimits.fromStatusLine(stdinData)
    if let limits {
        do {
            try StatusDirectory.writeLimits(limits)
        } catch {
            FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
        }
    }

    let isReentry = ProcessInfo.processInfo.environment[StatusLineChain.reentryVariable] != nil
    if !isReentry,
       let command = StatusLineChain.originalCommand(),
       // 5 s: a doc não fixa limite e o Claude Code cancela o script na
       // próxima atualização; mais que isso já é rodapé travado.
       let result = StatusLineChain.run(command: command, input: stdinData, timeout: 5) {
        FileHandle.standardOutput.write(result.output)
        exit(result.status)
    }

    // Sem statusline anterior (ou ele falhou em rodar): uma linha curta em vez
    // de vazio, porque com statusline configurado o Claude Code esconde as
    // dicas do rodapé.
    let shown = limits ?? StatusDirectory.readLimits() ?? RateLimits()
    print(shown.summary())
    exit(0)
}
```
Em `run()`:
```swift
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    if command == "statusline" {
        statusLine(stdinData)
    }
```
O `fail("informe o estado ...")` continua como está. `statusline` não é estado e não entra nessa mensagem, que é para quem configura hooks.

### Testes (em `Tests/ClaudeBarTests/RateLimitsTests.swift`, novo)
O arquivo usa `@testable import ClaudeBarCore` (para `isSessionFile`) e `@testable import ClaudeBar` (para `MenuContent.limitLines`, F22.2). Todos passaram no protótipo.
```swift
@testable import ClaudeBarCore
import Foundation
import Testing

@testable import ClaudeBar

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

    /// `readAll` apagava todo `*.json` que não fosse sessão.
    @Test func readAllNaoApagaOsArquivosDoStatusline() {
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.limitsURL))
        #expect(!StatusDirectory.isSessionFile(StatusDirectory.originalStatusLineURL))
        #expect(StatusDirectory.isSessionFile(StatusDirectory.fileURL(sessionId: "abc")))
    }
}

@Suite("Encadeamento do statusline")
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
}
```
**Não** escreva teste de ponta a ponta do binário com `HOME` falso: o `NSHomeDirectory()` ignora a variável `HOME` (conferido no protótipo), e o teste escreveria no `~/.claude/claudebar` real. O ponta a ponta fica na verificação manual.

### README (`README.md` e `README.pt-BR.md`)
- Seção "Hook CLI usage": acrescentar `claudebar-hook statusline`. Ele lê o JSON do statusline, guarda só `rate_limits` em `~/.claude/claudebar/limits.json` (0600), roda o statusline anterior com `/bin/sh -c`, repassa stdin, stdout e código de saída, tem timeout de 5 s, e imprime `5h 23% · sem 41%` quando não havia statusline.
- Seção de privacidade: do JSON do statusline o hook lê **só** `rate_limits`. `transcript_path` e o resto são ignorados. Nenhuma chamada de rede, nenhum token.
- Limitações: só assinantes Pro, Max e Ultra recebem o campo, e só depois da primeira resposta de uma sessão. Com duas contas em terminais diferentes, vale a última sessão que atualizou.

### Verificação manual
1. `swift build && swift test`, sem warnings.
2. `./scripts/build-app.sh`. Em seguida:
   `echo '{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":4102444800}}}' | build/ClaudeBar.app/Contents/MacOS/claudebar-hook statusline; echo $?`
   → imprime `5h 24% · sem –` e sai com `0`. `stat -f %Lp ~/.claude/claudebar/limits.json` → `600`.
3. `echo '{}' | .../claudebar-hook statusline` → `limits.json` fica igual (`updated_at` não muda).
4. Com o app aberto e um `limits.json` presente, abrir o menu e esperar 10 s: `ls ~/.claude/claudebar/limits.json` continua lá (prova do `readAll`).
5. Encadeamento: `printf '{"type":"command","command":"cat >/dev/null; echo minha-linha"}' > ~/.claude/claudebar/statusline-original.json && chmod 600 $_`, e depois repetir o passo 2 → imprime `minha-linha`. Trocar o comando por `sleep 10` → volta em cerca de 5 s com o resumo e código `0`. Apagar o arquivo no fim.
6. Ao vivo (sem F22.3): pôr à mão `"statusLine": {"type": "command", "command": "<caminho>/claudebar-hook statusline"}` no `~/.claude/settings.json` (com backup), abrir uma sessão nova, mandar uma mensagem e conferir o rodapé e o `limits.json`. **Exige conta Pro/Max**: registrar como "não verificado" se a conta da máquina for de API.
7. **Shell (não confirmado):** antes do merge, configurar à mão um `statusLine` `echo "$0"` sem o ClaudeBar e ver no rodapé qual shell o Claude Code usa. Se não for `sh`/`/bin/sh`, trocar o `executableURL` para o mesmo shell e registrar no PR.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| `readAll` apagar `limits.json`/`statusline-original.json` | `isSessionFile` + teste. |
| Laço infinito (o original é o próprio hook) | Filtro em `originalCommand`, variável `CLAUDEBAR_STATUSLINE` e o `.keep` do F22.3. São três camadas. |
| Script do usuário lento ou travado | Timeout de 5 s → SIGTERM e resumo. O neto que segura o stdout pode sobrar vivo (comentário `ponytail:` no código). |
| Claude Code cancela o hook (sinal não documentado) e o filho fica órfão | `limits.json` gravado antes. O filho termina sozinho ou no próprio timeout do script. Aceito. |
| SIGPIPE quando o original não lê stdin | `SIG_IGN` + teste. |
| `/bin/sh` diferente do shell do Claude Code | Verificação manual 7. O comando é do usuário e costuma ser um caminho de script com shebang, que roda igual em qualquer shell. |
| Janela de 0644 entre a escrita atômica e o `chmod` | Diretório 0700, mesmo padrão já aceito nos arquivos de sessão. Aceito. |
| Sobrecarga a cada atualização do rodapé | Um processo Swift curto a mais por atualização, e o Claude Code já faz debounce de 300 ms. Aceito. |
| Duas contas alternando o arquivo | Vence a última. Documentado no README, sem código. |

### Critérios de aceite
- `swift build` sem erro e sem warning, e `swift test` verde com os testes acima.
- Payload sem `rate_limits` (ou sem janela) não cria nem altera `limits.json`.
- `limits.json` com permissão 0600, diretório 0700, conteúdo só com `five_hour`, `seven_day` e `updated_at`.
- Com o original `cat`, o stdout do hook é byte a byte o stdin. Com `exit 3`, o hook sai com 3. Com `sleep 10`, o hook sai com 0 em até 6 s.
- O hook nunca sai com código diferente de zero por erro próprio (sem arquivo, arquivo inválido, diretório sem permissão).
- `readAll` não apaga `limits.json` nem `statusline-original.json`.
- `grep -rn "transcript_path\|URLSession" Sources/` → nada.

### O que NÃO fazer
- Não ler `transcript_path`, `.credentials.json`, Keychain nem cookie. Não chamar `api/oauth/usage` como fallback.
- Não montar texto de shell com dado nosso, e não usar `$SHELL` sem a verificação 7 mostrar que é preciso.
- Não gravar `0%` nem `limits.json` vazio quando o campo falta.
- Não adicionar `refreshInterval`, porque o Claude Code já re-roda o script no `resets_at`.
- Não criar subdiretório, watcher novo nem dependência.
- Não tratar `spend_limit`, nem janelas por modelo (o payload não traz).

---

## F22.2 — Seção de limites no menu

### Objetivo
O topo do menu mostra `Limite 5 h: 23% · renova 14:30`, `Semanal: 41% · renova sex., 09:00` e `Atualizado há 3 min`. Sem dado, mostra "indisponível", nunca 0%.

### Decisão técnica e por quê
- **Ler no `merge()` do `SessionStore`.** O `limits.json` está no diretório que o `DirectoryWatcher` já observa, e o timer de 5 s já chama `merge()` via `refreshAgents()`. Assim não precisa de watcher, timer nem tarefa nova.
  - Descartada: um `limitsWatcher` dedicado. Seria duplicado.
- **Texto montado numa função `static` pura (`limitLines`).** Dá para testar sem SwiftUI e sem relógio real.
- **Janela com `resets_at` no passado: "renovado, aguardando dado novo".** O número antigo já não vale, e o Claude Code também descarta a janela nesse caso.
- **Hora de renovação: só a hora se for hoje, dia da semana + hora se não for.** Usa `Date.formatted` (Foundation, macOS 12+) no locale do sistema, para o F21 não ter de mexer nisso.
- **Idade sempre visível**, com o `relativeFormatter` que já existe. Ela cobre os casos em que o hook não roda (statusline de projeto, `disableAllHooks`, workspace sem trust).
  - Descartada: destaque quando a idade passa de 1 h. O estilo `.menu` quase não tem estilo de texto, e a idade já está escrita. Adicionar se alguém reclamar.
- **Sem `TimelineView`.** **[Não confirmado]** O conteúdo do `.menu` parece ser montado ao abrir. Se ficar aberto, a idade não anda. Aceito: fechar e abrir de novo atualiza.

### Arquivos e código

**`Sources/ClaudeBar/SessionStore.swift`**:
```swift
    private(set) var rows: [SessionRow] = []
    /// Últimos limites de uso gravados pelo statusline. `nil` = indisponível.
    private(set) var limits: RateLimits?
```
No fim de `merge()`:
```swift
        rows = merged
        // Mesmo diretório, mesmo watcher e mesmo timer: nada novo a observar.
        limits = StatusDirectory.readLimits()
```

**`Sources/ClaudeBar/MenuContent.swift`**: no começo do `body`:
```swift
    var body: some View {
        ForEach(Self.limitLines(store.limits, now: Date()), id: \.self) { line in
            Text(line)
        }

        Divider()

        if store.rows.isEmpty {
```
E a função:
```swift
    /// Linhas dos limites no topo do menu. Sem dado é "indisponível", nunca 0%:
    /// chave de API e sessão antes da 1ª resposta não recebem o campo.
    static func limitLines(_ limits: RateLimits?, now: Date) -> [String] {
        guard let limits else { return ["Limites de uso: indisponível"] }

        func line(_ title: String, _ window: RateWindow?) -> String {
            guard let window else { return "\(title): indisponível" }
            // O Claude Code descarta a janela depois do reset: o número velho
            // não vale mais, e o novo só chega com a próxima resposta.
            guard window.resetsAt > now else { return "\(title): renovado, aguardando dado novo" }
            let reset = Calendar.current.isDate(window.resetsAt, inSameDayAs: now)
                ? window.resetsAt.formatted(date: .omitted, time: .shortened)
                : window.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return "\(title): \(window.displayPercent)% · renova \(reset)"
        }

        var lines = [line("Limite 5 h", limits.fiveHour), line("Semanal", limits.sevenDay)]
        if let updatedAt = limits.updatedAt {
            lines.append("Atualizado \(relativeFormatter.localizedString(for: updatedAt, relativeTo: now))")
        }
        return lines
    }
```
Quem nunca instalou o statusline vê uma linha só, "Limites de uso: indisponível". Se o gestor preferir esconder a seção nesse caso, troque o `guard` por `return []` e tire o `Divider` quando a lista vier vazia. Isso fica como decisão de UX, não de técnica.

### Testes (no mesmo `RateLimitsTests.swift`, suíte "Limites do statusline")
```swift
    @Test func menuSemDadoDizIndisponivel() {
        #expect(MenuContent.limitLines(nil, now: Date()) == ["Limites de uso: indisponível"])
        let lines = MenuContent.limitLines(RateLimits(updatedAt: Date()), now: Date())
        #expect(lines[0] == "Limite 5 h: indisponível")
        #expect(lines[1] == "Semanal: indisponível")
        #expect(!lines.contains { $0.contains("0%") })
    }

    @Test func menuJanelaRenovada() {
        let now = Date()
        let limits = RateLimits(fiveHour: RateWindow(usedPercentage: 90, resetsAt: now.addingTimeInterval(-60)))
        #expect(MenuContent.limitLines(limits, now: now)[0] == "Limite 5 h: renovado, aguardando dado novo")
    }
```
Não teste o texto exato da hora, porque ele depende do locale da máquina.

### README
Na lista do que o menu mostra, acrescentar: limites de 5 h e semanal (%, hora de renovação e idade), ou "indisponível". Captura de tela fica para o F49.

### Verificação manual
1. Sem `limits.json` → "Limites de uso: indisponível".
2. Gravar o `limits.json` do passo 2 do F22.1 → em até cerca de 1 s (watcher) o menu mostra `Limite 5 h: 24% · renova <dia>, <hora>` e `Semanal: indisponível`.
3. Editar à mão o `resets_at` para um valor no passado → "renovado, aguardando dado novo".
4. Abrir o menu, esperar 2 min com ele aberto, fechar e abrir → a idade avançou (confirma ou desmente o "montado ao abrir").
5. VoiceOver lê as linhas por extenso (F19). Nenhum emoji nessas linhas.

### Riscos e mitigação
- Idade parada com o menu aberto: aceito (ver acima).
- Mais renders do menu: `merge()` já roda a cada evento do diretório, e o `limits.json` só soma eventos durante as respostas. Ler um arquivo de cerca de 200 bytes é desprezível.
- Strings em português fixas: o F21 as move para `Localizable.strings`.

### Critérios de aceite
- Sem dado, nenhuma linha com "%". Com dado, o percentual é inteiro, de 0 a 100.
- Janela vencida nunca mostra o número antigo.
- A atualização chega pelo watcher já existente (nenhum `Timer`/`DirectoryWatcher` novo no diff).
- Testes `menu*` verdes.

### O que NÃO fazer
- Não pôr o percentual no ícone ou no título da barra. Isso é o F31/F32, depois.
- Não criar `TimelineView`, timer ou observador novo.
- Não mostrar 0% quando falta dado.

---

## F22.3 — Instalar e remover o `statusLine`

### Objetivo
No F16, uma opção separada e desligada por padrão, "Mostrar limites de uso (usa o statusline do Claude Code)". Ao instalar, o `statusLine` original é guardado em `statusline-original.json` (0600) e o `settings.json` passa a apontar para o hook. Ao remover, o original volta inteiro (`padding`, `refreshInterval` incluídos).

### Decisão técnica e por quê
- **Funções puras sobre o dicionário do `JSONSerialization`** (`StatusLineInstall.install/uninstall`). Ler, fazer backup, validar e gravar o `settings.json` é do F02. O F22.3 só calcula o novo dicionário e diz o que fazer com o arquivo do original.
  - Descartada: estender o `jq` do `install.sh`. O F02 tira o `jq`, e editar `statusLine` com `jq` seria código jogado fora.
- **Identificar o nosso pela presença de `claudebar-hook` no `command`**, o mesmo critério que o F02 usa para os hooks.
- **Reinstalar não sobrescreve o original** (`.keep`). Sem isso, o "original" viraria o próprio hook.
- **Sem statusline anterior → `.remove`** (apaga um `statusline-original.json` velho). Senão um original esquecido voltaria a rodar.
- **Remover só desfaz se o `statusLine` atual ainda é o nosso.** Se o usuário trocou depois, a escolha dele fica.
- **Opt-in separado, desligado por padrão.** Ele muda o rodapé do Claude Code, o que é mais invasivo que os hooks.
  - Descartada: oferecer só a quem já tem statusline. Isso exclui justamente o usuário comum.
- **`hookCommand` vem pronto do F02/F03**, com o mesmo quoting que o F02 usa nos hooks, mais ` statusline`. O caminho recomendado é o estável do F03 (`~/.claude/claudebar/bin/claudebar-hook`), para que mover o app não quebre o rodapé.
- **Só settings do usuário** (`~/.claude/settings.json`). **[Não confirmado]** Um `statusLine` em settings de projeto provavelmente vence o nosso naquele repo. Não mexer: a idade no menu mostra o dado parado.

### Arquivos e código

**`Sources/ClaudeBarCore/StatusLineInstall.swift`** (novo):
```swift
import Foundation

/// Troca o `statusLine` do `settings.json` pelo do ClaudeBar e desfaz a troca.
/// Funções puras sobre o dicionário do `JSONSerialization`; ler, fazer backup
/// e gravar o arquivo é do instalador (F02).
public enum StatusLineInstall {
    /// O que fazer com `statusline-original.json` depois da troca.
    public enum Original {
        /// Já estava instalado: o arquivo guarda o original de verdade.
        case keep
        /// Gravar este objeto (0600).
        case save([String: Any])
        /// Não havia statusline: apagar um arquivo velho, se existir.
        case remove
    }

    /// `true` quando o `statusLine` é o nosso.
    public static func isOurs(_ statusLine: Any?) -> Bool {
        guard let command = (statusLine as? [String: Any])?["command"] as? String else { return false }
        return command.contains("claudebar-hook")
    }

    /// `hookCommand` já vem pronto para shell (o mesmo quoting que o F02 usa
    /// para os hooks), com ` statusline` no fim.
    public static func install(
        _ settings: [String: Any],
        hookCommand: String
    ) -> (settings: [String: Any], original: Original) {
        let current = settings["statusLine"] as? [String: Any]
        // Reinstalar não pode salvar o nosso como "original": o hook chamaria
        // a si mesmo.
        if isOurs(current) { return (settings, .keep) }

        // Mantém `padding`, `refreshInterval` e o que mais o usuário tinha.
        var ours = current ?? [:]
        ours["type"] = "command"
        ours["command"] = hookCommand
        var result = settings
        result["statusLine"] = ours
        return (result, current.map { .save($0) } ?? .remove)
    }

    /// Só desfaz se o `statusLine` ainda é o nosso: se o usuário trocou depois,
    /// a escolha dele fica. O instalador apaga `statusline-original.json` depois.
    public static func uninstall(_ settings: [String: Any], original: [String: Any]?) -> [String: Any] {
        guard isOurs(settings["statusLine"]) else { return settings }
        var result = settings
        result["statusLine"] = original
        return result
    }
}
```
No instalador do F02, que ainda não existe e por isso aparece aqui só como contrato:
- Instalar: `let (novo, original) = StatusLineInstall.install(settings, hookCommand: ...)`. Para `.save(obj)`: `JSONSerialization.data(withJSONObject: obj)` → gravar em `StatusDirectory.originalStatusLineURL` com o mesmo atômico + 0600 (exponha o `writeAtomically` como `public`, ou acrescente um `writeOriginalStatusLine(_ data:)`, uma linha). Para `.remove`: `try? removeItem`. Para `.keep`: nada. Depois disso, o fluxo normal do F02 (backup, validar, escrita atômica do `settings.json`).
- **Ordem:** gravar o `statusline-original.json` **antes** do `settings.json`. Se a segunda escrita falhar, o settings continua com o original, e o arquivo extra é inofensivo.
- Remover: ler o original (pode faltar) → `StatusLineInstall.uninstall(settings, original:)` → gravar o settings → apagar o `statusline-original.json`.
- `--dry-run` do F02 mostra o `statusLine` antes e depois no diff.

**Tela do F16**: um toggle próprio, desligado. Ao ligar, ele mostra o objeto `statusLine` atual e o novo (o JSON exato) e, **se não havia statusline**, este aviso:
> "O Claude Code esconde algumas dicas do rodapé (como `esc to interrupt`) quando existe um statusline. No lugar delas aparece `5h 23% · sem 41%`. Os limites só aparecem para assinantes Pro, Max e Ultra."

Se havia statusline: "Seu statusline continua aparecendo igual. O ClaudeBar só lê os limites antes de repassar." O F17 (status "tudo ok") pode checar se o `statusLine.command` aponta para um binário existente. Isso é uma linha, que fica no F17.

### Testes (no mesmo arquivo)
```swift
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
}
```
O F02 acrescenta o teste do ciclo de arquivo (instalar → remover → `settings.json` igual ao backup, exceto a ordem das chaves) na suíte dele.

### Scripts e README
- `scripts/install.sh`: **não** mexe no `statusLine` enquanto usar `jq`. Quando o F02 trocar o `jq` por `claudebar-hook install`, a opção entra como flag explícita (`--statusline`), desligada por padrão.
- README (as duas línguas), seção de instalação e remoção: o que muda no rodapé, onde fica o backup (`statusline-original.json` + o backup com timestamp do F02), e a remoção manual: "copie o conteúdo de `~/.claude/claudebar/statusline-original.json` de volta para `statusLine` no `~/.claude/settings.json`, ou apague a chave se o arquivo não existir".

### Verificação manual
1. Sem statusline → instalar → o `settings.json` tem `statusLine.command` com o hook, não existe `statusline-original.json`, e uma sessão nova mostra `5h … · sem …`.
2. Com `{"type":"command","command":"~/x.sh","padding":2}` → instalar → o arquivo do original é 0600 e igual ao objeto. O rodapé mostra a saída de `~/x.sh`. Remover → o objeto volta idêntico.
3. Instalar duas vezes → o `statusline-original.json` não muda.
4. Trocar o `statusLine` à mão depois de instalar → remover não toca nele.
5. Mover o `.app` (com F03) → o rodapé continua funcionando. Sem F03, ele fica em branco: registrar.

### Riscos e mitigação
- Perder o statusline do usuário: o original é gravado antes, o backup com timestamp vem do F02, `.keep` na reinstalação e remoção condicional.
- Dicas do rodapé somem: aviso no opt-in, resumo no lugar e opção desligada por padrão.
- App apagado sem remover: o rodapé fica em branco, como acontece com os hooks hoje. Documentado no README e mitigado pelo F03 (binário fora do `.app`).
- `JSONSerialization` reordena chaves: o F02 já avisa.

### Critérios de aceite
- Os 4 testes de instalação verdes.
- Ida e volta (instalar e remover) devolve o `statusLine` original igual (comparação de dicionário).
- Nenhuma escrita no `settings.json` sem consentimento explícito na tela do F16, e a opção nasce desligada.
- `statusline-original.json` sempre 0600.

### O que NÃO fazer
- Não editar settings de projeto nem `settings.local.json`.
- Não instalar o statusline junto com os hooks sem um opt-in próprio.
- Não montar o comando original dentro do nosso `command`.
- Não "reparar" o `statusLine` em silêncio na abertura do app (o F03 só oferece).

---

## Pontos não confirmados e como a implementação se protege

| Ponto | Proteção |
|---|---|
| `/bin/sh` ou `$SHELL` | `/bin/sh`, com a verificação manual 7 do F22.1 antes do merge. Se a verificação mostrar outro shell, troca de uma linha. |
| Sinal de cancelamento e filho órfão | `limits.json` gravado antes, timeout de 5 s, fail-open. Órfão aceito (comentário `ponytail:`). |
| Timeout de 5 s | Literal com comentário em `main.swift`. Sem configuração. |
| Precedência de `statusLine` de projeto | Não mexer. A idade no menu denuncia dado parado. |
| Menu `.menu` montado só ao abrir | A idade é calculada na renderização. Verificação manual 4 do F22.2. |
| Globais `Sendable` no `main.swift` (SE-0343) | **Resolvido:** protótipo compila em Swift 6 sem warnings. Nada em top-level. |
| 0644 temporário | Diretório 0700, mesmo padrão já aceito. |
| Regressão da v2.1.96 e conta Pro/Max real | "indisponível" e "não grava sem campo" cobrem a ausência. A verificação com conta real fica como **não verificada** no relatório. |
| Duas contas | Vence a última. README. |
| Mover o app | Resolvido pelo F03 (caminho estável). O F17 detecta. |
| `NSHomeDirectory()` ignora `HOME` | Constatado no protótipo. Nada de teste de ponta a ponta com `HOME` falso. Os testes usam funções puras e `temporaryDirectory`. |
