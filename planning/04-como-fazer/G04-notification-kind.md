# G04 — Notification por tipo (F05) + permissão × pergunta (F24)

Pesquisa de COMO FAZER. Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial (doc do Claude Code, Apple) ou verificado localmente; **[ISSUE]** = relato de usuário em issue do GitHub da Anthropic, com reprodução; **[SUPOSIÇÃO]** = inferência minha, testar antes de afirmar.

Fonte principal: <https://code.claude.com/docs/en/hooks> (baixada como `hooks.md` em 2026-11-15; Claude Code local `2.1.325`).

## 1. Ponto de partida no código

- `scripts/install.sh` registra `Notification: entry("waiting")` **sem matcher** → todo tipo de notificação (inclusive `idle_prompt`, `auth_success`, `agent_completed`, `quota_*`, `plugin_notification`) vira "esperando". É a origem do "contador mente".
- O `jq` faz `.hooks + {Notification: ...}`: **substitui o array `Notification` inteiro** do usuário. Já está no escopo do F02 (merge aditivo); F05 deve entrar em cima do F02, não do `jq`.
- `claudebar-hook` decodifica só `session_id`, `cwd`, `message` (`Sources/claudebar-hook/main.swift`).
- `SessionStatus` (`Sources/ClaudeBarCore/SessionStatus.swift`) não tem `kind`. `StatusDirectory.list` (linha ~69) faz `try? decoder.decode` e, **se falhar, apaga o arquivo**. Isso pesa na escolha do tipo do campo (ver §4).
- UI: `BarState.symbolName` (`SessionStore.swift`), `StatusHUD.symbolName`, `MenuContent.icon/description(for:)` e `Alert` em `Notifier.swift` (som `Submarine` para `.waiting`). `SessionRow` é montado em `SessionMerge.swift` (linhas 18 e 37) e precisa carregar o `kind`.

## 2. O que a doc oficial diz sobre `Notification`

**[CONFIRMADO]** (hooks.md, seção "Notification" e tabela "What the matcher filters"):

