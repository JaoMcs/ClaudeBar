# Spec G06 — Estado de erro (F07)

Insumos: `04-como-fazer/G06-erro.md`, `03-validacao/BACKLOG.md` (F07: P, depende de F02), `04-como-fazer/G04-notification-kind.md` (lista de `notification_type`), código em `main` @ f943cc4.

**Verificado nesta spec** (diff de F07.1 + F07.2 aplicado numa cópia do projeto real, Swift 6.3.3, tools 6.0):
- `swift build`: 0 avisos. `swift test`: 41 testes passam (34 atuais + 7 novos).
- Com a linha `error` de `barState` neutralizada, `erroNaoVistoVenceProntoMasPerdeParaEsperando` falha (`→ .done`). O teste pega a regressão.
- Hook real: payload oficial grava `"state" : "error"`, `"message" : "rate_limit — 429 Too Many Requests"`, sem `NAO-DEVE-APARECER`. Payload sem campos: sem `message`, exit 0. Payload inválido: exit 0. `idle` com `last_assistant_message`: nada do texto no arquivo.
- `NSImage(systemSymbolName: "exclamationmark.triangle.fill")` existe (teste `simbolosDaBarraExistem`, rodado no macOS 26; o símbolo é do SF Symbols 1, macOS 11+, então vale para o 14). Som `Basso.aiff` existe em `/System/Library/Sounds`.
- **Achado:** o ClaudeBar antigo instalado, rodando ao mesmo tempo, **apagou** os arquivos com `"state": "error"` em menos de 1 s (`readAll` não decodifica e remove). Confirma o risco "app antigo × arquivo novo" e muda a verificação manual: sair do app instalado antes de testar.
- Fecha o "não confirmado" da lista de `notification_type`: ela está em G04 (`idle_prompt` incluso).

Dividido em duas entregas, e cada uma vira um PR:

| Id | Entrega | Obrigatória? | Arquivos | Esforço |
|---|---|---|---|---|
| **F07.1** | Estado `error`: hook `StopFailure`, `"failed"` do CLI, ícone, menu, precedência | sim | `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/claudebar-hook/main.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/SessionMerge.swift`, `Sources/ClaudeBar/AgentsProbe.swift`, `Sources/ClaudeBar/MenuContent.swift`, `scripts/install.sh` (ou o instalador do F02), `Tests/ClaudeBarTests/SessionMergeTests.swift`, `README.md`, `README.pt-BR.md` | 2,5 h |
| **F07.2** | Aviso "a resposta falhou" (popup + som) | opcional, recomendada | `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/StatusHUD.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Tests/ClaudeBarTests/AlertTests.swift`, `README.md`, `README.pt-BR.md` | 1 h |

Ordem recomendada para o gestor:
- **F02 antes de F07.1.** A entrada `StopFailure` entra no mecanismo de instalação que estiver em `main`.
- **F05 antes de F07.1.** O F05 tira o `Notification` sem matcher, e isso elimina o risco de o `idle_prompt` sobrescrever `error` (ver Riscos).
- F07.2 depois de F07.1 e de F01, que mexe no `Notifier.post`.
- Conflitos: `SessionStore.swift` e `MenuContent.swift` também são tocados por F05/F24 (símbolos e `notifyTransitions`), F19 e F12. Esses PRs rodam em sequência, não em paralelo.

---

## F07.1 — Estado `error`

### Objetivo
Quando o turno termina por erro de API, a sessão aparece como **falhou**: ⚠️ no menu e `exclamationmark.triangle.fill` na barra até você marcar como visto. Ela não fica presa em ⏳ "processando" (o que acontece hoje, porque o `Stop` não roda) e não aparece como ✅ "pronto" (o que acontece hoje com `"failed"` do `claude agents --json`, em `AgentsProbe.swift:46`).

### Decisão técnica e por quê
- **Novo `case error` em `SessionState`.** O hook já converte o argumento com `SessionState(rawValue:)`, então `claudebar-hook error` funciona sem parsing novo. Cada `switch` exaustivo passa a falhar no build até ser tratado, e assim nenhum lugar cai em "pronto" por acidente.
  - Descartada: flag `failed: Bool` mantendo `idle`. Cada teste de `.idle` vira armadilha, e era justamente isso que fazia o erro parecer pronto.
  - Descartada: reaproveitar `waiting`. Erro não é "esperando você", e o som e o texto ficariam mentindo.
