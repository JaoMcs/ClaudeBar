# T11 — "Testar integração" ponta a ponta + `Shell` com prazo

- **Funcionalidade:** F17 — spec [G03, F17](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P1 · **Esforço:** 2 h
- **Depende de:** T10, T08 (`readAll(isAlive:)`) · **Bloqueia:** T19 (move o `Shell` com os parâmetros novos)
- **Branch:** `feat/testar-integracao`
- **PR:** `feat: testar integração ponta a ponta pelo menu`

## Objetivo

Um clique responde "por que o ícone não muda?": hooks registrados, executável presente e igual ao do app, o hook **roda de verdade e grava**, último evento recebido, dica de pasta não confiada e `disableAllHooks`. Termina mostrando o popup de exemplo. `Shell.output` ganha `input` e `timeout`, para um hook travado (ex.: em quarentena) não congelar a main.

## Subtasks

- [ ] `Sources/ClaudeBar/Shell.swift`: versão completa da spec (`input`, `timeout`, `kill(pid, SIGTERM)` agendado, `F_SETNOSIGPIPE`). Chamadores atuais não mudam (parâmetros com padrão).
- [ ] `HookSetup`: `selfTest(openSessions:)` e `check(_:_:)`.
- [ ] **Ajuste sobre a spec:** o "último evento" usa `StatusDirectory.readAll(isAlive: ProcessProbe.live.isAlive)` (assinatura de T08).
- [ ] `MenuContent`: no fim do `integrationMenu`, `Divider()` + "Testar integração".
- [ ] `ShellTimeoutTests` (2) em `SessionTerminatorTests.swift`.
- [ ] Verificação manual 1–5 da spec (inclui quarentena: volta em ~3 s com ✗, app não congela).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/Shell.swift` | `input`, `timeout` |
| `Sources/ClaudeBar/HookSetup.swift` | `selfTest` |
| `Sources/ClaudeBar/MenuContent.swift` | item |
| `Tests/ClaudeBarTests/SessionTerminatorTests.swift` | `ShellTimeoutTests` |
| READMEs | o que é checado |

## Código-chave (da spec)

```swift
    static func output(of url: URL, arguments: [String], input: Data? = nil,
                       timeout: TimeInterval? = nil) -> String? {
        let process = Process()
        let pipe = Pipe()
        let stdin = Pipe()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if input != nil { process.standardInput = stdin }
        do { try process.run() } catch { return nil }

        let pid = process.processIdentifier
        let deadline = DispatchWorkItem { _ = kill(pid, SIGTERM) }
        if let timeout { DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline) }
        defer { deadline.cancel() }

        if let input {
            let handle = stdin.fileHandleForWriting
            // Filho que morreu cedo não pode derrubar o app com SIGPIPE.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? handle.write(contentsOf: input)
            try? handle.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
```

```swift
    func selfTest(openSessions: Int) {
        refresh()
        let manager = FileManager.default
        let hook = HookInstaller.stableBinary
        let id = "claudebar-selftest"
        let payload = Data(#"{"session_id":"\#(id)","cwd":"/"}"#.utf8)
        // `--pid 0`: o arquivo de teste não depende de processo vivo.
        let ran = Shell.output(of: hook, arguments: ["waiting", "--pid", "0"], input: payload, timeout: 3) != nil
        let wrote = manager.fileExists(atPath: StatusDirectory.fileURL(sessionId: id).path)
        _ = Shell.output(of: hook, arguments: ["end"], input: payload, timeout: 3)
        var lines = [
            check(state != .notInstalled && state != .legacyHooks && state != .hooksOutdated, "Hooks registrados no settings.json"),
            check(manager.isExecutableFile(atPath: hook.path), "Executável em \(hook.path)"),
            check(state != .binaryOutdated, "Executável igual ao deste app"),
            check(ran && wrote, "O hook rodou e gravou o estado"),
        ]
        // … hooksDisabled, último evento (readAll(isAlive: ProcessProbe.live.isAlive),
        //   sem o selftest) e a dica de workspace trust, como na spec …
        report(title: "Teste da integração", message: lines.joined(separator: "\n"))
    }
```

Menu:

```swift
            Divider()
            Button("Testar integração") {
                setup.selfTest(openSessions: store.openSessionCount)
                store.notifier.showSample()
            }
```

## Testes obrigatórios

```swift
@Suite("Shell com prazo")
struct ShellTimeoutTests {
    @Test func filhoTravadoEhEncerrado() {
        let inicio = Date()
        #expect(Shell.output(of: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(inicio) < 5)
    }

    @Test func stdinChegaAoFilho() {
        let saida = Shell.output(of: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("oi".utf8), timeout: 5)
        #expect(saida == "oi")
    }
}
```

`selfTest` não tem teste automatizado (escreveria no `~/.claude/claudebar` real).

## Critérios de aceite

- "Testar integração" nunca bloqueia o app por mais de ~6 s.
- ✓/✗ para: hooks registrados, executável presente, executável igual ao do app, hook rodou e gravou.
- Sem evento + sessões abertas → dica de workspace trust e `disableAllHooks`/`/hooks`.
- Nenhum `claudebar-selftest.json` sobra.
- `swift test` = anterior + 2.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Menu → "Testar integração": o que é checado; o que não dá para ver daqui (`disableAllHooks` em settings de projeto, `allowManagedHooksOnly`) → conferir `/hooks` no Claude Code; a pasta precisa estar confiada.

## Riscos

| Risco | Mitigação |
|---|---|
| Hook travado congela o app | `timeout: 3` + teste |
| Linha `claudebar-selftest` piscando no menu | `--pid 0` (escondida pelo cruzamento do T08) + `end` logo depois |
| `SIGPIPE` | `F_SETNOSIGPIPE` |

## Fora do escopo

Ler `~/.claude/debug/*` ou transcript; chamar `claude` para testar; ler settings de projeto/managed; checar o `statusLine` (vem com T30, se couber em uma linha).
