# G09 — Spec técnica: popup persistente (F12) e lembrete de espera (F13)

Insumos: `04-como-fazer/G09-popup-lembrete.md` (pesquisa), `03-validacao/BACKLOG.md` (F12: P1, P, sem dependência; F13: P1, P, depende de F15 para o toggle), `00-PLANO.md` (guard rails: sem rede, não ler conversas, `0700`/`0600`, sem shell com interpolação, hook fail-open, menor código que resolve).
Código lido em 2026-11-15, na árvore de `74fa932` (as fontes são iguais às de `f943cc4`; o commit só acrescenta CI).

**Verificado nesta spec:** todo o código Swift abaixo foi aplicado numa cópia limpa do projeto (`git archive HEAD`), com Swift 6.3.3 / tools 6.0:
- `swift build`: 0 avisos. `swift test`: **45 testes passam** (34 atuais + 6 do F13 + 5 do F12).
- Mutação: tirar a condição `previous[...] == .waiting` de `dueReminders` derruba `naoDisparaNaRodadaDaTransicao`. Tirar a margem do canto (`insetBy(dx: 0, dy: 0)`) derruba `cursorNaMargemTambemEvita`. Ou seja, os testes pegam essas regressões.
- O programa `jq` do `install.sh` foi rodado num `settings.json` de exemplo com um `PostToolUse` do usuário (`prettier`): a entrada do usuário fica, a do ClaudeBar é acrescentada, e rodar duas vezes dá o mesmo arquivo (idempotente).
- `claudebar-hook working --if-waiting` com arquivo ausente: não grava nada. Custo medido: 20 chamadas em 0,5 s de relógio (≈ 25 ms cada, incluindo o `bash`), binário release.
- `FirstClickHostingView` (plano B do clique, seção F12) compila, mas **não** entra no diff padrão.

Não verificado (só dá para ver com o app rodando e o Claude Code real): ver a lista "Não confirmado" em cada funcionalidade.

## Resumo para o gestor

| Item | O quê | Arquivos tocados | Esforço |
|---|---|---|---|
| **H0** (pré-requisito de F12 e F13) | Hooks: `Notification` só para espera real (matcher) + `PostToolUse`/`PostToolUseFailure` tiram de `waiting` | `scripts/install.sh`, `Sources/claudebar-hook/main.swift`, `README.md`, `README.pt-BR.md` | 1 h |
| **F12** | Popup de "esperando" fica até o clique ou a transição; "terminou" não tapa "esperando"; canto longe do cursor | `Sources/ClaudeBar/StatusHUD.swift`, `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Tests/ClaudeBarTests/AlertTests.swift`, `README.md`, `README.pt-BR.md` | 2 h |
| **F13** | 1 lembrete após N min em `waiting`, sem timer novo; toggle provisório no menu | `Sources/ClaudeBar/SessionMerge.swift`, `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/Notifier.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/SessionMergeTests.swift`, `README.md`, `README.pt-BR.md` | 1,5 h |

Ordem obrigatória: **H0 → F12 → F13**. Sem H0, F12 deixa um popup persistente a cada resposta concluída (`idle_prompt`) e mantém o popup aberto com o Claude já trabalhando depois da aprovação. F13 herdaria os dois erros como lembrete falso.

Não toca: `ClaudeBarCore`, `AgentsProbe.swift`, `SessionRow.swift`, `SessionTerminator.swift`, `ProcessProbe.swift`, `DirectoryWatcher.swift`, `Shell.swift`, `ClaudeBarApp.swift`, `scripts/build-app.sh`, `Package.swift`.

Conflitos com outros itens do backlog (mesmo arquivo):

| Item | Onde cruza | Como resolver |
|---|---|---|
| F05 (`Notification` com matchers) | `install.sh` (`Notification`), `claudebar-hook/main.swift` (`--kind`) | Se F05 entrar **antes**, H0 não mexe em `Notification` (mantém os matchers e o `--kind` do F05) e só acrescenta `PostToolUse`/`PostToolUseFailure`. O `PostToolUse` com matcher `AskUserQuestion` → `working` do G04 fica **coberto** pelo `PostToolUse` sem matcher do H0. Não registrar os dois. |
| F02 (instalador em Swift) | `install.sh` | Se F02 entrar antes, as 3 entradas do H0 vão para a lista de entradas do instalador dele, com a mesma regra: acrescentar sem apagar o que é do usuário. |
| F07 (`StopFailure`) | `install.sh` | Mesmo bloco `jq`; só somar a chave. |
| F01 (som respeita o toggle) | `Notifier.post` | Compatível. Com F01, `guard isEnabled` vira a 1ª linha de `post`; o parâmetro `sessionId` deste diff entra igual. |
| F08 (polling leve) | `pollTimer` em `SessionStore` | F13 depende do `merge()` periódico. Se F08 levar o poll para 30–60 s, o lembrete atrasa até esse tanto. Aceitável para "5 min"; se não for, F08 mantém um `merge()` local (sem CLI) a cada 5 s. |
| F10 (clique leva à sessão) | `HUDView.onTapGesture` | F10 troca o `onDismiss` do clique. F12 não muda o clique. |
| F15 (Ajustes) | `Notifier` | F15 liga `isReminderEnabled`/`reminderMinutes` na cena `Settings` e apaga o `Toggle` provisório do menu. |
| F19 (VoiceOver) | `StatusHUD.show` | Anúncio do popup entra em `show`, depois do `orderFrontRegardless`. Sem conflito de lógica. |
| F25 (modo sem conteúdo) | corpo do lembrete | O lembrete usa `row.message`. Quando F25 entrar, o corpo passa pela mesma troca que o aviso de transição. |

---

## H0 — Hooks: só espera real vira `waiting`, e aprovação tira de `waiting`

### Objetivo