- **Mensagem do erro = `error` + `error_details` do payload, nunca `last_assistant_message`.** No `Stop` esse campo traz a resposta do Claude. Ler o campo só em `error` exigiria confiar que ele nunca traz conteúdo da conversa, e o guard rail é "não ler conversas". O código (`rate_limit`) e o detalhe HTTP (`429 Too Many Requests`) bastam para saber o que houve.
  - Descartada: tabela código → texto em português. Seriam 12 strings a manter por uma melhora cosmética. Fica para F21, se alguém pedir.
- **`error` não é enum no hook, é `String?`.** Valores novos de erro (a doc já soma 12 e cresce, por exemplo `cloud_credential_error`) não podem derrubar o decode. Payload sem os campos dá `message = nil`.
- **Precedência: `waiting > error (não visto) > done (não visto) > working > idle`.** `waiting` trava a sessão até você agir. `error` pede ação (reenviar, esperar o limite), mas não trava uma ferramenta. `error` vence `done` porque uma falha não pode ficar escondida atrás de um "pronto".
- **`error` respeita o `acknowledged`, como o `done`.** "Marcar como visto" ou "Marcar tudo como visto" apaga o destaque da barra. A linha continua ⚠️ até o próximo `UserPromptSubmit` (→ `working`), e um rate limit não deixa a barra acesa por horas.
  - Correção da pesquisa: abrir o menu **não** marca nada como visto no código atual. Só os dois botões fazem isso, e o `error` segue exatamente a mesma regra.
- **Rearmar o destaque na transição para `error`.** Hoje `acknowledged` só é limpo em `→ idle (vindo de working)` e `→ waiting`. Uma sessão vista como pronta, que depois recebe um prompt e falha, ainda estaria em `acknowledged`, e a falha nasceria "já vista". Por isso entra `case .error: acknowledged.remove(...)` em `notifyTransitions`. Esse `switch` tem `default: break`, e o compilador **não** avisa.
- **`"failed"` do CLI → `.error`.** É uma linha. Vale para background (`state`) e para interativa (`status`), se um dia vier.
- **`StopFailure` sem matcher.** Todo erro vira `error`. Filtrar por tipo não traz ganho hoje.

### Arquivos e código

**`Sources/ClaudeBarCore/SessionStatus.swift`**: um caso a mais. Arquivo antigo continua decodificando, e app antigo lendo arquivo novo descarta e apaga o arquivo (`readAll`), sem travar. Hook e app saem no mesmo bundle.
```swift
public enum SessionState: String, Codable, Sendable, CaseIterable {
    /// Prompt enviado — o Claude está trabalhando.
    case working
    /// O Claude terminou de responder e está ocioso.
    case idle
    /// O Claude está esperando algo de você (permissão, escolha).
    case waiting
    /// A resposta falhou por erro de API (limite, sobrecarga, autenticação…).
    /// Não é "pronto": o turno acabou sem resposta.
    case error
}
```

**`Sources/claudebar-hook/main.swift`**: dois campos opcionais e a mensagem escolhida pelo estado.
```swift
// Uso: claudebar-hook <working|idle|waiting|error|end> [--pid <pid do claude>]

/// Campos do payload que os hooks do Claude Code entregam no stdin.
private struct HookPayload: Decodable {
    let sessionId: String?
    let cwd: String?
    let message: String?
    /// Só no `StopFailure`: código do erro da API (`rate_limit`, `overloaded`…).
    /// `String`, não enum: código novo não pode derrubar o decode.
    let error: String?
    /// Só no `StopFailure`, opcional: detalhe técnico (`429 Too Many Requests`).
    let errorDetails: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case message
        case error
        case errorDetails = "error_details"
    }
}

/// O que mostrar quando a resposta falhou. `last_assistant_message` fica de
/// fora de propósito: no `Stop` ele é a resposta do Claude, e o app não lê
/// conversa.
private func errorSummary(_ payload: HookPayload?) -> String? {
    let parts = [payload?.error, payload?.errorDetails].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " — ")
}
```
Em `run()`, troque a mensagem do `fail` (`"informe o estado (working|idle|waiting|error|end)"`) e a construção do status:
```swift
    let text = state == .error ? errorSummary(payload) : payload?.message

    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: payload?.cwd ?? FileManager.default.currentDirectoryPath,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: text.map { String($0.prefix(200)) }
    )
```
(O `catch { error.localizedDescription }` no fim continua compilando: o `error` implícito do `catch` não colide com `SessionState.error`, que sempre aparece qualificado ou como `.error` com tipo inferido.)

