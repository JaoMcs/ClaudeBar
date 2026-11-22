# Spec G14 — Rede zero verificável (F27)

Insumos: `04-como-fazer/G14-rede-zero.md`, `03-validacao/BACKLOG.md` (F27: P2, esforço P, sem dependência), guard rails do `00-PLANO.md`, código em `chore/ci-github-actions` @ 74fa932 (igual a `main` em `Sources/` e `Tests/`).

**Verificado nesta spec** (cópia do projeto no scratchpad, Swift 6, tools 6.0, macOS 26):
- O `NoNetworkTests.swift` abaixo compila sem nenhum aviso. `swift test` dá **37 testes** (34 atuais + 3 novos, e os parametrizados contam como 1), todos passando.
- Mutação: com `let _x = URLSession.shared` no fim de `Shell.swift`, o teste falha com `Shell.swift:27 parece rede (\bURLSession\b)`. Sem a linha, ele volta a passar.
- Fecha 3 itens "não confirmados" da pesquisa:
  - **`nm -u` no binário release** de `ClaudeBar` **e** de `claudebar-hook`: nenhum símbolo `NSURLSession|_nw_|CFSocket|_socket|_connect|_getaddrinfo`, e o `otool -L` não lista `Network` nem `CFNetwork`.
  - **`lsof -i -a -c ClaudeBar`** com o app instalado rodando (`~/Applications/ClaudeBar.app`, pid 7842): sai vazio, com código 1.
  - **`nettop -p ClaudeBar -L 1 -t external -n`** e `nettop -p <pid>`: imprimem só a linha de cabeçalho CSV. `nettop -P -L 1` lista `claude.<pid>` e `Claude Helper.<pid>`, mas nenhuma linha `ClaudeBar`, porque um processo sem fluxo nenhum não aparece.
- **Não deu para isolar** o tráfego de `claude agents --json`. O `nettop -p claude` mistura com as sessões interativas abertas, que têm o mesmo nome de processo. Isso continua não confirmado e **não bloqueia** a F27 (ver Riscos).

| Id | Entrega | Obrigatória? | Arquivos | Esforço |
|---|---|---|---|---|
| **F27.1** | Teste `NoNetworkTests` (varre `Sources/`) | sim | `Tests/ClaudeBarTests/NoNetworkTests.swift` (novo) | 0,5 h |
| **F27.2** | README: "Verify it yourself" + regra de log de caminho | sim | `README.md`, `README.pt-BR.md` | 0,5 h |
| F27.3 | Checagem `nm` no `build-app.sh` | **adiar** | `scripts/build-app.sh` | 0,25 h (quando fizer) |

Para o gestor:
- F27.1 e F27.2 podem ir num PR só (são ~1 h no total). O F27.1 não conflita com nada, porque o arquivo é novo.
- O F27.2 toca os dois READMEs, que quase toda feature também toca (F01, F07, F13…). Fazer o rebase no fim, ou juntar o texto no PR que estiver aberto.
- **Nenhum arquivo em `Sources/` é alterado.** "Logs com `.private` para caminhos" vira regra documentada, e não código, porque hoje nenhum log grava caminho (ver F27.2).

---

## F27.1 — Teste de varredura `NoNetworkTests`

### Objetivo
`swift test` (local e na CI, que já roda `swift test` em cada PR) falha se algum `.swift` em `Sources/` passar a usar uma API de rede conhecida ou um literal `http(s)://`. Assim o "sem rede" do README deixa de ser só promessa e passa a ser checado a cada mudança.

### Decisão técnica e por quê
- **Varredura de texto dos fontes, num teste Swift Testing do target existente.** Roda onde os outros testes já rodam e não precisa de ferramenta nova.
  - Descartado: SwiftLint `custom_rules`. É ferramenta nova e não roda no `swift test`.
  - Descartado: plugin de build SwiftPM. Dá mais código, deixa o build mais lento e não ganha nada sobre o teste.
  - Descartado: App Sandbox sem `network.client`. Quebraria `Process` (`claude agents`, `claude stop`) e o `kill` do `SessionTerminator`.
  - Adiado: `nm` no binário (F27.3).
