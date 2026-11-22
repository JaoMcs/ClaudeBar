# Spec G05: sessões fantasmas (F06) + polling leve (F08)

Insumos: `04-como-fazer/G05-fantasmas-polling.md`, `03-validacao/BACKLOG.md` (F06 P–M, P0; F08 P, depende de F06), `00-PLANO.md` (guard rails), código em `main` @ f943cc4.

**Verificado nesta spec.** Apliquei o diff de F06 e depois o de F08 numa cópia do projeto (Swift 6.3.3, tools 6.0, macOS 26):
- `swift build`: 0 avisos nos dois passos. `swift test`: **46** testes passam só com F06 (34 atuais + 12 novos) e **49** com F08 (+3). Rodei 3 vezes sem flake.
- Mutação: com a regra de horário de início neutralizada, `pidRecicladoPorOutroClaudeApaga` falha. O teste pega a regressão.
- Hook com payload `lixo` e com `{}`: exit 0, nenhum arquivo novo em `~/.claude/claudebar/`.
- `/usr/bin/time -l sh -c '4× claude agents --json'`: user+sys = 0,57 s (≈ 4 × 0,14) e RSS máx. 161 MB. **Soma os netos reapados.** `instructions retired` (27 M) **não soma**, então para medir vale user+sys e não instruções.
- Com um `MenuBarExtra` `.menu` mínimo, aberto por `performClick` no `NSStatusBarButton`, montei uma sonda descartável em `scratchpad/menuprobe`.

Respostas aos "não confirmados" da pesquisa:

| Item | Resultado | Efeito na spec |
|---|---|---|
| `proc_bsdinfo`, `PROC_PIDTBSDINFO`, `pbi_start_tvsec` via `import Darwin` | **Compila** e devolve o início certo (teste com `/bin/sleep`, erro < 2 s) | Usado em F06 |
| `makeProcessSource(.exit)` em PID que já morreu (e foi reapado) | **Avisa na hora**: o libdispatch entrega `.exit` | Virou teste (`pidJaMortoAvisaAoObservar`). Sem corrida entre listar e observar |
| `NSMenu.didBeginTrackingNotification` no `MenuBarExtra` `.menu` | **Dispara**, com `object` = `SwiftUIMenu` | — |
| A fila main roda com o menu aberto? | **Não.** `DispatchQueue.main.async` e `Task { @MainActor }` só rodam **depois** que o menu fecha. Só `RunLoop.main.perform(inModes: [.common])` roda | O gatilho "abrir o menu" **sai** de F08 (ver "O que NÃO fazer") |
| O conteúdo SwiftUI do menu aberto se atualiza? | **Não**: mudei o `@Observable` com o menu aberto e os itens continuaram com o texto antigo | Idem |
| `SessionEnd` em terminal fechado, `tmux kill-server`, crash | Não testado | Irrelevante: a fonte `.exit` cobre qualquer morte |
| `proc_pidpath` em processo de outro usuário (`EPERM`) | Não testado | Protegido: caminho `nil` = mantém |
| Entitlement no app ad-hoc | `swift test` (binário sem assinatura) funciona | Conferir no `.app` instalado (verificação manual) |
| `$PPID` = PID do `claude` | Só empírico | Se mudar, o arquivo é apagado (caminho sem `claude`) e o app cai para o estado do CLI. Degrada sem fantasma. Ver Riscos |
| 2 s de throttle / 60 s de polling | Escolha, não medida | Medir (critério de aceite de F08) |

Dividido em duas entregas, uma por PR:

| Id | Entrega | Arquivos | Esforço |
|---|---|---|---|
| **F06** | Regra de vida conservadora, `pid 0` decidido pelo CLI, hook sem `unknown.json`, 12 testes | `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/ClaudeBarCore/StatusDirectory.swift`, `Sources/ClaudeBar/ProcessProbe.swift`, `Sources/ClaudeBar/SessionMerge.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Sources/claudebar-hook/main.swift`, `Tests/ClaudeBarTests/GhostSessionTests.swift` (novo), `README.md`, `README.pt-BR.md` | 3 h |
| **F08** | Fonte `.exit` por PID, consulta ao CLI no evento de hook com throttle de 2 s, timer de 60 s ± 6 s, `SessionStart`, contador no log | `Sources/ClaudeBar/ProcessExitWatcher.swift` (novo), `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/AgentsProbe.swift`, `Tests/ClaudeBarTests/ProcessExitWatcherTests.swift` (novo), `scripts/install.sh` (ou o instalador do F02), `README.md`, `README.pt-BR.md` | 3,5 h (inclui 1 h de medição antes/depois) |

Ordem para o gestor:
- **F06 antes de F08.** O F08 usa `agents: [AgentSession]?` e `ProcessProbe.exists`, que entram no F06.
- **Conflitos.** `SessionStore.swift`, `SessionMerge.swift`, `AgentsProbe.swift`, `claudebar-hook/main.swift`, `install.sh` e os READMEs também são tocados por F07 (G06), F02, F05, F12 e F19. Esses PRs rodam em sequência.
- **Se o F02 (instalador) já estiver em `main`**, a entrada `SessionStart` do F08 vai nele, não no `install.sh`.

