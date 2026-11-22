# T16 — Permissão × pergunta: símbolo, texto e som distintos

- **Funcionalidade:** F24 — spec [G04, F24](../05-specs/G04-notification-kind.md)
- **Épico:** Notificações · **Prioridade:** P2 (inovação) · **Esforço:** 2,5 h
- **Depende de:** T07 (`kind`), T09 (`PostToolUse --if-waiting`), T12 (`error`), T13 (`.failed`) · **Bloqueia:** T17, T23, T24, T31
- **Branch:** `feat/permissao-x-pergunta`
- **PR:** `feat: distinguir pedido de permissão de pergunta`

## Objetivo

Saber pelo ícone, pelo texto e pelo som se o Claude quer **aprovar uma ferramenta** ou **uma resposta sua**:

| `kind` | barra | menu | popup | som |
|---|---|---|---|---|
| `permission` | `hand.raised.fill` | ✋ "pede permissão" | "Claude pede permissão" | `Submarine` 75% |
| `question` | `questionmark.bubble.fill` | ❓ "fez uma pergunta" | "Claude fez uma pergunta" | `Purr` 75% |
| `nil` | `exclamationmark.bubble.fill` | 🔸 "aguardando você" | "Claude está esperando você" | `Submarine` 75% |

## Ajuste sobre a spec

- Só registrar `PreToolUse` com matcher `AskUserQuestion` → `waiting --kind question`. **Não** registrar `PostToolUse:AskUserQuestion`: o `PostToolUse --if-waiting` do T09 já volta a sessão para `working` quando a pergunta é respondida.
- O estado `error` (T12) e o aviso `.failed` (T13) já existem: incluir nos `switch` e na precedência.

## Subtasks

- [ ] `HookInstaller.entries`: `Entry(event: "PreToolUse", matcher: "AskUserQuestion", args: ["waiting", "--kind", "question"])`.
- [ ] `SessionStatus.absorbs(_:kind:)` (Core) e checagem no `main.swift` antes de gravar (fail-open).
- [ ] `SessionRow.kind` (último parâmetro do `init`, com padrão); `SessionMerge` repassa nas duas construções.
- [ ] `BarState`: `.permission`, `.question` (sem valor associado); precedência **permission > waiting > question > error (não visto) > done (não visto) > working > idle**.
- [ ] `SessionStore`: `previousRows: [String: SessionRow]` no lugar de `previousStates`; `notifyTransitions` compara `(state, kind)` e usa `Alert(waiting: row.kind)`. Manter os casos `.idle`, `.error`/`.failed` existentes.
- [ ] `Alert`: `.permission`, `.question`, `init(waiting:)`, títulos/sons/volumes; `showSample` usa `.permission`. `import ClaudeBarCore` no `Notifier`.
- [ ] `StatusHUD`: símbolo e cor dos novos casos.
- [ ] `MenuContent`: `icon(for row:)`/`description(for row:)` por tupla `(state, kind)`, incluindo `(.error, _)`.
- [ ] Testes (abaixo). Simulação isolada com `CFFIXED_USER_HOME` e verificação manual 5 da spec com `claude` real.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionStatus.swift`, `main.swift`, `HookInstaller.swift`, `SessionRow.swift`, `SessionMerge.swift`, `SessionStore.swift`, `MenuContent.swift`, `Notifier.swift`, `StatusHUD.swift`, `SessionStatusTests.swift`, `SessionMergeTests.swift`, `AlertTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    /// O `AskUserQuestion` grava a pergunta na hora (`PreToolUse`) e, ~6 s
    /// depois, o Claude Code dispara um `permission_prompt` para a mesma tela.
    /// Essa "permissão" não pode apagar a pergunta aberta.
    public func absorbs(_ state: SessionState, kind: WaitKind?) -> Bool {
        self.state == .waiting && waitKind == .question && state == .waiting && kind == .permission
    }
```

`main.swift`, entre o `let kind` e o `let status`:

```swift
    // Pergunta aberta vence a "permissão" que o AskUserQuestion dispara depois.
    // Sem arquivo ou arquivo ilegível: grava normalmente.
    if let data = try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)),
       let current = try? StatusDirectory.decoder.decode(SessionStatus.self, from: data),
       current.absorbs(state, kind: kind) {
        return
    }