Que `waiting` no arquivo de estado signifique "o Claude está parado esperando você agora". Hoje há dois furos, e os dois viram bug visível com F12/F13:

1. `Notification` está registrado sem matcher. Assim, `idle_prompt` (≈ 60 s depois de cada resposta) também grava `waiting`.
2. Nenhum hook dispara quando você aprova uma permissão. A sessão fica em `waiting` até o `Stop`, com o Claude já trabalhando.

### Decisão técnica

- `Notification` com `"matcher": "permission_prompt|elicitation_dialog"`. Matcher só com letras, `_` e `|` é lista exata (confirmado na doc de hooks, G03/G04). Os outros tipos nem chamam o binário.
- `PostToolUse` e `PostToolUseFailure`, sem matcher → `claudebar-hook working --if-waiting --pid $PPID`. Com `--if-waiting`, o hook só regrava se o arquivo atual estiver em `waiting`. No resto do turno ele lê ~200 bytes e sai sem gravar: o `updatedAt` continua sendo "quando o estado mudou" (o menu mostra "processando (há X)" com base nele) e o app não acorda a cada ferramenta.
- Esses dois eventos **acrescentam** a entrada do ClaudeBar (tirando a nossa de uma instalação anterior). Não trocam o evento inteiro. `PostToolUse` é onde as pessoas põem formatador e lint; o `+` atual do `jq` apagaria isso.

Alternativas descartadas:
- Ler `notification_type` do stdin e filtrar no binário: o processo sobe para todo tipo, e a regra fica escondida do `settings.json` (F16, transparência).
- `PreToolUse` → `working`: dispara antes do prompt de permissão, então apagaria o `waiting` antes de ele existir.
- `PostToolUse` sem `--if-waiting`: N gravações por turno, `updatedAt` perde o sentido, `DirectoryWatcher` dispara `merge()` a cada ferramenta.
- `PermissionRequest`/`PermissionDenied`: não resolvem a aprovação (o problema é o "depois") e somam eventos sem necessidade.
- Trocar o `+` para todos os eventos (merge aditivo completo): é o F02. Aqui só os 2 eventos novos, que é onde o estrago seria novo.

### Código — `Sources/claudebar-hook/main.swift`

Comentário de uso:

```swift
// Uso: claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>] [--if-waiting]
```

Logo depois do `guard let state = SessionState(rawValue: command) else { ... }`:

```swift
    // `PostToolUse` roda a cada ferramenta. Só interessa quando ela tira a sessão
    // de "esperando" (permissão aprovada); no resto do turno o arquivo já diz
    // `working`, e regravar só mexeria no `updatedAt` e acordaria o app à toa.
    // Arquivo ausente ou ilegível: não grava (o `Stop` acerta o estado depois).
    if arguments.contains("--if-waiting") {
        let current = (try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)))
            .flatMap { try? StatusDirectory.decoder.decode(SessionStatus.self, from: $0) }
        guard current?.state == .waiting else { return }
    }
```

Fail-open mantido: toda falha (arquivo ausente, JSON quebrado) cai em `return`, com saída 0. Não usar `fail(...)` nesse caminho. O nome do arquivo passa pelo `sanitize` de `fileURL`, como na escrita.

### Código — `scripts/install.sh`

Troca o bloco `jq` inteiro:

```bash
jq --arg hook "$HOOK" '
  def entry($state): [{ hooks: [{ type: "command", command: ($hook + " " + $state + " --pid $PPID") }] }];
  # Eventos que o usuário costuma usar para outras coisas (formatador, lint):
  # acrescenta a entrada do ClaudeBar em vez de trocar o evento inteiro, e tira
  # a nossa de uma instalação anterior para não duplicar.
  def appended($current; $state):
    [($current // [])[] | select(any(.hooks[]?; (.command // "") | contains($hook)) | not)] + entry($state);
  .hooks = ((.hooks // {}) + {
    UserPromptSubmit: entry("working"),
    Stop: entry("idle"),
    # Só espera de verdade. Sem matcher, o `idle_prompt` (60 s depois de cada
    # resposta) também viraria "esperando", com popup persistente e lembrete.
    Notification: [{ matcher: "permission_prompt|elicitation_dialog" } + entry("waiting")[0]],
    SessionEnd: entry("end")
  })
  # Permissão aprovada (ou ferramenta que falhou) tira a sessão de "esperando".
  | .hooks.PostToolUse = appended(.hooks.PostToolUse; "working --if-waiting")
  | .hooks.PostToolUseFailure = appended(.hooks.PostToolUseFailure; "working --if-waiting")
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

Resultado para `Notification` (conferido):

```json
"Notification": [{ "matcher": "permission_prompt|elicitation_dialog",
                   "hooks": [{ "type": "command", "command": "<hook> waiting --pid $PPID" }] }]