**`Sources/ClaudeBar/SessionStore.swift`**: `BarState` e `notifyTransitions`.
```swift
enum BarState {
    /// Alguma sessão está esperando você (permissão, escolha).
    case waiting
    /// Alguma resposta falhou e você ainda não viu.
    case error
    /// Alguma sessão terminou e você ainda não viu.
    case done
    /// Tem sessão processando, nada pendente.
    case working
    /// Nada acontecendo.
    case idle

    var symbolName: String {
        switch self {
        case .waiting: "exclamationmark.bubble.fill"
        case .error: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        case .working: "ellipsis.circle"
        case .idle: "circle.dotted"
        }
    }
}
```
```swift
            switch row.state {
            case .idle where previous == .working:
                acknowledged.remove(row.sessionId)
                notifier.post(.finished, body: row.name)
            case .waiting:
                acknowledged.remove(row.sessionId)
                // A mensagem do Claude ("needs your permission to use Bash") diz
                // mais que o nome do projeto quando ele está travado.
                notifier.post(.waiting, body: row.message ?? row.name)
            case .error:
                // Falha nova acende o ícone mesmo que a sessão já tenha sido
                // marcada como vista antes do prompt que falhou.
                acknowledged.remove(row.sessionId)
            default:
                break
            }
```

**`Sources/ClaudeBar/SessionMerge.swift`**: precedência.
```swift
    static func barState(rows: [SessionRow], acknowledged: Set<String>) -> BarState {
        let own = rows.filter { !$0.isSubagent }
        let unseen = own.filter { !acknowledged.contains($0.sessionId) }
        if own.contains(where: { $0.state == .waiting }) { return .waiting }
        // Falha vence "pronto": uma resposta que não veio não pode se esconder
        // atrás de outra que veio.
        if unseen.contains(where: { $0.state == .error }) { return .error }
        if unseen.contains(where: { $0.state == .idle }) { return .done }
        if own.contains(where: { $0.state == .working }) { return .working }
        return .idle
    }
```

**`Sources/ClaudeBar/AgentsProbe.swift`** (`sessionState`):
```swift
        switch status ?? state {
        case "idle", "completed": .idle
        // Falhou não é pronto: sem isso, um agente que quebrou aparecia com ✅.
        case "failed": .error
        case "waiting", "blocked": .waiting
        default: .working
        }
```

**`Sources/ClaudeBar/MenuContent.swift`**: os dois `switch` e o motivo no submenu.
```swift
    private func icon(for state: SessionState) -> String {
        switch state {
        case .working: "⏳"
        case .idle: "✅"
        case .waiting: "🔸"
        case .error: "⚠️"
        }
    }

    private func description(for state: SessionState) -> String {
        switch state {
        case .working: "processando"
        case .idle: "pronto"
        case .waiting: "aguardando você"
        case .error: "falhou"
        }
    }
```
No submenu, logo depois de `Text(row.cwd)`:
```swift
                    // O código do erro ("rate_limit — 429 Too Many Requests")
                    // diz se vale reenviar agora ou esperar.
                    if row.state == .error, let message = row.message {
                        Text(message)
                    }
```

**`scripts/install.sh`**: se o F02 ainda **não** entrou:
```bash
  .hooks = ((.hooks // {}) + {
    UserPromptSubmit: entry("working"),
    Stop: entry("idle"),
    StopFailure: entry("error"),
    Notification: entry("waiting"),
    SessionEnd: entry("end")
  })
```
Se o F02 já entrou (instalador em Swift), acrescente o par `StopFailure` → `error` na lista de entradas dele, sem matcher. A desinstalação do F02 remove pelo caminho do `claudebar-hook`, então essa entrada sai junto sem código extra.