- **Raiz por `#filePath` + 3× `deletingLastPathComponent()`.** No Swift 6 o `#file` vem abreviado (SE-0274), e o cwd do `swift test` muda entre Xcode, CLI e CI.
- **Regex ICU (`range(of:options: .regularExpression)`), não o `Regex` nativo.** O `\b` Unicode do `Regex` nativo não casa `\bURLSession\b` em `URLSession.shared`, e o teste ficaria verde à toa. O caso entra nos testes de prova (`pegaRede`).
- **Linha a linha, pulando linhas que começam com `//`.** Um comentário que explica "não usamos X" não quebra o build. Um `/* */` ou um comentário no fim da linha ainda dispara, e é aceito como falso positivo barato.
- **Sanidade `arquivos.count > 5`.** Com o caminho errado o enumerator volta vazio, e sem essa checagem o teste passaria sem varrer nada.
- **A lógica de casamento fica numa função `static` (`acerto(em:)`) testada com argumentos.** São só duas linhas a mais, e elas provam que a lista de padrões pega o que deve, sem precisar de fonte falsa em disco.
  - Descartado: diretório de fixtures com `.swift` falsos. Seria mais arquivo, e o `swift build` tentaria olhar para eles.
- **`@Test` síncrono.** Evita o aviso de `DirectoryEnumerator.makeIterator` em contexto async. Isso não foi confirmado, mas com teste síncrono a dúvida simplesmente não se aplica.
- **Sem `@testable import ClaudeBar`.** O teste só lê arquivos.
- **`"https?://"` proibido sem allowlist.** Hoje há 0 ocorrências em `Sources/`. Se surgir um link legítimo ("Ajuda" no menu), entra uma allowlist explícita **no teste**, com justificativa, e o padrão não é afrouxado.

### Arquivo a criar

**`Tests/ClaudeBarTests/NoNetworkTests.swift`** (exatamente o que foi compilado e rodado):
```swift
import Foundation
import Testing

/// Rede zero (F27): o app não fala com a internet. Se este teste falhar, ou a
/// mudança é rede de verdade (precisa ser opt-in, explícita e documentada no
/// README) ou é falso positivo: reescreva a linha.
@Suite("Rede zero")
struct NoNetworkTests {
    /// APIs de rede conhecidas. A lista é curta de propósito: cresce quando
    /// aparecer API nova, nunca afrouxa.
    static let proibidos = [
        #"\bimport\s+(Network|CFNetwork|WebKit)\b"#,
        #"\bURLSession\b"#, #"\bNSURLConnection\b"#,
        #"\bNW(Connection|Listener|PathMonitor|Browser|Endpoint)\b"#, #"\bnw_[a-z_]+\("#,
        #"\bCFSocket"#, #"\bCFStreamCreatePairWithSocket"#, #"getStreamsToHost"#,
        #"\bsocket\("#, #"\bgetaddrinfo\("#,
        #""https?://"#,
    ]

    /// Devolve o padrão se a linha parece rede. Comentário `//` não conta.
    static func acerto(em linha: Substring) -> String? {
        guard !linha.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { return nil }
        // ICU, não `Regex` nativo: o `\b` Unicode acha que "URLSession.shared"
        // é uma palavra só e não casa.
        return proibidos.first { linha.range(of: $0, options: .regularExpression) != nil }
    }

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

    /// Prova que a varredura pega o que deve — inclusive o caso em que o
    /// `Regex` nativo falharia — e não pega comentário nem arquivo local.
    @Test(arguments: [
        "import Network",
        "let s = URLSession.shared",
        "let c = NWConnection(host: h, port: p, using: .tcp)",
        #"let u = URL(string: "https://exemplo.com")!"#,
        "let fd = socket(AF_INET, SOCK_STREAM, 0)",
    ])
    func pegaRede(_ linha: String) {
        #expect(Self.acerto(em: Substring(linha)) != nil)
    }

    @Test(arguments: [
        "// URLSession em comentário não conta",
        "let data = try Data(contentsOf: arquivo)",
        "import Foundation",
    ])
    func ignoraNaoRede(_ linha: String) {
        #expect(Self.acerto(em: Substring(linha)) == nil)
    }
}
```

Observação: `Data(contentsOf:)` **não** entra na lista, porque `StatusDirectory.swift:68` lê arquivo local com ele. A URL remota é pega pelo literal `"https://`.

