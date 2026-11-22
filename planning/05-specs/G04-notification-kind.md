# G04 — Spec técnica: `Notification` por tipo (F05) + permissão × pergunta (F24)

Insumos: `04-como-fazer/G04-notification-kind.md`, `03-validacao/BACKLOG.md` (F05: P0, P, bug, depende de F02; F24: P2, P, inovação, depende de F05), `00-PLANO.md` (guard rails).
Código lido em 2026-11-15 (`main` @ f943cc4).

**Verificado nesta spec.** Os trechos abaixo foram aplicados numa cópia do projeto real (Swift 6, tools 6.0):
- `swift build`: 0 avisos. `swift test`: **47 testes passam** (34 atuais + 4 do F05 + 9 do F24).
- O `claudebar-hook` compilado foi rodado com `CFFIXED_USER_HOME=<pasta temporária>`, que isola o `NSHomeDirectory()` e por isso não toca o `~/.claude/claudebar` real. Resultado: `question` seguido de `permission` mantém `question`, `working` limpa o `kind`, `permission` depois de `working` grava `permission`, `--kind zzz` não grava `kind`, e um estado inválido sai com código 1.
- O trecho `jq` alternativo do F05 foi rodado e gera o JSON esperado.
- SF Symbols no macOS 14: conferido em `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist`. `hand.raised.fill` = 2019 (macOS 10.15), `questionmark.bubble.fill` = 2022 (macOS 13), `exclamationmark.bubble.fill` = 2019. Isso **fecha** o "não confirmado" da pesquisa.
- Correção da pesquisa: a função que apaga o arquivo que não decodifica é `StatusDirectory.readAll` (linha 59), não `list`.

## Resumo para o gestor

| Id | PR | Arquivos | Esforço |
|---|---|---|---|
| **F05** | `Notification` só para `permission_prompt`/`elicitation_dialog`, `kind` no arquivo | `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/claudebar-hook/main.swift`, instalador do F02 (ou `scripts/install.sh`), `Tests/ClaudeBarTests/SessionStatusTests.swift` (novo), `README.md`, `README.pt-BR.md` | 1,5 h |
| **F24** | Símbolo, texto e som distintos + `AskUserQuestion` | `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/claudebar-hook/main.swift`, `Sources/ClaudeBar/SessionRow.swift`, `Sources/ClaudeBar/SessionMerge.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/StatusHUD.swift`, instalador do F02, `Tests/ClaudeBarTests/SessionStatusTests.swift`, `Tests/ClaudeBarTests/SessionMergeTests.swift`, `Tests/ClaudeBarTests/AlertTests.swift`, `README.md`, `README.pt-BR.md` | 2,5 h |

Ordem e conflitos:
- **F02 → F05 → F24.** F24 **não pode** sair com o `jq` atual do `install.sh`. O `jq` substitui o array inteiro de cada evento, e o F24 registra `PreToolUse`/`PostToolUse`, que é onde o usuário costuma ter os próprios hooks. Sairia apagando esses hooks. O F05 pode sair antes do F02 só pela variante `jq`, porque hoje o array `Notification` já é substituído.
- **Decisão de escopo (registrar no backlog).** As entradas `PreToolUse`/`PostToolUse` de `AskUserQuestion` e a regra "permissão não apaga pergunta" ficam no **F24**, não no F05. Para o F05 (fim do "esperando" falso) basta o `Notification` com matcher: a pergunta continua aparecendo como "esperando", só que com `kind` errado, e isso só importa quando alguém lê o `kind`, que é o F24. Assim o F05 fica literal ao backlog.
- O F07 (G06) também mexe em `SessionStatus.swift`, `SessionStore.swift` (`BarState`, `notifyTransitions`), `SessionMerge.barState` e `MenuContent.swift`. Rodar em sequência. Quem entrar depois acrescenta o próprio ramo; ver a nota de rebase em cada código abaixo.
- O F01 (G01) mexe no `init`/`post` do `Notifier`. O F24 só mexe no `enum Alert` e no `showSample`, então não conflita em linha.
- F12, F13, F19 e F25 virão depois e vão ler `row.kind`/`Alert`. Nada aqui os bloqueia.

---

## F05 — `Notification` com matchers

### Objetivo
"Esperando você" só aparece quando o Claude realmente espera você: um pedido de permissão (`permission_prompt`) ou um formulário de servidor MCP (`elicitation_dialog`). `idle_prompt`, `auth_success`, `agent_completed`, `quota_*` etc. deixam de virar `waiting`. Hoje, cerca de 60 s depois de cada resposta, o `idle_prompt` troca "pronto" por "esperando", e é por isso que "o contador mente". O tipo da espera fica gravado no arquivo (`kind`), pronto para o F24.

