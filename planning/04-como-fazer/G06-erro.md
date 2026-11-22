# G06 — Estado de erro (F07): `StopFailure` → `error`

Pesquisa de "como fazer". Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial citada; **[SUPOSIÇÃO]** = inferência minha, precisa de teste ou payload real.

## 1. O evento existe? Payload

Fonte: https://code.claude.com/docs/en/hooks (seções "Stop" e "StopFailure", lida em 2026-11-15).

- **[CONFIRMADO]** `StopFailure` existe. Descrição na tabela de eventos: "When the turn ends due to an API error".
- **[CONFIRMADO]** Ele roda **no lugar** do `Stop`. Na seção Stop: "API errors fire StopFailure instead." Na seção StopFailure: "Runs instead of Stop when the turn ends due to an API error."
  - Consequência para o ClaudeBar: hoje a falha **não** grava `idle`, porque `Stop` não roda. A sessão fica presa em `working` (⏳ "processando") até o próximo prompt. O "falso pronto" do backlog vem de outro lugar (ver §3, `AgentsProbe`).
- **[CONFIRMADO]** Campos de entrada, além dos comuns (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, …):
  - `error`: um dos valores `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error` ou `unknown`. É a chave do matcher.
  - `error_details`: opcional (ex.: `"429 Too Many Requests"`).
  - `last_assistant_message`: opcional. No `StopFailure` ele traz o texto do erro (ex.: `"API Error: Rate limit reached"`), e não a resposta do Claude.
  - Exemplo oficial:
    ```json
    {"session_id":"abc123","transcript_path":"...","cwd":"/Users/...","hook_event_name":"StopFailure",
     "error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"API Error: Rate limit reached"}
    ```