---

## F06: sessões fantasmas

### Objetivo
Nenhum arquivo de hook fica para sempre, e nenhuma linha fica no menu, quando o processo que o gravou já não é aquela sessão do Claude. Isso vale para processo morto, PID reciclado por outro programa, PID reciclado por outro `claude`, `pid 0` e `unknown.json`. A regra é **conservadora**: sem prova de morte, a sessão fica.

### Decisão técnica e por quê
- **A regra de vida sai de `SessionStatus.isAlive` (Core) e vira `ProcessProbe.isAlive(_:)` (app).** O `ProcessProbe` já é injetável e já tem `executablePath`. Ganha mais dois campos: `exists` (`kill(pid,0)` ≠ `ESRCH`) e `startTime` (`proc_pidinfo` + `PROC_PIDTBSDINFO`). O hook não lê o diretório, então a regra não precisa estar no Core.
  - Descartada: manter `isAlive` no Core e mover o `ProcessProbe` para lá. Isso puxaria `getpgid`/`proc_pidpath` para o binário do hook sem uso nenhum.
  - Descartada: protocolo `LivenessChecking`. Seria uma interface com uma implementação só, quando o `ProcessProbe` já é o ponto de injeção.
- **Os campos novos têm valor padrão "sem informação"** (`exists = true`, `startTime = nil`). Os 9 `ProcessProbe(isGroupLeader:executablePath:)` dos testes atuais continuam compilando sem mudança, e um probe incompleto nunca apaga nada.
- **`readAll(in: URL = url, isAlive:)`.** O parâmetro de diretório resolve o `static let url`, que não dava para testar, sem abstração nova. `isAlive` não tem padrão porque o Core não conhece o `ProcessProbe`. O único chamador é `SessionStore.merge()`.
- **Ordem da regra** (conservadora, uma prova por linha):

  | Situação | Decisão |
  |---|---|
  | Não decodifica, `sessionId` vazio ou `"unknown"`, ou nome do arquivo ≠ `sanitize(sessionId).json` | apaga |
  | `pid <= 0` | **mantém no disco**. O CLI decide no cruzamento |
  | `kill` → `ESRCH` | apaga |
  | `proc_pidpath` nil (outro usuário, corrida com a saída) | mantém |
  | Caminho sem `claude` | apaga (PID reciclado) |
  | Início do processo > `updatedAt + 1 s` | apaga (outro `claude` herdou o PID) |
  | Senão | mantém |

  Base do horário de início: a Apple (DTS) recomenda combinar PID com horário de início contra reuso de PID. O item dispensa campo novo no JSON e mudança no formato. `EPERM` conta como "existe".
  - Descartada: gravar `procStart` no arquivo pelo hook. Mudaria o formato e criaria compatibilidade entre versões para ganhar o mesmo que a comparação com `updatedAt` já dá.
  - Descartada: `sysctl(KERN_PROC_PID)` para o horário. É mais verboso e da mesma família.
- **`pid 0` e sobra de `/clear` são decididos no `SessionMerge`, não no disco.** `rows(agents:)` passa a receber `[AgentSession]?`, com `nil` = "CLI ainda não respondeu". Quando o CLI respondeu, uma linha só do hook some se `pid <= 0` ou se o CLI lista aquele PID com **outro** `sessionId`. A doc do `SessionEnd` confirma que `/clear` e `/resume` trocam o id no mesmo processo. Só esconde, não apaga, então um erro aqui se corrige sozinho na próxima consulta.
  - Descartada: TTL por `updatedAt`. Esconderia sessão ociosa real deixada aberta o dia todo.
- **Hook sem `session_id` sai 0 sem gravar.** Some o `?? "unknown"` e some também o `CLAUDE_SESSION_ID`, que não está na doc oficial de hooks (o `session_id` está no stdin de todo evento). Fail-open: a sessão do Claude nunca vê erro.
- Quem compartilha a regra: `SessionTerminator` continua com a própria checagem (`path.contains("claude")` antes de sinalizar). Não vale unificar agora: são decisões diferentes (sinalizar × esconder) e o diff cresceria sem ganho.

### Arquivos e código

**`Sources/ClaudeBarCore/SessionStatus.swift`**: remove `isAlive`. O único uso era o `readAll`.
```swift
-    /// `false` quando o processo do Claude morreu sem disparar o hook de saída.
-    public var isAlive: Bool {
-        guard pid > 0 else { return true }
-        return kill(pid, 0) == 0 || errno == EPERM
-    }
```

