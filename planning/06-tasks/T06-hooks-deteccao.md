# T06 — Detectar o estado da integração (`IntegrationState`)

- **Funcionalidade:** F03 (detecção) — spec [G03, F03](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P0 · **Esforço:** 1,5 h
- **Depende de:** T05 · **Bloqueia:** T07, T10, T30
- **Branch:** `feat/hooks-deteccao-estado`
- **PR:** `feat: detectar estado da integração dos hooks`

## Objetivo

Função só de leitura que diz em que pé está a integração: hooks ausentes, legados (do `install.sh` antigo), faltando, binário ausente ou de outra versão, settings inválido, somente leitura, `disableAllHooks`. Cada estado ≠ `ok`/`notInstalled` vira **oferta** de reparo no app (T10). Nunca grava nada.

## Subtasks

- [ ] `HookInstaller.swift`: `public enum IntegrationState` (9 casos) e `public static func state(bundledBinary:settings:binary:)`.
- [ ] Testes `estados` e `somenteLeitura` na suíte `HookStateTests` (o `fixture` já veio em T04).
- [ ] README (seção "Moving or updating the app").
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | `IntegrationState`, `state(...)` |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | 2 testes |
| `README.md`, `README.pt-BR.md` | 1 seção curta |

## Código-chave (da spec, G03 linhas 84–102 e 247–279)

```swift
public enum IntegrationState: Equatable, Sendable {
    case notInstalled
    case ok
    /// Hooks registrados, mas a cópia estável do executável sumiu.
    case binaryMissing
    /// A cópia estável difere do executável deste `.app` (o app foi atualizado).
    case binaryOutdated
    /// Faltam entradas, ou sobram entradas de outra versão.
    case hooksOutdated
    /// Entradas do `install.sh` antigo: shell form, caminho dentro do bundle.
    case legacyHooks
    case invalidSettings
    /// Precisa gravar, mas o arquivo (já sem symlink) não é gravável.
    case readOnlySettings
    /// `disableAllHooks: true` no settings do usuário. Não mexemos nisso.
    case hooksDisabled
}

    public static func state(bundledBinary: URL?, settings: URL = settingsURL,
                             binary: URL = stableBinary) -> IntegrationState {
        let manager = FileManager.default
        let real = settings.resolvingSymlinksInPath()
        let data = manager.fileExists(atPath: real.path) ? try? Data(contentsOf: real) : Data()
        guard let data, let root = try? parse(data) else { return .invalidSettings }
        if root["disableAllHooks"] as? Bool == true { return .hooksDisabled }

        let ours = handlers(in: root).filter { isOurs($0.handler, binary: binary.path) }
        let current = ours.filter { $0.handler["args"] != nil && $0.handler["command"] as? String == binary.path }
        let complete = current.count == entries.count && entries.allSatisfy { entry in
            current.contains { $0.event == entry.event && $0.handler["args"] as? [String] == entry.args }
        }
        let settingsState: IntegrationState? =
            if ours.isEmpty { .notInstalled }
            else if current.count != ours.count { .legacyHooks }
            else if !complete { .hooksOutdated }
            else { nil }
        if let settingsState {
            return isWritable(real) ? settingsState : .readOnlySettings
        }
        guard manager.isExecutableFile(atPath: binary.path) else { return .binaryMissing }
        if let bundledBinary, !manager.contentsEqual(atPath: bundledBinary.path, andPath: binary.path) {
            return .binaryOutdated
        }
        return .ok
    }
```

Nota para T07: quando `Entry` ganhar `matcher`, `handlers(in:)` passa a devolver o `matcher` do grupo e `complete` compara também o matcher.

## Testes obrigatórios

`estados` (notInstalled → binaryMissing → ok → binaryOutdated; legacyHooks; hooksOutdated; hooksDisabled; invalidSettings) e `somenteLeitura` (arquivo `0400` → `readOnlySettings`; `apply` lança `readOnly`), exatamente como na spec.

## Critérios de aceite

- `state` cobre os 9 estados nos testes e não grava nada.
- `readOnlySettings` só aparece quando é preciso gravar.
- `swift test` = anterior + 2.

## Gates

`swift build`, `swift test`.

## README

"Moving or updating the app": o hook é uma cópia em `~/.claude/claudebar/bin`; mover ou apagar o `.app` não quebra os hooks; depois de atualizar o app, o menu oferece atualizar a cópia (oferta chega em T10).

## Riscos

| Risco | Mitigação |
|---|---|
| `contentsEqual` em cada render | `state` só roda no launch, depois de ação e no "Atualizar" (T10) |
| `disableAllHooks` de projeto/managed invisível | o "Testar integração" (T11) manda conferir `/hooks` |

## Fora do escopo

Qualquer reparo automático; UI (T10); embutir versão no binário.
