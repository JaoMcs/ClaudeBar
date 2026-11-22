# G05: sessões fantasmas (F06) + polling leve (F08)

Pesquisa de "como fazer". Não é o plano final. Legenda:
**[CONFIRMADO]** = fonte oficial (Apple / code.claude.com) ou medido nesta máquina.
**[SUPOSIÇÃO]** = inferência ou fonte não oficial; precisa de teste antes de virar regra.

---

## 1. Ponto de partida (código em `main`, f943cc4)

| Onde | O que faz hoje | Problema para F06/F08 |
|---|---|---|
| `ClaudeBarCore/SessionStatus.swift` `isAlive` | `pid <= 0` → **vivo**; senão `kill(pid,0)==0 \|\| errno==EPERM` | **Bug real:** arquivo com `pid 0` nunca é limpo, fica fantasma para sempre. Não confere se o PID ainda é `claude` (PID reciclado passa como vivo). |
| `ClaudeBarCore/StatusDirectory.swift` `readAll()` | Decodifica, apaga inválido e morto | `url` é `static let`, então não dá para testar com diretório temporário. Liveness chumbada, não injetável. |
| `ClaudeBar/ProcessProbe.swift` | `isGroupLeader` + `executablePath` (`proc_pidpath`), injetável | Só o `SessionTerminator` usa. `readAll` (Core) não enxerga, porque está em outro target. |
| `claudebar-hook/main.swift` | `sessionId = payload.session_id ?? env CLAUDE_SESSION_ID ?? "unknown"`; `--pid` ausente → `0` | Grava `unknown.json` quando o payload falha. `CLAUDE_SESSION_ID` **não aparece** na doc oficial de hooks (ver §2). |
| `SessionMerge.rows` | Linha só do hook entra mesmo sem o CLI conhecer | Correto quando o CLI está fora, mas mantém o fantasma de `pid 0` para sempre. |
| `SessionStore.startWatching` | `DirectoryWatcher` (hook, instantâneo) + `Timer` de **5 s** chamando `claude agents --json` | O custo de F08 (§4). |
| `scripts/install.sh` | Registra `UserPromptSubmit`, `Stop`, `Notification`, `SessionEnd` com `--pid $PPID` | Sem `SessionStart`: sessão nova que nunca recebeu prompt só aparece pelo polling. |

[CONFIRMADO, medido aqui] `$PPID` do hook é o PID do processo `claude`. Os dois arquivos em `~/.claude/claudebar/` têm PIDs 77570 e 85940, iguais aos de `~/.claude/sessions/<pid>.json`. `ps` mostra o executável `.../Claude/claude-code/2.1.325/.../claude.app/Contents/MacOS/claude` (sessões do app desktop). Na CLI, o `~/.local/bin/claude` é link para `~/.local/share/claude/versions/2.1.325`. Os dois caminhos contêm `claude`, então o filtro atual do `SessionTerminator` (`path.lowercased().contains("claude")`) serve.

---

## 2. O que a doc oficial do Claude Code garante

Fonte: https://code.claude.com/docs/en/hooks