- **[CONFIRMADO]** O hook não tem decision control e o Claude Code ignora a saída e o exit code ("ignores the hook's output and exit code, apart from terminalSequence"). Para o ClaudeBar isso é bom: um hook com falha não afeta a sessão.
- **[CONFIRMADO]** O matcher só aceita letras, dígitos, `_` e `|`. Sem matcher, o hook roda para todos os erros. `cloud_credential_error` exige v2.1.267 ou mais nova.
- **[CONFIRMADO]** Timeout padrão de um hook `command`: 30 s (tabela de configuração, mesma página).
- Versão de introdução: v2.1.78, segundo mirrors do changelog (https://newreleases.io/project/github/anthropics/claude-code/release/v2.1.78 e https://claude-code-changelog-web.pages.dev/releases/v2.1.78). **[SUPOSIÇÃO parcial]**: não li o CHANGELOG oficial direto. Em versões mais antigas, a chave `StopFailure` no `settings.json` é ignorada ou gera aviso. Não testei.
- Atenção: um guia de terceiros (agentpatterns.ai/tool-engineering/stopfailure-hook) cita os campos `error_type` e `error_message`, que **não** estão na doc oficial. Vale só a doc oficial: `error`, `error_details` e `last_assistant_message`.

### Outros fatos da doc que afetam a precedência
- **[CONFIRMADO]** `Stop` "Does not run if the stoppage occurred due to a user interrupt." Esc/Ctrl-C não dispara nem `Stop` nem `StopFailure`, então a sessão continua presa em `working`. Isso fica fora do F07 (é F06/fantasma), mas convém registrar.
- **[CONFIRMADO]** O `Notification` com `notification_type` `idle_prompt` dispara "about 60 seconds" depois de o Claude terminar, se você não digitou nada. O payload traz `message`, `title` (opcional) e `notification_type`.
- **[SUPOSIÇÃO]** O `idle_prompt` provavelmente também dispara depois de um `StopFailure`. A doc diz "finished responding", sem distinguir sucesso de falha. Nesse caso, o `install.sh` atual (Notification sem matcher → `waiting`) sobrescreveria `error` com `waiting` uns 60 s depois. Isso precisa de payload real: bater num erro, esperar 60 s e olhar o arquivo.
- Há relatos (issue 87972, via claudeissues.com, que não abriu no fetch) de turnos encerrados por stream stall. **[SUPOSIÇÃO]**: em algumas versões, esses turnos não disparam nem `Stop` nem `StopFailure`. Não confirmado.

## 2. Ponto de partida no código

- `Sources/ClaudeBarCore/SessionStatus.swift`: `enum SessionState: String, Codable { working, idle, waiting }`.
- `Sources/claudebar-hook/main.swift`: `claudebar-hook <estado> --pid $PPID`. O estado vem do argumento e é convertido com `SessionState(rawValue:)`. O payload só lê `session_id`, `cwd` e `message`.
- `scripts/install.sh`: registra `UserPromptSubmit→working`, `Stop→idle`, `Notification→waiting` e `SessionEnd→end` por `jq`, todos sem matcher.
- `Sources/ClaudeBar/SessionMerge.swift` `barState`: precedência atual `waiting > done(idle não visto) > working > idle`.
- `Sources/ClaudeBar/SessionStore.swift` `BarState.symbolName`; `MenuContent.swift` `icon(for:)`/`description(for:)`; `notifyTransitions`.
- `Sources/ClaudeBar/AgentsProbe.swift:46`: `case "idle", "completed", "failed": .idle`. **Esta é a fonte real do falso "pronto"**: uma sessão sem arquivo de hook com status `failed` no `claude agents --json` aparece como ✅. **[SUPOSIÇÃO]**: não conferi quando o CLI emite `failed` (provavelmente só para subagente ou background). Conferir com um payload real.

## 3. Como fazer (recomendado, menor diff)

1. **Novo caso no enum** (Core): `case error`. Um caso a mais num enum `String` não quebra o `Codable` de arquivos antigos. Um app antigo lendo um arquivo novo falharia no decode, mas o `readAll` usa `try?` e simplesmente descarta o arquivo. Hook e app saem no mesmo bundle, então isso não é problema. O compilador aponta cada `switch` que precisa ser atualizado (`MenuContent`, `BarState`).
   - Alternativa (flag `failed: Bool` + manter `idle`): exige mexer em todo lugar que testa `.idle` e ainda corre o risco de aparecer como pronto. **Não recomendo.**
2. **Hook**: nenhum código novo de parsing. `claudebar-hook error --pid $PPID` já funciona via `SessionState(rawValue:)`. Para mostrar o motivo, adicionar `error` e `last_assistant_message` ao `HookPayload` e gravar em `message` algo como `last_assistant_message ?? error`, truncado em 200 como hoje. Esse texto vem de fora e vai para notificação/menu: manter o `prefix(200)`.
3. **install.sh**: acrescentar `StopFailure: entry("error")`, sem matcher (todos os erros). O `jq` já preserva o resto do arquivo.
4. **AgentsProbe**: `"failed"` → `.error` em vez de `.idle`. É uma linha só e fecha o falso "pronto" para sessões sem hook.
5. **Precedência do ícone** (`SessionMerge.barState`), proposta: `waiting > error > done > working > idle`.
   - Motivo: `waiting` bloqueia você e se resolve com uma ação; `error` também pede ação (reenviar ou esperar o limite), mas não trava uma ferramenta. Subagente continua fora, como hoje.
   - `error` deve respeitar o `acknowledged` como o `done`? Recomendo que **sim**: abrir o menu marca como visto e o ícone sai do estado de erro, mas a linha continua com o símbolo de erro até o próximo `UserPromptSubmit` (→ `working`). Com isso, um rate limit não deixa a barra vermelha por horas.
6. **Símbolo**: `exclamationmark.triangle.fill` para a barra (SF Symbol padrão; conferir no app SF Symbols, ver §5) e `⚠️` + "falhou" no menu (`MenuContent`). Nada de cor da marca nem logo (guard rail do ícone).
7. **Notificação**: no `notifyTransitions`, `case .error where previous == .working` → `notifier.post(.failed, body: row.message ?? row.name)`. É opcional: o backlog pede o estado e o símbolo, não alerta. **[SUPOSIÇÃO de UX]**: vale um alerta, porque o usuário que espera o "terminou" nunca recebe nada quando a resposta falha.
8. **`idle_prompt` sobrescrevendo `error`** (ver §1): a menor defesa fica no hook. Ao receber `waiting` com `notification_type == "idle_prompt"` e o arquivo atual em `error`, não sobrescrever. Hoje o hook não lê o arquivo existente. Isso acrescenta um `StatusDirectory` read ao hook. Fazer **só se** o teste do §1 mostrar que o caso acontece. Alternativa ainda menor: matcher `permission_prompt|elicitation_dialog` no `Notification` do `install.sh`, mas isso muda o comportamento atual do `waiting` por inatividade, e **[SUPOSIÇÃO]** não conferi a lista completa de `notification_type`.

Teste (gate do plano): em `SessionMergeTests`, um caso `error` mais um `waiting` → `.waiting`; `error` mais um `idle` não visto → `.error`; `error` visto → não `.error`. Em `AgentsProbe`, `"failed"` → `.error`.

## 4. Repos e exemplos

- Não encontrei app de barra de menu open source que já trate `StopFailure`. Os exemplos que aparecem são de log ou alerta:
  - https://hookstack.vercel.app/hook/stop-failure-log-api-errors (receita de log; não verifiquei o código)
  - https://agentpatterns.ai/tool-engineering/stopfailure-hook/ (padrão "observar e alertar, retry fora do Claude Code"; os nomes de campos divergem da doc oficial)
- Issues de contexto (via busca, sem abrir): pedido de tornar `StopFailure` acionável (58182, fechado) e bloqueável (87972). Isso confirma que o evento é só informativo, o que basta para o ClaudeBar.

## 5. Armadilhas

- **Swift 6 / MainActor**: nada novo. O estado chega pelo arquivo e pelo `DirectoryWatcher` → `Task { @MainActor in merge() }`, como os outros. O enum já é `Sendable`.
- **switch exaustivo**: o caso novo quebra o build até cada `switch` ser atualizado. Isso é desejável, porque nenhum lugar cai em "pronto" por default. Atenção ao `default: break` em `notifyTransitions`: ali o compilador não avisa.
- **Settings antigos**: quem já instalou só ganha o `StopFailure` depois de rodar o `install.sh` de novo, e só em sessões novas (a doc e o próprio script já dizem isso).
- **Versão do Claude Code < v2.1.78** **[SUPOSIÇÃO]**: o evento não existe e a sessão volta a ficar presa em `working`. Isso não regride nada.
- **LSUIElement / assinatura ad-hoc / SwiftPM**: não se aplicam. Não há API nova, permissão TCC ou recurso de bundle. O `build-app.sh` só é necessário porque o binário do hook muda.
- **SF Symbol**: o nome `exclamationmark.triangle.fill` é de conhecimento comum, mas **não abri o app SF Symbols** para confirmar a disponibilidade no macOS 14. Se o nome for inválido, `Image(systemName:)` não renderiza nada e não avisa em tempo de compilação.

## 6. Não confirmado (resumo)

- Versão exata de introdução (v2.1.78) só por mirrors, não pelo CHANGELOG oficial.
- Se o `Notification idle_prompt` dispara depois de um `StopFailure` (e sobrescreve `error`).
- Quando o `claude agents --json` emite `status: "failed"`.
- Comportamento em stream stall ou interrupção (nenhum dos dois eventos dispara?).
- Disponibilidade do SF Symbol escolhido no macOS 14 (conferir no app SF Symbols).
- Lista completa de `notification_type`.