**`Sources/ClaudeBarCore/StatusDirectory.swift`**: `readAll` com diretório e regra injetados, e checagem de nome.
```swift
    /// Lê todas as sessões, apagando arquivos inválidos e os que `isAlive` dá
    /// como mortos.
    ///
    /// A regra de vida vem de fora porque depende de inspecionar processos, e o
    /// hook (que também usa este target) não precisa disso. `directory` existe
    /// para os testes usarem uma pasta temporária.
    public static func readAll(
        in directory: URL = url,
        isAlive: (SessionStatus) -> Bool
    ) -> [SessionStatus] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                // Nome que não bate com o `sessionId` (ou `unknown.json`, gravado
                // por hook antigo quando o payload falhava) não é de sessão nenhuma.
                guard let data = try? Data(contentsOf: file),
                      let status = try? decoder.decode(SessionStatus.self, from: data),
                      case let name = sanitize(status.sessionId),
                      name != "unknown",
                      file.lastPathComponent == "\(name).json"
                else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                guard isAlive(status) else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                return status
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
```
`sanitize("")` já devolve `"unknown"`, então a mesma linha pega id vazio.

**`Sources/ClaudeBar/ProcessProbe.swift`**: dois campos e a regra. O arquivo passa a importar `ClaudeBarCore`.
```swift
import ClaudeBarCore
import Darwin
import Foundation

struct ProcessProbe: Sendable {
    // … isGroupLeader e executablePath como hoje …

    /// `false` só quando o sistema garante que o PID não existe (`ESRCH`).
    /// `EPERM` conta como existente: há processo, só não é nosso.
    var exists: @Sendable (Int32) -> Bool = { _ in true }

    /// Quando o processo começou. `nil` = sem informação.
    var startTime: @Sendable (Int32) -> Date? = { _ in nil }

    static let live = ProcessProbe(
        isGroupLeader: { /* como hoje */ },
        executablePath: { /* como hoje */ },
        exists: { pid in
            kill(pid, 0) == 0 || errno != ESRCH
        },
        startTime: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        }
    )
}

extension ProcessProbe {
    /// O arquivo de um hook ainda descreve uma sessão viva?
    ///
    /// Conservador: só devolve `false` com prova de que o processo que gravou o
    /// arquivo não está mais lá. Sem informação, mantém — limpar demais esconde
    /// sessão real, e o CLI ainda pode tirar a linha no cruzamento.
    func isAlive(_ status: SessionStatus) -> Bool {
        // Sem PID não há o que provar aqui: quem decide é o CLI, no cruzamento.
        guard status.pid > 0 else { return true }
        guard exists(status.pid) else { return false }
        // Sem caminho (outro usuário, corrida com a saída): sem informação.
        guard let path = executablePath(status.pid) else { return true }
        // PID reciclado por outro programa.
        guard path.lowercased().contains("claude") else { return false }
        // PID reciclado por outro `claude`: quem gravou o arquivo nasceu antes
        // da gravação. A folga de 1 s cobre arredondamento de relógio.
        if let start = startTime(status.pid), start > status.updatedAt.addingTimeInterval(1) {
            return false
        }
        return true
    }
}
```

**`Sources/ClaudeBar/SessionMerge.swift`**: `agents` opcional e filtro das linhas só do hook.
```swift
    /// O CLI manda em *quais* sessões existem; o hook, quando presente, manda no
    /// *estado* daquela sessão. Sessão que só os hooks conhecem entra do mesmo
    /// jeito, com duas exceções quando o CLI já respondeu (`agents != nil`):
    /// - `pid 0`: sem processo para conferir, o CLI é a única prova de vida;
    /// - PID que o CLI lista com outro `sessionId`: sobra de `/clear` ou
    ///   `/resume` cujo `SessionEnd` não rodou.
    ///
    /// `agents == nil` é "CLI ainda não respondeu": aí nada se esconde.
    static func rows(agents: [AgentSession]?, statuses: [SessionStatus]) -> [SessionRow] {
        let byId = Dictionary(statuses.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = agents ?? []
        let listedPids = Set(listed.compactMap(\.pid))

        var merged: [SessionRow] = listed.compactMap { agent in
            // … igual a hoje …
        }

        let known = Set(merged.map(\.sessionId))
        merged += statuses
            .filter { !known.contains($0.sessionId) }
            .filter { status in
                guard agents != nil else { return true }
                return status.pid > 0 && !listedPids.contains(status.pid)
            }
            .map { /* … igual a hoje … */ }
        // … ordenação igual …
    }
```
As chamadas atuais nos testes (`agents: []`, `agents: try decodeAgents()`) compilam sem mudança, por promoção implícita a opcional.

**`Sources/ClaudeBar/SessionStore.swift`**:
```swift
    /// Última lista devolvida pelo CLI. `nil` até a primeira consulta responder.
    private var agents: [AgentSession]?
    …
    func merge() {
        let merged = SessionMerge.rows(
            agents: agents,
            statuses: StatusDirectory.readAll(isAlive: ProcessProbe.live.isAlive)
        )
```
O `refreshAgents` atual não muda: falha do CLI mantém a última lista, como hoje.

