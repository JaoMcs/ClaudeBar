# T15 — Rede zero verificável (`NoNetworkTests`) + "Verify it yourself"

- **Funcionalidade:** F27 (F27.1 + F27.2) — spec [G14](../05-specs/G14-rede-zero.md)
- **Épico:** Qualidade · **Prioridade:** P2 · **Esforço:** 1 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `chore/rede-zero-verificavel`
- **PR:** `test: rede zero verificável e como conferir`

## Objetivo

`swift test` (local e na CI) falha se algum `.swift` em `Sources/` passar a usar API de rede conhecida ou literal `http(s)://`. O README ensina a provar em 1 minuto, com ferramentas do sistema, que o app não abre conexão, e escreve a regra de log para caminhos.

## Subtasks

- [ ] Criar `Tests/ClaudeBarTests/NoNetworkTests.swift` exatamente como na spec.
- [ ] Mutação: `let _x = URLSession.shared` num arquivo de `Sources/ClaudeBar/` → falha citando arquivo e linha. Desfazer.
- [ ] Rodar a partir de outro cwd: `cd /tmp && swift test --package-path <repo> --filter NoNetwork`.
- [ ] README: subseção "Verify it yourself" / "Confira você mesmo" no fim de Security; bullet da regra de log; linha de testes em Project structure.
- [ ] Verificação manual 1 da spec (`lsof`, `nettop` com o app instalado).
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Tests/ClaudeBarTests/NoNetworkTests.swift` | novo |
| `README.md`, `README.pt-BR.md` | Security |

Não toca `Sources/` nem `Package.swift`.

## Código-chave (da spec, copiar inteiro)

```swift
@Suite("Rede zero")
struct NoNetworkTests {
    static let proibidos = [
        #"\bimport\s+(Network|CFNetwork|WebKit)\b"#,
        #"\bURLSession\b"#, #"\bNSURLConnection\b"#,
        #"\bNW(Connection|Listener|PathMonitor|Browser|Endpoint)\b"#, #"\bnw_[a-z_]+\("#,
        #"\bCFSocket"#, #"\bCFStreamCreatePairWithSocket"#, #"getStreamsToHost"#,
        #"\bsocket\("#, #"\bgetaddrinfo\("#,
        #""https?://"#,
    ]

    static func acerto(em linha: Substring) -> String? {
        guard !linha.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { return nil }
        // ICU, não `Regex` nativo: o `\b` Unicode não casa "URLSession.shared".
        return proibidos.first { linha.range(of: $0, options: .regularExpression) != nil }
    }

    @Test func sourcesNaoUsamRede() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let arquivos = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        // Caminho errado = lista vazia = teste verde sem varrer nada.
        #expect(arquivos.count > 5, "não achou os fontes em \(sources.path)")
        for arquivo in arquivos {
            let linhas = try String(contentsOf: arquivo, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (i, linha) in linhas.enumerated() {
                if let padrao = Self.acerto(em: linha) {
                    Issue.record("\(arquivo.lastPathComponent):\(i + 1) parece rede (\(padrao))")
                }
            }
        }
    }
    // + pegaRede (5 argumentos) e ignoraNaoRede (3 argumentos), como na spec
}
```

## Testes obrigatórios

`sourcesNaoUsamRede`, `pegaRede` (inclui `"let s = URLSession.shared"` e `URL(string: "https://…")`), `ignoraNaoRede`.

## Critérios de aceite

- `swift build --build-tests` sem `warning:` vindo do arquivo novo; `swift test` = anterior + 3.
- A mutação faz `swift test` falhar citando arquivo e linha.
- README com `### Verify it yourself` (en) e `### Confira você mesmo` (pt-BR): `lsof -i -a -c ClaudeBar`, `nettop -p ClaudeBar -L 0 -t external -n` (explicando que só o cabeçalho aparece), Little Snitch opcional e a nota de que tráfego do `claude agents --json`/`claude stop` aparece como `claude`.
- Bullet: "Paths are never logged in the clear… `privacy: .private(mask: .hash)`; never `.public`".
- Diff não toca `Sources/`.

## Gates

`swift build`, `swift test`.

## README

Texto completo nas duas línguas na spec (G14, F27.2). Copiar.

## Riscos

| Risco | Mitigação |
|---|---|
| API de rede fora da lista | lista de APIs conhecidas; upgrade é F27.3 (`nm`), fora da rodada |
| Falso positivo | mensagem com arquivo e linha; reescrever a linha, nunca afrouxar |
| `#filePath` aponta para lugar inexistente | sanidade `count > 5` falha alto |

## Fora do escopo

F27.3 (`nm` no `build-app.sh`), SwiftLint, plugin de build, varrer `Tests/`, allowlist preventiva, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, trocar `.public` existentes.
