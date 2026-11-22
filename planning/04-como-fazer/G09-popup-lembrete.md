# G09 — Popup persistente (F12) e lembrete de espera (F13)

Pesquisa de COMO FAZER. Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial ou código do repo lido; **[SUPOSIÇÃO]** = inferência não verificada.

## Ponto de partida (código lido)

- `Sources/ClaudeBar/StatusHUD.swift`: um único `NSPanel` (`.borderless, .nonactivatingPanel`, nível `.statusBar`), reaproveitado. `show(_:body:)` sempre agenda `dismissTask` de 4 s (`Task.sleep`), e um aviso novo substitui o conteúdo e renova o timer. Posição: canto superior direito do `visibleFrame` da tela onde está o cursor (`NSEvent.mouseLocation`). Clique fecha (`onTapGesture` → `dismiss()`). O HUD não sabe de qual sessão é o aviso.
- `Notifier.post(_:body:)`: toca som e, sem Developer ID (caso normal, ad-hoc), chama `hud.show`. Com notificação nativa, cria `UNNotificationRequest` com `identifier: UUID().uuidString` (não dá para remover depois por sessão).
- `SessionStore.notifyTransitions(in:)`: compara `previousStates[sessionId]` com o estado novo; `.waiting` → `notifier.post(.waiting, ...)`; `.idle` vindo de `.working` → `.finished`. Nada acontece quando uma sessão **sai** de `waiting` nem quando some da lista.
- `merge()` roda a cada evento do `DirectoryWatcher` e a cada 5 s pelo `pollTimer` (`Timer.scheduledTimer`).
- `SessionRow.updatedAt` = quando o hook gravou o estado (`SessionStatus.updatedAt`, `Date()` no hook).
- `scripts/install.sh` registra só `UserPromptSubmit→working`, `Stop→idle`, `Notification→waiting` (sem matcher), `SessionEnd→end`.

## Achado que muda o desenho: quando a sessão SAI de `waiting`?

Sem resolver isto, F12 (popup que fica até a transição) e F13 (lembrete que cancela na transição) ficam errados.

1. **Nenhum hook dispara quando você aprova/nega um prompt de permissão.** [CONFIRMADO] O doc de hooks não tem evento para a decisão manual; `PermissionDenied` "doesn't run when you manually deny a permission dialog"; `PostToolUse` "Runs immediately after a tool completes successfully"; `PostToolUseFailure` roda quando a ferramenta falha. https://code.claude.com/docs/en/hooks
   - Consequência com os hooks atuais: aprovou o Bash → estado continua `waiting` até o `Stop` do fim do turno. O popup persistente ficaria na tela enquanto o Claude trabalha, e o lembrete de 5 min dispararia num turno longo já desbloqueado. [CONFIRMADO pelo código + doc]
   - Correção: adicionar `PostToolUse` (e `PostToolUseFailure`) → `working` no `install.sh`. É exatamente o que faz o "Handoff" do Josh Morony: "Permission: `PostToolUse` → `running` clears it after you approve. `PreToolUse` can't do this because it fires before the prompt." https://www.joshmorony.com/workflows/handoff-claude-code-tmux-status-indicator/
   - Negação manual: nenhuma ferramenta roda, o Claude responde e o `Stop` leva a `idle`. [SUPOSIÇÃO: o turno segue até o `Stop` depois da negação; não testado.]
   - Custo: `PostToolUse` roda a cada ferramenta (spawn do `claudebar-hook` + escrita de arquivo). [SUPOSIÇÃO: aceitável, o hook é um binário Swift pequeno; medir.] Se pesar, o hook pode ler o arquivo atual e só regravar quando o estado gravado for `waiting`.
   - Ferramentas em paralelo: um `PostToolUse` de outra ferramenta pode chegar enquanto um prompt de permissão está aberto e apagar o `waiting`. [SUPOSIÇÃO: risco existe em teoria; o `permission_prompt` só chega após ~6 s, então o `waiting` voltaria só se outro `Notification` chegasse. Testar.]