```

`SessionMerge.barState`:

```swift
        let waiting = own.filter { $0.state == .waiting }
        // Permissão vence: trava uma ferramenta já em andamento. Só mostra
        // "pergunta" quando todas as esperas são pergunta.
        if waiting.contains(where: { $0.kind == .permission }) { return .permission }
        if !waiting.isEmpty {
            return waiting.allSatisfy { $0.kind == .question } ? .question : .waiting
        }
        if unseen.contains(where: { $0.state == .error }) { return .error }
        // … done, working, idle como hoje
```

`Alert`:

```swift
    init(waiting kind: WaitKind?) {
        self = switch kind {
        case .permission: .permission
        case .question: .question
        case nil: .waiting
        }
    }
    // title:     .permission "Claude pede permissão"; .question "Claude fez uma pergunta"
    // soundName: .waiting, .permission "Submarine"; .question "Purr"
    // volume:    .waiting, .permission, .question 0.75
```

`notifyTransitions`:

```swift
        for row in merged where !row.isSubagent {
            // Pergunta que vira permissão (ou o contrário) avisa de novo.
            guard let previous = previousRows[row.sessionId],
                  previous.state != row.state || previous.kind != row.kind
            else { continue }
            switch row.state {
            case .idle where previous.state == .working: …
            case .waiting:
                acknowledged.remove(row.sessionId)
                notifier.post(Alert(waiting: row.kind), body: row.message ?? row.name)
            case .error: … (T12/T13, com `previous.state == .working`)
            default: break
            }
        }
```

## Testes obrigatórios

- `SessionStatusTests.swift`, suíte `WaitKindTests`: `permissaoNaoApagaPerguntaAberta`, `soAPermissaoSobreAPerguntaEhAbsorvida`.
- `SessionMergeTests.swift`, suíte `WaitingBarStateTests`: `permissaoVencePergunta`, `soPerguntasMostramPergunta`, `esperaSemTipoCaiNoGenerico`, `linhaCarregaOTipoDoHook`, e `erroPerdeParaPergunta` (pergunta + erro não visto → `.question`). Acrescentar `.permission, .question` ao `simbolosDaBarraExistem` do T12 (não duplicar).
- `AlertTests.swift`: lista de sons existentes com os 5 casos; `perguntaTemSomProprio`; `tipoDaEsperaEscolheOAviso`.
- `HookMergeTests`: `PreToolUse` do usuário preservado junto do nosso grupo com matcher.

## Critérios de aceite

- `PreToolUse:AskUserQuestion` registrado preservando os `PreToolUse` do usuário; nenhum `PostToolUse:AskUserQuestion`.
- `absorbs` em Core; o hook grava normalmente em qualquer falha de leitura.
- Precedência acima com testes; `Alert` sem valor associado; `notifyTransitions` reavisa quando só o `kind` muda.
- `HookPayload` sem `tool_input`, `notification_type`, `title`.
- `swift test` = anterior + ~11; nenhum removido.
- Com `claude` real: pergunta aparece ❓ na hora e continua ❓ 10 s depois (absorção). Registrar o que o `ExitPlanMode` mostra.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Tabela de símbolos com as três esperas; precedência **permission > waiting > question > failed (unseen) > ready (unseen) > working > idle** ("question" só quando todas as esperas são pergunta); exemplos ✋/❓ no menu; linha de alerta da pergunta (`Purr`); tabela de hooks `PreToolUse` (`AskUserQuestion`) → `waiting` (question); segurança: "for questions only the fact that Claude asked is stored, never the question text (`tool_input` is not read)".

## Riscos

| Risco | Mitigação |
|---|---|
| Comportamento do `AskUserQuestion` vem de issues | se o `permission_prompt` falso não vier, a regra não age; sem regressão |
| Permissão real com a pergunta aberta | fica ❓ até a resposta; estado continua `waiting` |
| Corrida entre dois hooks da mesma sessão | escrita atômica; pior caso é rótulo errado até o próximo evento; sem lock |
| Som `Purr` não agradar | uma linha; escolha por Ajustes em T24 |

## Fora do escopo

Ler `tool_input`/`transcript_path`; `PermissionRequest`; matcher para `ExitPlanMode`; `PostToolUse` sem matcher para "voltar depois da permissão" (já é o T09); Ajustes de som (T24); trocar emoji por rótulo acessível (T31).