**`Sources/claudebar-hook/main.swift`**:
```swift
    let payload = try? StatusDirectory.decoder.decode(HookPayload.self, from: stdinData)
    // Sem `session_id` não há de quem gravar o estado. Sai bem, sem arquivo: um
    // `unknown.json` juntaria sessões diferentes num só fantasma.
    guard let sessionId = payload?.sessionId, !sessionId.isEmpty else { return }
```

### Testes: `Tests/ClaudeBarTests/GhostSessionTests.swift` (novo, 12 `@Test`)
Mesmo padrão do `SessionTerminatorTests`: `ProcessProbe` falso por caso, mais um teste com processo real. Arquivo completo validado:

```swift
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
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(exists: false).isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }

    @Test func pidRecicladoPorOutroProgramaApaga() throws {
        let dir = try directory(with: [gravada])
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(path: "/usr/sbin/cron").isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }

    /// Outro `claude` herdou o PID: ele nasceu depois de o arquivo ser gravado.
    @Test func pidRecicladoPorOutroClaudeApaga() throws {
        let dir = try directory(with: [gravada])
        let depois = probe(start: Date())
        #expect(StatusDirectory.readAll(in: dir, isAlive: depois.isAlive).isEmpty)
    }

    @Test func claudeQueNasceuAntesDaGravacaoFica() throws {
        let dir = try directory(with: [gravada])
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe().isAlive).map(\.sessionId) == ["s1"])
        #expect(files(in: dir) == ["s1.json"])
    }

    /// Sem caminho nem horário (outro usuário, corrida com a saída): sem prova
    /// de morte, o arquivo fica.
    @Test func semInformacaoMantem() throws {
        let dir = try directory(with: [gravada])
        #expect(StatusDirectory.readAll(in: dir, isAlive: probe(path: nil, start: nil).isAlive).count == 1)
    }

    @Test func sessaoDoAppDesktopFica() throws {
        let dir = try directory(with: [gravada])
        let desktop = probe(path: "/Users/dev/Library/Application Support/Claude/claude-code/2.1.325/claude.app/Contents/MacOS/claude")
        #expect(StatusDirectory.readAll(in: dir, isAlive: desktop.isAlive).count == 1)
    }

    /// `pid 0` não tem processo para conferir: não sai do disco. Quem tira da
    /// lista é o cruzamento com o CLI.
    @Test func pidZeroNaoEhApagado() throws {
        let semPid = SessionStatus(sessionId: "s0", state: .working, cwd: "/x", pid: 0)
        let dir = try directory(with: [semPid])
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
        #expect(StatusDirectory.readAll(in: dir, isAlive: real.isAlive).count == 1)

        kill(pid, SIGKILL)
        process.waitUntilExit()
        #expect(ProcessProbe.live.exists(pid) == false)
        #expect(StatusDirectory.readAll(in: dir, isAlive: real.isAlive).isEmpty)
        #expect(files(in: dir).isEmpty)
    }
}
```
Armadilha já resolvida: comparar `SessionStatus` inteiro depois do round-trip pelo disco falha, porque `updatedAt` perde precisão em `secondsSince1970`. Compare `sessionId`.

O hook é target executável (`main.swift` com código no topo), então os testes não importam ele. O comportamento sem `session_id` é conferido na verificação manual.

### Scripts / README (`README.md` e `README.pt-BR.md`)
- "How it works" → "Duas decisões…" → **PID gravado junto**: trocar "o app checa `kill(pid, 0)`" pela regra. O arquivo é apagado quando o processo morreu, quando o PID virou outro programa ou quando virou outro `claude` que nasceu depois da gravação. Sem informação, fica. `pid 0` só some da lista quando o CLI responde sem aquela sessão.
- **Development**: o exemplo `… working --pid 1` deixa de funcionar, porque o PID 1 é o `launchd` e o arquivo é apagado na hora. Trocar por um que mude o estado de uma sessão real:
  ```bash
  # muda o estado de uma sessão real (a primeira do CLI com pid)
  s=$(claude agents --json | jq -c '[.[] | select(.pid)][0]')
  echo "$s" | jq -c '{session_id: .sessionId, cwd}' | \
    build/ClaudeBar.app/Contents/MacOS/claudebar-hook waiting --pid "$(echo "$s" | jq .pid)"
  ```
- Hook CLI usage: "sem `session_id` no stdin, não grava nada e sai 0".