2. **`Notification` sem matcher também cobre `idle_prompt`, `auth_success` etc.** [CONFIRMADO] Matchers documentados: `permission_prompt`, `idle_prompt`, `auth_success`, `auth_storage_failure`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_*`, `plugin_notification`. `idle_prompt` = "Claude finished responding about 60 seconds ago and you haven't typed since"; `permission_prompt` = "...and the prompt has waited about six seconds". https://code.claude.com/docs/en/hooks
   - Consequência hoje: 60 s depois de cada "terminou" a sessão vira `waiting` (via `idle_prompt`). Com F12, isso viraria um popup **persistente** em toda resposta concluída, e com F13 um lembrete 5 min depois. Isso inverte o objetivo do "terminou some em 4 s".
   - Correção recomendada: matcher no `install.sh`: `Notification` com `"matcher": "permission_prompt|elicitation_dialog"`. O formato de matcher com `|` aparece no próprio doc. Alternativa: o `claudebar-hook` ler `notification_type` do stdin (campo [CONFIRMADO]: "Notification hooks receive `message` with the notification text, an optional `title`, and `notification_type`") e ignorar os tipos que não são espera. Prefiro o matcher: menos código, e nem chama o binário.
   - `agent_needs_input` e `elicitation_url_dialog`: deixar fora até alguém pedir (YAGNI).
   - Quem já instalou precisa rodar `install.sh` de novo (os hooks valem só em sessões novas; o README já diz isso).

## F12 — popup persistente para `waiting`

### Recomendado (mudança pequena, só AppKit já usado)

1. **Timer só para `.finished`.** Em `StatusHUD.show`, `dismissTask?.cancel()` sempre; criar o `Task` de 4 s só se `alert == .finished`. (Já sugerido na lente de viabilidade, N8.)
2. **HUD sabe de qual sessão é o aviso.** `show(_ alert:, body:, sessionId:)` guarda `shownWaitingSession: String?`. Novo método `dismissWaiting(for sessionId:)` que só fecha se for a mesma sessão.
3. **"terminou" não apaga um "esperando" na tela.** Hoje um `.finished` de outra sessão substitui o conteúdo e agenda 4 s: o aviso de espera se perde (a dor nº 1). Regra: se há `waiting` visível, `.finished` só toca o som. [Decisão de produto, não de API.]
4. **Fechar na transição.** Em `SessionStore.notifyTransitions`, quando `previous == .waiting && row.state != .waiting`, chamar `notifier.dismissWaiting(sessionId)`. Também quando a sessão some de `merged` (sessão encerrada): comparar `previousStates.keys` com os ids novos.
5. **Vários `waiting` ao mesmo tempo:** mostra o mais recente (comportamento atual). Ao fechar o mostrado, não reabrir o anterior — o ícone laranja na barra continua avisando. ponytail: fila de avisos só se alguém reclamar.
6. **Não abrir sob o cursor.** Em `reposition`, testar cantos em ordem (sup. direito → inf. direito → sup. esquerdo) e usar o primeiro cujo retângulo, ampliado pela margem, não contém `NSEvent.mouseLocation`. Ambos em coordenadas de tela: `mouseLocation` "Reports the current mouse position in screen coordinates" [CONFIRMADO] https://developer.apple.com/documentation/appkit/nsevent/mouselocation ; `NSScreen.visibleFrame` também é em coordenadas de tela [CONFIRMADO por uso atual no código, que funciona]. A escolha do canto é função pura (frame, size, mouse) → dá para testar com `assert`/XCTest sem UI.
   - O cursor pode entrar no popup depois que ele abre; o clique só fecha (sem botões de ação), então o clique acidental é inofensivo — mitigação já prevista na lente de risco (N8).
7. **Notificação nativa (caminho Developer ID, futuro):** trocar `UUID().uuidString` por `"waiting-\(sessionId)"` e, na transição, `UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:)` — "Removes your app's notifications from Notification Center that match the specified identifiers." [CONFIRMADO] https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removedeliverednotifications(withidentifiers:) . Se a notificação fica na tela ou some depende do estilo (Banners/Alertas) escolhido pelo usuário nos Ajustes; o app não força. [SUPOSIÇÃO baseada no truque do Handoff, que precisa mexer em `NSUserNotificationAlertStyle` no Info.plist do terminal-notifier para ter alerta persistente.] Com ad-hoc este caminho nem roda (comentário do `Notifier`), então fica fora do escopo de F12.

### Alternativas descartadas

- `NSAlert`/janela ativada: rouba foco enquanto você digita. Contra o "sem roubar foco" do comentário atual.
- `ignoresMouseEvents = true` para nunca interceptar clique: quebra o "fecha no clique". Descartado.
- Mover o popup quando o mouse chega perto (`acceptsMouseMovedEvents`, tracking area): mais código para um problema que o clique-só-fecha já mitiga. YAGNI.

### Armadilhas

- **Swift 6 / MainActor:** `StatusHUD` e `Notifier` já são `@MainActor`; `Task { ... }` criado dentro deles roda no main actor e o padrão atual já compila em Swift 6 (`swift-tools-version: 6.0`). [CONFIRMADO pelo repo; a regra de herança de isolamento do `Task.init` não está escrita na página da Apple que li.]
- **`Task.sleep` e cancelamento:** "If the task is canceled before the time ends, this function throws `CancellationError`." Relógio padrão `.continuous`. [CONFIRMADO] https://developer.apple.com/documentation/swift/task/sleep(for:tolerance:clock:) — o `try?` + `guard !Task.isCancelled` atual está certo.
- **Clique em painel não ativante:** `NSView.acceptsFirstMouse(for:)` tem padrão `false` ("a click on a view in an inactive window only activates the window") [CONFIRMADO] https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:) . O `onTapGesture` atual já fecha o painel na prática [SUPOSIÇÃO: o README/código dizem que fecha; não reverifiquei se às vezes precisa de dois cliques].
- **`.transient` no `collectionBehavior`:** some ao trocar de Space? [SUPOSIÇÃO; com `.canJoinAllSpaces` deveria aparecer em todos. Testar troca de Space com popup persistente, porque agora ele dura minutos e não 4 s.]
- **Tela errada:** o popup abre na tela do cursor no momento do aviso. Persistente, ele pode ficar numa tela que você deixou de olhar. Aceitável (o ícone da barra também avisa).

## F13 — lembrete único após N min em `waiting`

### Recomendado: sem timer novo, aproveitar o `merge()` de 5 s

- No `SessionStore`, um `Set<String>` `reminded` com a chave `"\(sessionId)|\(updatedAt)"` (ou guardar o `updatedAt` lembrado por sessão).
- A cada `merge()`: para cada `row` não-subagente com `state == .waiting`, `updatedAt` conhecido e `now - updatedAt >= N min` e ainda não lembrado → `notifier.post(.waiting, body: "Ainda esperando: " + (row.message ?? row.name))` e marcar como lembrado. Isso dá exatamente **1** lembrete por episódio de espera.
- Cancelar na transição sai de graça: se o estado mudou, a condição `state == .waiting` deixa de valer. Um novo `waiting` tem outro `updatedAt` → novo episódio, novo lembrete. Limpar `reminded` com `formIntersection` dos ids atuais, como já é feito com `acknowledged`.
- Lógica como função pura em `SessionMerge` (ex.: `dueReminders(rows:now:after:reminded:)`) → um teste em `ClaudeBarTests` cobre: dispara aos N min, não dispara duas vezes, não dispara após transição, ignora subagente.
- Precisão: até +5 s (intervalo do poll) além de N min. Suficiente para "5 min".
- **Por que `updatedAt` e não `Task` por sessão:** sobrevive a reinício do app (o arquivo do hook guarda `updatedAt`), não precisa cancelar nada, e não tem dicionário de `Task` para vazar. A lente de viabilidade falava em `Timer` por sessão; esta forma é menor.
- **Armadilha do `Timer`:** `Timer.scheduledTimer` "schedules it on the current run loop in the default mode" [CONFIRMADO] https://developer.apple.com/documentation/foundation/timer/scheduledtimer(withtimeinterval:repeats:block:) . Com o menu aberto (`.menuBarExtraStyle(.menu)` → NSMenu em tracking), o poll não roda [SUPOSIÇÃO: modo de tracking do NSMenu não é o default]. Irrelevante para o lembrete (você está olhando o menu), mas não usar isso para nada que precise de precisão.
- **Sono do Mac:** com `updatedAt` (`Date`), dormir 1 h em `waiting` dispara o lembrete logo ao acordar. Aceitável e honesto (ainda está esperando). Se fosse `Task.sleep`, o relógio `.continuous` também conta o sono: "does not stop incrementing while the system is asleep" [CONFIRMADO] https://developer.apple.com/documentation/swift/continuousclock
- **Waiting gravado antes do fix de `idle_prompt`:** sessões antigas ainda com hooks sem matcher vão gerar lembrete após `idle_prompt`. Por isso o fix do matcher deve entrar junto ou antes.

### Desligável (dependência F15)

- `UserDefaults` com `register(defaults:)`, igual ao `notificationsEnabled` do `Notifier`: `waitingReminderEnabled` (padrão `true`) e `waitingReminderMinutes` (padrão `5`). Respeitar também `notifier.isEnabled` (notificações desligadas → sem lembrete; o som segue a regra do `post`).
- Até a F15 existir: um toggle no menu ao lado de "Notificações" basta; o intervalo fica só no default (sem UI). F15 depois liga os dois na cena `Settings`.

### Open source de referência

- Handoff (Josh Morony): alerta persistente por sessão (`-group "claude-$sid"`), retirado por `-remove` quando o trabalho volta (`PostToolUse`/`UserPromptSubmit` → `running`) ou a sessão termina. Mesmo desenho de "fecha na transição". https://www.joshmorony.com/workflows/handoff-claude-code-tmux-status-indicator/
- Claude Code Notifier: anuncia "Configurable reminders… If you don't respond within X minutes, get reminded", sem detalhe nem código aberto. https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji
- Nudgy (https://github.com/Hamma111/nudgy), claude-notify (https://github.com/armandsalle/claude-notify), Hawky: avisam por hook, mas não achei lembrete repetido nem popup persistente documentados neles. [Não li o código.]

## Ordem sugerida

1. `install.sh`: matcher `permission_prompt|elicitation_dialog` no `Notification` + `PostToolUse`/`PostToolUseFailure` → `working`. Atualizar a tabela de hooks no README.
2. F12: timer só para `.finished`, `sessionId` no HUD, dismiss na transição/sumiço, `.finished` não sobrepõe `waiting`, canto longe do cursor.
3. F13: `dueReminders` puro + teste, chamada no `merge()`, chaves no `UserDefaults`, toggle no menu.

Não verificado (guard rail "verificação honesta"): comportamento real do popup na barra, troca de Space, clique único no painel não ativante, custo do `PostToolUse` por ferramenta, ferramentas paralelas com prompt aberto.