### Scripts/README
Nenhum script muda, e a CI (`.github/workflows/ci.yml`) já roda `swift test`. O README entra no F27.2.

### Verificação manual
1. `swift test`: todos passam, e a contagem sobe de 34 para 37 (ou para atual + 3, se outras features já entraram).
2. Mutação: acrescentar `let _x = URLSession.shared` a qualquer arquivo de `Sources/ClaudeBar/`, rodar `swift test --filter NoNetwork` e ver a falha `<Arquivo>.swift:<linha> parece rede (\bURLSession\b)`. Depois desfazer.
3. Rodar `swift test --filter NoNetwork` a partir de outro cwd (`cd /tmp && swift test --package-path ~/ClaudeBar --filter NoNetwork`). Tem que continuar passando, o que prova que o teste não depende do cwd.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| API de rede fora da lista (por exemplo `NSStream`, `CFHost`, `Process` chamando `curl`) | Aceito: a lista é de APIs conhecidas. Comentário `ponytail:` implícito na doc de `proibidos`. O upgrade é o F27.3 (`nm`). Chamar `curl` via `Process` exige revisão humana, que já é guard rail. |
| Dependência SwiftPM com rede | Hoje não há nenhuma. Quando entrar a primeira, fazer o F27.3 no mesmo PR. |
| Falso positivo (`socket(` num nome próprio, URL em doc comment no fim da linha) | A mensagem diz arquivo e linha. É só reescrever a linha. Não afrouxar o padrão. |
| `#filePath` aponta para um caminho que não existe (build remoto, cache) | A sanidade `count > 5` falha alto, não passa em silêncio. |
| Conflito com outra feature | Nenhum: o arquivo é novo. |

### Critérios de aceite
1. `Tests/ClaudeBarTests/NoNetworkTests.swift` existe, e `swift build --build-tests` não mostra nenhum `warning:` vindo dele.
2. `swift test` passa, com 3 testes a mais que antes.
3. A mutação da verificação manual 2 faz `swift test` sair com código diferente de 0 e citar arquivo e linha.
4. Os casos `"let s = URLSession.shared"` e `#"URL(string: "https://…")"#` estão em `pegaRede`.
5. O diff não toca `Sources/` nem `Package.swift`.

### O que NÃO fazer
- Não usar `#file`, `FileManager.default.currentDirectoryPath` nem o `Regex` nativo (`/…/` ou `Regex(...)`).
- Não proibir `contentsOf` genericamente.
- Não tornar o teste `async`.
- Não adicionar SwiftLint, plugin de build nem dependência.
- Não varrer `Tests/` (o próprio teste contém os padrões).
- Não colocar allowlist "por via das dúvidas".

---

## F27.2 — README: como verificar + regra de log

### Objetivo
Quem desconfia (a persona f) consegue provar em 1 minuto, com ferramentas do sistema, que o ClaudeBar não abre conexão. O README também explica que o tráfego do `claude` (processo filho) não é do ClaudeBar. Fica escrita a regra de log para caminhos, para ninguém marcar `.public` "só para depurar".

### Decisão técnica e por quê
- **Comandos: `lsof -i -a -c ClaudeBar` e `nettop -p ClaudeBar -L 0 -t external -n`.** Os dois são nativos e foram conferidos agora no app instalado, com saída vazia e só o cabeçalho.
  - Descartado: só o Little Snitch. É pago, então entra como opção, não como verificação principal.
  - Descartado: `tcpdump`/Wireshark. Exige root e não mostra o processo.