### Verificação manual
Antes, **saia do ClaudeBar instalado** (`pkill -f ClaudeBar.app`). O app antigo apaga e reescreve arquivos ao mesmo tempo, como já se viu em G06.
1. `./scripts/build-app.sh && open build/ClaudeBar.app`.
2. **PID reciclado por outro programa:** `sleep 600 &`, depois grave à mão `~/.claude/claudebar/teste-fantasma.json` com `"sessionId":"teste-fantasma"`, o `pid` do `sleep` e o `updatedAt` atual (formato do README). O arquivo some em < 1 s (watcher → `merge`).
3. **`pid 0`:** `echo '{"session_id":"teste-pid0","cwd":"/tmp"}' | build/ClaudeBar.app/Contents/MacOS/claudebar-hook working` (sem `--pid`). O arquivo fica e a linha **não** aparece no menu depois da primeira resposta do CLI. Apague o arquivo à mão.
4. **Payload quebrado:** `echo lixo | …/claudebar-hook working --pid 1; echo $?` → `0`, e nenhum `unknown.json`.
5. **Morte sem hook:** abra `claude` num terminal, mande um prompt, e `kill -9 <pid>` (pegue o PID no submenu "Finalizar sessão (kill N)"). A linha some em ≤ 5 s com F06 (polling atual) e em < 1 s com F08.
6. **Sessão do app desktop** aberta: continua listada (o caminho `…/claude.app/Contents/MacOS/claude` contém `claude`).
7. `log show --last 5m --predicate 'subsystem == "com.joaomarcos.claudebar"'` sem erro novo.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Apagar sessão real (limpar demais) | Só três provas apagam: `ESRCH`, caminho sem `claude` e início depois da gravação. `nil` em qualquer sonda mantém. `pid 0` e sobra de `/clear` só são **escondidos**. Testes `semInformacaoMantem`, `sessaoDoAppDesktopFica` e `pidZeroNaoEhApagado` |
| Relógio ajustado para trás (NTP) depois da gravação faz o início parecer posterior | Folga de 1 s. Num ajuste maior, o arquivo é apagado e a sessão continua na lista pelo CLI. O próximo hook regrava |
| `$PPID` deixar de ser o `claude` numa versão futura | O arquivo é apagado (caminho sem `claude`) e o estado cai para o do CLI (`idle`/`waiting`/nenhum). Sem fantasma, só perde precisão. A verificação manual 5 pega isso |
| Linha escondida por PID listado com outro id, mas o CLI estava atrasado | Só esconde. O watcher chama `merge` a cada evento e o CLI é consultado de novo em ≤ 5 s (F06) / ≤ 2 s (F08) |
| App antigo × hook novo, ou o contrário | Formato do JSON igual. Hook novo só deixa de gravar `unknown.json`. App novo apaga `unknown.json` antigo |
| `fail()` no hook sai com **exit 2**, que para `UserPromptSubmit` **bloqueia o prompt** | Fora do escopo (só acontece com argumento inválido, que vem do `install.sh`). Registrar para F02/F07: trocar por exit 0 com log |

### Critérios de aceite
- `swift build` sem avisos. `swift test` com 46 testes passando: os 34 atuais **sem alteração** e os 12 novos.
- Neutralizar qualquer uma das três provas em `isAlive` faz ao menos um teste novo falhar.
- `grep -rn "CLAUDE_SESSION_ID\|\"unknown\"" Sources/claudebar-hook` sem resultado.
- `SessionStatus` não tem mais `isAlive`. `readAll` tem um único chamador no app.
- Verificação manual 2–6 conferida (ou marcada "não verificado" no PR).

### O que NÃO fazer
- Não ler `~/.claude/sessions/*.json` (formato interno não documentado).
- Não apagar arquivo de `pid 0` nem aplicar TTL por idade.
- Não sinalizar processo nenhum: F06 só lê o estado de processos e apaga arquivos do próprio diretório.
- Não mudar o formato do JSON nem gravar `procStart`.
- Não mexer na checagem do `SessionTerminator`.

---

## F08: polling leve

### Objetivo
Chamar `claude agents --json` ~10× menos (de 17.280/dia para ~1.000–2.000/dia) **sem** o menu ficar mais lento para refletir sessão aberta, fechada ou morta. Base medida: cada chamada custa ~0,15 s de CPU e ~160 MB de pico. Hoje isso soma ~43–55 min de CPU por dia, e o alvo é ~5 min.

### Decisão técnica e por quê
Quatro gatilhos, cada um cobrindo o que os outros não veem:

| Gatilho | Mecanismo | Cobre |
|---|---|---|
| Arquivo de hook muda | `DirectoryWatcher` (já existe) → `merge()` + `refreshAgents()` | Estado instantâneo. Sessão nova (`SessionStart`), sessão encerrada (`SessionEnd`), `/clear` |
| Processo sai | **`ProcessExitWatcher`** novo: `DispatchSource.makeProcessSource(.exit)` por PID das linhas → `merge()` + `refreshAgents()` | `kill -9`, crash, terminal fechado (nenhum hook roda) |
| Lista do CLI envelhece | No `merge()`, linha do CLI cujo `pid` dá `ESRCH` sai na hora | Fantasma vindo da lista guardada em memória (até 60 s de idade) |
| Nada aconteceu | `Timer` de **60 s**, `tolerance = 6` | Sessão aberta antes de os hooks existirem e agente background sem `pid` |

- **Throttle no `refreshAgents`:** uma consulta por vez, no máximo uma a cada 2 s. Pedido dentro da janela vira **uma** consulta no fim dela e não se perde. Isso evita a rajada `merge → readAll apaga → watcher → refresh`. `@MainActor`, então sem lock.
  - Descartada: consultar só quando o *conjunto* de ids muda. Seria mais preciso, mas o watcher não diz o que mudou e o throttle já limita a ~1 por evento.
  - Descartada: `force:` para pular o throttle. Nenhum gatilho precisa de menos de 2 s, porque o `merge()` local já tira a linha morta na hora.