- O matcher do `Notification` filtra pelo **tipo da notificação** ("Matches on notification type. Omit the matcher to run hooks for all notification types.").
- Valores listados: `permission_prompt`, `idle_prompt`, `auth_success`, `auth_storage_failure`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`, `plugin_notification`.
- Significado dos dois que importam:
  - `permission_prompt`: "Claude needs you to approve a tool use or a sandboxed command's network request, and the prompt has waited about six seconds".
  - `elicitation_dialog`: "An MCP server opens an elicitation form and you haven't typed for about six seconds". **É elicitação de servidor MCP, não o `AskUserQuestion` do Claude.**
- Payload no stdin: campos comuns + `message`, `title` (opcional) e `notification_type`. Exemplo oficial:
  ```json
  { "session_id": "abc123", "cwd": "/Users/...", "hook_event_name": "Notification",
    "message": "Claude needs your permission", "title": "Permission needed",
    "notification_type": "permission_prompt" }
  ```
- Sintaxe do matcher: só letras, dígitos, `_`, `-`, espaço, `,` e `|` → **string exata** (ou lista exata com `|`/`,`). Qualquer outro caractere → regex JS não ancorada. `permission_prompt` cai no caminho exato.
- A doc traz exatamente o padrão "um matcher por entrada" como exemplo:
  ```json
  { "hooks": { "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "/path/to/permission-alert.sh" }] },
      { "matcher": "idle_prompt",       "hooks": [{ "type": "command", "command": "/path/to/idle-notification.sh" }] }
  ]}}
  ```
- Tempo: `permission_prompt` e `elicitation_dialog` só disparam após **~6 s sem digitar** (cada tecla adia). Para sinal imediato de permissão a doc indica `PermissionRequest`. Em sessões via Agent SDK `canUseTool` (Claude Desktop, extensão VS Code) o `permission_prompt` sai ~6 s depois e não é adiado; antes da v2.1.233 não disparava lá. `CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS=1` desliga nesses hosts.
- Notification não bloqueia nada; exit code e stderr são ignorados.
- `PreToolUse`/`PostToolUse` aceitam matcher `AskUserQuestion` (listado entre as ferramentas built-in).
- Não há na doc nenhum valor de `notification_type` específico para `AskUserQuestion`.

Resposta direta à pergunta do backlog ("payload `notification_type` não confirmado"): **agora está confirmado na doc**, tanto o campo quanto o matcher casando com ele.

## 3. Armadilha principal: `AskUserQuestion` chega como `permission_prompt`

**[ISSUE]** <https://github.com/anthropics/claude-code/issues/74052> (aberta 2026-07-04, fechada pelo bot por inatividade, `NOT_PLANNED`, sem correção): `AskUserQuestion` dispara `Notification` com `notification_type: "permission_prompt"` e `message: "Claude needs your permission"`, igual a uma permissão real. Confirmado pelo autor via log do payload.
Relacionadas: <https://github.com/anthropics/claude-code/issues/89965> (app desktop mostra a pergunta como "Allow Claude to ask…", mesmo pipeline de permissão); <https://github.com/anthropics/claude-code/issues/16102> (`PreToolUse:AskUserQuestion` em T, `Notification:permission_prompt` em T+6 s); <https://github.com/anthropics/claude-code/issues/13830> e <https://github.com/anthropics/claude-code/issues/59908> (versões antigas em que `AskUserQuestion` não disparava nada).

Consequência: **matcher `elicitation_dialog` → `question` sozinho NÃO entrega o F24**. A pergunta comum do Claude (o caso que o usuário chama de "esperando resposta") seria mostrada como "esperando permissão". `elicitation_dialog` só cobre formulários de servidores MCP, raro.

## 4. Recomendação

### Hooks (F05) — em cima do merge do F02

```json
"Notification": [
  { "matcher": "permission_prompt",  "hooks": [{ "type": "command", "command": "<hook> waiting --kind permission --pid $PPID" }] },
  { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "<hook> waiting --kind question --pid $PPID" }] }
],
"PreToolUse":  [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "<hook> waiting --kind question --pid $PPID" }] }],
"PostToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "<hook> working --pid $PPID" }] }]
```

- Tipo por **argumento**, não lido do payload: o matcher já garante o tipo, e evita depender de `notification_type` presente (houve versão sem o campo: <https://github.com/anthropics/claude-code/issues/11964>, fechada). Ler `notification_type` do stdin fica só como desempate opcional.
- `PreToolUse`/`PostToolUse` de `AskUserQuestion` é **acréscimo ao escopo do F05** (a linha do backlog só fala de `Notification`). Sem ele o F24 não funciona para o caso comum. Decisão a registrar no backlog.
- Regra no `claudebar-hook` (uma condição): `waiting --kind permission` **não sobrescreve** um arquivo atual em `waiting` + `question`. Isso absorve o `permission_prompt` falso que chega 6 s depois do `PreToolUse:AskUserQuestion` (#16102/#74052). O `PostToolUse` volta para `working`, liberando a próxima permissão real. **[SUPOSIÇÃO]** que o Claude não mostra um prompt de permissão real enquanto o `AskUserQuestion` está aberto. A doc diz que uma permissão pode chegar "while another dialog is on screen". Risco aceito: nesse caso raro a sessão mostra "pergunta" em vez de "permissão" até a resposta.
- `idle_prompt` e os demais tipos deixam de ser registrados (é o bug). `elicitation_url_dialog` também é "esperando você" (MCP pede para abrir URL). Fica fora para respeitar o backlog. Se entrar, matcher `elicitation_dialog|elicitation_url_dialog` (lista exata com `|`, confirmada).
- Sabido e fora deste item: depois de aprovar uma permissão nada volta o estado para `working` até o próximo `Stop`/`UserPromptSubmit`. Um `PostToolUse` sem matcher → `working` resolveria, mas é outro item.
- `ExitPlanMode` (aprovar plano) provavelmente também chega como `permission_prompt`. **[SUPOSIÇÃO]**, não testado. Tratar como permissão está ok.

### Modelo (`SessionStatus.kind`)

```swift
/// Por que a sessão está esperando: "permission" ou "question". `nil` em arquivos antigos.
public let kind: String?
```

- **[CONFIRMADO localmente]** com script Swift 6 no Mac: `{"a":"x"}` decodifica com `kind == nil`, e `enum K?` com valor `"zzz"` faz o decode inteiro falhar. Base documental, não relida nesta pesquisa: o `Codable` sintetizado usa `decodeIfPresent` para propriedade `Optional`: arquivo antigo sem a chave decodifica com `nil` (SE-0166 Swift Archival & Serialization, <https://github.com/swiftlang/swift-evolution/blob/main/proposals/0166-swift-archival-serialization.md>; Apple, "Encoding and Decoding Custom Types", <https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types>).
- Por que `String?` e não um `enum WaitKind: String, Codable`: com enum, um valor desconhecido (hook mais novo que o app, ou downgrade) faz o decode **lançar**, e `StatusDirectory.list` **apaga o arquivo**. Com `String?` nunca lança, e a UI mapeia `"permission"`/`"question"` e cai no genérico para o resto. Se quiser enum, precisa de `init(from:)` manual com `try?`, que é mais código para o mesmo efeito.
- `init` ganha `kind: String? = nil` (fonte compatível). `Sendable`/`Equatable` continuam sintetizados (Swift 6 ok, `String?` é `Sendable`).
- `SessionRow` ganha `kind`. Em `SessionMerge`, vem de `hook?.kind`. Linhas vindas só do `claude agents --json` (`AgentsProbe`, estados `waiting`/`blocked`) ficam `nil` → texto genérico atual.
- O `claudebar-hook` só aceita `--kind` com `permission|question`. Outro valor é ignorado (nil). Mantém a regra "nada via shell com interpolação" do plano, porque o valor vem do argv fixo escrito pelo instalador.

### UI (F24)

| | símbolo | texto no menu | título da notificação | som |
|---|---|---|---|---|
| permission | `hand.raised.fill` | "pede permissão" | "Claude quer permissão" | `Submarine` (o atual) |
| question | `questionmark.bubble.fill` | "fez uma pergunta" | "Claude fez uma pergunta" | `Purr` ou `Tink` |
| nil (genérico) | `exclamationmark.bubble.fill` (atual) | "aguardando você" | atual | `Submarine` |

- `Alert` ganha um caso (ou `.waiting(kind)`). Som, título e volume já saem de `switch`, então é só mais um ramo. `NSSound(named:)` com nomes de `/System/Library/Sounds` **[CONFIRMADO localmente]**: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink. A escolha do som é gosto, então **[SUPOSIÇÃO]** de UX: deve soar diferente de `Glass` e `Submarine`.
- Ícone da barra com várias sessões esperando: se alguma é `permission` → `hand.raised.fill`, senão `question` → `questionmark.bubble.fill`, senão o atual. Permissão ganha porque bloqueia uma ferramenta já em andamento.
- `notifyTransitions` hoje só avisa quando `state` muda. Passar de `waiting/question` para `waiting/permission` (caso raro acima) não avisa de novo. Para avisar, comparar `(state, kind)`. Uma linha.
- O emoji do menu (`🔸`) pode virar `✋`/`❓`. São emoji Unicode genéricos, sem risco de marca (guard rail do ícone).
- Símbolos SF **[CONFIRMADO localmente]** com `NSImage(systemSymbolName:)` no macOS 26. **[SUPOSIÇÃO]** de que existem no macOS 14: `hand.raised.fill` e `questionmark.bubble.fill` são do SF Symbols 1/2 (macOS 11+). Conferir no app SF Symbols (coluna "Availability") antes do merge.

## 5. Alternativas consideradas

1. **Um só hook `Notification` sem matcher, filtrando `notification_type` no `claudebar-hook`.** Funciona e a doc confirma o campo. Contra: o processo sobe para todo tipo de notificação, e a lógica fica escondida no binário em vez de visível no `settings.json` (F16, transparência dos hooks). Fica em segundo lugar.
2. **`PermissionRequest` em vez de `Notification:permission_prompt`.** Imediato (sem os 6 s), mas aparece "esperando" enquanto o usuário ainda está olhando o terminal. É ruído, e o backlog quer "esperando" = "você precisa voltar". Em hosts sem prompt, "se nenhum hook decide, nega": um hook que não imprime nada não decide, mas é superfície a mais. Não recomendo agora. F38 já o cita para outro fim.
3. **Só `Notification` (escopo literal do backlog).** Resolve o F05 (fim do falso "esperando" do `idle_prompt`), mas o F24 vira "permissão" para quase tudo (§3). Aceitável só se o F24 for adiado.

**Recomendo:** §4 completo (Notification com 2 matchers + `PreToolUse`/`PostToolUse` de `AskUserQuestion` + `kind: String?`).

## 6. Repositórios open source

Não encontrei repo open source que já diferencie permissão de pergunta pelo `notification_type` com trecho verificável. As issues acima trazem os únicos trechos de payload reais. Workaround citado nelas: `PreToolUse` com matcher `AskUserQuestion`, que é o que §4 adota. Busca: "Claude Code Notification hook AskUserQuestion notification_type permission_prompt".

## 7. Como testar (honesto)

- Unitário (Core): decode de JSON antigo sem `kind` → `nil`; JSON com `kind: "foo"` → decodifica, com `kind == "foo"`, sem apagar o arquivo.
- Manual, com `claude` 2.1.325: pedir um `Bash` não liberado e esperar 6 s sem digitar → `permission`. Pedir ao Claude "me pergunte algo com AskUserQuestion" → `question` imediato, e continuar `question` após 6 s (regra de não sobrescrever). Ficar 60 s parado após resposta → **não** pode virar "esperando".
- Não verificável por agente: o som, o ícone na barra e a notificação nativa. Vai como "não verificado" no relatório.
