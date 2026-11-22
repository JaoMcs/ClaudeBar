# T22 — CLI `claudebar-hook status` / `next`

- **Funcionalidade:** F26 — spec [G07, F26](../05-specs/G07-ir-para-sessao.md)
- **Épico:** Navegação · **Prioridade:** P2 (inovação) · **Esforço:** 1,5 h
- **Depende de:** T19 (`SessionNavigator` no Core), T08 (`readAll(in:isAlive:)`) · **Bloqueia:** T28 (mesmo `main.swift`)
- **Branch:** `feat/cli-status-next`
- **PR:** `feat: comandos status e next no claudebar-hook`

## Objetivo

Sem abrir o menu:
- `claudebar-hook status [--json]`: uma sessão por linha, `estado<TAB>projeto<TAB>pasta`; `--json` no formato dos arquivos de estado. Para a barra do tmux, scripts e leitor de tela.
- `claudebar-hook next`: traz para a frente a sessão que espera você há mais tempo. Sai 1 se não houver.

Nenhuma ação destrutiva.

## Ajuste sobre a spec

Depois do T08, `readAll` exige `isAlive`, e o `ProcessProbe` mora no app. No CLI, só a prova mais forte:

```swift
/// Sem `ProcessProbe` (é do app): só apaga arquivo de processo que não existe mais.
private func readSessions() -> [SessionStatus] {
    StatusDirectory.readAll { $0.pid <= 0 || kill($0.pid, 0) == 0 || errno != ESRCH }
}
```

## Subtasks

- [ ] `main.swift`: `printStatus(json:)` e `goToNextWaiting()` (`@MainActor`, `async`).
- [ ] Despacho: `status` junto de `install`/`uninstall` no `switch` antes de ler o stdin; `next` no top-level com `await` (Swift 6: top-level é `@MainActor`).
- [ ] Comentário de uso atualizado.
- [ ] Verificação manual 1–5 da spec (stdin num tty não trava; `--json | jq .`; `next` sem sessão → 1; com sessão esperando → traz o terminal; hook continua gravando).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`Sources/claudebar-hook/main.swift`, READMEs.

## Código-chave (da spec)

```swift
private func printStatus(json: Bool) {
    let sessions = readSessions()
    if json {
        let data = (try? StatusDirectory.encoder.encode(sessions)) ?? Data("[]".utf8)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        return
    }
    for session in sessions {
        print("\(session.state.rawValue)\t\(session.projectName)\t\(session.cwd)")
    }
}

@MainActor
private func goToNextWaiting() async -> Int32 {
    let waiting = readSessions()
        .filter { $0.state == .waiting && $0.pid > 0 }
        .min { $0.updatedAt < $1.updatedAt }
    guard let waiting else { print("nenhuma sessão esperando você"); return 1 }
    guard let app = SessionNavigator.app(for: waiting.pid), await SessionNavigator.bringToFront(app) else {
        print("não achei o app de \(waiting.projectName) (\(waiting.cwd))")
        return 1
    }
    print(waiting.projectName)
    return 0
}

// `status` e `next` são digitados por você: o stdin é o terminal e nunca chega
// EOF. Por isso são tratados antes de `run()`, que lê o stdin inteiro.
if CommandLine.arguments.dropFirst().first == "next" {
    exit(await goToNextWaiting())
}
run()   // `run()` trata install/uninstall/status antes de ler o stdin
```

## Testes obrigatórios

Nenhum teste automatizado novo (filtro + `min` sobre `readAll`; o navegador já é testado no T19). Não escrever teste que grave no `~/.claude/claudebar` real. A verificação por execução é obrigatória:

```bash
H=build/ClaudeBar.app/Contents/MacOS/claudebar-hook
$H status                 # responde na hora, sem Ctrl-D
$H status --json | jq .   # array válido
$H next; echo $?          # sem sessão esperando: mensagem e 1
```

## Critérios de aceite

- `status`/`status --json`/`next` não leem stdin e respondem em < 1 s com stdin num tty.
- `--json` decodifica como `[SessionStatus]` com `StatusDirectory.decoder`.
- Caminho `working|idle|waiting|error|end` sem diff de comportamento.
- Nenhuma escrita nova em disco; só remove arquivo de processo que não existe (`ESRCH`).

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

"Hook CLI usage" com as três formas; subseção curta "Command line" com alias e o exemplo da barra do tmux (`status | grep -c ^waiting`); aviso: `status` só vê sessões que já dispararam hook. Usar o caminho estável `~/.claude/claudebar/bin/claudebar-hook` nos exemplos.

## Riscos

| Risco | Mitigação |
|---|---|
| Ativação a partir de CLI recusada | `bringToFront` cai no `openApplication`; se o passo 4 falhar, PR próprio para `/usr/bin/open -b` |
| `next` no tmux troca pane | é o pedido explícito; documentado |

## Fora do escopo

Comando que finalize/aprove sessão (F46); binário novo; symlink em `PATH`; `claude agents` ou rede na CLI; atalho global (F34).