- **`ProcessExitWatcher` é um tipo próprio**, espelhando o `DirectoryWatcher`: guarda as fontes (fonte não retida morre), cancela as que saíram e dá para testar com processo real.
  - Descartada: dicionário de fontes solto no `SessionStore`. Daria para testar só subindo o store inteiro, com CLI de verdade.
- **O evento `.exit` só pede recálculo**, como faz o VibeBar. Quem decide é a regra de F06.
- **`SessionStart` (matcher `startup|resume|clear`) grava `idle`.** Sem ele, sessão aberta e sem prompt levaria até 60 s para aparecer no número (hoje leva ≤ 5 s). O `compact` fica de fora: o auto-compact acontece **no meio** do turno, e gravar `idle` ali dispararia um "Claude terminou" falso.
- **Uma linha de log por consulta** (`Logger`, categoria `agents`). É o contador de spawns para medir antes e depois, sem código de métrica.
- **60 s + tolerância de 10%:** é o mínimo que o guia de energia da Apple pede. Com o menu aberto o timer não dispara (runloop em tracking), o que aqui é desejável.
  - Descartada: 30 s. Dobra o custo e o polling já não carrega a latência de nada importante.

### Arquivos e código

**`Sources/ClaudeBar/ProcessExitWatcher.swift`** (novo):
```swift
import Foundation

/// Avisa quando algum dos processos observados termina — inclusive por
/// `kill -9`, crash ou terminal fechado, quando nenhum hook roda.
///
/// O aviso só pede um recálculo: quem decide se a sessão morreu é
/// `ProcessProbe.isAlive`, no `merge()`.
final class ProcessExitWatcher {
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private let queue: DispatchQueue
    private let onExit: @Sendable () -> Void

    init(queue: DispatchQueue = .main, onExit: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onExit = onExit
    }

    /// Passa a observar exatamente estes PIDs: cria fonte para quem entrou e
    /// cancela a de quem saiu. `pid <= 0` é ignorado.
    func watch(_ pids: Set<Int32>) {
        for (pid, source) in sources where !pids.contains(pid) {
            source.cancel()
            sources[pid] = nil
        }
        for pid in pids where pid > 0 && sources[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler(handler: onExit)
            source.resume()
            sources[pid] = source
        }
    }

    deinit {
        sources.values.forEach { $0.cancel() }
    }
}
```

**`Sources/ClaudeBar/SessionStore.swift`** (sobre o F06):
```swift
    private var watcher: DirectoryWatcher?
    private var exitWatcher: ProcessExitWatcher?
    private var pollTimer: Timer?
    /// Uma consulta ao CLI por vez, e no máximo uma a cada `minProbeInterval`.
    private var probing = false
    private var trailingRefresh = false
    private var lastProbe = Date.distantPast
    private static let minProbeInterval: TimeInterval = 2

    /// Recalcula as linhas a partir das duas origens já em memória/disco.
    func merge() {
        let probe = ProcessProbe.live
        // A lista do CLI pode ter até um minuto: sessão cujo processo já não
        // existe sai agora, sem esperar a próxima consulta.
        let current = agents?.filter { agent in agent.pid.map(probe.exists) ?? true }
        let merged = SessionMerge.rows(agents: current, statuses: StatusDirectory.readAll(isAlive: probe.isAlive))

        notifyTransitions(in: merged)

        acknowledged.formIntersection(Set(merged.map(\.sessionId)))
        previousStates = Dictionary(uniqueKeysWithValues: merged.map { ($0.sessionId, $0.state) })
        rows = merged
        exitWatcher?.watch(Set(merged.compactMap(\.pid)))
    }

    /// Pergunta ao CLI quais sessões existem e recalcula as linhas.
    ///
    /// Cada consulta custa ~0,15 s de CPU e ~160 MB de pico. Pedido feito com
    /// uma consulta em andamento ou dentro da janela mínima não se perde: vira
    /// uma única consulta no fim da janela.
    func refreshAgents() {
        guard !probing, Date().timeIntervalSince(lastProbe) >= Self.minProbeInterval else {
            guard !trailingRefresh else { return }
            trailingRefresh = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.minProbeInterval))
                self?.trailingRefresh = false
                self?.refreshAgents()
            }
            return
        }

        probing = true
        lastProbe = Date()
        Task.detached(priority: .utility) {
            let probed = AgentsProbe.probe()
            await MainActor.run {
                if let probed {
                    self.agents = probed.filter { $0.sessionId != nil }
                }
                self.probing = false
                self.merge()
            }
        }
    }

    private func startWatching() {
        // Mudança de estado: chega em milissegundos, direto do hook. Arquivo
        // novo ou apagado (`SessionStart`, `SessionEnd`) também muda a lista,
        // então o CLI é consultado — com o limite de `refreshAgents`.
        watcher = DirectoryWatcher(url: StatusDirectory.url) { [weak self] in
            Task { @MainActor in
                self?.merge()
                self?.refreshAgents()
            }
        }

        // Sessão que morreu sem hook (kill -9, crash, terminal fechado): o
        // sistema avisa na hora, sem esperar o polling.
        exitWatcher = ProcessExitWatcher { [weak self] in
            Task { @MainActor in
                self?.merge()
                self?.refreshAgents()
            }
        }

        // Rede de segurança para o que nenhum evento vê: sessão aberta antes de
        // os hooks existirem e agente background sem `pid`. Tolerância de 10%
        // deixa o sistema agrupar o disparo com outros (guia de energia da Apple).
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAgents() }
        }
        timer.tolerance = 6
        pollTimer = timer
    }
```
O `init` fica como está (`merge()`, `startWatching()`, `refreshAgents()`). O primeiro `merge()` roda com `exitWatcher == nil`, e as fontes nascem no `merge()` que fecha a primeira consulta, ~150 ms depois. Isso é aceitável, porque processo que morre nesse meio tempo é pego pelo filtro de `exists`. Não há `deinit` no store: ele vive o app inteiro e o `ProcessExitWatcher` cancela as próprias fontes.

