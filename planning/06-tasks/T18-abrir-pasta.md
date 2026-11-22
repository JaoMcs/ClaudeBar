# T18 — Abrir pasta do projeto

- **Funcionalidade:** F11 — spec [G08, F11](../05-specs/G08-pasta-nome-branch.md)
- **Épico:** Navegação · **Prioridade:** P1 · **Esforço:** 1 h
- **Depende de:** — (em sequência depois de T17 por causa de `SessionStore`/`MenuContent`) · **Bloqueia:** T19
- **Branch:** `feat/abrir-pasta`
- **PR:** `feat: abrir a pasta do projeto pelo menu`

## Objetivo

Item **Abrir pasta do projeto** no submenu de cada sessão, logo abaixo do caminho: abre o `cwd` no gerenciador de pastas padrão. Se não der (pasta sumiu, acesso negado, é um pacote `.app`), alerta com o motivo provável. Nunca executa um `.app`.

## Subtasks

- [ ] `SessionStore`: `openFolder(_:)` e `static func isOpenableFolder(_:)`, logo depois de `terminate(_:)`.
- [ ] `MenuContent`: botão abaixo de `Text(row.cwd)`.
- [ ] `OpenFolderTests.swift` novo.
- [ ] Verificação manual 2–5 da spec (inclui `tccutil reset SystemPolicyDocumentsFolder com.joaomarcos.claudebar` e o caso `Calculator.app`). Se o Finder não vier para a frente, trocar por `open(url, configuration: .init())` e registrar.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionStore.swift`, `MenuContent.swift`, `Tests/ClaudeBarTests/OpenFolderTests.swift` (novo), READMEs.

## Código-chave (da spec)

```swift
    /// Abre a pasta do projeto no gerenciador de arquivos padrão (o Finder).
    func openFolder(_ row: SessionRow) {
        guard Self.isOpenableFolder(row.cwd),
              NSWorkspace.shared.open(URL(fileURLWithPath: row.cwd, isDirectory: true))
        else {
            report(title: "Não foi possível abrir a pasta",
                   message: "\(row.cwd)\n\nA pasta não existe mais ou o macOS negou o acesso.")
            return
        }
    }

    /// Só pasta de verdade: um `.app` também é diretório, e abri-lo executaria o app.
    static func isOpenableFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: path)
    }
```

```swift
                    Text(row.cwd)

                    Button("Abrir pasta do projeto") {
                        store.openFolder(row)
                    }
```

## Testes obrigatórios

```swift
@Suite("Abrir pasta do projeto")
@MainActor
struct OpenFolderTests {
    /// Abrir um `.app` executaria o app: só pasta comum pode passar.
    @Test func soAbrePastaDeVerdade() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = base.appendingPathComponent("Foo.app", isDirectory: true)
        let file = base.appendingPathComponent("arquivo.txt")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? manager.removeItem(at: base) }

        #expect(SessionStore.isOpenableFolder(base.path))
        #expect(!SessionStore.isOpenableFolder(app.path))
        #expect(!SessionStore.isOpenableFolder(file.path))
        #expect(!SessionStore.isOpenableFolder(base.appendingPathComponent("sumiu").path))
        #expect(!SessionStore.isOpenableFolder("relativo/pasta"))
    }
}
```

## Critérios de aceite

- Item presente em toda sessão (inclusive subagente), logo abaixo do caminho.
- Caminho inexistente, relativo, arquivo ou `.app`: nenhum app é lançado, aparece o alerta com o caminho.
- `rg 'usr/bin/open' Sources` vazio; nenhum `Process`/`Shell` novo.
- `swift test` = anterior + 1.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

The menu: "**Open project folder**: opens the `cwd` in Finder (only real folders; an `.app` is never launched)".

## Riscos

| Risco | Mitigação |
|---|---|
| Prompt de TCC em `~/Documents` | só depois de clique explícito; negado → alerta. Não adicionar `NSDocumentsFolderUsageDescription`. Plano B: `activateFileViewerSelecting` |
| Finder não vem para a frente | `open(url, configuration:)` |

## Fora do escopo

`/usr/bin/open`, `Task`/`DispatchQueue` em volta do `open`, "Abrir no terminal/editor", chaves `NS*UsageDescription`.