### Testes (Swift Testing, em `Tests/ClaudeBarTests/SessionMergeTests.swift`)
No topo do arquivo, `import AppKit`, para checar o símbolo.
```swift
@Suite("Estado de erro")
struct ErrorStateTests {
    private func hook(_ sessionId: String, _ state: SessionState) -> SessionStatus {
        SessionStatus(sessionId: sessionId, state: state, cwd: "/Users/dev/code", pid: 1, updatedAt: Date())
    }

    @Test func erroNaoVistoVenceProntoMasPerdeParaEsperando() {
        let comPronto = SessionMerge.rows(agents: [], statuses: [hook("e", .error), hook("p", .idle)])
        #expect(SessionMerge.barState(rows: comPronto, acknowledged: []) == .error)

        let comEspera = SessionMerge.rows(agents: [], statuses: [hook("e", .error), hook("w", .waiting)])
        #expect(SessionMerge.barState(rows: comEspera, acknowledged: []) == .waiting)
    }

    /// Visto, o erro sai da barra, mas a linha continua dizendo que falhou.
    @Test func erroVistoApagaOIconeMasNaoViraPronto() {
        let rows = SessionMerge.rows(agents: [], statuses: [hook("e", .error)])
        #expect(SessionMerge.barState(rows: rows, acknowledged: ["e"]) == .idle)
        #expect(rows[0].state == .error)
    }

    /// Ver o erro não pode esconder um "pronto" de outra sessão.
    @Test func erroVistoNaoEscondeProntoDeOutraSessao() {
        let rows = SessionMerge.rows(agents: [], statuses: [hook("e", .error), hook("p", .idle)])
        #expect(SessionMerge.barState(rows: rows, acknowledged: ["e"]) == .done)
    }

    /// Era a origem do falso "pronto": `failed` do CLI virava `.idle`. E um
    /// subagente que falhou não acende a barra, como qualquer subagente.
    @Test func failedDoCliViraErroSemMudarABarra() throws {
        let json = """
        [{"id":"dddddddd","cwd":"/Users/dev/x","kind":"background",
          "sessionId":"dddddddd-0000-0000-0000-000000000000","state":"failed"}]
        """
        let agents = try JSONDecoder().decode([AgentSession].self, from: Data(json.utf8))
        #expect(agents[0].sessionState == .error)
        let rows = SessionMerge.rows(agents: agents, statuses: [])
        #expect(SessionMerge.barState(rows: rows, acknowledged: []) == .idle)
    }

    /// O hook grava `"state": "error"`. Se o nome do caso mudar, o app apaga o
    /// arquivo em vez de mostrar a falha.
    @Test func arquivoComEstadoErrorDecodifica() throws {
        let json = #"{"sessionId":"s","state":"error","cwd":"/tmp","pid":1,"updatedAt":0,"message":"rate_limit"}"#
        let status = try StatusDirectory.decoder.decode(SessionStatus.self, from: Data(json.utf8))
        #expect(status.state == .error)
    }

    /// Nome de SF Symbol errado não falha no build: a barra só fica vazia.
    @Test func simbolosDaBarraExistem() {
        for state in [BarState.waiting, .error, .done, .working, .idle] {
            #expect(NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil) != nil, "\(state)")
        }
    }
}
```
Não testado por unidade: `notifyTransitions`, porque o `SessionStore` lê o diretório real, e `errorSummary`, que está no target executável. Os dois ficam cobertos pela verificação manual abaixo. Extrair código só para testar não compensa nesse tamanho.

### Scripts / README (`README.md` e `README.pt-BR.md`)
- Tabela de símbolos: nova linha `exclamationmark.triangle.fill` | "a reply failed (API error) and you haven't seen it yet" / "a resposta falhou (erro de API) e você ainda não viu".
- Precedência: **waiting > failed (unseen) > ready (unseen) > working > idle** / **esperando > falhou (não visto) > pronto (não visto) > processando > ocioso**.
- Exemplo do menu: incluir uma linha `⚠️  api — falhou (há 1 min)`.
- Tabela de hooks: `StopFailure` | `error`.
- Uso do CLI: `claudebar-hook <working|idle|waiting|error|end>`.
- Instalação: "four hooks" → "five hooks", e `StopFailure` na lista dos que são substituídos (se o F02 ainda não entrou). Desinstalação: "four" → "five".
- Requisitos: "the error state needs a Claude Code version with the `StopFailure` hook; older versions keep the failed session as *working*". Sem número de versão, porque a v2.1.78 não foi confirmada no CHANGELOG oficial.
- Segurança: "`message` is capped at 200 characters" continua valendo. Acrescentar: "for failures only the API error code/details are stored, never Claude's reply".

### Verificação manual
0. **Saia do ClaudeBar instalado** (`pkill -f ClaudeBar.app`). Ele não conhece `error`, e apaga o arquivo antes de você conseguir ler (visto nesta spec).
1. `swift build && swift test` verdes.
2. `./scripts/build-app.sh`, e depois a simulação sem Claude (deve gravar `"state" : "error"` e `"message" : "rate_limit — 429 Too Many Requests"`, sem o texto do `last_assistant_message`):
   ```bash
   echo '{"session_id":"t-err","cwd":"/tmp","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"NAO-DEVE-APARECER"}' | \
     build/ClaudeBar.app/Contents/MacOS/claudebar-hook error --pid $$
   cat ~/.claude/claudebar/t-err.json   # na mesma linha de comando: com $$ morto, o app apaga o arquivo
   ```
   Payload sem os campos (`{"session_id":"t-err2","cwd":"/tmp"}`): `message` ausente, exit 0.
   Payload `Stop` com `last_assistant_message` via `claudebar-hook idle`: `message` ausente (garante que a resposta nunca é gravada).