### Decisão técnica e por quê
- **Uma entrada por tipo, com matcher e o tipo no argumento** (`waiting --kind permission`). É exatamente o formato do exemplo da doc oficial. O matcher `permission_prompt` só tem letras e `_`, e por isso cai no caminho de string exata, não no de regex. O tipo vem do argv, que o instalador escreveu, e não do `notification_type` do payload: uma versão antiga não mandava o campo (#11964), e o matcher já garante o tipo.
- **`kind: String?` no arquivo e `enum WaitKind` só para ler.** Com `String?`, um valor desconhecido nunca quebra o decode. Um `enum` armazenado com valor novo (hook mais novo que o app, ou downgrade) faz `try? decode` falhar, e `readAll` **apaga o arquivo**. O `WaitKind` existe para o hook validar o argumento e para a UI ter `switch` exaustivo. `waitKind` converte e devolve `nil` (genérico) para valor desconhecido. Testado: JSON sem a chave dá `nil`, e `"kind":"plan"` decodifica normalmente.
- **`kind` só existe com `waiting`.** O hook descarta `--kind` em outros estados, então `working`/`idle` nunca carregam um tipo velho.
- **`fail` sai com 1, não com 2.** O código 2 é "bloqueante": no `UserPromptSubmit` ele **apaga o prompt** do usuário, e no `PreToolUse` (F24) bloqueia a ferramenta. Qualquer outro código não-zero só vira aviso. Isso aplica o guard rail "hook nunca quebra a sessão" a um caso que hoje não se cumpre. É uma linha, então entra já, no primeiro PR que toca o hook.

Descartadas:
- Um `Notification` sem matcher, filtrando `notification_type` dentro do binário: a regra fica escondida no executável, ao contrário do que o F16 pede (mostrar o que está instalado), e o processo sobe para todo tipo de notificação.
- `enum WaitKind: Codable` armazenado: um valor desconhecido apaga o arquivo da sessão (acima).
- `init(from:)` manual com `try?`: mais código para o mesmo efeito do `String?`.
- Registrar também `elicitation_url_dialog`: fica fora do backlog. Se entrar depois, é só trocar o matcher por `elicitation_dialog|elicitation_url_dialog`.
- `PermissionRequest`: dispara imediato e marca "esperando" enquanto você ainda está olhando o terminal.

### Código

**`Sources/ClaudeBarCore/SessionStatus.swift`**: depois de `enum SessionState`:
```swift
/// Por que a sessão está esperando você.
///
/// No arquivo o campo é texto (`kind: String?`), não este enum: um valor que o
/// app não conhece (hook mais novo, downgrade) faria o decode falhar, e
/// `StatusDirectory.readAll` apaga arquivo que não decodifica.
public enum WaitKind: String, Sendable {
    /// Aprovar uma ferramenta (`Notification` `permission_prompt`).
    case permission
    /// Responder uma pergunta (`AskUserQuestion`, formulário de servidor MCP).
    case question
}
```
Em `SessionStatus`, depois de `message`:
```swift
    public let message: String?
    /// `WaitKind` em texto. `nil` em arquivo antigo e fora de `waiting`.
    public let kind: String?

    public var id: String { sessionId }

    /// O `kind` que o app sabe mostrar; valor desconhecido vira `nil` (genérico).
    public var waitKind: WaitKind? {
        kind.flatMap(WaitKind.init(rawValue:))
    }
```
`init`: um parâmetro a mais, com padrão. Assim todas as chamadas atuais, inclusive as dos testes, continuam compilando:
```swift
        message: String? = nil,
        kind: WaitKind? = nil
    ) {
        ...
        self.message = message
        self.kind = kind?.rawValue
    }
```
O `Codable` sintetizado usa `decodeIfPresent`/`encodeIfPresent` para `Optional`. Sem `kind`, a chave nem é gravada, e o arquivo fica idêntico ao de hoje (teste `semKindNaoGravaAChave`). `Sendable`/`Equatable` continuam sintetizados.

**`Sources/claudebar-hook/main.swift`**:
```swift
// Uso: claudebar-hook <working|idle|waiting|end> [--kind <permission|question>] [--pid <pid do claude>]
```
```swift
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("claudebar-hook: \(message)\n".utf8))
    // 2 bloqueia a ferramenta no PreToolUse e apaga o prompt no
    // UserPromptSubmit. Qualquer outro código só vira aviso: fail-open.
    exit(1)
}

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
}

private func parsePID(_ arguments: [String]) -> Int32 {
    value(after: "--pid", in: arguments).flatMap { Int32($0) } ?? 0
}
```
Em `run()`, depois do `guard let state` e antes de montar o status:
```swift
    // O tipo vem do argumento que o instalador escreveu (um matcher por tipo),
    // não do payload: `notification_type` já faltou em versão antiga do Claude
    // Code. Valor desconhecido ou fora de `waiting` fica `nil` (genérico).
    let kind = state == .waiting
        ? value(after: "--kind", in: arguments).flatMap(WaitKind.init(rawValue:))
        : nil

    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: payload?.cwd ?? FileManager.default.currentDirectoryPath,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: payload?.message.map { String($0.prefix(200)) },
        kind: kind
    )
```
`HookPayload` **não muda**: nem `notification_type`, nem `title`.

**Instalador.** O caminho preferido é o F02 já em `main`. Nesse caso, troque a entrada `Notification` dele por duas, no formato do instalador do F02 (exec form, com `args`, como na G03):
```json
"Notification": [
  { "matcher": "permission_prompt",  "hooks": [{ "type": "command", "command": "<hook>", "args": ["waiting", "--kind", "permission"], "timeout": 5 }] },
  { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "<hook>", "args": ["waiting", "--kind", "question"], "timeout": 5 }] }
]
```
(O `--pid` segue o que o F02 decidir para o exec form, que não expande `$PPID`. Não é decisão deste item.)
A desinstalação do F02 identifica as entradas pelo caminho do executável, então as duas saem sem código novo. O teste do F02 que confere as entradas registradas passa a esperar dois grupos em `Notification`, cada um com `matcher`.

Variante `jq`, se o F05 entrar antes do F02 (verificada). Em `scripts/install.sh`:
```bash
jq --arg hook "$HOOK" '
  def entry($state): [{ hooks: [{ type: "command", command: ($hook + " " + $state + " --pid $PPID") }] }];
  # Notification só para o que de fato espera você: um matcher por tipo.
  def matched($matcher; $args): { matcher: $matcher, hooks: [{ type: "command", command: ($hook + " " + $args + " --pid $PPID") }] };
  .hooks = ((.hooks // {}) + {
    UserPromptSubmit: entry("working"),
    Stop: entry("idle"),
    Notification: [
      matched("permission_prompt"; "waiting --kind permission"),
      matched("elicitation_dialog"; "waiting --kind question")
    ],
    SessionEnd: entry("end")
  })
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

### Testes: `Tests/ClaudeBarTests/SessionStatusTests.swift` (novo)
```swift
import ClaudeBarCore
import Foundation
import Testing

@Suite("Arquivo de estado")
struct SessionStatusTests {
    private func decode(_ json: String) throws -> SessionStatus {
        try StatusDirectory.decoder.decode(SessionStatus.self, from: Data(json.utf8))
    }

    /// Arquivo gravado antes do F05 não tem `kind`. Se o decode falhasse,
    /// `readAll` apagaria o estado de todas as sessões na atualização.
    @Test func arquivoAntigoSemKindDecodifica() throws {
        let status = try decode(#"{"sessionId":"s","state":"waiting","cwd":"/tmp","pid":1,"updatedAt":0}"#)
        #expect(status.kind == nil)
        #expect(status.waitKind == nil)
    }

    /// Valor que este app não conhece não derruba o decode: vira genérico.
    @Test func kindDesconhecidoDecodificaComoGenerico() throws {
        let status = try decode(#"{"sessionId":"s","state":"waiting","cwd":"/tmp","pid":1,"updatedAt":0,"kind":"plan"}"#)
        #expect(status.kind == "plan")
        #expect(status.waitKind == nil)
    }

    @Test func kindSobreviveAoEncodeEDecode() throws {
        let original = SessionStatus(sessionId: "s", state: .waiting, cwd: "/tmp", pid: 1, kind: .question)
        let data = try StatusDirectory.encoder.encode(original)
        #expect(try StatusDirectory.decoder.decode(SessionStatus.self, from: data).waitKind == .question)
    }

    /// Sem `kind`, a chave nem é gravada: o arquivo continua igual ao de antes.
    @Test func semKindNaoGravaAChave() throws {
        let data = try StatusDirectory.encoder.encode(
            SessionStatus(sessionId: "s", state: .working, cwd: "/tmp", pid: 1)
        )
        #expect(!String(decoding: data, as: UTF8.self).contains("kind"))
    }
}
```
Sem teste de unidade: o parse de `--kind` e o `exit(1)`. Os dois estão no target executável, que tem código top-level e não é importável pelos testes. Extrair só para testar não compensa nesse tamanho, e a verificação manual (passos 2 e 3) cobre os dois.

### README (`README.md` e `README.pt-BR.md`)
- Tabela de hooks: `Notification` passa a `Notification` (`permission_prompt`, `elicitation_dialog`) | `waiting`, e acrescentar: "other notification types (idle reminder, auth, quota…) are not registered" / "os demais tipos (lembrete de ociosidade, autenticação, cota…) não são registrados".
- Exemplo de arquivo de estado: acrescentar `"kind" : "permission",`.
- Uso do CLI: `claudebar-hook <working|idle|waiting|end> [--kind <permission|question>] [--pid <claude pid>]`.
- Instalação: deixar dito que `Notification` agora usa dois matchers. Se ainda for o `jq`, manter o aviso de que ele é substituído.
- Desenvolvimento: um exemplo `... claudebar-hook waiting --kind permission --pid 1`.

### Verificação manual
1. `swift build && swift test` verdes, 38 testes.
2. Simulação isolada (não toca o estado real nem dispara alerta no app aberto):
   ```bash
   swift build
   export CFFIXED_USER_HOME="$(mktemp -d)"
   echo '{"session_id":"t","cwd":"/tmp","notification_type":"permission_prompt"}' | .build/debug/claudebar-hook waiting --kind permission --pid 1
   cat "$CFFIXED_USER_HOME/.claude/claudebar/t.json"     # "kind" : "permission"
   echo '{"session_id":"t","cwd":"/tmp"}' | .build/debug/claudebar-hook working --pid 1
   grep -c kind "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # 0
   echo '{"session_id":"t","cwd":"/tmp"}' | .build/debug/claudebar-hook waiting --kind zzz --pid 1
   grep -c kind "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # 0
   .build/debug/claudebar-hook bogus </dev/null; echo $?        # 1, não 2
   unset CFFIXED_USER_HOME
   ```
3. `./scripts/install.sh` (ou o instalador do F02). Em `~/.claude/settings.json`, `Notification` tem dois grupos com `matcher`. Numa sessão nova, `/hooks` lista os dois sem aviso de settings inválido.
4. Com `claude` real, numa pasta temporária:
   - Mande um prompt simples, espere o ✅ e **fique 90 s sem mexer**. A linha continua "pronto" e não aparece aviso de "esperando". **Este é o bug do F05.**
   - Peça um `Bash` fora da allowlist e espere 6 s sem digitar. O estado vira "aguardando você" e o arquivo tem `"kind" : "permission"`.
5. Atualização sem perda: com o app antigo rodando e uma sessão aberta, instale o build novo. A sessão continua no menu, porque o arquivo sem `kind` decodifica.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Decode quebrar e `readAll` apagar os estados na atualização | `kind: String?` + os testes `arquivoAntigoSemKindDecodifica` e `kindDesconhecidoDecodificaComoGenerico`. A revisão deve recusar `kind` como enum armazenado. |
| App antigo lendo arquivo novo | Chave extra é ignorada pelo `Codable` sintetizado, sem perda. |
| Nome do matcher mudar numa versão futura do Claude Code | É string exata: se o tipo sumir, o hook simplesmente não dispara, e "esperando" volta a vir só do `claude agents --json` (`waiting`/`blocked`). É fail-safe, não é "esperando" falso. A verificação 3 confere os nomes na versão instalada. |
| `--kind` com valor estranho (settings editado à mão) | `WaitKind(rawValue:)` descarta e grava sem `kind`. Não falha e não sai com 2. |
| `permission_prompt` sai só após ~6 s sem digitar | É o comportamento documentado e aceito (alternativa `PermissionRequest` descartada). README: "after a few seconds without typing". |
| Variante `jq` continua substituindo `Notification` do usuário | Comportamento de hoje, já documentado. O F02 resolve. |
| Depois de aprovar uma permissão, nada volta o estado a `working` até `Stop`/`UserPromptSubmit` | Já acontece hoje e está fora do F05. Registrar como item novo no backlog (`PostToolUse` sem matcher → `working`). **Não** resolver aqui. |

### Critérios de aceite
- O instalador registra `Notification` com exatamente dois grupos: `permission_prompt` → `waiting --kind permission` e `elicitation_dialog` → `waiting --kind question`. Não sobra nenhum grupo `Notification` do ClaudeBar sem matcher.
- `SessionStatus.kind` é `String?`. `WaitKind` não é `Codable`.
- Os 4 testes novos passam. `swift test` = 38, nenhum removido, `swift build` sem avisos.
- `claudebar-hook` com estado inválido sai com 1 (passo 2).
- Passo 4: 90 s depois de "pronto", a sessão **não** vira "esperando".
- `HookPayload` continua com só `session_id`, `cwd`, `message`.
- README em inglês e em português atualizados (hooks, exemplo do arquivo, uso do CLI).

### O que NÃO fazer
- Não ler `notification_type` nem `title` do payload. O tipo vem do argv.
- Não guardar `kind` como enum `Codable`.
- Não registrar `idle_prompt`, `agent_needs_input` ou `elicitation_url_dialog` (fora do backlog).
- Não mudar UI neste PR. Símbolo, texto e som são o F24.
- Não adicionar `PreToolUse`/`PostToolUse` aqui (F24, e só depois do F02).
- Não usar `PermissionRequest`.

---

## F24 — Permissão × pergunta

### Objetivo
Saber pelo ícone, pelo texto e pelo som se o Claude quer **aprovar uma ferramenta** ou **uma resposta sua**:

| `kind` | barra | menu | título do popup | som |
|---|---|---|---|---|
| `permission` | `hand.raised.fill` | ✋ "pede permissão" | "Claude pede permissão" | `Submarine` 75% |
| `question` | `questionmark.bubble.fill` | ❓ "fez uma pergunta" | "Claude fez uma pergunta" | `Purr` 75% |
| `nil` (só o CLI sabe, ou arquivo antigo) | `exclamationmark.bubble.fill` | 🔸 "aguardando você" | "Claude está esperando você" | `Submarine` 75% |

### Decisão técnica e por quê
- **`PreToolUse` com matcher `AskUserQuestion` → `waiting --kind question`; `PostToolUse` com matcher `AskUserQuestion` → `working`.** Sem isso o F24 não entrega o caso comum. O `AskUserQuestion` chega no `Notification` como `permission_prompt` (#74052, fechada sem correção; #16102), e o `elicitation_dialog` cobre só formulário de MCP. A pergunta passa a aparecer na hora, sem os 6 s. O hook não decodifica `tool_input` (o texto da pergunta é conversa), então o popup mostra o nome do projeto.
- **Regra no hook: `waiting/permission` não sobrescreve `waiting/question`.** Ela absorve o `permission_prompt` falso que chega ~6 s depois da pergunta. É uma função pura em Core (`SessionStatus.absorbs`), testável. O hook lê o arquivo atual com `try?`: se faltar ou estiver ilegível, grava normalmente (fail-open). O `PostToolUse` volta a sessão para `working` e libera a próxima permissão real.
- **Ícone da barra: permissão > genérico > pergunta.** Permissão trava uma ferramenta já em andamento. "Pergunta" só aparece quando **todas** as esperas são pergunta, porque uma espera sem tipo pode ser permissão e não deve se esconder atrás de "pergunta". Uma linha a mais que a sugestão da pesquisa (permissão > pergunta > genérico), e mais honesta.
- **`BarState` e `Alert` ganham dois casos simples (`.permission`, `.question`), sem valor associado.** `.waiting` continua sendo o genérico. Com isso os testes existentes (`== .waiting`) ficam intactos, os `switch` continuam exaustivos e `Alert` segue `Equatable` sintetizado. `Alert(waiting:)` faz o mapeamento num lugar só, e esse lugar é testável.
- **`notifyTransitions` compara `(state, kind)`.** Guardar a `SessionRow` anterior no lugar do `SessionState` é uma linha. Pergunta → permissão real (o caso raro que não é absorvido) avisa de novo.
- **Som da pergunta: `Purr`.** É diferente de `Glass` (sino) e de `Submarine` (pulso). A escolha é gosto (não confirmado como UX) e fica numa linha, fácil de trocar no F15.

Descartadas:
- Só `Notification` (escopo literal): quase toda pergunta apareceria como "permissão".
- Filtrar `notification_type` no binário: lógica escondida (F16).
- `PermissionRequest`: dispara imediato e é ruído enquanto você ainda olha o terminal.
- `BarState.waiting(WaitKind?)` com valor associado: quebra os testes atuais e exige `Equatable` manual, sem ganho.
- Ler `tool_input.questions[0].question` para mostrar a pergunta no popup: é conteúdo da conversa (guard rail). Isso é o F38, atrás do F25.

### Código

**`Sources/ClaudeBarCore/SessionStatus.swift`**: em `SessionStatus`, depois de `waitKind`:
```swift
    /// O `AskUserQuestion` grava a pergunta na hora (`PreToolUse`) e, ~6 s
    /// depois, o Claude Code dispara um `permission_prompt` para a mesma tela.
    /// Essa "permissão" não pode apagar a pergunta aberta; quem libera é o
    /// `PostToolUse`, que volta a sessão para `working`.
    public func absorbs(_ state: SessionState, kind: WaitKind?) -> Bool {
        self.state == .waiting && waitKind == .question && state == .waiting && kind == .permission
    }
```

**`Sources/claudebar-hook/main.swift`**: em `run()`, entre o `let kind` (F05) e o `let status`:
```swift
    // Pergunta aberta vence a "permissão" que o AskUserQuestion dispara depois.
    // Sem arquivo ou arquivo ilegível: grava normalmente.
    if let data = try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)),
       let current = try? StatusDirectory.decoder.decode(SessionStatus.self, from: data),
       current.absorbs(state, kind: kind) {
        return
    }
```
Corrida: dois hooks da mesma sessão ao mesmo tempo (o `PostToolUse` e o `permission_prompt` atrasado) podem intercalar leitura e escrita. O pior caso é ficar "pergunta" ou "permissão" até o próximo evento, e a escrita continua atômica. Não colocar lock.

**`Sources/ClaudeBar/SessionRow.swift`**:
```swift
    let message: String?
    /// Por que está esperando. Só vem do hook; sessão que só o CLI conhece fica
    /// `nil` e aparece com o texto genérico.
    let kind: WaitKind?
```
`init` ganha `kind: WaitKind? = nil` como **último** parâmetro (depois de `backgroundId`), e `self.kind = kind`. Com o padrão, todas as chamadas atuais continuam compilando.

**`Sources/ClaudeBar/SessionMerge.swift`**: nas duas construções de `SessionRow`:
```swift
                backgroundId: agent.isSubagent ? agent.id : nil,
                kind: hook?.waitKind
```
```swift
                    pid: status.pid,
                    kind: status.waitKind
```
Em `barState`, troque a linha do `.waiting` por:
```swift
        let waiting = own.filter { $0.state == .waiting }
        // Permissão vence: trava uma ferramenta já em andamento. Só mostra
        // "pergunta" quando todas as esperas são pergunta; tipo desconhecido
        // pode ser permissão, então cai no genérico.
        if waiting.contains(where: { $0.kind == .permission }) { return .permission }
        if !waiting.isEmpty {
            return waiting.allSatisfy { $0.kind == .question } ? .question : .waiting
        }
```
(Se o F07 entrar antes, a linha do `.error` vem logo depois deste bloco, sem outra mudança.)

**`Sources/ClaudeBar/SessionStore.swift`**:
```swift
enum BarState {
    /// Alguma sessão pede permissão para usar uma ferramenta.
    case permission
    /// Todas as sessões que esperam você fizeram uma pergunta.
    case question
    /// Alguma sessão está esperando você, sem saber por quê (sessão que só o
    /// CLI conhece, ou arquivo gravado antes do `kind`).
    case waiting
    ...
    var symbolName: String {
        switch self {
        case .permission: "hand.raised.fill"
        case .question: "questionmark.bubble.fill"
        case .waiting: "exclamationmark.bubble.fill"
        ...
```
```swift
    /// Última linha conhecida de cada sessão, para detectar transições.
    private var previousRows: [String: SessionRow] = [:]
```
Em `merge()`:
```swift
        previousRows = Dictionary(uniqueKeysWithValues: merged.map { ($0.sessionId, $0) })
```
Em `notifyTransitions`:
```swift
        for row in merged where !row.isSubagent {
            // Pergunta que vira permissão (ou o contrário) avisa de novo.
            guard let previous = previousRows[row.sessionId],
                  previous.state != row.state || previous.kind != row.kind
            else { continue }

            switch row.state {
            case .idle where previous.state == .working:
                acknowledged.remove(row.sessionId)
                notifier.post(.finished, body: row.name)
            case .waiting:
                acknowledged.remove(row.sessionId)
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto quando ele está travado.
                // Na pergunta não há `message`: o texto dela é conversa e o
                // hook não lê. Fica o nome do projeto.
                notifier.post(Alert(waiting: row.kind), body: row.message ?? row.name)
            default:
                break
            }
        }
```

**`Sources/ClaudeBar/Notifier.swift`**: `import ClaudeBarCore` no topo. Em `enum Alert`:
```swift
    /// A sessão está travada esperando você, sem saber por quê.
    case waiting
    /// O Claude quer aprovar uma ferramenta.
    case permission
    /// O Claude fez uma pergunta e espera a resposta.
    case question

    init(waiting kind: WaitKind?) {
        self = switch kind {
        case .permission: .permission
        case .question: .question
        case nil: .waiting
        }
    }

    var title: String {
        switch self {
        case .finished: "Claude terminou"
        case .waiting: "Claude está esperando você"
        case .permission: "Claude pede permissão"
        case .question: "Claude fez uma pergunta"
        }
    }

    var soundName: String {
        switch self {
        case .finished: "Glass"
        case .waiting, .permission: "Submarine"
        // Grave e curto, diferente do sino e do pulso: dá para saber que é
        // pergunta sem olhar.
        case .question: "Purr"
        }
    }

    var volume: Float {
        switch self {
        case .finished: 1
        case .waiting, .permission, .question: 0.75
        }
    }
```
Em `showSample`: `post(.permission, body: "Exemplo: Claude needs your permission to use Bash")`.

**`Sources/ClaudeBar/StatusHUD.swift`** (`HUDView`):
```swift
    private var symbolName: String {
        switch alert {
        case .finished: "checkmark.circle.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .permission: "hand.raised.fill"
        case .question: "questionmark.bubble.fill"
        }
    }

    private var tint: Color {
        switch alert {
        case .finished: .green
        case .waiting, .permission: .orange
        case .question: .blue
        }
    }
```

**`Sources/ClaudeBar/MenuContent.swift`**: `label(for:)` passa a linha inteira:
```swift
        var text = "\(icon(for: row))  "
        ...
        text += "\(row.name) — \(description(for: row))"
```
```swift
    private func icon(for row: SessionRow) -> String {
        switch (row.state, row.kind) {
        case (.working, _): "⏳"
        case (.idle, _): "✅"
        case (.waiting, .permission): "✋"
        case (.waiting, .question): "❓"
        case (.waiting, nil): "🔸"
        }
    }

    private func description(for row: SessionRow) -> String {
        switch (row.state, row.kind) {
        case (.working, _): "processando"
        case (.idle, _): "pronto"
        case (.waiting, .permission): "pede permissão"
        case (.waiting, .question): "fez uma pergunta"
        case (.waiting, nil): "aguardando você"
        }
    }
```
(Se o F07 entrar antes: `case (.error, _): "⚠️"` / `"falhou"`. O compilador cobra, porque o `switch` de tupla é exaustivo.)

**Instalador (só o do F02; nunca o `jq`)**: duas entradas a mais. Elas se juntam aos hooks `PreToolUse`/`PostToolUse` que o usuário já tenha:
```json
"PreToolUse":  [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "<hook>", "args": ["waiting", "--kind", "question"], "timeout": 5 }] }],
"PostToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "<hook>", "args": ["working"], "timeout": 5 }] }]
```
O hook não imprime nada no stdout e sai com 0 (ou 1 em erro de argumento). No `PreToolUse` isso quer dizer "sem decisão": a pergunta segue normalmente. A remoção do F02 (pelo caminho do executável) tira as duas.

### Testes
`Tests/ClaudeBarTests/SessionStatusTests.swift`, uma suíte a mais:
```swift
@Suite("Permissão × pergunta")
struct WaitKindTests {
    private func waiting(_ id: String, _ kind: WaitKind?) -> SessionStatus {
        SessionStatus(sessionId: id, state: .waiting, cwd: "/tmp", pid: 1, kind: kind)
    }

    /// O `permission_prompt` que o AskUserQuestion dispara ~6 s depois não
    /// troca "pergunta" por "permissão".
    @Test func permissaoNaoApagaPerguntaAberta() {
        #expect(waiting("s", .question).absorbs(.waiting, kind: .permission))
    }

    @Test func soAPermissaoSobreAPerguntaEhAbsorvida() {
        let pergunta = waiting("s", .question)
        #expect(!pergunta.absorbs(.working, kind: nil))
        #expect(!pergunta.absorbs(.idle, kind: nil))
        #expect(!pergunta.absorbs(.waiting, kind: .question))
        #expect(!waiting("s", .permission).absorbs(.waiting, kind: .question))
        #expect(!waiting("s", nil).absorbs(.waiting, kind: .permission))
    }
}
```
`Tests/ClaudeBarTests/SessionMergeTests.swift`: `import AppKit` no topo e, no fim:
```swift
@Suite("Ícone de espera por tipo")
struct WaitingBarStateTests {
    private func waiting(_ id: String, _ kind: WaitKind?) -> SessionStatus {
        SessionStatus(sessionId: id, state: .waiting, cwd: "/tmp/\(id)", pid: 1, kind: kind)
    }

    private func barState(_ statuses: [SessionStatus]) -> BarState {
        SessionMerge.barState(rows: SessionMerge.rows(agents: [], statuses: statuses), acknowledged: [])
    }

    @Test func permissaoVencePergunta() {
        #expect(barState([waiting("a", .question), waiting("b", .permission)]) == .permission)
    }

    @Test func soPerguntasMostramPergunta() {
        #expect(barState([waiting("a", .question), waiting("b", .question)]) == .question)
    }

    /// Tipo desconhecido pode ser permissão: não se esconde atrás de "pergunta".
    @Test func esperaSemTipoCaiNoGenerico() {
        #expect(barState([waiting("a", .question), waiting("b", nil)]) == .waiting)
        #expect(barState([waiting("a", nil)]) == .waiting)
    }

    @Test func linhaCarregaOTipoDoHook() throws {
        let rows = SessionMerge.rows(agents: [], statuses: [waiting("a", .question)])
        #expect(rows.first?.kind == .question)
    }

    /// Nome de SF Symbol errado não falha no build: a barra só fica vazia.
    @Test func simbolosDeEsperaExistem() {
        for state in [BarState.permission, .question, .waiting] {
            #expect(NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil) != nil, "\(state)")
        }
    }
}
```
(Se o F07 já tiver entrado com `simbolosDaBarraExistem` cobrindo todos os casos, acrescente `.permission, .question` lá e não crie o teste duplicado.)

`Tests/ClaudeBarTests/AlertTests.swift`: `import ClaudeBarCore`. Em `osDoisSonsExistemNoSistema`, troque a lista por `[Alert.finished, .waiting, .permission, .question]`. Acrescente:
```swift
    /// Pergunta e permissão se distinguem pelo ouvido (F24).
    @Test func perguntaTemSomProprio() {
        #expect(Alert.question.soundName != Alert.permission.soundName)
        #expect(Alert.question.soundName != Alert.finished.soundName)
    }

    @Test func tipoDaEsperaEscolheOAviso() {
        #expect(Alert(waiting: .permission) == .permission)
        #expect(Alert(waiting: .question) == .question)
        #expect(Alert(waiting: nil) == .waiting)
    }
```
Sem teste de unidade: `notifyTransitions`, porque o `SessionStore` lê o diretório real e cria o `Notifier`. A verificação manual cobre o reaviso pergunta → permissão.

### README (`README.md` e `README.pt-BR.md`)
- Tabela de símbolos: `exclamationmark.bubble.fill` vira três linhas. `hand.raised.fill`: Claude wants permission to use a tool. `questionmark.bubble.fill`: Claude asked you a question. `exclamationmark.bubble.fill`: waiting for you (kind unknown).
- Precedência: **permission > waiting > question > ready (unseen) > working > idle**, e explicar que "question" só aparece quando todas as esperas são pergunta.
- Exemplo do menu: `✋  my-app — pede permissão (há 10 s)` e `❓  api — fez uma pergunta (há 1 min)`.
- Tabela de alertas: uma linha "→ asked a question" | "Claude fez uma pergunta" + project name | `Purr` | 75%. A linha de permissão passa a ter o título "Claude pede permissão".
- Tabela de hooks: `PreToolUse` (`AskUserQuestion`) | `waiting` (question), `PostToolUse` (`AskUserQuestion`) | `working`.
- Segurança: "for questions only the fact that Claude asked is stored, never the question text (`tool_input` is not read)".

### Verificação manual
1. `swift build && swift test` verdes, 47 testes.
2. Simulação isolada da regra (mesma técnica do F05):
   ```bash
   export CFFIXED_USER_HOME="$(mktemp -d)"; H=.build/debug/claudebar-hook
   echo '{"session_id":"t","cwd":"/tmp"}' | $H waiting --kind question --pid 1
   echo '{"session_id":"t","cwd":"/tmp","message":"Claude needs your permission"}' | $H waiting --kind permission --pid 1
   cat "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # continua "kind" : "question", sem message
   echo '{"session_id":"t","cwd":"/tmp"}' | $H working --pid 1
   echo '{"session_id":"t","cwd":"/tmp","message":"x"}' | $H waiting --kind permission --pid 1
   cat "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # "kind" : "permission"
   unset CFFIXED_USER_HOME
   ```
3. App aberto, estado real (depois, `claudebar-hook end`): simular `waiting --kind question` → barra `questionmark.bubble.fill`, menu ❓ "fez uma pergunta", popup azul e som `Purr`. Numa segunda sessão, `waiting --kind permission` → barra `hand.raised.fill`, popup laranja e `Submarine`. "Ver exemplo de popup" mostra o de permissão.
4. Instalar pelo F02. `/hooks` mostra `PreToolUse`/`PostToolUse` com `AskUserQuestion`, e os hooks `PreToolUse` que você já tinha continuam lá.
5. Com `claude` real (2.1.325):
   - "Use a ferramenta AskUserQuestion para me perguntar a cor favorita." → ❓ **na hora**. Espere 10 s sem responder: **continua ❓** (absorção, #16102). Responda: ⏳ e depois ✅.
   - Peça um `Bash` fora da allowlist e espere 6 s → ✋.
   - Plano: entre em plan mode e deixe o `ExitPlanMode` pedir aprovação. Anote se aparece ✋ (esperado). Não confirmado, só registrar no PR.
6. Não verificável por agente: som ouvido, aparência na barra, popup. Vão como "não verificado" no relatório.

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| Comportamento do `AskUserQuestion` vem de issues, não da doc (não confirmado nesta versão) | Se o `permission_prompt` falso não vier, a regra simplesmente não age. Se o `PreToolUse` não disparar, fica como no F05 (✋ após 6 s), sem regressão. O passo 5 registra o que a versão instalada faz. |
| Permissão real enquanto o `AskUserQuestion` está aberto (a doc admite que pode acontecer) | Fica ❓ até a resposta. O estado continua `waiting`, então a barra e o aviso não somem, só o rótulo fica impreciso. Risco aceito, raro. |
| Usuário cancela a pergunta (Esc) e o `PostToolUse` não dispara | Fica ❓ até o próximo `UserPromptSubmit` (→ `working`). É o mesmo comportamento de hoje com permissão. |
| Instalar `PreToolUse`/`PostToolUse` apagando hooks do usuário | F24 **só** pelo instalador do F02 (merge aditivo). Critério de aceite e passo 4. |
| Hook bloquear o `AskUserQuestion` | O hook sai com 0/1, nunca 2 (F05). Nada no stdout. `timeout: 5`. |
| Hook mais lento no `PreToolUse` (agora lê o arquivo antes de gravar) | Lê um JSON de menos de 1 KB do disco local, na casa de milissegundos. Sem rede. |
| `ExitPlanMode` chegar como `permission_prompt` (não confirmado) | Aparece ✋. Aprovar plano é aprovação, então está correto. Não adicionar matcher para ele. |
| SF Symbols no macOS 14 | Confirmado no `name_availability.plist` (10.15 e 13). O teste `simbolosDeEsperaExistem` pega um nome digitado errado. |
| Som `Purr` não agradar | É uma linha. A escolha fica para o F15. O teste só exige que seja diferente dos outros e que exista. |
| `kind` no menu e `message` no popup com compartilhamento de tela | `message` já existe hoje. O F25 vai cobrir. O F24 não acrescenta conteúdo novo, porque a pergunta não é lida. |

### Critérios de aceite
- `PreToolUse`/`PostToolUse` com matcher `AskUserQuestion` registrados pelo instalador do F02, preservando hooks preexistentes desses eventos (teste do F02 ou passo 4).
- `SessionStatus.absorbs` existe em Core, com os 2 testes. O hook grava por cima em qualquer falha de leitura.
- `BarState` tem `.permission` e `.question`, com precedência permissão > genérico > pergunta (3 testes).
- `Alert` tem `.permission` e `.question`, `Alert(waiting:)` mapeia (teste), e o som da pergunta existe e é diferente de `Glass` e `Submarine` (teste).
- `notifyTransitions` reavisa quando só o `kind` muda.
- `HookPayload` continua sem `tool_input`, `notification_type` e `title`.
- `swift build` sem avisos. `swift test` = 47 (ou 38 + 9 sobre o total que existir), nenhum removido.
- README em inglês e em português atualizados (símbolos, precedência, alertas, hooks, segurança).

### O que NÃO fazer
- Não ler `tool_input` (texto da pergunta) nem `transcript_path`.
- Não registrar `PreToolUse`/`PostToolUse` pelo `jq` atual.
- Não usar `PermissionRequest` e não criar matcher para `ExitPlanMode`.
- Não adicionar `PostToolUse` sem matcher para "voltar a working depois da permissão" (é outro item do backlog).
- Não criar `Settings` para escolher o som (F15) nem toggle por tipo.
- Não pôr lock de arquivo para a corrida do hook.
- Não trocar o emoji do menu por rótulo de acessibilidade aqui (F19).
- Não usar valor associado em `BarState`/`Alert`.

---

## Pendências para o backlog
- Registrar que as entradas `PreToolUse`/`PostToolUse:AskUserQuestion` passam a fazer parte do **F24** (decisão desta spec).
- Item novo: depois de aprovar uma permissão, voltar a `working` (`PostToolUse` sem matcher → `working`). Hoje fica "esperando" até `Stop`.
- Item opcional: `elicitation_url_dialog` → `question`.
