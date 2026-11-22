# T05 — `claudebar-hook install/uninstall`, `install.sh` sem `jq`, `uninstall.sh`, exit 1

- **Funcionalidades:** F02 parte 3 de 3; F03 (hooks apontam para o caminho estável) — spec [G03, F02](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P0 · **Esforço:** 1,5 h
- **Depende de:** T04 · **Bloqueia:** T06, T07, T08, T09, T12, T22, T28, T33
- **Branch:** `fix/hooks-install-sem-jq`
- **PR:** `fix: instalar hooks sem apagar os do usuário (claudebar-hook install)`

## Objetivo

Ligar o `HookInstaller` ao CLI e aos scripts:
- `claudebar-hook install|uninstall [--dry-run]` (antes de ler o stdin);
- hooks em **exec form** apontando para `~/.claude/claudebar/bin/claudebar-hook`;
- `install.sh` mostra a prévia, pergunta e não depende mais de `jq`; novo `uninstall.sh`;
- `fail` sai com **1**, nunca 2 (2 bloqueia o prompt no `UserPromptSubmit`);
- sem `--pid $PPID` (exec form não expande): `getppid()` só se o pai for mesmo `claude`.

## Subtasks

- [ ] `SessionStatus.swift` (Core): acrescentar `public func processExecutablePath(_ pid: Int32) -> String?`.
- [ ] `ProcessProbe.swift`: `import ClaudeBarCore` e `executablePath: { processExecutablePath($0) }`.
- [ ] `claudebar-hook/main.swift`: arquivo completo da spec (G03 linhas 445–560): `fail` → `exit(1)`, `parsePID` com `getppid()`, `manage(_:dryRun:)`, despacho de `install`/`uninstall` antes do `readDataToEndOfFile`.
- [ ] `scripts/install.sh` completo da spec (prévia + `read -r -p "Aplicar? [s/N]"` + `install`).
- [ ] `scripts/uninstall.sh` novo (`chmod +x`).
- [ ] Verificação manual 2–10 da spec (com backup próprio do `settings.json` antes). Registrar no PR o `pid` gravado no passo 6 (se vier 0, anotar: comportamento igual ao de hoje).
- [ ] README, README.pt-BR e `TODO.md` (marcar "Merge instead").
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/SessionStatus.swift` | `processExecutablePath` |
| `Sources/ClaudeBar/ProcessProbe.swift` | reusa o Core |
| `Sources/claudebar-hook/main.swift` | install/uninstall, exit 1, `getppid` |
| `scripts/install.sh` | sem `jq` |
| `scripts/uninstall.sh` | novo |
| `README.md`, `README.pt-BR.md`, `TODO.md` | instalação, requisitos, CLI, desinstalação |

## Código-chave (da spec)

```swift
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("claudebar-hook: \(message)\n".utf8))
    // 1, nunca 2: no Claude Code, exit 2 bloqueia o prompt (UserPromptSubmit)
    // e impede o Claude de parar (Stop). 1 é erro que não bloqueia nada.
    exit(1)
}

private func parsePID(_ arguments: [String]) -> Int32 {
    if let index = arguments.firstIndex(of: "--pid"),
       arguments.indices.contains(index + 1),
       let pid = Int32(arguments[index + 1]) {
        return pid
    }
    // Exec form não tem `$PPID`: o pai direto deve ser o Claude Code. Só
    // aceita se for mesmo um `claude`; senão 0 = "sem pid", como antes.
    let parent = getppid()
    let isClaude = processExecutablePath(parent)?.lowercased().contains("claude") == true
    return isClaude ? parent : 0
}

