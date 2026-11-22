# T14 — Polling leve: `.exit` por PID, throttle, 60 s, `SessionStart`

- **Funcionalidade:** F08 — spec [G05, F08](../05-specs/G05-fantasmas-polling.md)
- **Épico:** Base/Bugs · **Prioridade:** P1 (energia) · **Esforço:** 3,5 h (inclui 1 h de medição)
- **Depende de:** T08, T10 (texto do resumo da integração) · **Bloqueia:** —
- **Branch:** `feat/polling-leve`
- **PR:** `perf: consultar o claude agents por evento, não a cada 5 s`

## Objetivo

Chamar `claude agents --json` ~10× menos (hoje 17.280/dia, ~0,15 s de CPU e ~160 MB de pico cada) **sem** o menu demorar mais para refletir sessão aberta, fechada ou morta. Quatro gatilhos: arquivo de hook muda (watcher → `merge` + `refreshAgents`), processo sai (`DispatchSource` `.exit`), filtro de `ESRCH` em todo `merge`, e um timer de 60 s ± 6 s.

## Subtasks

- [ ] **Medição antes** (no `main`, 10 min ociosos com 2 sessões; `/usr/bin/time -l`, user+sys e RSS). Anotar.
- [ ] Criar `Sources/ClaudeBar/ProcessExitWatcher.swift`.
- [ ] `SessionStore`: `exitWatcher`, throttle (`probing`, `trailingRefresh`, `lastProbe`, 2 s), timer 60 s com `tolerance = 6`, filtro `exists` no `merge()`, `exitWatcher?.watch(...)` no fim do `merge()`; watcher do diretório chama `merge()` **e** `refreshAgents()`.
- [ ] `AgentsProbe`: `Logger` categoria `agents`, uma linha por consulta.
- [ ] `HookInstaller.entries`: `Entry(event: "SessionStart", matcher: "startup|resume|clear", args: ["idle"])` (timeout 5). **Sem** `compact`.
- [ ] `HookSetup.summary` (`.notInstalled`): trocar "de 5 em 5 s" por "a cada minuto".
- [ ] `ProcessExitWatcherTests` (3).
- [ ] **Medição depois** com `log stream … category == "agents" | grep -c` ao lado. Números no PR.
- [ ] Verificação manual 3–8 da spec.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/ProcessExitWatcher.swift` | novo |
| `Sources/ClaudeBar/SessionStore.swift` | throttle, gatilhos, timer |
| `Sources/ClaudeBar/AgentsProbe.swift` | log |
| `Sources/ClaudeBarCore/HookInstaller.swift` | `SessionStart` |
| `Sources/ClaudeBar/HookSetup.swift` | 1 string |
| `Tests/ClaudeBarTests/ProcessExitWatcherTests.swift` | novo |
| READMEs | diagrama, hooks, debug |

## Código-chave (da spec)

```swift
final class ProcessExitWatcher {
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private let queue: DispatchQueue
    private let onExit: @Sendable () -> Void

    init(queue: DispatchQueue = .main, onExit: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onExit = onExit
    }

    /// Passa a observar exatamente estes PIDs. `pid <= 0` é ignorado.
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

    deinit { sources.values.forEach { $0.cancel() } }
}
```

```swift
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
                if let probed { self.agents = probed.filter { $0.sessionId != nil } }
                self.probing = false
                self.merge()
            }
        }
    }
```

No `merge()`: `let current = agents?.filter { agent in agent.pid.map(probe.exists) ?? true }` antes do `SessionMerge.rows`, e `exitWatcher?.watch(Set(merged.compactMap(\.pid)))` no fim. Manter o resto do `merge()` como estiver em `main` (`notifyTransitions`, `previousStates`, `acknowledged`).

## Testes obrigatórios

`ProcessExitWatcherTests` da spec: `avisaQuandoOProcessoMorre`, `pidRemovidoNaoAvisa`, `pidJaMortoAvisaAoObservar` (processo real `/bin/sleep`). Throttle sem teste unitário: coberto pela medição.

## Critérios de aceite

- ≤ 15 consultas ao CLI em 10 min com 2 sessões ociosas (hoje ≈ 120); ≤ 1 a cada 2 s em uso.
- user+sys do app (com filhos) em 10 min ociosos ≤ 1/5 do `main`. Números no PR.
- `kill -9` numa sessão: some em < 1 s. Sessão nova sem prompt aparece em < 1 s (`SessionStart`). `/compact` não toca "terminou".
- `SessionStart` instalado com `"matcher": "startup|resume|clear"`, sem apagar outros hooks.
- `swift test` = anterior + 3.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Diagrama: `(polled every 5 s…)` → `(on hook events, on process exit and every 60 s; ≤ 1 call / 2 s)`. Parágrafo do `claude agents --json` sem "polled every 5 seconds". Tabela de hooks: `SessionStart` (`startup`, `resume`, `clear`) → `idle`. Debug: `log stream --level info --predicate 'subsystem == "com.joaomarcos.claudebar" AND category == "agents"'`.

## Riscos

| Risco | Mitigação |
|---|---|
| Sessão aberta antes dos hooks leva até 60 s | `SessionStart` cobre sessão nova; só a antiga depende do timer |
| Rajada `readAll` apaga → watcher → refresh | throttle 2 s com consulta final |
| Matcher do `SessionStart` ignorado (`compact` gravaria `idle`) | verificação 7; se falhar, tirar o `SessionStart` |
| Lembrete (T26) roda no `merge()`: com 60 s ele pode atrasar até 1 min | aceito para "5 min"; T26 documenta |

## Fora do escopo

Consultar ao abrir o menu (`NSMenu.didBeginTrackingNotification` — medido: chega tarde); MenuBarExtraAccess/`.window`; ler `~/.claude/sessions/*.json`; statusline como heartbeat; timer < 60 s.