3. Com o app aberto: a barra mostra o triângulo, e o menu mostra `⚠️ tmp — falhou` com `rate_limit — 429 Too Many Requests` no submenu. Depois de "Marcar como visto", a barra volta e a linha continua ⚠️. Simule `working` e depois `error` de novo na mesma sessão: a barra acende de novo (prova o rearme). Por fim, `claudebar-hook end`.
4. `./scripts/install.sh`. Em `~/.claude/settings.json` existe `StopFailure` e o resto está intacto. Numa sessão nova do Claude Code, `/hooks` lista `StopFailure`, sem aviso de settings inválido.
5. Erro real (melhor esforço; se não disparar, o passo 2 vale como prova). Em uma pasta temporária, rode `claude --model claude-modelo-inexistente` e envie "oi". Se o turno terminar em `model_not_found`/`invalid_request`, o arquivo da sessão vira `error`. **Espere 70 s e confira de novo o arquivo.** Se virar `waiting` (`idle_prompt`) e o F05 ainda não estiver em `main`, registre isso no PR (ver Riscos).

### Riscos e mitigação
| Risco | Mitigação |
|---|---|
| `Notification idle_prompt` ~60 s depois sobrescreve `error` com `waiting` (não confirmado) | F05 antes: ele registra `Notification` só para `permission_prompt`/`elicitation_dialog`, e o `idle_prompt` deixa de chegar. **Não** fazer o hook ler o arquivo atual para decidir: é código novo (I/O + regra) para um caso que o F05 elimina. Se F07 entrar antes de F05, aceitar e registrar no PR. |
| Claude Code antigo sem `StopFailure` (versão de introdução não confirmada) | A entrada é ignorada e a sessão fica em `working` como hoje, sem regressão. O passo 4 confere que não há aviso de settings inválido na versão instalada. Não fazer checagem de versão no `install.sh`. |
| Campos do payload mudarem (`error_type`/`error_message` do guia de terceiros) | Todos opcionais. Campo ausente gera `message = nil`, e o estado `error` vem do **argumento**, não do payload. Ou seja, a sessão nunca fica "pronta" por causa de um campo faltando. |
| Interrupção pelo usuário (Esc) ou stream stall não disparam nada | Fora do F07: a sessão fica em `working` como hoje. Fica registrado para o F06. |
| `"failed"` do CLI só aparece em background (não confirmado) | O mapeamento vale para os dois campos, e subagente já não acende a barra. Sem risco. |
| `default: break` em `notifyTransitions` engole o caso novo | O código acima trata o caso explicitamente. O revisor do PR confere esse `switch` (o compilador não confere). |
| App antigo lendo arquivo com `"error"` apaga o arquivo (**confirmado** nesta spec) | Hook e app estão no mesmo bundle e o `install.sh` troca os dois juntos. Na pior hipótese (app velho aberto durante a instalação), a sessão some até o próximo evento. Não vale tornar o decode tolerante (`unknown` → ignorar) para uma janela de segundos. |

### Critérios de aceite
- `swift build` sem avisos e `swift test` verde: 6 testes novos em `ErrorStateTests` (40 no total, sem F07.2), nenhum removido.
- `claudebar-hook error` com o payload oficial grava `state: "error"` e `message` = `"<error> — <error_details>"`, com até 200 caracteres. O texto de `last_assistant_message` nunca aparece no arquivo, em nenhum estado.
- O hook sai com código 0 com payload vazio, inválido ou sem os campos de erro.
- `barState` segue `waiting > error não visto > done não visto > working > idle`, e subagente em `error` não muda a barra.
- `"failed"` em `claude agents --json` gera `⚠️ … — falhou`, nunca `✅`.
- Uma falha depois de "Marcar como visto" acende a barra de novo.
- `settings.json` ganha `StopFailure` e mantém o resto, e o README (en e pt-BR) foi atualizado nos pontos listados.