**`Sources/ClaudeBar/AgentsProbe.swift`**: contador.
```swift
import OSLog
…
enum AgentsProbe {
    /// Uma linha por consulta, para medir quantas vezes o CLI é chamado:
    /// `log stream --level info --predicate 'subsystem == "com.joaomarcos.claudebar" AND category == "agents"'`
    private static let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "agents")
    …
    static func probe() -> [AgentSession]? {
        log.info("claude agents --json")
        guard let executableURL, …
```

**`scripts/install.sh`**: uma entrada a mais, com matcher (saída do `jq` conferida):
```bash
jq --arg hook "$HOOK" '
  def entry($state): [{ hooks: [{ type: "command", command: ($hook + " " + $state + " --pid $PPID") }] }];
  .hooks = ((.hooks // {}) + {
    SessionStart: [entry("idle")[0] + { matcher: "startup|resume|clear" }],
    UserPromptSubmit: entry("working"),
    Stop: entry("idle"),
    Notification: entry("waiting"),
    SessionEnd: entry("end")
  })
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```
Se o F02 já tiver trocado o mecanismo de instalação, a mesma entrada vai lá.

### Testes: `Tests/ClaudeBarTests/ProcessExitWatcherTests.swift` (novo, 3 `@Test`, processo real)
```swift
import Foundation
import Testing

@testable import ClaudeBar

@Suite("Aviso de saída de processo")
struct ProcessExitWatcherTests {
    private func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    @Test func avisaQuandoOProcessoMorre() throws {
        let process = try sleeper()
        defer { if process.isRunning { process.terminate() } }
        let avisou = DispatchSemaphore(value: 0)
        let watcher = ProcessExitWatcher(queue: .global()) { avisou.signal() }
        watcher.watch([process.processIdentifier])

        kill(process.processIdentifier, SIGKILL)
        #expect(avisou.wait(timeout: .now() + 2) == .success)
    }

    /// PID que saiu da lista não avisa mais: a fonte foi cancelada.
    @Test func pidRemovidoNaoAvisa() throws {
        let process = try sleeper()
        defer { if process.isRunning { process.terminate() } }
        let avisou = DispatchSemaphore(value: 0)
        let watcher = ProcessExitWatcher(queue: .global()) { avisou.signal() }
        watcher.watch([process.processIdentifier])
        watcher.watch([])

        kill(process.processIdentifier, SIGKILL)
        #expect(avisou.wait(timeout: .now() + 0.5) == .timedOut)
    }

    /// A doc não diz o que acontece com PID que morreu antes de a fonte nascer.
    /// Medido: o libdispatch avisa na hora — a sessão não fica presa até o polling.
    @Test func pidJaMortoAvisaAoObservar() throws {
        let process = try sleeper()
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        let avisou = DispatchSemaphore(value: 0)
        let watcher = ProcessExitWatcher(queue: .global()) { avisou.signal() }
        watcher.watch([process.processIdentifier])
        #expect(avisou.wait(timeout: .now() + 2) == .success)
    }
}
```
O throttle não tem teste unitário: ele vive no `SessionStore` (`@MainActor`, chama o CLI de verdade), e extrair isso para testar seria abstração só para o teste. Ele é coberto pela medição (critério de aceite).

### Scripts / README (`README.md` e `README.pt-BR.md`)
- Diagrama de "How it works": `(polled every 5 s, ~150 ms per call)` → `(on hook events, on process exit and every 60 s; ≤ 1 call / 2 s)`.
- Parágrafo do `claude agents --json`: tirar "polled every 5 seconds". Dizer que ele é consultado quando um hook grava, quando um processo de sessão termina e a cada 60 s, e que a saída de processo é observada pelo sistema (`DispatchSource`). Uma sessão morta some na hora, sem esperar o polling.
- Tabela de hooks: nova linha `SessionStart` (`startup`, `resume`, `clear`) → `idle`.
- Installation: "registers the **five** hooks" e a lista de hooks substituídos inclui `SessionStart`. Uninstall: "the five `claudebar-hook` entries".
- Debug: o comando `log stream … category == "agents"` para contar consultas.