- **Explicar "o cabeçalho é a única linha".** No teste, o `nettop` sempre imprime o cabeçalho CSV. Sem essa explicação o usuário acha que "apareceu algo".
- **Avisar sobre `claude agents --json` sem afirmar se ele gera tráfego.** Isso não foi confirmado, então o texto diz "qualquer tráfego desse comando aparece como `claude`" e aponta para a doc do Claude Code, sem prometer zero.
  - Descartado: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` no `Shell.swift`. Mudaria o comportamento de outra ferramenta sem medição de que há tráfego. Adiar até alguém medir (ver Riscos).
- **Logs: regra documentada, sem código.** Hoje nenhum `Logger` grava caminho, `cwd` ou `sessionId` (os únicos `.public` são números, frames, `rawValue` e `localizedDescription` de erros do `UNUserNotificationCenter`). Segundo a Apple, string dinâmica já sai oculta por padrão. A regra fica: caminho, `cwd`, `sessionId` e `message` usam `privacy: .private(mask: .hash)`, explícito (o hash por processo permite correlacionar a mesma sessão no Console).
  - Descartado: um teste regex de `.public` em nomes de caminho. Não existe hoje nenhum log de caminho para proteger. Adicionar quando surgir o primeiro.
  - Descartado: trocar os `.public` de `Notifier.swift:133/146`. Não está confirmado que esses erros nunca trazem caminho, mas eles vêm do `UNUserNotificationCenter` (autorização e entrega), não de `FileManager`. Ficam como estão, e a regra do README cobre os logs novos.
  - Fora do escopo: o `claudebar-hook` escreve `error.localizedDescription` no stderr (`main.swift:69`), que pode conter o caminho do arquivo de estado. Isso vai para o Claude Code local, não para a rede nem para o log do sistema. Não mexer.

### Arquivos a alterar

**`README.md`**: nova subseção no fim de `## Security`, antes de `## Uninstall`, e o primeiro bullet passa a apontar para ela.
```md
- **No secrets in the project.** The app makes no network calls (see
  [Verify it yourself](#verify-it-yourself)), does not authenticate anywhere,
  and does not read conversation history — only project paths, `sessionId`,
  session state and the hook's notification message.
…
- **Paths are never logged in the clear.** Any log line with a path, `cwd`,
  `sessionId` or hook message uses `privacy: .private(mask: .hash)`; never
  `.public`.

### Verify it yourself

ClaudeBar opens no network connections. A test (`NoNetworkTests`) fails
`swift test` if networking code is ever added to `Sources/`. To check the
running app:

    lsof -i -a -c ClaudeBar                     # prints nothing
    nettop -p ClaudeBar -L 0 -t external -n     # only the CSV header line; Ctrl-C to stop

With Little Snitch: open Network Monitor and search for "ClaudeBar". It should
never show a connection.

Note: ClaudeBar runs `claude agents --json` (and `claude stop` when you
terminate a subagent). Any traffic from those commands shows up under
`claude`, not ClaudeBar: it belongs to Claude Code and follows its settings
(https://code.claude.com/docs/en/data-usage#telemetry-services).
```

Na `## Project structure`, a linha de testes passa a ser:
```
Tests/ClaudeBarTests/         subagents, count, icon, precedence, real kills, no network
```

**`README.pt-BR.md`**: o mesmo conteúdo, com a âncora em português.
```md
- **Sem segredo nenhum no projeto.** O app não fala com rede (veja
  [Confira você mesmo](#confira-você-mesmo)), não autentica em nada e não lê o
  histórico das conversas — só caminhos de projeto, `sessionId`, o estado da
  sessão e a mensagem de notificação do hook.
…
- **Caminhos nunca vão em claro para o log.** Linha de log com caminho, `cwd`,
  `sessionId` ou mensagem do hook usa `privacy: .private(mask: .hash)`; nunca
  `.public`.

### Confira você mesmo

O ClaudeBar não abre conexão de rede. Um teste (`NoNetworkTests`) faz o
`swift test` falhar se entrar código de rede em `Sources/`. Para conferir o
app rodando:

    lsof -i -a -c ClaudeBar                     # não imprime nada
    nettop -p ClaudeBar -L 0 -t external -n     # só a linha de cabeçalho CSV; Ctrl-C para parar

Com o Little Snitch: abra o Network Monitor e busque "ClaudeBar". Não deve
aparecer conexão nenhuma.

Atenção: o ClaudeBar roda `claude agents --json` (e `claude stop` quando você
encerra um subagente). Qualquer tráfego desses comandos aparece como `claude`,
não como ClaudeBar: é do Claude Code e segue as configurações dele
(https://code.claude.com/docs/en/data-usage#telemetry-services).
```

A URL da doc no README **não** quebra o F27.1, porque o teste só varre `Sources/`.

### Testes
Nenhum novo. É documentação, e o F27.1 cobre o código.

