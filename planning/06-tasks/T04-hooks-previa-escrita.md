# T04 — Prévia, backup e escrita segura do `settings.json` + cópia estável do binário

- **Funcionalidades:** F02 parte 2 de 3; F03 (cópia estável) — spec [G03, F02 e F03](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P0 · **Esforço:** 1,5 h
- **Depende de:** T03 · **Bloqueia:** T05
- **Branch:** `feat/hooks-previa-escrita`
- **PR:** `feat: prévia, backup e escrita segura do settings.json`

## Objetivo

Completar o `HookInstaller` com a parte de IO: montar a prévia (diff só do bloco `hooks`), gravar exatamente o que a prévia mostrou (com backup `0600`, respeitando symlink, recusando arquivo que mudou ou é só leitura) e copiar o executável do hook para `~/.claude/claudebar/bin/claudebar-hook` (`0700`, só os bytes, sem quarentena, troca por `rename`). Ainda sem chamador (T05 liga).

## Subtasks

- [ ] Acrescentar `HookPlan` (struct pública), `plan(_:settings:binary:)`, `apply(_:backups:)`, `snippet(binary:)`, `installBinary(from:to:)`, `isWritable(_:)`, `timestamp()`.
- [ ] Acrescentar ao arquivo de teste o helper `tempFolder()`, a suíte `HookWriteTests` e o teste `copiaComPermissao0700ESubstituiInteiro` (numa suíte `HookStateTests` com o `fixture`, que T06 completa).
- [ ] Rodar os testes 3 vezes (mexem em disco/permissão) sem flake.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | IO: plano, escrita, backup, cópia |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | `HookWriteTests` + teste da cópia |

## Código-chave (da spec, G03 linhas 104–243 e 407–420)

```swift
    @discardableResult
    public static func apply(_ plan: HookPlan, backups: URL = backupsURL) throws -> URL? {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: plan.settingsURL.path)
        let now = exists ? try Data(contentsOf: plan.settingsURL) : Data()
        // O Claude Code também grava esse arquivo (`/config`, `/model`).
        guard now == plan.original else { throw HookInstallError.changedSinceReview }
        guard isWritable(plan.settingsURL) else { throw HookInstallError.readOnly }

        var backup: URL?
        if exists {
            try manager.createDirectory(at: backups, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let url = backups.appendingPathComponent("settings.json.\(timestamp())")
            // O settings pode ter `env` com token: o backup já nasce `0600`.
            guard manager.createFile(atPath: url.path, contents: now,
                                     attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            backup = url
        }
        try plan.updated.write(to: plan.settingsURL, options: .atomic)
        if !exists {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.settingsURL.path)
        }
        return backup
    }

    /// Copia só os bytes (assinatura embutida vai junto), não os xattrs: uma
    /// cópia com `com.apple.quarantine` trava no Gatekeeper a cada exec.
    public static func installBinary(from source: URL, to destination: URL = stableBinary) throws {
        let manager = FileManager.default
        guard !manager.contentsEqual(atPath: source.path, andPath: destination.path) else { return }
        let folder = destination.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let temp = folder.appendingPathComponent(".claudebar-hook.\(UUID().uuidString)")
        guard manager.createFile(atPath: temp.path, contents: try Data(contentsOf: source),
                                 attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temp.path, destination.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
```

Pontos obrigatórios de `plan`: `settings.resolvingSymlinksInPath()` antes de ler; `diff` = `lineDiff` de `serialize(hooksOnly(root))` × `serialize(hooksOnly(next))` (nunca o arquivo inteiro: `env` pode ter token); `hasChanges = current != updated`; `reformats = !original.isEmpty && current != original`. Backup com milissegundos no nome (`yyyyMMdd-HHmmss-SSS`, `en_US_POSIX`).

## Testes obrigatórios

- `HookWriteTests`: `gravaPeloSymlinkComBackup` (link continua link, backup `0600` com o conteúdo original, diff sem `opus`), `recusaSeMudouDepoisDaPrevia`, `removerSemNadaNossoNaoMuda`.
- `copiaComPermissao0700ESubstituiInteiro`: quarentena da origem não vai para a cópia, modo `0700`, inode novo na troca.
- Todos em pasta temporária: `NSHomeDirectory()` ignora `$HOME`, nenhum teste usa os caminhos padrão.

## Critérios de aceite

- Backup `0600` antes de toda escrita em arquivo existente; nunca janela `0644`.
- `apply` nunca grava algo diferente do que `plan` mostrou (`changedSinceReview`).
- Arquivo `0444` com pasta gravável → `readOnly`.
- Cópia do binário: `0700`, mesmo conteúdo, sem `com.apple.quarantine`, trocada por `rename`.
- `swift test` = anterior + 4.

## Gates

`swift build`, `swift test` (3 rodadas sem flake).

## README

Nada ainda (T05).

## Riscos

| Risco | Mitigação |
|---|---|
| Symlink de dotfiles virar arquivo | `resolvingSymlinksInPath()` + teste |
| Corrida com `/config`/`/model` | releitura e `changedSinceReview` |
| Quarentena trava o hook | cópia só de bytes + teste (achado confirmado na spec) |

## Fora do escopo

`xattr -d` em qualquer arquivo; `copyItem`; limitar número de backups; CLI, scripts e app (T05, T10); estados (T06).