```

O `$hook` vem de `--arg` (sem interpolação de shell no programa `jq`), e o `$PPID` é literal: quem expande é o shell do Claude Code ao rodar o hook, como hoje.

### README (`README.md` e `README.pt-BR.md`)

Tabela de hooks:

```markdown
| Hook | State written |
|---|---|
| `UserPromptSubmit` | `working` |
| `PostToolUse`, `PostToolUseFailure` | `working`, only if the session was `waiting` (a permission was just approved) |
| `Stop` | `idle` |
| `Notification` (`permission_prompt`, `elicitation_dialog` only) | `waiting` |
| `SessionEnd` | deletes the file |
```

Em "Installation": "registers the four hooks" → "registers the hooks"; na lista do que é **substituído**, manter `UserPromptSubmit`, `Stop`, `Notification`, `SessionEnd` e acrescentar: "`PostToolUse` and `PostToolUseFailure` are appended to, not replaced." Em "Hook CLI usage", acrescentar `[--if-waiting]` e uma linha explicando. Em "Uninstall": "remove the `claudebar-hook` entries" (sem "four"). Mesmas mudanças no `README.pt-BR.md`.

### Verificação manual

1. `./scripts/install.sh` com um `PostToolUse` seu já presente em `~/.claude/settings.json` → ele continua lá, com a entrada do ClaudeBar depois. Rodar `install.sh` de novo → ainda uma só entrada do ClaudeBar.
2. Sessão nova do Claude Code: `/hooks` lista `PostToolUse`, `PostToolUseFailure` e `Notification` com matcher, sem aviso de settings inválido.
3. Mandar um prompt curto, esperar terminar e **esperar 90 s**: o arquivo `~/.claude/claudebar/<id>.json` continua `idle` (antes do H0 virava `waiting`).
4. Pedir um comando fora da allowlist (ex.: `rm` num arquivo temporário) → arquivo em `waiting`. Aprovar → em ≤ 1 s o arquivo volta a `working` (`cat` no arquivo ou o ícone da barra).
5. Repetir o 4 e **negar** → anotar o que acontece (vai para `idle` no `Stop`? fica em `waiting`?). Registrar no PR (não confirmado).
6. Durante um turno longo com várias ferramentas, `stat -f %m` no arquivo antes e depois: o `mtime` não muda a cada ferramenta.

### Não confirmado → como se proteger

| Ponto | Proteção |
|---|---|
| O turno segue até o `Stop` depois de uma negação manual | Se não seguir, a sessão fica em `waiting` até o próximo prompt (igual a hoje). F12 limita o dano (clique fecha), F13 dá no máximo 1 lembrete. Registrar o resultado do passo 5. Não inventar heurística. |
| Custo de rodar o hook a cada `PostToolUse` | Caminho sem gravação medido em ≈ 25 ms por chamada. Se pesar no uso real, trocar o matcher vazio por uma lista das ferramentas que pedem permissão (`Bash|Edit|Write|...`). Não fazer isso antes de medir. |
| `PostToolUse` de ferramenta paralela apaga um `waiting` com o prompt ainda aberto | Risco aceito: o pior caso é o popup fechar cedo e o ícone voltar a "processando", que é o estado de hoje sem o lembrete. Testar com dois comandos em paralelo, um deles fora da allowlist. Se acontecer com frequência, adiar o `PostToolUse` e deixar só o `Stop`, documentando que o popup some no fim do turno. |
| Versão do Claude Code sem `PostToolUseFailure` | Evento desconhecido é ignorado. O passo 2 confere que não há aviso de settings inválido. |

### Critérios de aceite

- `jq` do `install.sh` preserva entradas do usuário em `PostToolUse`/`PostToolUseFailure` e é idempotente.
- `Notification` registrado com o matcher `permission_prompt|elicitation_dialog`.
- `claudebar-hook working --if-waiting` não grava quando o arquivo está ausente ou fora de `waiting`, e sai com código 0.
- Tabela de hooks atualizada nos dois READMEs.

### O que NÃO fazer

- Não registrar `PreToolUse` → `working`.
- Não ler `tool_input`/`tool_response` do payload do `PostToolUse` (pode conter conteúdo da conversa: guard rail).
- Não trocar o `+` dos outros 4 eventos por merge aditivo aqui (F02).
- Não chamar `fail()` no caminho `--if-waiting`.

---

## F12 — Popup persistente para "esperando"

### Objetivo

Aviso de espera perdido enquanto você digita é a dor nº 1 (BACKLOG). O popup de `waiting` fica na tela até você clicar nele ou até **aquela** sessão sair de `waiting` (respondeu, terminou, fechou). "Terminou" continua sumindo em 4 s e nunca tapa um "esperando" aberto. O popup não nasce debaixo do cursor.

### Decisão técnica

1. **Timer só para `.finished`.** Em `StatusHUD.show`, o `dismissTask` anterior é sempre cancelado; o novo só é criado se `alert == .finished`.
2. **O HUD sabe de qual sessão é o aviso.** `show(_:body:sessionId:)` guarda `shownAlert` e `shownSessionId`. `dismissWaiting(for:)` só fecha se o que está na tela é `waiting` daquela sessão.
3. **"Terminou" não tapa "esperando".** Se `shownAlert == .waiting`, `show(.finished, ...)` retorna sem mexer no painel. O som já tocou no `Notifier`.
4. **Fechar na transição.** No começo de `notifyTransitions`, para cada sessão que estava `waiting` em `previousStates` e agora não está (ou sumiu de `merged`), chama `notifier.dismissWaiting(for:)`. Fica **antes** do loop de avisos: assim, num `waiting → idle`, o popup de espera fecha e aí o "terminou" pode aparecer.
5. **Vários `waiting`:** mostra o mais recente (como hoje). Quando ele fecha, o anterior não reabre; o ícone laranja na barra continua avisando. `ponytail:` sem fila de avisos.
6. **Canto longe do cursor:** função pura `StatusHUD.origin(for:in:avoiding:margin:)` testa, em ordem, superior direito → inferior direito → superior esquerdo e devolve o primeiro cujo retângulo (com a margem) não contém o cursor. `NSEvent.mouseLocation` e `visibleFrame` estão os dois em coordenadas de tela (confirmado). Vale também para "terminou".
7. O exemplo do menu ("Ver exemplo de popup") passa `sessionId: nil`: fica até o clique, que é como o popup real de espera se comporta.

Alternativas descartadas:
- `NSAlert`/janela que ativa o app: rouba o foco enquanto você digita.
- `ignoresMouseEvents = true`: quebra o "fecha no clique".
- Seguir o mouse com tracking area para fugir do cursor: mais código para um problema que "o clique só fecha" já mitiga.
- Fila/pilha de vários popups: YAGNI; a barra já mostra que há mais alguém esperando.
- `removeDeliveredNotifications` no caminho nativo agora: esse caminho não roda com ad-hoc (ver `Notifier`). Fica para o F28.
- Guardar o `sessionId` no `Notifier` em vez do HUD: o HUD é quem sabe o que está na tela. No `Notifier` seriam dois lugares para manter em sincronia.

### Código — `Sources/ClaudeBar/StatusHUD.swift`

Propriedades novas, depois de `dismissTask`:

```swift
    private var dismissTask: Task<Void, Never>?
    /// O que está na tela agora. `nil` com o painel fechado.
    private var shownAlert: Alert?
    /// Sessão do aviso de "esperando" na tela, para fechá-lo quando ela sair de
    /// `waiting`. `nil` no exemplo do menu, que só fecha no clique.
    private var shownSessionId: String?