### Verificação manual
1. Com o app instalado aberto: `lsof -i -a -c ClaudeBar` não imprime nada. `nettop -p ClaudeBar -L 0 -t external -n` mostra só o cabeçalho por ~30 s, incluindo um ciclo de polling (5 s) e um popup ("Ver exemplo de popup").
2. Clicar nas âncoras `#verify-it-yourself` e `#confira-você-mesmo` no GitHub (preview do PR) e confirmar que rolam até a seção.
3. Opcional, só para responder a dúvida da pesquisa: fechar todas as sessões interativas do `claude` e rodar `nettop -p claude -L 0 -t external -n` com o app aberto. Linhas `claude.<pid>` = tráfego do `agents --json`. Registrar o resultado no PR. Não muda o texto do README.

### Riscos e mitigação
| Risco | Status | Mitigação |
|---|---|---|
| `claude agents --json` gera tráfego (telemetria/flags) e o usuário culpa o app | **não confirmado** | O texto já atribui ao `claude` e linka a doc. Se a verificação 3 mostrar tráfego, abrir item separado para avaliar `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` no `environment` do `Process` (`Shell.swift`), testando se o `agents --json` continua igual. Não fazer agora. |
| Nome do processo truncado no `nettop -p` | conferido: `ClaudeBar` funciona | Se uma versão futura do macOS mudar isso, `nettop -p $(pgrep -x ClaudeBar)` é a alternativa. Não pôr no README agora. |
| Algum framework do sistema abrir socket em nome do app (o `lsof` deixaria de sair vazio) | conferido vazio hoje | Se aparecer, o README está errado: investigar antes de mexer no texto. O F27.1 não pegaria esse caso. |
| Como o Little Snitch mostra app com assinatura ad-hoc | **não confirmado** | O texto só manda buscar "ClaudeBar", sem descrever ícone ou status de assinatura. |
| O valor oculto aparecer como `<private>` no `log stream` | **não confirmado** | O README diz "never in the clear" e não cita o literal. |
| Conflito de merge nos READMEs | provável | Seção nova no fim de `Security`, um trecho isolado. É só rebase. |

### Critérios de aceite
1. `README.md` tem `### Verify it yourself` com os dois comandos (`lsof -i -a -c ClaudeBar`, `nettop -p ClaudeBar -L 0 -t external -n`), a menção ao Little Snitch e a nota sobre `claude`.
2. `README.pt-BR.md` tem `### Confira você mesmo` com o mesmo conteúdo.
3. Os dois READMEs têm o bullet da regra `privacy: .private(mask: .hash)` e citam `NoNetworkTests`.
4. A verificação manual 1 foi feita, ou está registrada no PR como "não verificado".
5. O diff não toca `Sources/`.

### O que NÃO fazer
- Não prometer que o `claude` não usa rede.
- Não pôr `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` no código.
- Não trocar `.public` existente nem adicionar `.private` em log que não tem caminho (diff sem ganho).
- Não citar o literal `<private>`.
- Não recomendar App Sandbox.
- Não criar CONTRIBUTING.md só para essa regra (o README basta).

---

## F27.3 — Checagem `nm` no `build-app.sh` (adiar)

Registrado para quem pegar depois. Fazer no **mesmo PR que adicionar a primeira dependência SwiftPM** ou o primeiro `Process` que chame ferramenta de rede. Hoje é redundante: os binários release estão limpos (conferido nesta spec), e o F27.1 cobre os fontes.

Trecho pronto, a entrar em `scripts/build-app.sh` logo depois dos dois `cp` dos binários e antes do `Info.plist`:
```bash
echo "==> Conferindo que os binários não importam rede"
if nm -u "$BUNDLE/Contents/MacOS/"* | grep -E 'NSURLSession|_nw_|CFSocket|_socket$|_connect$|_getaddrinfo$'; then
  echo "ERRO: binário importa símbolo de rede (F27)"; exit 1
fi
```
Critério de aceite quando for feito: o `./scripts/build-app.sh` atual passa, e um build com `URLSession.shared` em qualquer fonte sai com código diferente de 0 nesse passo. A CI já roda o script.

---

## Guard rails
- Sem rede: este é o objeto da feature.
- Não ler conversas, permissões `0700`/`0600`, shell com interpolação e hook fail-open: nada disso é tocado, porque `Sources/` não muda.

## Resumo de esforço
- F27.1: 0,5 h.
- F27.2: 0,5 h.
- F27.3: adiado (0,25 h quando entrar).
- Total agora: ~1 h.
