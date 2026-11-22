# T08 — Sessões fantasmas: regra de vida conservadora

- **Funcionalidade:** F06 — spec [G05, F06](../05-specs/G05-fantasmas-polling.md)
- **Épico:** Base/Bugs · **Prioridade:** P0 · **Esforço:** 3 h
- **Depende de:** T05 (`processExecutablePath` no Core, `main.swift` novo) · **Bloqueia:** T09, T11, T14, T22, T28
- **Branch:** `fix/sessoes-fantasmas`
- **PR:** `fix: sessões fantasmas com regra de vida conservadora`

## Objetivo

Nenhum arquivo de hook nem linha do menu sobrevive quando o processo que o gravou já não é aquela sessão (processo morto, PID reciclado por outro programa, PID reciclado por outro `claude`, `pid 0`, `unknown.json`). Regra **conservadora**: sem prova de morte, fica.

## Subtasks

- [ ] `SessionStatus.swift`: remover `isAlive`.
- [ ] `StatusDirectory.readAll(in: URL = url, isAlive: (SessionStatus) -> Bool)` + checagem de nome (`sanitize(sessionId).json`, rejeita `unknown`).
- [ ] `ProcessProbe`: campos `exists` (`ESRCH`) e `startTime` (`proc_pidinfo` + `PROC_PIDTBSDINFO`), com padrão "sem informação"; extensão `isAlive(_:)`.
- [ ] `SessionMerge.rows(agents: [AgentSession]?, …)`: com CLI respondido, linha só do hook some se `pid <= 0` ou se o CLI lista o PID com outro `sessionId`.
- [ ] `SessionStore`: `agents: [AgentSession]?` e `readAll(isAlive: ProcessProbe.live.isAlive)`.
- [ ] `main.swift`: sem `session_id` sai 0 sem gravar; remover `?? CLAUDE_SESSION_ID ?? "unknown"`.
- [ ] `GhostSessionTests.swift` (12 testes) da spec.
- [ ] Mutação: neutralizar cada uma das três provas → algum teste falha.
- [ ] Verificação manual 2–6 da spec (saia do ClaudeBar instalado antes).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/SessionStatus.swift` | sai `isAlive` |
| `Sources/ClaudeBarCore/StatusDirectory.swift` | `readAll(in:isAlive:)` |
| `Sources/ClaudeBar/ProcessProbe.swift` | `exists`, `startTime`, `isAlive` |
| `Sources/ClaudeBar/SessionMerge.swift` | `agents` opcional + filtro |
| `Sources/ClaudeBar/SessionStore.swift` | `agents?`, chamada do `readAll` |
| `Sources/claudebar-hook/main.swift` | guard de `session_id` |
| `Tests/ClaudeBarTests/GhostSessionTests.swift` | novo |
| READMEs | regra de vida, exemplo de Development |

## Código-chave (da spec)

```swift
extension ProcessProbe {
    /// Conservador: só devolve `false` com prova de que o processo que gravou o
    /// arquivo não está mais lá.
    func isAlive(_ status: SessionStatus) -> Bool {
        // Sem PID não há o que provar aqui: quem decide é o CLI, no cruzamento.
        guard status.pid > 0 else { return true }
        guard exists(status.pid) else { return false }
        // Sem caminho (outro usuário, corrida com a saída): sem informação.
        guard let path = executablePath(status.pid) else { return true }
        // PID reciclado por outro programa.
        guard path.lowercased().contains("claude") else { return false }
        // PID reciclado por outro `claude`: quem gravou nasceu antes da gravação.
        if let start = startTime(status.pid), start > status.updatedAt.addingTimeInterval(1) {
            return false
        }
        return true
    }
}

    // ProcessProbe.live
        exists: { pid in kill(pid, 0) == 0 || errno != ESRCH },
        startTime: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        }
```

`executablePath` do `live` continua `{ processExecutablePath($0) }` (T05). Campos novos com padrão `{ _ in true }` / `{ _ in nil }`: os `ProcessProbe(isGroupLeader:executablePath:)` dos testes atuais compilam sem mudança.

`readAll` (guard combinado da spec):

```swift
                guard let data = try? Data(contentsOf: file),
                      let status = try? decoder.decode(SessionStatus.self, from: data),
                      case let name = sanitize(status.sessionId),
                      name != "unknown",
                      file.lastPathComponent == "\(name).json"
                else { try? FileManager.default.removeItem(at: file); return nil }
                guard isAlive(status) else { try? FileManager.default.removeItem(at: file); return nil }
```

`SessionMerge.rows`, trecho novo:

```swift
        let listed = agents ?? []
        let listedPids = Set(listed.compactMap(\.pid))
        // … merged de `listed` igual a hoje …
        merged += statuses
            .filter { !known.contains($0.sessionId) }
            .filter { status in
                guard agents != nil else { return true }
                return status.pid > 0 && !listedPids.contains(status.pid)
            }
```

`main.swift`:

```swift
    // Sem `session_id` não há de quem gravar o estado. Sai bem, sem arquivo: um
    // `unknown.json` juntaria sessões diferentes num só fantasma.
    guard let sessionId = payload?.sessionId, !sessionId.isEmpty else { return }
```

## Testes obrigatórios

`GhostSessionTests.swift` completo da spec: `GhostFileTests` (8, incluindo o parametrizado), `GhostMergeTests` (3), `GhostLiveTests.processoQueMorreSaiDoDisco` (processo real `/bin/sleep`). Comparar `sessionId`, não o `SessionStatus` inteiro (precisão do `updatedAt`).

## Critérios de aceite

- Os testes atuais passam **sem alteração**; `swift test` = anterior + 12.
- Neutralizar qualquer uma das três provas em `isAlive` derruba ao menos um teste.
- `grep -rn 'CLAUDE_SESSION_ID\|"unknown"' Sources/claudebar-hook` vazio.
- `SessionStatus` sem `isAlive`; `readAll` com um único chamador no app.
- `echo lixo | claudebar-hook working; echo $?` → 0, nenhum `unknown.json`.

## Gates

`swift build`, `swift test` (3 rodadas sem flake), `./scripts/build-app.sh`.

## README (as duas línguas)

- "How it works" → PID gravado junto: o arquivo é apagado quando o processo morreu, quando o PID virou outro programa ou outro `claude` nascido depois da gravação; sem informação, fica; `pid 0` só some da lista quando o CLI responde sem a sessão.
- Development: trocar o exemplo `working --pid 1` (o PID 1 é o `launchd` e o arquivo some na hora) pelo exemplo com sessão real da spec.
- Hook CLI: sem `session_id` no stdin, não grava nada e sai 0.

## Riscos

| Risco | Mitigação |
|---|---|
| Apagar sessão real | só três provas apagam; `nil` em qualquer sonda mantém; `pid 0`/sobra de `/clear` só são escondidos |
| NTP volta o relógio | folga de 1 s; o CLI mantém a linha e o próximo hook regrava |
| `getppid()` (T05) deixar de ser o `claude` | o arquivo some (caminho sem `claude`) e o estado cai para o do CLI; sem fantasma |

## Fora do escopo

Ler `~/.claude/sessions/*.json`; TTL por idade; mudar o formato do JSON (`procStart`); mexer no `SessionTerminator`; polling (T14).