- **[CONFIRMADO]** Campos comuns no stdin de todo hook: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode` (entre outros). O nome certo é `session_id`, que o hook já usa.
- **[CONFIRMADO]** Existe `SessionStart`, com `source` ∈ `startup | resume | clear | compact | fork`.
- **[CONFIRMADO]** `SessionEnd` recebe `reason` ∈ `clear | resume | logout | prompt_input_exit | other`. Budget padrão de **1,5 s**. Ele dispara em `/clear` e em `/resume` interativo: **o processo continua vivo e o `session_id` muda**. Logo, "PID vivo" não prova que *aquele* `sessionId` está vivo.
- **[CONFIRMADO]** Hook sem `args` roda via `sh -c` no macOS e "em sua própria sessão, sem terminal de controle". A doc não fala do `$PPID`. O valor foi confirmado empiricamente, ver §1.
- **[CONFIRMADO]** Variáveis de ambiente documentadas para hooks: `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_CODE_REMOTE`, `CLAUDE_EFFORT`, entre outras. **`CLAUDE_SESSION_ID` não está na lista.** O fallback do hook depende de algo não documentado.
- **[SUPOSIÇÃO]** A doc não diz se `SessionEnd` dispara quando o terminal fecha (SIGHUP), em `tmux kill-server` ou em crash. Com SIGKILL, por definição de POSIX, nenhum código do processo roda. Portanto **sempre** vai existir sessão que morre sem hook, e é isso que justifica F06.
- **[CONFIRMADO]** Statusline (https://code.claude.com/docs/en/statusline): debounce de 300 ms e `refreshInterval` opcional (mínimo 1 s). **Não recomendo** usar como heartbeat: o usuário só tem um `statusLine` e o app passaria a disputá-lo, e a statusline não roda em sessão sem TUI.
- **[CONFIRMADO, help local]** `claude agents --json`: "Print active sessions (interactive and background) as a JSON array and exit". O `--all` inclui background concluídos (não usamos).
- **[SUPOSIÇÃO / não documentado]** `~/.claude/sessions/<pid>.json` existe localmente com `pid`, `sessionId`, `procStart`, `kind`, `entrypoint`, `status`, `updatedAt`… Ler isso direto seria ~0 custo e traria o `procStart` de graça, mas é **interface interna não documentada**. O guard rail de risco do `00-PLANO.md` desaconselha. Fica como alternativa C (§6), não como recomendação.

---

## 3. F06: como provar que não fica fantasma

### 3.1 Regra de liveness proposta (conservadora)

Sinal de vida de um arquivo de hook, nesta ordem:

| # | Situação | Decisão | Por quê |
|---|---|---|---|
| 1 | Arquivo não decodifica | apagar (já faz) | — |
| 2 | `sessionId` vazio, `"unknown"` ou nome do arquivo ≠ `sanitize(sessionId).json` | apagar | Arquivo nasceu de payload quebrado ou foi forjado à mão. O hook também deve **parar de gravar** `unknown` (sair 0 sem gravar). |
| 3 | `pid <= 0` | **não apagar no `readAll`**. No `SessionMerge`, esconder se o CLI respondeu e não conhece o `sessionId`. Se o CLI estiver indisponível, mostrar. | Conservador: sem PID não há prova de morte, mas o CLI é a fonte de verdade da lista. Hoje o arquivo fica para sempre. |
| 4 | `kill(pid,0) == -1 && errno == ESRCH` | apagar | Processo morreu. |
| 5 | Vivo, `proc_pidpath` devolve caminho **sem** `claude` | apagar | PID reciclado por outro programa. |
| 6 | Vivo, caminho com `claude`, **início do processo > `updatedAt` do arquivo** (+ folga de 1 s) | apagar | O PID foi reciclado por *outro* `claude`. O processo que gravou o arquivo tem que ter nascido antes da gravação. |
| 7 | `proc_pidpath` falha (nil) ou `EPERM` | manter | Sem informação, o critério é conservador (o painel pediu "limpar demais esconde sessão real"). |

O item 6 dispensa campo novo no JSON e mudança no hook. Base:
- **[CONFIRMADO, Apple DTS]** https://developer.apple.com/forums/thread/824760: a resposta aceita (DTS/WWDR) recomenda combinar PID + horário de início do processo contra reuso de PID, porque um PID praticamente nunca é reusado no mesmo microssegundo (paráfrase, não citação). Também aponta audit token como o caminho "certo", mas ele só serve com conexão XPC/Mach, que não temos.
- **[CONFIRMADO, header XNU, não é doc "bonita"]** `proc_pidinfo(pid, PROC_PIDTBSDINFO, …)` preenche `struct proc_bsdinfo` com `pbi_start_tvsec`/`pbi_start_tvusec`: https://opensource.apple.com/source/xnu/xnu-7195.81.3/bsd/sys/proc_info.h.auto.html. `libproc` não tem página no developer.apple.com. É a mesma família do `proc_pidpath` que o `ProcessProbe` já usa.
- Alternativa: `sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, pid])` → `kinfo_proc.kp_proc.p_starttime`. É mais verboso em Swift e não vale a troca.

Esboço (dentro do `ProcessProbe` existente, sem tipo novo):

```swift
/// Início do processo, para detectar PID reciclado. nil = sem informação.
var startTime: @Sendable (Int32) -> Date?
// live:
startTime: { pid in
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
        + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
}
```
[SUPOSIÇÃO] Os nomes `proc_bsdinfo`, `PROC_PIDTBSDINFO`, `pbi_start_tvsec` vêm do header XNU acima e devem ser importáveis via `Darwin` (o `proc_pidpath` já é). Confirmar compilando.

### 3.2 Onde mexer (menor diff)

- `ProcessProbe` hoje está no target `ClaudeBar` e o `readAll` no `ClaudeBarCore`. Opção mais barata: `StatusDirectory.readAll(in url: URL = url, isAlive: (SessionStatus) -> Bool)`. O app passa a regra montada com `ProcessProbe.live` e os testes passam um fake. `SessionStatus.isAlive` vira a regra pura `Liveness.isAlive(status, probe:)` ou some. O hook (`claudebar-hook`) não usa `readAll`, então mover a regra para o target do app não quebra nada.
- O parâmetro `in url:` resolve o `static let url` não testável sem precisar de abstração.
- Regra 3 (pid 0) fica em `SessionMerge.rows(agents:statuses:)`, que já é puro e testado. Hoje a assinatura recebe `agents: [AgentSession]` e não distingue "CLI não respondeu" de "CLI respondeu vazio". O `SessionStore` usa `[]` nos dois casos. Precisa virar `agents: [AgentSession]?`, ou guardar um `Bool` de "CLI já respondeu".
- Cinto extra contra fantasma vindo do **cache do CLI** (relevante para F08): no `merge()`, descartar linha do CLI com `pid` conhecido em que `kill` dá `ESRCH`. É barato (syscall), sem subprocesso.

### 3.3 Testes (Swift Testing, já usado em `Tests/ClaudeBarTests`)

Padrão existente: `SessionTerminatorTests` injeta `ProcessProbe(isGroupLeader:executablePath:)`. Basta estender com `exists`/`startTime`. Casos mínimos, um `@Test` parametrizado:

1. processo morto (`exists = false`) → arquivo apagado do diretório temporário
2. PID vivo, caminho `/usr/sbin/cron` → apagado
3. PID vivo, caminho `claude`, início **depois** de `updatedAt` → apagado
4. PID vivo, caminho `claude`, início antes → mantido
5. `executablePath == nil` → mantido (conservador)
6. `pid 0` + CLI respondeu sem esse id → linha some do `SessionMerge`, arquivo fica
7. `pid 0` + CLI indisponível (`nil`) → linha aparece
8. `sessionId = "unknown"` / nome do arquivo divergente → apagado
9. sessão do app desktop (caminho `.../claude.app/Contents/MacOS/claude`) → mantida
10. Teste real sem fake: `Process` rodando `/bin/sleep 30`, grava status com o PID dele, `kill`, `waitUntilExit`, `readAll` → apagado. Valida o `ProcessProbe.live` de ponta a ponta. [SUPOSIÇÃO] Funciona no runner do `swift test` sem sandbox.

---

## 4. F08: custo medido (antes)

**[CONFIRMADO, medido nesta máquina]** `/usr/bin/time -l ~/.local/bin/claude agents --json`, 3 execuções, claude 2.1.325 (binário nativo arm64, não Node):

| métrica | por chamada |
|---|---|
| wall | 0,14–0,22 s |
| CPU (user+sys) | ~0,15–0,19 s |
| pico de RSS | **~159 MB** |
| instruções | ~1,12 × 10⁹ |

Projeção (aritmética sobre a medição acima, não medição contínua):

| cenário | chamadas/dia | CPU/dia | instruções/dia |
|---|---|---|---|
| hoje, 5 s fixo | 17.280 | **~43–55 min** | ~1,9 × 10¹³ |
| 60 s + abrir menu (~50) + hooks com throttle (~300) | ~1.800 | ~5 min | ~2 × 10¹² |
| 30 s + mesmo | ~3.200 | ~9 min | ~3,6 × 10¹² |

Correção do backlog: o binário atual é Mach-O nativo, não "processo Node". O custo por chamada é o da tabela.

### Como medir antes/depois (sem sudo)
1. `/usr/bin/time -l build/ClaudeBar.app/Contents/MacOS/ClaudeBar`, deixar 10 min com 2 sessões abertas e encerrar com Ctrl-C. Repetir no build novo. [SUPOSIÇÃO, semântica POSIX de `wait4`/rusage] O `user`/`sys` reportado inclui os filhos que o app reapou (o `Process.waitUntilExit` reapa), então mede o custo dos `claude agents` somados.
2. Contador: um `os_log`/`Logger` com `privacy: .public` só no número de spawns, ou `log stream --predicate 'subsystem == "…"'`. Spawns por 10 min: hoje ≈ 120, alvo ≲ 15.
3. Opcional, com sudo: `sudo powermetrics --samplers tasks --show-process-coalition -i 60000 -n 10` (energia por coalizão; filhos entram na coalizão do app). Activity Monitor → Energy também serve como visual.

---

## 5. F08: como fazer o novo agendamento

### 5.1 Gatilhos

| Gatilho | Mecanismo | Status |
|---|---|---|
| Evento de hook | `DirectoryWatcher` já existe. No callback, além de `merge()`, chamar `refreshAgents()` com **throttle** | [CONFIRMADO] O padrão "dispatch source em vez de timer" é o que a Apple recomenda: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html ("Instead of using timers to watch for events, use a more efficient service, such as a dispatch source.") |
| Morte de processo sem hook | **`DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue:)`** para cada PID conhecido → `merge()` + `refreshAgents()` | [CONFIRMADO] A API existe: https://developer.apple.com/documentation/dispatch/dispatchsource/makeprocesssource(identifier:eventmask:queue:). Uso real em OSS: VibeBar (MIT) `Sources/VibeBarApp/SessionProcessObserver.swift`, https://github.com/yelog/vibebar (trecho abaixo). [SUPOSIÇÃO] Comportamento quando o PID já morreu antes do `resume()`: a doc não diz. Por isso a checagem por `kill` em todo `merge()` continua. |
| Abrir o menu | ver §5.2 | precisa de teste |
| Polling lento | `Timer` de **60 s** com `tolerance = 6 s` (≥ 10%) | [CONFIRMADO] Guia de energia da Apple: "set the tolerance to at least 10 percent of the interval". Mesma URL do guia acima, e https://developer.apple.com/documentation/foundation/timer/tolerance |
| Sessão nova sem prompt | registrar também **`SessionStart`** no `install.sh` (grava `idle`) | [CONFIRMADO] O evento existe na doc de hooks. Mudança de `install.sh`/README fica para a task, não para esta pesquisa. |

Com a fonte `.exit` e a checagem por `kill` no `merge()`, o fantasma **não** espera os 60 s do polling. O polling sobra só para o que nenhum evento vê: sessão aberta antes de os hooks serem instalados e agente background sem `pid`. Isso tira a premissa "fantasma demora mais" do risco de F08.

Trecho do VibeBar (MIT, `SessionProcessObserver.swift`):
```swift
let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: [.exit], queue: queue)
source.setEventHandler { [weak self] in
    Task { @MainActor [weak self] in guard let self else { return }; await self.handleExit(pid: pid) }
}
```
O comentário do autor diz: "Exit events only request a refresh — they never mutate sessions directly. PID zero and negative PIDs are ignored." O ClaudeBar deve seguir a mesma regra: o evento só dispara `merge()`/`refresh`, e quem decide é a regra da §3.

Outros OSS de referência:
- agent-status (Apache-2.0), https://github.com/autonomous-ai/agent-status `AgentStatus/Store/SessionStore.swift`: ticker de liveness de 5 s que só faz `kill(pid,0)` em memória ("Cheap: just re-validate PIDs … no disk I/O"). Mostra que um timer curto só com syscall é aceitável. O caro é o subprocesso.
- Clawdboard (MIT), https://github.com/ApocoHQ/clawdboard `SessionStateWatcher.swift`: `DispatchSource` no diretório, igual ao `DirectoryWatcher`. A limpeza por PID fica num daemon Python à parte, o que não serve para nós.

### 5.2 Detectar "menu abriu" com `.menuBarExtraStyle(.menu)`

| Opção | Evidência | Custo |
|---|---|---|
| A. `NotificationCenter` em `NSMenu.didBeginTrackingNotification` com `object: nil` | [CONFIRMADO] A notificação existe: "Posted when menu tracking begins" (https://developer.apple.com/documentation/appkit/nsmenu/didbegintrackingnotification). A doc diz que o `object` é o main menu ou o menu raiz de popup button e **não cita status item**. [SUPOSIÇÃO] Ela dispara para o NSMenu que o SwiftUI cria para o `MenuBarExtra`. Como o app é `.accessory` e não tem outro menu, qualquer tracking seria o nosso. | ~5 linhas, zero dependência. **Testar primeiro.** |
| B. KVO no estado do botão do `NSStatusItem`, como faz o MenuBarExtraAccess | https://github.com/orchetect/MenuBarExtraAccess `MenuBarExtraAccess.swift` (`setupStatusItemButtonStateObserver`, `newVal != .off` ⇒ aberto). O README avisa que no estilo `.menu` "Observing the `isPresented` binding will not work as expected", porque o menu bloqueia o runloop. | Introspecção de janela/status item, frágil entre versões do macOS. O código menciona tratamento especial para macOS 27+. Evitar como dependência. |
| C. Trocar para `.menuBarExtraStyle(.window)` e usar `.onAppear` | [SUPOSIÇÃO, fonte não oficial] Em `.menu` o `onAppear` só roda na 1ª renderização, em `.window` roda a cada abertura (thread do fórum sem resposta aceita: https://developer.apple.com/forums/thread/721627). | Muda o visual e o comportamento do menu. Fora do escopo de F08. |

Recomendação: **A**, com teste manual. Se não disparar, cair para "polling lento + hooks" sem gatilho de abertura e registrar como não verificado. Não puxar B nem C só por isso.

### 5.3 Throttle (evita rajada de `claude agents`)

A `DirectoryWatcher` dispara em toda gravação/remoção, inclusive as remoções que o próprio `readAll` faz. O app passaria a chamar `claude agents` na própria limpeza. Regra mínima no `SessionStore` (`@MainActor`, então sem lock):

```swift
private var probing = false, pending = false, lastProbe = Date.distantPast