private func manage(_ action: HookAction, dryRun: Bool) {
    do {
        let plan = try HookInstaller.plan(action)
        print(plan.hasChanges ? plan.diff : "Nada a mudar em \(plan.settingsURL.path).")
        if plan.hasChanges, plan.reformats {
            print("\nO arquivo será reformatado (ordem das chaves); fora de \"hooks\" o conteúdo não muda.")
        }
        guard !dryRun else { return }
        if action == .install {
            // O próprio executável que está rodando vira a cópia estável.
            guard let me = processExecutablePath(getpid()) else { fail("executável não encontrado") }
            try HookInstaller.installBinary(from: URL(fileURLWithPath: me))
        }
        if plan.hasChanges, let backup = try HookInstaller.apply(plan) {
            print("Backup: \(backup.path)")
        }
        if action == .uninstall {
            try? FileManager.default.removeItem(at: HookInstaller.stableBinary)
        }
    } catch {
        fail(error.localizedDescription)
    }
}
```

Em `run()`, antes de ler o stdin:

```swift
    // Antes de ler o stdin: num terminal, ler o stdin travaria esperando EOF.
    switch command {
    case "install": return manage(.install, dryRun: arguments.contains("--dry-run"))
    case "uninstall": return manage(.uninstall, dryRun: arguments.contains("--dry-run"))
    default: break
    }
```

`scripts/uninstall.sh`:

```bash
#!/bin/bash
# Remove o ClaudeBar: tira só as entradas dele do settings.json (com backup),
# fecha o app e apaga o bundle. Estado e backups ficam em ~/.claude/claudebar.
set -euo pipefail

HOOK="$HOME/.claude/claudebar/bin/claudebar-hook"
[[ -x "$HOOK" ]] || HOOK="$HOME/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook"

"$HOOK" uninstall
pkill -x ClaudeBar || true
rm -rf "$HOME/Applications/ClaudeBar.app"

echo "Removido. Backups do settings.json em ~/.claude/claudebar/backups (apague à mão se quiser)."
```

## Testes obrigatórios

Os de T03/T04 continuam verdes. O `exit(1)` e o `install --dry-run` ficam na verificação manual (o target executável não é importável). Comandos mínimos:

```bash
./scripts/build-app.sh
H=build/ClaudeBar.app/Contents/MacOS/claudebar-hook
shasum ~/.claude/settings.json; $H install --dry-run; shasum ~/.claude/settings.json   # iguais
echo '{}' | $H bogus; echo $?        # 1
$H; echo $?                          # 1
```

## Critérios de aceite

- `grep -rn jq scripts/` vazio.
- `install` com hook do usuário no mesmo grupo preserva o hook (passo manual 4 da spec).
- Hooks registrados apontam para `~/.claude/claudebar/bin/claudebar-hook`, em exec form, nunca para dentro do bundle.
- Settings inválido: nada gravado, mensagem e exit 1.
- `claudebar-hook` sem argumento ou com estado inválido sai com 1.
- `install` duas vezes → "Nada a mudar".

## Gates

`swift build`, `swift test`, `bash -n scripts/*.sh`, `./scripts/build-app.sh`.

## README (as duas línguas)

- Requirements: tirar `jq`; "Claude Code 2.1.139 or later (hooks use exec form, `args`)".
- Installation: prévia + pergunta; só as entradas do ClaudeBar mudam; backup `0600` em `~/.claude/claudebar/backups/`; arquivo reformatado (ordem das chaves). Trocar "Hooks only apply to new sessions" por "Claude Code reloads `settings.json`, so open sessions pick the hooks up (folders must be trusted)". Tirar "`settings.json` must already exist".
- Hook CLI usage: `claudebar-hook <working|idle|waiting|end> [--pid <pid>]` e `claudebar-hook install|uninstall [--dry-run]`; fallback `getppid()`; exit 1.
- How it works: o hook mora em `~/.claude/claudebar/bin/claudebar-hook` (cópia do bundle).
- Uninstall: `./scripts/uninstall.sh` (tirar "remove the four claudebar-hook entries").
- Security: backups `0600`, sem `jq`, exec form = sem shell nos hooks.
- Project structure: `HookInstaller.swift`, `scripts/uninstall.sh`.

## Riscos

| Risco | Mitigação |
|---|---|
| `getppid()` não ser o Claude (não confirmado) | só aceito se `proc_pidpath` contém `claude`; senão 0 |
| Claude Code < 2.1.139 ignora `args` | roda sem argumento → exit 1, não bloqueia; README declara o mínimo |
| Teste manual estragar o `settings.json` real | backup próprio antes (`cp ~/.claude/settings.json "$TMPDIR/settings.antes.json"`) |

## Fora do escopo

Campo `matcher` (T07), detecção de estado e oferta de reparo (T06, T10), `status`/`next` (T22), `statusline` (T28), remover o `?? "unknown"` (T08).
