# T12 — Estado de erro (`StopFailure`, `failed` do CLI)

- **Funcionalidade:** F07, parte 1 de 2 (F07.1) — spec [G06, F07.1](../05-specs/G06-erro.md)
- **Épico:** Hooks · **Prioridade:** P1 · **Esforço:** 2,5 h
- **Depende de:** T07 (sem `idle_prompt` sobrescrevendo `error`) · **Bloqueia:** T13, T16
- **Branch:** `feat/estado-erro`
- **PR:** `feat: estado de erro quando a resposta falha (StopFailure)`

## Objetivo

Quando o turno termina por erro de API, a sessão aparece como **falhou**: ⚠️ no menu e `exclamationmark.triangle.fill` na barra até você marcar como visto. Não fica presa em "processando" (hoje o `Stop` não roda) nem aparece como "pronto" (hoje `"failed"` do CLI vira `.idle`). A mensagem é só o código da API (`rate_limit — 429 Too Many Requests`), nunca `last_assistant_message`.

## Subtasks

- [ ] `SessionStatus.swift`: `case error` em `SessionState` (com `CaseIterable`).
- [ ] `HookInstaller.entries`: `Entry(event: "StopFailure", args: ["error"])` (timeout 5, sem matcher).
- [ ] `main.swift`: `HookPayload.error`/`errorDetails`, `errorSummary`, mensagem escolhida pelo estado; texto do `fail` com `error`.
- [ ] `SessionStore`: `BarState.error` + símbolo; `notifyTransitions` com `case .error: acknowledged.remove(...)` (o `default: break` não é cobrado pelo compilador).
- [ ] `SessionMerge.barState`: `waiting > error (não visto) > done (não visto) > working > idle`.
- [ ] `AgentsProbe.sessionState`: `"failed"` → `.error`.
- [ ] `MenuContent`: ⚠️ / "falhou" nos dois `switch`; no submenu, `Text(message)` só para `.error`.
- [ ] `ErrorStateTests` (6) em `SessionMergeTests.swift` (`import AppKit` no topo).
- [ ] Mutação: neutralizar a linha `error` do `barState` → `erroNaoVistoVenceProntoMasPerdeParaEsperando` falha.
- [ ] Verificação manual 0–5 da spec (**sair do ClaudeBar instalado antes**: o app antigo apaga arquivo com `"error"`).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionStatus.swift`, `main.swift`, `HookInstaller.swift`, `SessionStore.swift`, `SessionMerge.swift`, `AgentsProbe.swift`, `MenuContent.swift`, `SessionMergeTests.swift`, READMEs.

## Código-chave (da spec)

```swift
private struct HookPayload: Decodable {
    let sessionId: String?
    let cwd: String?
    let message: String?
    /// Só no `StopFailure`. `String`, não enum: código novo não pode derrubar o decode.
    let error: String?
    let errorDetails: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", cwd, message, error
        case errorDetails = "error_details"
    }
}

/// `last_assistant_message` fica de fora de propósito: no `Stop` ele é a
/// resposta do Claude, e o app não lê conversa.
private func errorSummary(_ payload: HookPayload?) -> String? {
    let parts = [payload?.error, payload?.errorDetails].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " — ")
}

    let text = state == .error ? errorSummary(payload) : payload?.message
    // … SessionStatus(…, message: text.map { String($0.prefix(200)) }, kind: kind)
```

```swift
    static func barState(rows: [SessionRow], acknowledged: Set<String>) -> BarState {
        let own = rows.filter { !$0.isSubagent }
        let unseen = own.filter { !acknowledged.contains($0.sessionId) }
        if own.contains(where: { $0.state == .waiting }) { return .waiting }
        // Falha vence "pronto": uma resposta que não veio não pode se esconder.
        if unseen.contains(where: { $0.state == .error }) { return .error }
        if unseen.contains(where: { $0.state == .idle }) { return .done }
        if own.contains(where: { $0.state == .working }) { return .working }
        return .idle
    }
```

```swift
            case .error:
                // Falha nova acende o ícone mesmo que a sessão já tenha sido
                // marcada como vista antes do prompt que falhou.
                acknowledged.remove(row.sessionId)
```

## Testes obrigatórios

`ErrorStateTests` da spec: `erroNaoVistoVenceProntoMasPerdeParaEsperando`, `erroVistoApagaOIconeMasNaoViraPronto`, `erroVistoNaoEscondeProntoDeOutraSessao`, `failedDoCliViraErroSemMudarABarra`, `arquivoComEstadoErrorDecodifica`, `simbolosDaBarraExistem` (todos os casos de `BarState`). Formato do handler `StopFailure` coberto no `formatoDoHandler` de T03 (acrescentar o evento à lista).

Simulação (com o app instalado fechado):

```bash
echo '{"session_id":"t-err","cwd":"/tmp","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"NAO-DEVE-APARECER"}' | \
  build/ClaudeBar.app/Contents/MacOS/claudebar-hook error --pid $$ && cat ~/.claude/claudebar/t-err.json
# "state" : "error", "message" : "rate_limit — 429 Too Many Requests", sem NAO-DEVE-APARECER
```

## Critérios de aceite

- `claudebar-hook error` com o payload oficial grava `state: "error"` e `message` = `"<error> — <error_details>"` (≤ 200). `last_assistant_message` nunca aparece no arquivo, em estado nenhum.
- Hook sai 0 com payload vazio, inválido ou sem os campos de erro.
- `barState` segue a precedência acima; subagente em `error` não muda a barra.
- `"failed"` do CLI → `⚠️ … — falhou`, nunca ✅.
- Falha depois de "Marcar como visto" acende a barra de novo.
- `swift test` = anterior + 6.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Símbolo `exclamationmark.triangle.fill`; precedência **waiting > failed (unseen) > ready (unseen) > working > idle**; exemplo `⚠️  api — falhou (há 1 min)`; tabela de hooks `StopFailure` → `error`; CLI `<working|idle|waiting|error|end>`; requisito "versões sem `StopFailure` mantêm a sessão como *working*"; segurança: "for failures only the API error code/details are stored, never Claude's reply".

## Riscos

| Risco | Mitigação |
|---|---|
| App antigo apaga arquivo com `"error"` (confirmado) | hook e app no mesmo bundle; verificação com o app antigo fechado |
| Claude Code sem `StopFailure` | entrada ignorada, sessão fica `working` como hoje |
| `default: break` engolir o caso novo | tratado explicitamente; revisor confere |

## Fora do escopo

Aviso/som de falha (T13); tabela de códigos traduzidos; matcher no `StopFailure`; ler o arquivo atual no hook para "proteger" `error`; Esc/stall.