### O que NÃO fazer
- Não gravar nem exibir `last_assistant_message`.
- Não criar `enum` de códigos de erro nem tabela de tradução.
- Não pôr matcher no `StopFailure` nem um estado por tipo de erro (rate limit × auth).
- Não ler o arquivo existente no hook para "proteger" `error` (o F05 resolve).
- Não tratar Esc/stall aqui.
- Não usar cor fixa nem logo no ícone da barra: SF Symbol template, como os outros.

---

## F07.2 — Aviso de falha (opcional)

### Objetivo
Quem espera o sino do "Claude terminou" hoje não recebe nada quando a resposta falha. A F07.2 dá um aviso próprio, com som distinto, para essa transição.

### Decisão técnica e por quê
- **Terceiro caso em `Alert` (`.failed`)**, com título "A resposta do Claude falhou", som `Basso` (grave e "negativo", diferente de `Glass` e `Submarine`, presente em `/System/Library/Sounds`), volume 1 e popup com `exclamationmark.triangle.fill` em `.red`.
  - Descartada: reusar `.finished`, porque "terminou" seria mentira.
  - Descartada: reusar `.waiting`, porque o som de "travado esperando você" ensina o significado errado.
- **Só a transição de `working`** avisa. Uma sessão que o app já encontra em `error` ao abrir não avisa, igual ao `finished`.
- O toggle "Notificações" vale igual para os outros avisos (e o som segue o F01, quando ele entrar).

### Arquivos e código
**`Sources/ClaudeBar/Notifier.swift`** (`Alert`):
```swift
    /// A resposta falhou por erro de API (limite, sobrecarga…): o turno acabou
    /// sem o "terminou" que você esperava.
    case failed
```
Nos três `switch`:
```swift
        case .failed: "A resposta do Claude falhou"   // title
        case .failed: "Basso"                         // soundName
        case .failed: 1                               // volume
```
**`Sources/ClaudeBar/StatusHUD.swift`** (`HUDView`):
```swift
        case .failed: "exclamationmark.triangle.fill"  // symbolName
        case .failed: .red                             // tint
```
**`Sources/ClaudeBar/SessionStore.swift`**: o caso `.error` do F07.1 passa a ser:
```swift
            case .error:
                // Falha nova acende o ícone mesmo que a sessão já tenha sido
                // marcada como vista antes do prompt que falhou.
                acknowledged.remove(row.sessionId)
                if previous == .working {
                    // O código do erro diz se vale reenviar ou esperar o limite.
                    notifier.post(.failed, body: row.message.map { "\(row.name): \($0)" } ?? row.name)
                }
```

### Testes (`Tests/ClaudeBarTests/AlertTests.swift`)
```swift
    @Test func osTresAvisosTocamSonsDiferentes() {
        let sons = [Alert.finished, .waiting, .failed].map(\.soundName)
        #expect(Set(sons).count == 3)
    }
```
Em `osDoisSonsExistemNoSistema`, trocar o array por `[Alert.finished, .waiting, .failed]`. Acrescentar `#expect(Alert.failed.title.contains("falhou"))` em `cadaAvisoTemSeuTitulo`.

### Scripts / README
Tabela de alertas: linha `working → failed` | "A resposta do Claude falhou" + projeto e código do erro | `Basso` | 100%. Texto "There are two alerts" → "three alerts". Fazer o mesmo no pt-BR.

### Verificação manual
Com o app aberto, rode `claudebar-hook working` e depois `claudebar-hook error` (payload do passo 2 do F07.1) na mesma sessão. Deve aparecer o popup vermelho "A resposta do Claude falhou", com `tmp: rate_limit — 429 Too Many Requests`, e tocar o `Basso`. Repita o `error` sem `working` antes: nenhum aviso. Com Notificações desligadas, nenhum popup (o som depende do F01).

### Riscos e mitigação
- **Aviso repetido se o `idle_prompt` alternar estados**: o aviso só sai a partir de `working`, então `error → waiting → error` não repete o `.failed`.
- **Rate limit em várias sessões ao mesmo tempo gera vários sons**: o `play` já rebobina o mesmo `NSSound`, e o HUD reaproveita o painel. Fica aceitável.

### Critérios de aceite
- Os testes de `AlertTests` passam com 3 sons distintos e existentes (41 testes no total com F07.1).
- A transição `working → error` mostra o popup e toca `Basso`.
- `error` sem `working` antes não avisa, e subagente não avisa.

### O que NÃO fazer
- Não criar um toggle só para esse aviso: isso é com o F15, se pedirem.
- Não pôr retry nem ação no popup.
- Não avisar de novo enquanto a sessão continuar em `error`.
