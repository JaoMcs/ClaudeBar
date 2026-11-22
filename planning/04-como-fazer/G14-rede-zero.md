# G14: Rede zero verificável (F27)

Pesquisa de "como fazer". Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial citada ou testado aqui; **[SUPOSIÇÃO]** = inferência minha, precisa de teste.

Backlog F27: um teste que falha se `Sources/` usar `URLSession`, `Network`, `NWConnection`, `CFSocket` etc., uma seção no README sobre como verificar com `nettop`/Little Snitch e logs com `privacy: .private` para caminhos. Guard rail (00-PLANO): "sem rede por padrão (qualquer rede é opt-in e explícita)".

## 1. Ponto de partida (lido no código em 2026-11-15)

- **[CONFIRMADO]** Nenhum arquivo em `Sources/` usa rede. Rodei o regex do §3 nos 15 `.swift` e não houve nenhum acerto. Os imports são só `Foundation`, `SwiftUI`, `AppKit`, `Observation`, `OSLog`, `UserNotifications`, `Darwin` e `ClaudeBarCore`. O único `Data(contentsOf:)` (`StatusDirectory.swift:68`) lê arquivo local, então **não** dá para proibir `contentsOf` de forma genérica.
- **[CONFIRMADO]** No binário, `otool -L .build/arm64-apple-macosx/debug/ClaudeBar` não lista `Network.framework` nem `CFNetwork`. `nm -u` não mostra símbolo de `URLSession`, `nw_*`, `CFSocket`, `socket`, `connect` ou `getaddrinfo`.
- **[CONFIRMADO]** O app **cria processos filhos**: `Shell.output` roda `claude agents --json` (`AgentsProbe.swift:87`) e, em último caso, `zsh -lc "command -v claude"`. Qualquer tráfego desses filhos aparece no `nettop` e no Little Snitch com o nome do processo filho, não como `ClaudeBar`. O README precisa dizer isso com todas as letras, senão o usuário (persona f) vai ver tráfego do `claude` e culpar o app.
- **[SUPOSIÇÃO]** Não sei se `claude agents --json` faz chamada de rede (telemetria ou feature flags). A doc oficial diz que o Claude Code envia métricas e relatórios de erro e que `DISABLE_TELEMETRY` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` também desligam a avaliação de feature flags (https://code.claude.com/docs/en/data-usage, seção "Telemetry services", **[CONFIRMADO]**). A doc não diz se um subcomando curto como `agents` dispara isso. Para descobrir, rodar `nettop -p claude -L 0` enquanto o app faz polling.
- Logs: 2 `Logger`s (`Notifier`, `StatusHUD`). **Nenhum loga caminho hoje.** `claudebar-hook` e `ClaudeBarCore` não logam nada. O `.public` existente só aparece em números, frames, `rawValue` e `error.localizedDescription`.

## 2. Teste de varredura: decisões

| Decisão | Escolha | Por quê |
|---|---|---|
| Como achar a raiz do repo | `URL(fileURLWithPath: #filePath)` + 3× `deletingLastPathComponent()` | **[CONFIRMADO]** SE-0274: `#filePath` mantém o caminho completo, e `#file` passa a ser `Módulo/Arquivo.swift` no modo Swift 6 (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0274-magic-file.md). O pacote é `swift-tools-version: 6.0`, então **não** usar `#file`. O cwd do `swift test` não é garantido (Xcode e CI mudam), e `#filePath` não depende dele. Padrão citado no fórum: https://forums.swift.org/t/how-to-get-project-root-directory-from-inside-tests/17174 |
| Motor de regex | `String.range(of:options: .regularExpression)` (ICU/Foundation) | **[CONFIRMADO, testado aqui]** **Armadilha:** o `Regex` nativo do Swift usa por padrão a fronteira de palavra Unicode (UAX#29), que trata `URLSession.shared` como **uma palavra só**. Com isso `\bURLSession\b` **não casa** e o teste passa sem detectar nada. Medido: `Regex(#"\bURLSession\b"#)` em `"let s = URLSession.shared"` → `false`. O ICU → `true`. `.wordBoundaryKind(.simple)` também resolve, mas o ICU é uma linha e não precisa de nada além do Foundation. |
| Unidade da varredura | linha a linha, pulando linhas que começam com `//` | Assim um comentário que explica "não usamos URLSession" não quebra o teste. Comentário `/* */` ou doc no fim da linha ainda dispara, e isso é aceitável (falso positivo barato, corrige-se reescrevendo). |
| Sanidade | `#expect(arquivos.count > 5)` | Se o caminho estiver errado, o enumerator devolve vazio e o teste passaria "verde" sem varrer nada. Esse é o falso negativo clássico desse tipo de teste. |
| Framework | Swift Testing (`import Testing`, `@Test`, `#expect`, `Issue.record`) | Já é o que `Tests/ClaudeBarTests` usa. |
| Alvo do teste | `ClaudeBarTests`, sem `@testable import` | O teste só lê arquivos. Não depende de símbolo do app. |

Lista de padrões proibidos (curta e explícita, cresce quando aparecer API nova):

- `\bimport\s+(Network|CFNetwork|WebKit)\b`: frameworks de rede ou web
- `\bURLSession\b`, `\bNSURLConnection\b`
- `\bNW(Connection|Listener|PathMonitor|Browser|Endpoint)\b`, `\bnw_[a-z_]+\(`: Network.framework em Swift e em C
- `\bCFSocket`, `\bCFStreamCreatePairWithSocket`, `getStreamsToHost`: sockets e streams do CoreFoundation e do Foundation
- `\bsocket\(`, `\bgetaddrinfo\(`: BSD/Darwin direto (o target já importa `Darwin`)
- `"https?://`: literal de URL remota em código. Pega `Data(contentsOf: URL(string: "https://…"))` e `NSWorkspace.open(URL https)`. Se um dia houver um link "Ajuda" legítimo, colocar uma allowlist explícita no teste, não afrouxar o padrão.

## 3. Código recomendado (protótipo compilado e rodado aqui com `swiftc -swift-version 6`)

`Tests/ClaudeBarTests/NoNetworkTests.swift`:

```swift
import Foundation
import Testing

/// Rede zero (F27): o app não fala com a internet. Se este teste falhar, ou a
/// mudança é rede de verdade (precisa ser opt-in, explícita e documentada no
/// README) ou é falso positivo: reescreva a linha.
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

    @Test func sourcesNaoUsamRede() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ClaudeBarTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // raiz do pacote
            .appendingPathComponent("Sources")
        let arquivos = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(arquivos.count > 5, "não achou os fontes em \(sources.path)")

        for arquivo in arquivos {
            let linhas = try String(contentsOf: arquivo, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (i, linha) in linhas.enumerated()
            where !linha.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                // ICU, não `Regex` nativo: o `\b` Unicode acha que
                // "URLSession.shared" é uma palavra só e não casa.
                for padrao in Self.proibidos
                where linha.range(of: padrao, options: .regularExpression) != nil {
                    Issue.record("\(arquivo.lastPathComponent):\(i + 1) parece rede (\(padrao))")
                }
            }
        }
    }
}
```

Validação feita aqui (no scratchpad, fora do repo): com os `Sources/` reais, 15 arquivos e 0 acertos. Com fontes falsas, acertou `import Network`, `NWConnection(…)`, `URL(string: "https://x")`, `socket(AF_INET…)` e `URLSession.shared`, e ignorou `// URLSession em comentário`.

Swift 6 strict concurrency: `static let proibidos: [String]` é `Sendable`, e o `@Test` é síncrono, então não há aviso. **[SUPOSIÇÃO]** Num `@Test` **async**, iterar `FileManager.DirectoryEnumerator` pode gerar o aviso "makeIterator is unavailable from asynchronous contexts". O `compactMap` em teste síncrono evita isso.

### Camada 2 opcional: checar o binário (1 linha no `build-app.sh`)

A varredura de fonte não pega uma dependência SwiftPM que use rede (hoje não há nenhuma) nem uma API que não esteja na lista. Checar símbolos do binário pega as duas coisas:

```bash
if nm -u "$BUNDLE/Contents/MacOS/"* | grep -E 'NSURLSession|_nw_|CFSocket|_socket$|_connect$|_getaddrinfo$'; then
  echo "ERRO: binário importa símbolo de rede"; exit 1; fi
```

**[CONFIRMADO, testado aqui]** No binário debug atual não aparece nada. **[SUPOSIÇÃO]** Isso continua verdade no binário release e no `claudebar-hook` (não rodei). Recomendo **adiar**: o teste de fonte cobre F27, e esta checagem só vale a pena quando entrar a primeira dependência externa. `ponytail:` só lista padrões conhecidos; o upgrade é o `nm`.

## 4. README: como verificar (texto proposto, em inglês e espelhado no pt-BR)

**[CONFIRMADO]** Flags do `nettop` (`man nettop`, macOS 26): `-p <process-name|pid>` (o nome precisa ser exato e pode vir truncado), `-L <samples>` (CSV, e `0` = infinito), `-l` (texto cru), `-P` (só o resumo por processo), `-m tcp|udp|route`, `-t external` (só interfaces fora do loopback), `-n` (não resolve nomes).

```md
### Verify it yourself

ClaudeBar makes no network connections. A test (`NoNetworkTests`) fails the build
if networking code is ever added. To check the running app:

    nettop -p ClaudeBar -L 0 -t external     # stays empty; Ctrl-C to stop
    lsof -i -a -c ClaudeBar                  # prints nothing

With Little Snitch: open Network Monitor and search for "ClaudeBar". It should
never show a connection.

Note: ClaudeBar runs `claude agents --json` to list sessions. Any traffic from
that command shows up under `claude`, not ClaudeBar. That traffic belongs to
Claude Code and follows its settings
(https://code.claude.com/docs/en/data-usage#telemetry-services).
```

- **[CONFIRMADO]** Little Snitch: o Network Monitor mostra "which application, Unix command or system service … connects to which Internet server", processos auxiliares aparecem dentro do app ao expandir, e há busca textual na lista (https://help.obdev.at/littlesnitch6/lsm-overview). A versão 6 exige macOS 14+. O Little Snitch Mini mostra de graça os últimos 5 minutos (https://help.obdev.at/littlesnitchmini/main-connectionlist).
- **[SUPOSIÇÃO]** O nome do processo no `nettop` é exatamente `ClaudeBar`, porque o `CFBundleExecutable` é `ClaudeBar`. Conferir uma vez com `nettop -P -L 1 | grep -i claude`.
- **[SUPOSIÇÃO]** `lsof -i -a -c ClaudeBar` não lista nada. Isso vale se nenhum framework do sistema abrir um socket "de rede" em nome do app (o `UserNotifications` usa XPC, não socket). Conferir no app real antes de pôr no README.
- **Alternativa** (não recomendo agora): passar `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` no `environment` do `Process` em `Shell.swift`, para que o filho `claude` também não gere tráfego não essencial. **[CONFIRMADO]** essa variável existe e desliga a telemetria e as feature flags (data-usage). Contra: ela muda o comportamento de outra ferramenta e pode afetar o `agents --json` se ele depender de feature flag. Fazer só se o teste do §1 mostrar tráfego.

## 5. Logs com `privacy: .private` para caminhos

- **[CONFIRMADO]** "By default, the system doesn't redact integer, floating-point and Boolean values, but it does redact the contents of dynamic strings and complex dynamic objects." (https://developer.apple.com/documentation/os/generating-log-messages-from-your-code). Ou seja, um caminho interpolado **sem** modificador já sai oculto. O risco real é alguém pôr `.public` para depurar e esquecer.
- **[CONFIRMADO]** `OSLogPrivacy` tem `.auto`, `.private`, `.public`, `.sensitive` e as variantes `private(mask:)`, `sensitive(mask:)`, `auto(mask:)`. Com `mask: .hash`, o valor oculto vira um hash, o que "makes it possible to correlate log messages that contain the same original value" (https://developer.apple.com/documentation/os/oslogprivacy). Pela página Generating log messages, o hash é único por processo.
- **Recomendado:** caminhos e `cwd` com `privacy: .private(mask: .hash)`, explícito mesmo sendo o padrão. Isso documenta a intenção e permite correlacionar a mesma sessão no Console. `sessionId` também. `message` do hook com `.private`.
- **Armadilha:** `error.localizedDescription, privacy: .public` (Notifier.swift:133 e :146). Erros de `FileManager`/Cocoa costumam trazer o caminho no texto. **[SUPOSIÇÃO]** Os erros do `UNUserNotificationCenter` desses dois pontos não trazem caminho, então dá para deixar como está. Para qualquer novo log de erro de arquivo, usar `.private`.
- Teste: dá para estender o `NoNetworkTests` com um padrão `(path|cwd|Path|directory)[^)]*privacy: \.public` sobre os mesmos arquivos. **Recomendo não fazer**: hoje não há nenhum log de caminho, e o padrão do sistema já oculta. Basta um comentário no README/CONTRIBUTING. Adicionar quando surgir o primeiro log de caminho.
- Para ver os logs: `log stream --predicate 'subsystem == "com.joaomarcos.claudebar"'`. Valores privados aparecem ocultos. **[SUPOSIÇÃO]** Eles aparecem como `<private>`, porque a página da Apple não mostra o literal.

## 6. Repos e alternativas

- Não achei repo open source com um teste Swift pronto de "varrer Sources por import de rede". A busca só trouxe o fórum Swift sobre `#filePath` + `deletingLastPathComponent`. O código do §3 é próprio, mas foi testado.
- **Alternativas consideradas:**
  1. **SwiftLint `custom_rules`** com regex. Exige instalar uma ferramenta nova e não roda no `swift test`. Rejeitada (o guard rail e o backlog pedem que o teste esteja no `swift test`).
  2. **Plugin de build SwiftPM** que falha a compilação. É mais código e mais lento, e não traz ganho sobre o teste. Rejeitada.
  3. **App Sandbox sem `com.apple.security.network.client`**, que faria o kernel bloquear a rede de verdade. É a garantia mais forte. Mas o app roda `claude` e `zsh` via `Process` e envia sinais a PIDs de outros processos (`SessionTerminator`). **[SUPOSIÇÃO]** Num app em sandbox, o processo filho herda o sandbox e o `claude` deixa de funcionar, e o `kill` em processos fora do sandbox é negado. Isso inviabiliza o app como ele é hoje. Fica registrado como ideia, não como recomendação.
  4. **Checar o binário com `nm`/`otool`** (§3, camada 2). Adiar.
- **Recomendação:** teste de fonte do §3 (1 arquivo novo) + seção do README do §4 + regra de `.private(mask: .hash)` do §5 aplicada quando houver log de caminho. A camada `nm` fica para quando entrar dependência externa.

## 7. Notas de LSUIElement / assinatura ad-hoc / MainActor

Nada disso afeta a F27. O teste é só leitura de arquivo, o `nettop` não depende de assinatura, e o Little Snitch identifica o processo pelo caminho e pela assinatura de código. **[SUPOSIÇÃO]** Com assinatura ad-hoc, o Little Snitch mostra o app como "not code signed" ou "ad-hoc" e cada rebuild muda o hash. Isso só importa para quem cria uma regra de bloqueio, não para a verificação visual.

_Revisado em 2026-11-15 (2ª passada): repeti a medição do `\b` (`Regex` nativo → false, ICU → true, `swiftc -swift-version 6`), conferi as flags `-p/-L/-P/-m/-t/-n` no `man nettop` e confirmei que `Sources/` não tem literal `http(s)://`._