func refreshAgents(force: Bool = false) {
    guard !probing else { pending = true; return }
    guard force || Date().timeIntervalSince(lastProbe) >= 2 else { pending = true; scheduleTrailing(); return }
    probing = true; lastProbe = Date()
    Task.detached(priority: .utility) {
        let probed = AgentsProbe.probe()
        await MainActor.run {
            if let probed { self.agents = probed.filter { $0.sessionId != nil } }
            self.probing = false; self.merge()
            if self.pending { self.pending = false; self.refreshAgents() }
        }
    }
}
```
`force: true` vale para menu aberto e morte de processo. O debounce do hook fica em 2 s, número arbitrário. Medir.

---

## 6. Alternativas consideradas

| | Como | Prós | Contras | Veredito |
|---|---|---|---|---|
| **A (recomendada)** | Hooks + `.exit` por PID + `kill`/`proc_pidpath`/start time no merge + `claude agents` em menu/hook/60 s | Só interfaces documentadas (hooks, CLI `--json`, APIs Apple). ~10× menos CPU. Fantasma some em ms. | Precisa testar o gatilho de menu. | Fazer. |
| B | Só subir o timer para 30–60 s, sem `.exit` | 1 linha | Fantasma do cache do CLI dura até 60 s, o risco que o backlog cita. | Insuficiente sozinho. |
| C | Ler `~/.claude/sessions/*.json` em vez de chamar o CLI (com `DispatchSource` no diretório) | Custo ~0, traz `procStart`, evento instantâneo de sessão nova | **Formato interno não documentado.** Pode mudar sem aviso em qualquer versão. Contraria o risco "dependência de interface não documentada". | Não agora. Talvez como otimização opt-in depois, com fallback para o CLI. |
| D | Statusline como heartbeat | Sinal periódico por sessão | Rouba o `statusLine` do usuário e não roda fora da TUI | Não. |
| E | TTL por `updatedAt` (ex.: some se > N h sem evento) | Simples | Esconde sessão ociosa real (o usuário deixa a sessão aberta o dia todo) | Não. Só como desempate para `pid 0` se o CLI sumir de vez. |

---

## 7. Armadilhas

- **Swift 6 / MainActor.** O callback do `Timer` e o handler do `DispatchSource` não são isolados ao MainActor. O padrão atual (`Task { @MainActor in self?.… }`) é o certo, e o VibeBar faz igual. `ProcessProbe` é `Sendable` com closures `@Sendable`, e o `startTime` novo precisa seguir isso. O `Task.detached` captura `self` (`@MainActor` → Sendable implícito): ok, já compila hoje.
- **Fontes `DispatchSource` precisam ser retidas e canceladas.** Guardar em `[Int32: DispatchSourceProcess]` no store, cancelar quando o PID sai da lista e no `deinit`. Fonte não retida morre na hora. [SUPOSIÇÃO] Pela doc o `makeProcessSource` nasce inativo, então é preciso `activate()`/`resume()`. A doc da Apple cita `activate()` e o VibeBar usa `resume()`.
- **Runloop e menu `.menu`.** O MenuBarExtraAccess diz que o menu bloqueia o runloop enquanto está aberto. [SUPOSIÇÃO] `Timer.scheduledTimer` (modo `.default`) não dispara com o menu aberto, o que aqui é desejável. Já `DispatchQueue.main`/MainActor costuma ser drenado também em event tracking, mas isso não está em doc oficial. Também não se sabe se o conteúdo SwiftUI do menu aberto se atualiza quando o `refresh` disparado na abertura volta ~150 ms depois. Testar à mão.
- **`/clear` e `/resume`** trocam o `session_id` no mesmo PID ([CONFIRMADO], doc do `SessionEnd`). Se o `SessionEnd` falhar, o arquivo antigo fica com PID vivo e caminho `claude`. Nenhuma regra de PID pega isso. Só o CLI pega: linha hook-only cujo PID aparece no CLI com **outro** `sessionId` ⇒ esconder. Isso vale entrar no `SessionMerge`. É um caso a mais de teste.
- **`EPERM`.** Hoje conta como vivo. Sessões do Claude são do mesmo usuário, então `EPERM` significa outro usuário, ou seja, PID reciclado. Pelo critério conservador vale manter só se `proc_pidpath` não responder. [SUPOSIÇÃO] `proc_pidpath` em processo de outro usuário pode falhar sem root.
- **LSUIElement / `.accessory`.** O app é accessory (`setActivationPolicy(.accessory)`). Nada em F06/F08 depende de foco. O `NSMenu` tracking não exige app ativo. [SUPOSIÇÃO]
- **Assinatura ad-hoc / sandbox.** O app não é sandboxed. `kill(pid,0)`, `proc_pidpath`, `proc_pidinfo` e `makeProcessSource` em processos do mesmo usuário não pedem entitlement. [SUPOSIÇÃO, não encontrei doc oficial que liste isso. Hoje o `proc_pidpath` já funciona no build ad-hoc.] Se um dia entrar App Sandbox, essas chamadas e o `Process` para `claude` quebram.
- **SwiftPM.** `libproc` vem via `import Darwin`, sem `linkerSettings` extra, porque o `proc_pidpath` já compila assim. Testes do target executável usam `@testable import ClaudeBar`, que já funciona no repo.
- **Guard rails (`00-PLANO.md`).** Nada aqui usa rede ou shell com interpolação (`Shell` já passa argumentos separados). O diretório continua `0700`/`0600`, e nenhuma conversa é lida (só metadados de processo).

---

## 8. Recomendação resumida

1. F06 primeiro: regra da §3.1 no merge/readAll com `ProcessProbe` estendido (`startTime`), `readAll(in:isAlive:)` testável, hook sem `unknown`, `pid 0` decidido pelo CLI, e os 10 testes da §3.3.
2. F08 em seguida: `.exit` por PID, throttle, `refreshAgents` no evento de hook, menu via `NSMenu.didBeginTrackingNotification`, timer de 60 s com tolerância de 6 s, `SessionStart` no `install.sh`.
3. Medir antes/depois com `/usr/bin/time -l` no binário do app (10 min) e contador de spawns. Linha de base por chamada: ~0,15 s de CPU e 159 MB de pico.