### Verificação manual
Saia do ClaudeBar instalado antes.
1. **Medição antes:** no `main`, `./scripts/build-app.sh`, depois `/usr/bin/time -l build/ClaudeBar.app/Contents/MacOS/ClaudeBar` com 2 sessões abertas e sem uso por 10 min. Encerre com `pkill -TERM -f 'build/ClaudeBar.app/Contents/MacOS/ClaudeBar'` e anote user+sys e o RSS máximo. **Não** use `instructions retired`, que não soma os filhos.
2. **Medição depois:** o mesmo no branch, com `log stream --level info --predicate 'subsystem == "com.joaomarcos.claudebar" AND category == "agents"' | grep -c "claude agents"` rodando ao lado.
3. **Sessão nova sem prompt** (com hooks reinstalados pelo `install.sh` do branch): abra `claude` num terminal. O número na barra sobe em < 1 s (`SessionStart` → watcher), sem esperar 60 s.
4. **`kill -9`** numa sessão de terminal: a linha some em < 1 s.
5. **Fechar a aba do terminal** com sessão aberta: some em < 1 s.
6. **`/clear`** numa sessão: a linha antiga não fica duplicada com a nova por mais de ~2 s.
7. **`/compact`** com a sessão trabalhando: **não** toca "Claude terminou" (matcher sem `compact`).
8. **Sessão aberta antes de instalar os hooks:** aparece em ≤ 60 s.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Sessão aberta sem hook demorar até 60 s para aparecer | `SessionStart` cobre toda sessão nova com os hooks instalados. Só sessão anterior à instalação depende do timer |
| Fantasma esperar o polling (o risco citado no backlog) | Fonte `.exit` (inclusive em PID já morto, testado) mais o filtro `exists` em todo `merge()`. O polling já não carrega a latência de morte |
| Rajada de consultas (watcher dispara nas remoções do próprio `readAll`) | No máximo 1 consulta a cada 2 s, uma por vez, com consulta final. No pior caso contínuo (≥ 0,5 evento/s) o custo é de 0,5 Hz, ainda ~2,5× abaixo dos 5 s de hoje. O critério de aceite mede |
| Matcher do `SessionStart` ignorado numa versão do Claude Code (`compact` gravaria `idle` no meio do turno) | Verificação manual 7. Se falhar: tirar o `SessionStart` e aceitar ≤ 60 s para sessão nova sem prompt |
| `SessionStart` em sessão nova acende o ✅ "pronto (não visto)" | É o comportamento **atual** para sessão `idle` vinda do CLI, ou seja, não é regressão. Registrar como possível ajuste à parte (fora de F08) |
| Fontes de processo vazando | O conjunto observado é exatamente o das linhas (`watch` cancela quem saiu). Teste `pidRemovidoNaoAvisa` |
| Menu aberto: fila main parada | Medido. Watcher, `.exit` e o fim da consulta rodam ao fechar o menu, e nada se perde |

### Critérios de aceite
- `swift build` sem avisos. `swift test` com 49 testes (46 do F06 + 3), os anteriores sem alteração.
- Consultas ao CLI em 10 min com 2 sessões ociosas: **≤ 15** (hoje ≈ 120). Com uso normal (prompts), ≤ 1 a cada 2 s em qualquer janela.
- user+sys do app (com filhos) em 10 min ociosos: **≤ 1/5 do `main`** na mesma máquina. Registrar os números no PR.
- Verificação manual 3–7 conferida (ou marcada "não verificado" no PR, com o motivo).
- `scripts/install.sh` produz `SessionStart` com `"matcher": "startup|resume|clear"` e mantém os outros hooks.

### O que NÃO fazer
- **Não** registrar `NSMenu.didBeginTrackingNotification` para consultar ao abrir o menu. Medido: a notificação dispara, mas `Task { @MainActor }` e `DispatchQueue.main` só rodam **depois** que o menu fecha, e o conteúdo SwiftUI não se atualiza com o menu aberto. A consulta chegaria tarde para aquela abertura. Também não buscar contorno: consulta síncrona atrasaria a abertura em ~150 ms, e `RunLoop.perform(.common)` não resolve o redesenho do SwiftUI.
- Não usar MenuBarExtraAccess nem trocar para `.menuBarExtraStyle(.window)`.
- Não ler `~/.claude/sessions/*.json` como atalho para a lista (formato interno não documentado). Reavaliar só como opt-in com fallback para o CLI.
- Não usar a statusline como heartbeat.
- Não registrar `SessionStart` para `compact`.
- Não baixar o timer abaixo de 60 s sem medição que justifique.