```

`show` (assinatura e começo):

```swift
    func show(_ alert: Alert, body: String, sessionId: String? = nil) {
        // "Terminou" é informativo e não pode tapar um "esperando" ainda aberto:
        // fica só o som, que o `Notifier` já tocou.
        if alert == .finished, shownAlert == .waiting { return }

        let content = HUDView(alert: alert, body: body, width: Self.width) { [weak self] in
        ... (igual até `panel.orderFrontRegardless()`)
```

Fim de `show`, `dismissWaiting` e `dismiss` (substitui o bloco do timer e o `dismiss` atual):

```swift
        shownAlert = alert
        shownSessionId = sessionId

        // Aviso novo cancela o tempo do anterior em vez de empilhar painéis.
        // Só "terminou" some sozinho; "esperando" fica até o clique ou até a
        // sessão sair de `waiting` (`dismissWaiting`).
        dismissTask?.cancel()
        dismissTask = nil
        guard alert == .finished else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Fecha o "esperando" se ele for desta sessão. Aviso de outra sessão, ou um
    /// "terminou", continua onde está.
    func dismissWaiting(for sessionId: String) {
        guard shownAlert == .waiting, shownSessionId == sessionId else { return }
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        shownAlert = nil
        shownSessionId = nil
        panel?.orderOut(nil)
    }
```

`reposition` (o `log.info` que vem depois fica igual):

```swift
    /// Tela onde está o cursor — a mesma em que a barra de menu do ClaudeBar está
    /// sendo olhada —, no primeiro canto longe dele.
    private func reposition(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let origin = Self.origin(for: size, in: frame, avoiding: mouse, margin: Self.margin)
        panel.setFrameOrigin(origin)
        ...
```

Função pura, no fim da classe `StatusHUD`:

```swift
    /// Primeiro canto, nesta ordem, que não fica sob o cursor: superior direito,
    /// inferior direito, superior esquerdo. Um popup que dura minutos e nasce
    /// debaixo do mouse leva clique sem querer. Tudo em coordenadas de tela
    /// (origem embaixo à esquerda), as mesmas de `NSEvent.mouseLocation`.
    nonisolated static func origin(for size: NSSize, in frame: NSRect, avoiding mouse: NSPoint, margin: CGFloat) -> NSPoint {
        let right = frame.maxX - size.width - margin
        let left = frame.minX + margin
        let top = frame.maxY - size.height - margin
        let bottom = frame.minY + margin
        let corners = [
            NSPoint(x: right, y: top),
            NSPoint(x: right, y: bottom),
            NSPoint(x: left, y: top),
        ]
        // A margem entra na conta: cursor encostado na borda do popup também conta.
        return corners.first { corner in
            !NSRect(origin: corner, size: size).insetBy(dx: -margin, dy: -margin).contains(mouse)
        } ?? corners[0]
    }
```

`nonisolated` é necessário: a classe é `@MainActor`, e sem isso o teste teria de ser `@MainActor` só para fazer conta. `Alert` não tem valor associado, então `==` já existe (Equatable sintetizado).

### Código — `Sources/ClaudeBar/Notifier.swift`

```swift
    /// A sessão saiu de "esperando" (respondeu, terminou ou fechou): o popup
    /// dela não tem mais o que pedir.
    func dismissWaiting(for sessionId: String) {
        hud.dismissWaiting(for: sessionId)
    }
```

e em `post`:

```swift
    func post(_ alert: Alert, body: String, sessionId: String? = nil) {
        ...
            hud.show(alert, body: body, sessionId: sessionId)
```

O caminho nativo (`UNNotificationRequest`) não muda: continua com `UUID().uuidString`.

### Código — `Sources/ClaudeBar/SessionStore.swift`

Começo de `notifyTransitions`:

```swift
    private func notifyTransitions(in merged: [SessionRow]) {
        // Saiu de "esperando" (respondeu, terminou) ou sumiu da lista (fechou):
        // o popup daquela sessão fecha. Subagente nunca abre popup, então para
        // ele isto não faz nada.
        let current = Dictionary(merged.map { ($0.sessionId, $0.state) }, uniquingKeysWith: { first, _ in first })
        for (sessionId, previous) in previousStates where previous == .waiting && current[sessionId] != .waiting {
            notifier.dismissWaiting(for: sessionId)
        }

        // Subagente é trabalho delegado: aparece no menu, mas não avisa nada.
        for row in merged where !row.isSubagent {
        ...
```

E as duas chamadas de `post` passam a sessão:

```swift
                notifier.post(.finished, body: row.name, sessionId: row.sessionId)
            ...
                notifier.post(.waiting, body: row.message ?? row.name, sessionId: row.sessionId)
```

### Teste — `Tests/ClaudeBarTests/AlertTests.swift`

Suíte nova no fim do arquivo (o arquivo já importa `AppKit`):

```swift
@Suite("Canto do popup")
struct PopupCornerTests {
    /// `visibleFrame` de uma tela 1440x900, já sem a barra de menu.
    private let tela = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let tamanho = NSSize(width: 320, height: 80)

    private func origem(mouse: NSPoint, tela: NSRect? = nil) -> NSPoint {
        StatusHUD.origin(for: tamanho, in: tela ?? self.tela, avoiding: mouse, margin: 16)
    }

    @Test func cursorLongeFicaNoSuperiorDireito() {
        #expect(origem(mouse: NSPoint(x: 700, y: 400)) == NSPoint(x: 1104, y: 779))
    }

    @Test func cursorNoSuperiorDireitoVaiParaBaixo() {
        #expect(origem(mouse: NSPoint(x: 1300, y: 820)) == NSPoint(x: 1104, y: 16))
    }

    /// Encostado na borda do popup também conta: a margem faz parte da área.
    @Test func cursorNaMargemTambemEvita() {
        #expect(origem(mouse: NSPoint(x: 1100, y: 870)) == NSPoint(x: 1104, y: 16))
    }

    /// Tela tão baixa que os dois cantos da direita pegam o cursor.
    @Test func semSaidaNaDireitaVaiParaEsquerda() {
        let baixa = NSRect(x: 0, y: 0, width: 1440, height: 150)
        #expect(origem(mouse: NSPoint(x: 1300, y: 75), tela: baixa) == NSPoint(x: 16, y: 54))
    }

    /// Segundo monitor à esquerda: coordenadas negativas, mesma regra.
    @Test func telaComOrigemNegativa() {
        let esquerda = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        #expect(origem(mouse: NSPoint(x: -100, y: 1000), tela: esquerda) == NSPoint(x: -336, y: 16))
    }
}
```

**Não** testar `show`/`dismissWaiting` no `StatusHUD` real: `show` cria `NSPanel` e `NSHostingView` no processo de teste (mesma decisão do G01). A regra de quem fecha o quê é coberta pela verificação manual.

### README (`README.md` e `README.pt-BR.md`)

Em "Why the app draws its own popup", trocar "It disappears after 4 seconds or on click" por:

```markdown
in a corner of the screen where the mouse is, away from the cursor. "Claude
terminou" disappears after 4 seconds; "Claude está esperando você" stays until
you click it or that session stops waiting (you answered, it finished, or it
was closed). A "terminou" never covers a "waiting" popup that is still open:
you only hear its sound.
```

No pt-BR, a frase "que some em 4s ou ao clique" recebe a mesma troca.

### Verificação manual

Gate: `swift build && swift test` (45 testes) e `./scripts/build-app.sh`; depois `./scripts/install.sh` (H0 já aplicado).

1. Menu → "Ver exemplo de popup" → não some em 4 s; um clique fecha. **Anotar se precisou de 1 ou 2 cliques.**
2. Sessão nova: pedir um comando fora da allowlist e tirar a mão do mouse → popup "esperando" fica > 1 min. Aprovar no terminal → o popup fecha em ≤ 1 s.
3. Repetir o 2 e, em vez de aprovar, fechar a sessão (`/exit`) → o popup fecha (sessão some da lista).
4. Com o popup de espera da sessão A aberto, fazer a sessão B terminar → toca `Glass`, o popup de A **continua** na tela.
5. Pôr o cursor no canto superior direito e disparar o exemplo → o popup nasce no canto inferior direito.
6. Com o popup de espera aberto, trocar de Space (Ctrl+→) → **anotar** se ele aparece no outro Space ou some.
7. Com o popup aberto, desligar **Notificações** no menu → o popup fecha (já é o comportamento de `setEnabled(false)`).

### Não confirmado → como se proteger

| Ponto | Proteção |
|---|---|
| `onTapGesture` em painel não ativante fecha com um clique só | `acceptsFirstMouse` vem `false` por padrão (confirmado na Apple). Se o passo 1 mostrar 2 cliques, aplicar o plano B abaixo (compila, conferido). Não aplicar sem a verificação. |
| `.transient` no `collectionBehavior` faz o popup sumir ao trocar de Space | Se o passo 6 mostrar que some, tirar só `.transient` (fica `[.canJoinAllSpaces, .ignoresCycle]`). Uma linha. Não trocar por `.stationary` sem testar Mission Control. |
| A notificação nativa ficar ou não na tela depende do estilo Banners/Alertas | Fora do escopo: o caminho nativo não roda com ad-hoc. F28 trata com identificador por sessão + `removeDeliveredNotifications`. |
| Herança de `MainActor` do `Task {}` não está escrita na Apple | Não criar `Task` novo além do que já existe; o `Task` do timer é o mesmo de hoje, que compila em Swift 6. |

Plano B do clique (só se o passo 1 falhar), em `StatusHUD.swift`:

```swift
/// Painel não ativante: sem isto, o primeiro clique pode só "acordar" a janela e
/// o popup não fechar.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

e em `show`: `let hosting = FirstClickHostingView(rootView: content)`.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Popup persistente sem motivo (`waiting` falso) | É o que o H0 corrige. Por isso a ordem é obrigatória. Clique sempre fecha. |
| Clique acidental com o popup persistente na tela | Nasce longe do cursor, e o clique só fecha (não aprova nada, não abre nada). |
| Interrupção com Esc no prompt não dispara hook (G06) | A sessão fica em `waiting` até o próximo prompt, como hoje. O popup fica até o clique. Aceito; registrar se observado. |
| Popup numa tela que você deixou de olhar | Aceito: o ícone da barra também avisa. |
| Duas sessões esperando, só a última aparece | Aceito (`ponytail:` sem fila). O ícone laranja segue aceso até a outra sair de `waiting`. |

### Critérios de aceite

- `show(.waiting, ...)` não agenda `dismissTask`; `show(.finished, ...)` agenda 4 s.
- `show(.finished, ...)` com `waiting` na tela retorna sem trocar o conteúdo do painel.
- `dismissWaiting(for:)` só fecha se o que está na tela é `waiting` daquela sessão.
- `SessionStore` chama `dismissWaiting` para toda sessão que estava `waiting` e agora não está ou sumiu, antes de postar avisos novos.
- `StatusHUD.origin` é `nonisolated static`, pura, e os 5 testes de `PopupCornerTests` passam.
- `swift build` sem avisos novos; `swift test` com os testes atuais intactos.
- Passos 1–5 e 7 da verificação manual feitos; resultado dos passos 1 e 6 registrado no PR.

### O que NÃO fazer

- Não pôr botão "Aprovar" no popup (F46, vetado por risco alto).
- Não criar fila de avisos, nem um `NSPanel` por sessão.
- Não ativar o app (`NSApp.activate`) ao mostrar o popup.
- Não mudar o nível do painel (`.statusBar`) nem `hidesOnDeactivate`.
- Não mexer no caminho `UNUserNotificationCenter` (F28).
- Não ler `NSEvent.mouseLocation` dentro da função pura: ele entra por parâmetro, para ela continuar testável.

---

## F13 — Lembrete de espera

### Objetivo

Sessão sua parada em `waiting` há N minutos (padrão 5) recebe **um** lembrete: o mesmo som de espera e o popup "Ainda esperando: <mensagem>". Responder (sair de `waiting`) cancela. Um novo episódio de espera ganha lembrete novo. Dá para desligar.

### Decisão técnica

- **Sem timer novo.** O `merge()` já roda a cada evento de hook e a cada 5 s pelo poll. A cada `merge()`, `SessionMerge.dueReminders` devolve as sessões vencidas e o `SessionStore` posta o lembrete. Atraso máximo: 5 s além de N min.
- **Chave do episódio = `sessionId|updatedAt`.** `updatedAt` é gravado pelo hook quando a sessão entra em `waiting`. Sair de `waiting` faz a condição deixar de valer (cancela sozinho). Um `waiting` novo traz outro `updatedAt`, e com ele outra chave. O `Set` `reminded` é podado a cada `merge()` para só guardar chaves de sessões ainda em `waiting`, então não cresce.
- **Só quem já estava `waiting` na rodada anterior** (`previous[sessionId] == .waiting`). Assim o lembrete nunca sai na mesma rodada do aviso da transição (que já tocou som), nem na primeira leitura depois que o app abre. App aberto com uma sessão esperando há 20 min → lembrete no próximo poll (≤ 5 s). É honesto: ela ainda está esperando.
- **Sono do Mac:** `updatedAt` é `Date`, então acordar depois de 1 h dispara o lembrete no próximo poll. Aceito.
- **Desligável sem F15:** `UserDefaults`, no mesmo padrão do `notificationsEnabled`: `waitingReminderEnabled` (padrão `true`) e `waitingReminderMinutes` (padrão `5`). Um `Toggle` no menu, visível só com notificações ligadas. Os minutos ficam sem UI (`defaults write`). O lembrete também respeita o toggle **Notificações**: o `SessionStore` checa `notifier.isEnabled` antes de postar, então o som não toca nem antes do F01.

Alternativas descartadas:
- `Task.sleep`/`Timer` por sessão: dicionário de tarefas para cancelar e vazar, e não sobrevive a reinício do app. A pesquisa achava que a lente de viabilidade previa isso; a forma por `updatedAt` é menor.
- Lembrete repetido a cada N min: o backlog pede 1. Repetir é F36/F50 (adiar/silenciar).
- `Alert` novo (`.reminder`) com som próprio: um terceiro som não diz nada que o texto "Ainda esperando" não diga. Se pedirem, é uma linha no enum.
- Persistir `reminded` em disco: reiniciar o app e levar um lembrete de novo para uma espera longa é aceitável.
- Campo de minutos no menu: o F15 é o lugar. `Stepper` dentro de `NSMenu` é UI ruim.

### Código — `Sources/ClaudeBar/SessionMerge.swift`

Antes de `openSessionCount`:

```swift
    /// Sessões suas paradas em "esperando" há `delay` ou mais que ainda não
    /// levaram lembrete neste episódio de espera (F13).
    ///
    /// Só conta quem já estava esperando na rodada anterior: assim o lembrete
    /// nunca sai junto com o aviso da transição, nem na primeira leitura depois
    /// que o app abre.
    static func dueReminders(
        rows: [SessionRow],
        previous: [String: SessionState],
        reminded: Set<String>,
        now: Date,
        delay: TimeInterval
    ) -> [SessionRow] {
        rows.filter { row in
            guard !row.isSubagent,
                  row.state == .waiting,
                  previous[row.sessionId] == .waiting,
                  let since = row.updatedAt,
                  let key = reminderKey(row)
            else { return false }
            return now.timeIntervalSince(since) >= delay && !reminded.contains(key)
        }
    }

    /// Um episódio de espera: a sessão + quando ela entrou em `waiting`. Um novo
    /// `waiting` grava outro `updatedAt` e ganha lembrete próprio.
    static func reminderKey(_ row: SessionRow) -> String? {
        row.updatedAt.map { "\(row.sessionId)|\($0.timeIntervalSince1970)" }
    }
```

### Código — `Sources/ClaudeBar/Notifier.swift`

Propriedade, ao lado de `isEnabled`:

```swift
    /// Lembrete único para sessão parada em "esperando" (F13). Persiste.
    private(set) var isReminderEnabled: Bool
```

Chaves, ao lado de `enabledKey`:

```swift
    private static let reminderEnabledKey = "waitingReminderEnabled"
    private static let reminderMinutesKey = "waitingReminderMinutes"

    /// Minutos em "esperando" até o lembrete. Sem UI até o F15:
    /// `defaults write com.joaomarcos.claudebar waitingReminderMinutes -int 10`.
    /// Valor inválido (0, negativo, texto) vira 1 min, nunca lembrete imediato.
    var reminderMinutes: Int {
        max(defaults.integer(forKey: Self.reminderMinutesKey), 1)
    }
```

`init`:

```swift
        defaults.register(defaults: [
            Self.enabledKey: true,
            Self.reminderEnabledKey: true,
            Self.reminderMinutesKey: 5,
        ])
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        isReminderEnabled = defaults.bool(forKey: Self.reminderEnabledKey)
```

Setter, ao lado de `setEnabled`:

```swift
    func setReminderEnabled(_ enabled: Bool) {
        isReminderEnabled = enabled
        defaults.set(enabled, forKey: Self.reminderEnabledKey)
    }
```

(`reminderMinutes` lê o `UserDefaults` na hora: um `defaults write` vale no próximo `merge()`, sem reiniciar. O rótulo do menu atualiza quando o menu reabre.)

### Código — `Sources/ClaudeBar/SessionStore.swift`

Estado, depois de `previousStates`:

```swift
    /// Episódios de espera que já levaram lembrete (`SessionMerge.reminderKey`).
    private var reminded: Set<String> = []
```

Em `merge()`, logo depois de `notifyTransitions(in: merged)` e **antes** de `previousStates` ser reescrito (a função lê a rodada anterior):

```swift
        notifyTransitions(in: merged)
        remindWaiting(in: merged)
```

Função nova:

```swift
    /// Lembrete único para quem segue esperando. Roda dentro do `merge()`, que o
    /// poll já chama a cada 5 s: sem timer próprio, e o atraso máximo é esse.
    private func remindWaiting(in merged: [SessionRow]) {
        // Esquece episódios encerrados: a sessão saiu de `waiting` ou sumiu.
        reminded.formIntersection(merged.filter { $0.state == .waiting }.compactMap(SessionMerge.reminderKey))

        guard notifier.isEnabled, notifier.isReminderEnabled else { return }
        let due = SessionMerge.dueReminders(
            rows: merged,
            previous: previousStates,
            reminded: reminded,
            now: Date(),
            delay: TimeInterval(notifier.reminderMinutes * 60)
        )
        reminded.formUnion(due.compactMap(SessionMerge.reminderKey))
        for row in due {
            notifier.post(.waiting, body: "Ainda esperando: \(row.message ?? row.name)", sessionId: row.sessionId)
        }
    }
```

O `sessionId` no `post` faz o lembrete entrar no mesmo esquema do F12: o popup fica até a transição, e `dismissWaiting` fecha.

### Código — `Sources/ClaudeBar/MenuContent.swift`

Dentro do `if store.notifier.state != .off {` já existente, antes de "Ver exemplo de popup":

```swift
        if store.notifier.state != .off {
            // Provisório: o F15 leva isto (e os minutos) para os Ajustes.
            Toggle("Lembrar após \(store.notifier.reminderMinutes) min esperando", isOn: Binding(
                get: { store.notifier.isReminderEnabled },
                set: { store.notifier.setReminderEnabled($0) }
            ))

            Button("Ver exemplo de popup") {
```

### Testes — `Tests/ClaudeBarTests/SessionMergeTests.swift`

Suíte nova no fim do arquivo:

```swift
@Suite("Lembrete de espera")
struct WaitingReminderTests {
    private let agora = Date(timeIntervalSince1970: 1_800_000_000)
    private let cincoMin: TimeInterval = 5 * 60

    private func esperando(_ sessionId: String, ha segundos: TimeInterval, subagente: Bool = false) -> SessionRow {
        SessionRow(
            sessionId: sessionId,
            name: nil,
            cwd: "/Users/dev/code",
            state: .waiting,
            updatedAt: agora.addingTimeInterval(-segundos),
            message: "Claude needs your permission to use Bash",
            isSubagent: subagente
        )
    }

    /// Por padrão, todas já estavam esperando na rodada anterior.
    private func devidos(
        _ rows: [SessionRow],
        previous: [String: SessionState]? = nil,
        reminded: Set<String> = []
    ) -> [String] {
        let anterior = previous ?? Dictionary(uniqueKeysWithValues: rows.map { ($0.sessionId, SessionState.waiting) })
        return SessionMerge.dueReminders(rows: rows, previous: anterior, reminded: reminded, now: agora, delay: cincoMin)
            .map(\.sessionId)
    }

    @Test func disparaAosCincoMinutosNaoAntes() {
        #expect(devidos([esperando("s1", ha: cincoMin - 1)]).isEmpty)
        #expect(devidos([esperando("s1", ha: cincoMin)]) == ["s1"])
    }

    /// Um lembrete por episódio: a chave lembrada segura os próximos `merge()`.
    @Test func lembraUmaVezSo() throws {
        let row = esperando("s1", ha: 600)
        let chave = try #require(SessionMerge.reminderKey(row))
        #expect(devidos([row], reminded: [chave]).isEmpty)
    }

    /// Nova espera grava outro `updatedAt`: a chave antiga não vale para ela.
    @Test func novoEpisodioGanhaNovoLembrete() throws {
        let antigo = try #require(SessionMerge.reminderKey(esperando("s1", ha: 900)))
        #expect(devidos([esperando("s1", ha: 400)], reminded: [antigo]) == ["s1"])
    }

    /// Saiu de `waiting`: nada a lembrar, mesmo com o tempo vencido.
    @Test func transicaoCancela() {
        let respondida = SessionRow(
            sessionId: "s1", name: nil, cwd: "/tmp", state: .working,
            updatedAt: agora.addingTimeInterval(-900), message: nil, isSubagent: false
        )
        #expect(devidos([respondida], previous: ["s1": .waiting]).isEmpty)
    }

    /// Acabou de entrar em `waiting` (ou o app acabou de abrir): o aviso da
    /// transição já tocou nesta rodada, o lembrete fica para a próxima.
    @Test func naoDisparaNaRodadaDaTransicao() {
        let row = esperando("s1", ha: 900)
        #expect(devidos([row], previous: ["s1": .working]).isEmpty)
        #expect(devidos([row], previous: [:]).isEmpty)
    }

    @Test func subagenteNaoLembra() {
        #expect(devidos([esperando("bg", ha: 900, subagente: true)]).isEmpty)
    }
}
```

Sem teste de `Notifier`/`UserDefaults` para o toggle: é um `bool` lido e gravado, igual ao `notificationsEnabled`, que também não tem teste. A regra que importa está na função pura.

### README (`README.md` e `README.pt-BR.md`)

Em "Alerts", depois da tabela:

```markdown
- **Reminder.** A session still waiting for you after 5 minutes gets one more
  alert ("Ainda esperando: …", same sound). Answering cancels it; a new wait
  gets a new reminder. Turn it off with **Lembrar após 5 min esperando** in the
  menu. To change the delay:
  `defaults write com.joaomarcos.claudebar waitingReminderMinutes -int 10`.
```

Na listagem do menu, acrescentar a linha `Lembrar após 5 min esperando ✓   (one reminder after 5 min waiting)` abaixo de `Notificações`. Mesmas mudanças no pt-BR.

### Verificação manual

Gate: `swift build && swift test` (45 testes) e `./scripts/build-app.sh`.

1. `defaults write com.joaomarcos.claudebar waitingReminderMinutes -int 1` e reabrir o app → o menu mostra "Lembrar após 1 min esperando ✓".
2. Provocar um pedido de permissão e não responder → aviso na hora; ~60–65 s depois, toca `Submarine` de novo e o popup mostra "Ainda esperando: …". Esperar mais 2 min → **nenhum** outro lembrete.
3. Aprovar → o popup fecha (F12). Provocar outra permissão na mesma sessão → novo lembrete depois de 1 min.
4. Provocar permissão e aprovar antes de 1 min → nenhum lembrete.
5. Desligar o toggle do lembrete → repetir o 2: só o aviso inicial. Religar.
6. Desligar **Notificações** → nenhum lembrete e nenhum som.
7. Abrir o menu e deixá-lo aberto quando o lembrete deveria sair → **anotar** se ele sai com o menu aberto ou só depois de fechar.
8. `defaults delete com.joaomarcos.claudebar waitingReminderMinutes` → volta a 5.

### Não confirmado → como se proteger

| Ponto | Proteção |
|---|---|
| `pollTimer` para enquanto o `NSMenu` está aberto (modo de tracking) | Irrelevante para o lembrete: com o menu aberto você está olhando o ícone. Se o passo 7 mostrar atraso, aceitar. **Não** trocar para `RunLoop.main.add(timer, forMode: .common)` nesta task: muda o poll do CLI (F08). |
| Sessão conhecida só pelo CLI (sem arquivo de hook) em `waiting`: `updatedAt` = `startedAt` | O lembrete sai no 2º poll depois da transição, não em N min, e só uma vez por sessão (a chave não muda). `ponytail:` raro com os hooks instalados; corrigir só se aparecer, guardando no `SessionStore` quando a linha virou `waiting`. |
| `idle_prompt` em sessões abertas antes do H0 (hooks antigos) | Hooks valem só em sessão nova. Até reabrir essas sessões, pode haver lembrete falso. README já diz que hooks valem em sessão nova; o PR lembra de reabrir as sessões. |

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Lembrete chato | Um só por episódio, desligável no menu, intervalo ajustável. |
| Lembrete sobre `waiting` falso (Esc, negação sem `Stop`) | Depende do H0; no pior caso é 1 lembrete, e o clique fecha. |
| `waitingReminderMinutes` com lixo (`0`, negativo, string) | `integer(forKey:)` devolve 0 para string; `max(..., 1)` segura em 1 min. |
| F08 espaçar o poll | Ver tabela de conflitos: atraso ≤ intervalo do poll, ou F08 mantém um `merge()` local de 5 s. |
| `reminded` crescer sem limite | Podado a cada `merge()` para as chaves de sessões ainda em `waiting`. |

### Critérios de aceite

- `SessionMerge.dueReminders` e `reminderKey` são puras (sem `Date()`, disco ou `UserDefaults` dentro) e os 6 testes de `WaitingReminderTests` passam.
- No máximo 1 lembrete por par `sessionId|updatedAt`; nenhum para subagente; nenhum na mesma rodada do aviso da transição.
- Com `waitingReminderEnabled = false` ou **Notificações** desligado, nenhum lembrete e nenhum som de lembrete.
- Padrões registrados: `waitingReminderEnabled = true`, `waitingReminderMinutes = 5`.
- Nenhum `Timer`, `Task` ou `DispatchSource` novo.
- `swift build` sem avisos novos; `swift test` com todos os testes anteriores passando.

### O que NÃO fazer

- Não criar `Timer`/`Task.sleep` por sessão.
- Não repetir o lembrete (F36/F50).
- Não pôr campo de minutos no menu; não criar cena `Settings` aqui (F15).
- Não persistir `reminded` em disco.
- Não criar `Alert.reminder` nem som novo.
- Não ler histórico/transcript para "contexto" do lembrete: só `row.message`, que o hook já grava com limite de 200 caracteres.

---

## Esforço total

| Item | Horas |
|---|---|
| H0 | 1 h (inclui teste manual com Claude Code real) |
| F12 | 2 h (diff validado; o tempo vai nos 7 passos manuais) |
| F13 | 1,5 h |
| **Total** | **4,5 h** |
