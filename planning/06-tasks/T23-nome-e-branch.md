# T23 — Branch ao lado do nome da sessão

- **Funcionalidade:** F20 — spec [G08, F20](../05-specs/G08-pasta-nome-branch.md)
- **Épico:** UI/Ajustes · **Prioridade:** P1 · **Esforço:** 2,5 h
- **Depende de:** T16 (`SessionRow`/`label` já com `kind`) · **Bloqueia:** T31
- **Branch:** `feat/nome-e-branch`
- **PR:** `feat: mostrar a branch ao lado do nome da sessão`

## Objetivo

Cada linha mostra **nome · branch** (`ClaudeBar · feat/x — processando (há 10 s)`), para distinguir sessões do mesmo projeto em worktrees diferentes. O nome já existe (`claude agents --json`); falta a branch. Quem lê a branch é o **hook** (roda no terminal, que já tem acesso à pasta), direto de `.git/HEAD`, sem rodar `git`. O app nunca lê nada dentro do projeto.

## Subtasks

- [ ] Criar `Sources/ClaudeBarCore/GitHead.swift` (código validado da spec).
- [ ] `SessionStatus`: `branch: String?` + parâmetro `branch: String? = nil` **depois de `kind`** no `init`.
- [ ] `main.swift`: calcular `cwd` uma vez e passar `branch: GitHead.branch(at: cwd)`.
- [ ] `SessionRow.branch` (último parâmetro, com padrão) e `SessionMerge` repassando nas duas construções.
- [ ] `MenuContent.label(for:)`: `· branch` entre o nome e a descrição.
- [ ] `GitHeadTests.swift` novo + `branchDoHookChegaNaLinha` em `SessionMergeTests`.
- [ ] Corrigir a linha F20 do `planning/03-validacao/BACKLOG.md` (nome já exibido; falta a branch; leitura no hook).
- [ ] Verificação manual 2–7 da spec (inclui o teste de TCC em `~/Documents`). Se aparecer prompt de "Arquivos e Pastas" para o ClaudeBar, **parar** e registrar no PR (não adicionar chave de uso).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`GitHead.swift` (novo), `SessionStatus.swift`, `main.swift`, `SessionRow.swift`, `SessionMerge.swift`, `MenuContent.swift`, `GitHeadTests.swift` (novo), `SessionMergeTests.swift`, READMEs, `BACKLOG.md`.

## Código-chave (da spec)

```swift
public enum GitHead {
    /// `"main"`, `"@1a2b3c4"` com HEAD solto, ou `nil` fora de repositório / reftable.
    public static func branch(at cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            if let head = headURL(dotGit: dotGit) { return readRegularFile(head).flatMap(parse) }
            if dir.path == "/" { return nil }
            dir.deleteLastPathComponent()
        }
    }

    static func parse(_ text: String) -> String? {
        guard let head = firstLine(text) else { return nil }
        if head.hasPrefix("ref: ") {
            var ref = head.dropFirst("ref: ".count)
            if ref.hasPrefix("refs/heads/") { ref = ref.dropFirst("refs/heads/".count) }
            // Reftable: HEAD é um stub fixo; sem rodar git, não mostrar branch.
            guard !ref.isEmpty, ref != ".invalid" else { return nil }
            return String(ref.prefix(80))
        }
        let isSHA = (head.count == 40 || head.count == 64) && head.allSatisfy(\.isHexDigit)
        return isSHA ? "@\(head.prefix(7))" : nil
    }

    /// Só arquivo comum: um FIFO chamado `HEAD` travaria o hook, e com ele a sessão.
    private static func readRegularFile(_ url: URL) -> String? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
    // headURL(dotGit:) segue `gitdir:` absoluto ou relativo à pasta do `.git`; firstLine — como na spec.
}
```

```swift
        text += row.name
        // A branch distingue duas sessões do mesmo projeto em worktrees diferentes.
        if let branch = row.branch { text += " · \(branch)" }
        text += " — \(description(for: row))"
```

## Testes obrigatórios

- `GitHeadTests`: `interpretaOConteudoDoHead` (main, feat/x, `.invalid`, SHA → `@a1a1a1a`, lixo, vazio) e `achaOHeadCertoNoDisco` (subpasta, worktree `gitdir:` relativo e absoluto, fora de repo, relativo).
- `SessionMergeTests.branchDoHookChegaNaLinha`.
- `sessaoConhecidaSoPelosHooksNaoEhPerdida` continua verde sem mudança (formato antigo decodifica).

## Critérios de aceite

- Label com `nome · branch` quando o hook gravou; só `nome` quando não. Resto do label igual.
- Worktree mostra a branch do worktree; HEAD solto `@` + 7 hex; reftable/fora de git/relativo → nada.
- `rg '"git"' Sources` vazio; `rg GitHead Sources/ClaudeBar` vazio.
- `GitHead` não lança; o hook nunca falha por causa da branch.
- `swift test` = anterior + 3.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Exemplo do menu com `· feat/x`; JSON de exemplo com `"branch" : "main",`; frase sobre `.git/HEAD`/`gitdir:`/`@sha7`/reftable; Project structure: `GitHead.swift`; Security: "The only file read inside your project is `.git/HEAD` (or the `.git` gitfile of a worktree), by the hook, never by the app, and `git` is never run."

## Riscos

| Risco | Mitigação |
|---|---|
| TCC atribuir a leitura ao ClaudeBar | passo 6; se aparecer prompt, parar e registrar; fail-open garantido (`nil`) |
| Leitura bloqueante | só arquivo comum; timeout 5 do hook |
| Branch atrasada um turno após `checkout` fora do Claude | aceito, documentado |

## Fora do escopo

Ler `.git/HEAD` no app; rodar `git`; ler `refs/`, `packed-refs`, `reftable/`; toggle "mostrar branch"; agrupar por branch (F42).
