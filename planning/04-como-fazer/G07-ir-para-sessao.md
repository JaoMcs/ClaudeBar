# G07 — Ir para a sessão (F09, F10, F14, F26)

> Pesquisa de "como fazer". Não é o plano final (isso é o 05-specs).
> Legenda: **[CONFIRMADO]** = fonte oficial (Apple, Claude Code, man do tmux) ou testado nesta máquina (macOS 26 / Darwin 25.5, Swift 6.3.3).
> **[SUPOSIÇÃO]** = inferência, prática de repositório de terceiros ou não testado.

## 0. Ponto de partida no código

- O hook já grava `pid` do Claude: `scripts/install.sh` registra `claudebar-hook <estado> --pid $PPID`. O hook roda via `sh -c`, então `$PPID` do `sh` é o processo `claude`. [CONFIRMADO: a doc de hooks diz que, sem `args`, o comando vai para `sh -c` no macOS; https://code.claude.com/docs/en/hooks]
- `SessionRow.pid` também vem do `claude agents --json` (`AgentsProbe`), então sessão sem hook ainda tem PID.
- `ProcessProbe` (struct `Sendable` com closures `@Sendable`, `.live`) já é o padrão para consultar processo de forma testável. **Reusar e estender** (`parentPID`, `ttyPath`) em vez de criar outro tipo.
- `Shell.output(of:arguments:)` já executa sem shell, com argumentos separados. É síncrono e bloqueia: chamar fora da main actor.
- `StatusHUD.show(_:body:)` não recebe sessão; o `onTapGesture` só chama `dismiss`. F10 precisa passar a sessão (ou um closure de ação) para o HUD.
- `Notifier.post` toca o som sempre; F14 entra aqui (ou no `SessionStore.notifyTransitions`, que conhece a sessão).
- `claudebar-hook/main.swift` lê **todo o stdin antes** de olhar o comando. Para `status`/`next` isso é um bug esperando para acontecer (ver §5).

## 1. F09 camada 1: subir a árvore até o app GUI

### Como

1. A partir do `pid` do `claude`, pegar o pai repetidamente até achar um `NSRunningApplication(processIdentifier:)` com `activationPolicy == .regular`.
2. Ativar esse app.

### API de PPID: use `sysctl(KERN_PROC_PID)`, **não** `proc_pidinfo`

- **[CONFIRMADO, testado aqui]** `proc_pidinfo(pid, PROC_PIDTBSDINFO, …)` **falha para processo de root** (testei com `logd`, pid 332: retorno ≠ tamanho do struct). `sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, pid])` → `kinfo_proc.kp_eproc.e_ppid` funciona para o mesmo processo.
- Isso importa: Terminal.app (e, pelo que se sabe, Ghostty) iniciam o shell via `/usr/bin/login`, que é setuid root. Com `proc_pidinfo` a subida pararia no `login`. [SUPOSIÇÃO sobre login em cada terminal; o teste do root é CONFIRMADO]
- Campos existem no SDK: `kinfo_proc.kp_eproc.e_ppid`, `kp_eproc.e_tdev` (`sys/sysctl.h`); `proc_bsdinfo.pbi_ppid` (`sys/proc_info.h`). [CONFIRMADO no SDK]
- PID inexistente: `sysctl` devolve 0 com `size == 0`. Checar `size > 0`. [CONFIRMADO, testado]

### `NSRunningApplication(processIdentifier:)`

- "Returns the running application with the given process identifier, or nil if no application has that pid." [CONFIRMADO: https://developer.apple.com/documentation/appkit/nsrunningapplication/init(processidentifier:)]
- `NSRunningApplication` é `NS_SWIFT_SENDABLE` no SDK e "thread safe, in that its properties are returned atomically" (as propriedades mudam a cada volta do run loop principal). [CONFIRMADO: header `NSRunningApplication.h` + https://developer.apple.com/documentation/appkit/nsrunningapplication]
- Filtrar por `.regular`: apps auxiliares (helpers do Electron, `LSUIElement`) podem aparecer como `NSRunningApplication` com política `.accessory`/`.prohibited`. Continuar subindo até achar um `.regular`. [SUPOSIÇÃO para helpers do VS Code/Cursor; o filtro é barato e não atrapalha]

### Testado nesta máquina (Claude.app)

```
77570  …/Application Support/Claude/claude-code/<ver>/claude.app/Contents/MacOS/claude  -> NSRunningApplication nil
77569  /Applications/Claude.app/Contents/Helpers/disclaimer                              -> nil
77165  /Applications/Claude.app/Contents/MacOS/Claude  -> com.anthropic.claudefordesktop, .regular
```

[CONFIRMADO] O binário do Claude Code dentro do Claude.app fica num `claude.app` aninhado, mas **não** vira `NSRunningApplication` (foi lançado por exec, não pelo LaunchServices). A subida chega ao Claude.app corretamente.

### Código de referência (compila com `-swift-version 6`, testado)

```swift
import AppKit
import Darwin

/// PPID e TTY numa chamada. Funciona também para processo de root (login).
func kinfo(_ pid: pid_t) -> kinfo_proc? {
    var kp = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
    return kp
}

func guiAncestor(of pid: pid_t, parent: (pid_t) -> pid_t?) -> NSRunningApplication? {
    var current = pid
    for _ in 0..<64 where current > 1 {          // limite contra ciclo/árvore estranha
        if let app = NSRunningApplication(processIdentifier: current),
           app.activationPolicy == .regular { return app }
        guard let next = parent(current), next != current else { return nil }
        current = next
    }
    return nil
}
```

`parent` entra no `ProcessProbe` como `parentPID: @Sendable (Int32) -> Int32?`, para os testes descreverem árvores falsas (mesmo padrão de `isGroupLeader`).

### Ativar: macOS 14 mudou as regras

- `activateIgnoringOtherApps` está **deprecado no 14 e "will have no effect"**. [CONFIRMADO: header + https://developer.apple.com/documentation/appkit/nsapplication/activationoptions/activateignoringotherapps]
- `activate(from:options:)` (14+): "Returns true if the request is allowed by the system… doesn't guarantee app activation. For cooperative activation, the other application should call `yieldActivation(to:)`…". [CONFIRMADO: https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)]
- Artigo oficial: "Only the active app can influence the activation context… **NSWorkspace automatically handles this for you when opening URLs or applications.**" [CONFIRMADO: https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation]
- `NSRunningApplication` **não tem** `activate()` sem argumentos no header (só `activate(options:)` e `activate(from:options:)`); o exemplo do artigo usa `targetApp.activate()`. Usar `activate(options: [])`. [CONFIRMADO no header do SDK]
- Relatos de que `activate` de app de barra de menu falha no Sonoma: https://developer.apple.com/forums/thread/739524, https://developer.apple.com/forums/thread/836619. [SUPOSIÇÃO quanto ao nosso caso: o clique no menu/HUD é interação do usuário com o ClaudeBar, o que deve contar a favor; **não testável por agente**]
- `.activateAllWindows`: relato de que não funciona desde 10.15 (fórum 739524). [SUPOSIÇÃO; não usar]

Recomendação (mínimo com rede de segurança):

```swift
@MainActor
func bringToFront(_ app: NSRunningApplication) {
    if app.activate(options: []) { return }
    // NSWorkspace faz o "yield" cooperativo por nós (doc acima).
    guard let url = app.bundleURL else { return }
    let config = NSWorkspace.OpenConfiguration()   // activates == true por padrão
    NSWorkspace.shared.openApplication(at: url, configuration: config)
}
```

`OpenConfiguration.activates`: "default value… is true". [CONFIRMADO: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/activates]. Abrir um app já em execução ativa a instância existente (`createsNewApplicationInstance` é `false` por padrão). [SUPOSIÇÃO: comportamento conhecido do LaunchServices, não li a página]

Se nem assim: fallback honesto "trouxe a janela, não a aba" / "não achei o app; abrindo a pasta" (F11, `NSWorkspace.open(cwd)`).

### Sem TCC

Nada aqui pede permissão: `sysctl`, `NSRunningApplication`, `NSWorkspace.openApplication`, `Process` com `tmux`. Testei `sysctl`/`proc_pidinfo`/`NSRunningApplication` num binário `swiftc` sem assinatura. [CONFIRMADO para o que testei]. Apple Events (aba exata) é F30 e fica fora.

## 2. F09 tmux

### O problema

Dentro do tmux, o `claude` é filho do **servidor** tmux, cujo pai é `launchd` (pid 1). A subida de §1 termina sem app GUI. É preciso:
1. saber em qual pane o `claude` está;
2. achar o **cliente** tmux anexado àquela sessão (é ele que roda dentro do terminal);
3. trocar o cliente para o pane e subir a árvore **a partir do `client_pid`**.

[SUPOSIÇÃO: servidor tmux é daemon com pai launchd; é como o tmux funciona por padrão, não testei aqui porque o tmux não está instalado nesta máquina]

### Detectar tmux e achar o pane

Opção A — **TTY** (o que o backlog pede; sem mudar o formato do arquivo):
- TTY do `claude`: `kinfo_proc.kp_eproc.e_tdev` + `devname_r(dev, S_IFCHR, …)`. Testado: devolveu `/dev/ttys001` sob um pty; processo sem terminal tem `e_tdev == -1` (NODEV). [CONFIRMADO, testado]
- `devname` usa buffer estático → **use `devname_r`** (Swift 6 / chamadas fora da main). [CONFIRMADO: ambos declarados em `_stdlib.h` do SDK]
- `tmux list-panes -a -F '#{pane_tty}\t#{pane_id}'` e casar `pane_tty` com o TTY. Formatos `pane_tty` ("Pseudo terminal of pane"), `pane_id` ("#D"), `-a` = "all panes on the server". [CONFIRMADO: man do tmux, https://github.com/tmux/tmux/blob/master/tmux.1]
- Detecção barata de "está no tmux": durante a subida, algum ancestral tem executável de basename `tmux` (`proc_pidpath`, já existe em `ProcessProbe.executablePath`). Só então rodar o `tmux`. [SUPOSIÇÃO de design]

Opção B — **ambiente capturado pelo hook**: a doc diz que o hook "inherits the parent environment" (CONFIRMADO: https://code.claude.com/docs/en/hooks), logo `TMUX_PANE` e `TMUX` estão no ambiente do `claudebar-hook`. O man confirma: "The pane ID is passed to the child process of the pane in the `TMUX_PANE` environment variable". `TMUX` contém "some internal information" (formato **não documentado**; na prática `socket,pid,índice` — [SUPOSIÇÃO]).
- O agentoast faz exatamente isso: `tmux_pane: std::env::var("TMUX_PANE")`, `terminal_bundle_id: std::env::var("__CFBundleIdentifier")` — https://github.com/shuntaka9576/agentoast/blob/main/crates/agentoast-cli/src/hooks/mod.rs
- Vantagem: acerta o **socket** (`-L`/`TMUX_TMPDIR`), que a opção A não conhece. Custo: 2 campos opcionais em `SessionStatus` (o `Codable` sintetizado usa `decodeIfPresent` para `Optional`, então arquivos antigos continuam válidos).

**Recomendo A agora** (zero mudança de formato, serve também para sessões vistas só pelo `claude agents`). B vira melhoria se aparecer usuário com socket não padrão. Socket padrão: diretório `tmux-UID` sob `TMUX_TMPDIR` ou `/tmp`, nome `default`. [CONFIRMADO: man, opção `-L`]. App de barra de menu não herda `TMUX_TMPDIR` do shell → com `TMUX_TMPDIR` customizado, A falha (cair no fallback). [CONFIRMADO o mecanismo; impacto real SUPOSIÇÃO]

Observação: o agentoast chama o tmux com `.env_remove("TMPDIR")` (https://github.com/shuntaka9576/agentoast/blob/main/src-tauri/src/terminal.rs). Motivo não documentado. [SUPOSIÇÃO: proteção contra builds que derivam o socket de `TMPDIR`; vale replicar, custa uma linha em `Process.environment`]

### Trocar de pane e achar o terminal

```
tmux display-message -p -t %7 '#{session_name}'
tmux list-clients -t <sessão> -F '#{client_tty}\t#{client_pid}\t#{client_activity}'
tmux switch-client -c <client_tty> -t %7
```

- `list-clients -t target-session`: "list only clients connected to that session". Formatos `client_tty`, `client_pid`, `client_activity`, `client_session`. [CONFIRMADO: man]
- `switch-client -t`: "As a special case, -t may refer to a pane (a target that contains ':', '.' or '%'), to change session, window and pane." [CONFIRMADO no man do `master`; **versão mínima do tmux não confirmada**]. Rodando de fora do tmux não existe "cliente atual", por isso `-c <client_tty>`. [SUPOSIÇÃO coerente com o man]
- Alternativa usada em produção (agentoast, ccnotifs): `switch-client -t sessão` + `select-window -t sessão:janela.pane` + `select-pane -t …`. ccnotifs: https://github.com/polyphilz/ccnotifs (`notify.sh`). Usar como fallback se o `switch-client -t %N` falhar em tmux antigo.
- Vários clientes anexados: escolher o de maior `client_activity`. Nenhum cliente: "sessão tmux sem terminal anexado" (fallback honesto).
- Depois: `guiAncestor(of: client_pid)` + `bringToFront`.
- Binário: o app não tem o `PATH` do shell. Reusar a ideia de `AgentsProbe.candidatePaths`: `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, `/usr/bin/tmux` (mesma lista do agentoast `crates/agentoast-shared/src/tmux.rs` e do macos-notify-mcp `MacOSNotifyMCP/main.swift`). Sem fallback de `zsh -lc` aqui: se não achou, não há tmux.
- Tudo via `Shell.output` (sem shell, argumentos separados). Pane id e tty vêm do próprio tmux, mas continuam indo como argumento, nunca interpolados. [guard rail do PLANO]

## 3. Matriz de suporte por terminal

| Terminal | Cadeia esperada até o app | Camada 1 (app) | tmux | Status |
|---|---|---|---|---|
| Claude.app | `claude` (em `claude.app` aninhado) → `disclaimer` → `Claude` | sim; traz a janela, não a conversa | n/a | **CONFIRMADO** (testado) |
| Terminal.app | `claude` → shell → `login` (root) → `Terminal` | sim, exige `sysctl` por causa do `login` | sim | SUPOSIÇÃO (cadeia) |
| Ghostty | `claude` → shell → `login` → `ghostty` | sim | sim | SUPOSIÇÃO (instalado, não estava rodando; não abri para não mexer na tela) |
| iTerm2 | shell → `iTermServer-x.y` → ? | **incerto**: o `iTermServer` pode ter pai `launchd` (amostra do iTerm mostra "Parent Process: ?" em https://gitlab.com/gnachman/iterm2/-/issues/8975) | sim | SUPOSIÇÃO. Fallback: `__CFBundleIdentifier` (ver abaixo) |
| VS Code | shell/`claude` → `Code Helper` (pty host) → `Code` | sim, se os helpers forem pulados pelo filtro `.regular` | sim | SUPOSIÇÃO |
| Cursor | igual ao VS Code (Electron) | sim | sim | SUPOSIÇÃO |
| Warp | shell → processo servidor do Warp → `Warp` | provável | sim | SUPOSIÇÃO |

Plano B quando a subida chega no pid 1 sem app (iTerm2 com servidor, sessões antigas): o agentoast lê `__CFBundleIdentifier` no hook e ativa por bundle id. Essa variável é posta pelo LaunchServices no ambiente de apps lançados e herdada pelos filhos, mas **não é documentada pela Apple**. [SUPOSIÇÃO]. `TERM_PROGRAM` não serve para distinguir VS Code de Cursor (ambos `vscode`). [SUPOSIÇÃO]. Dentro do tmux as duas variáveis refletem o terminal que **iniciou o servidor**, não o atual.

Como validar à mão (não verificável por agente, já listado no BACKLOG): em cada terminal, `ps -o pid,ppid,user,comm -p <pid>` subindo até o app; anotar no README.

## 4. F10 e F14

**F10 (clique no popup):** `HUDView` ganha uma ação `onOpen` (ou o `StatusHUD.show` recebe `sessionId`/`pid`); o tap chama o mesmo `Navigator.go(to:)` do menu e depois `dismiss()`. O painel é `.nonactivatingPanel`, então clicar nele não ativa o ClaudeBar, o que é o que queremos (o foco vai direto para o terminal). [SUPOSIÇÃO de comportamento; não testável por agente]. Se um dia houver Developer ID e notificação nativa, o clique chega por `UNUserNotificationCenterDelegate` `userNotificationCenter(_:didReceive:withCompletionHandler:)` com o `sessionId` em `userInfo`. Hoje não é necessário (ad-hoc cai sempre no HUD).

**F14 (silenciar som se já está olhando):** em `notifyTransitions`, antes de `notifier.post`, calcular `guiAncestor(of: pid)` e comparar `bundleIdentifier`/`processIdentifier` com `NSWorkspace.shared.frontmostApplication` ("the app that receives key events", KVO). [CONFIRMADO: https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication]. Como `NotificationState`/`post` já existem, o jeito mínimo é um parâmetro `playSound: Bool` em `post`. Limites conhecidos (aceitos pelo backlog, nível app): Claude.app na frente mas em outra conversa → silencia errado; sessão em tmux sem cliente → não silencia. A subida custa poucos `sysctl` (microssegundos); pode rodar na main actor sem cache. `frontmostApplication` só se atualiza com o run loop principal girando (ver doc de `NSRunningApplication`), o que é o caso no app. [CONFIRMADO o mecanismo]

## 5. F26 CLI `status [--json]` e `next`

- **Armadilha (confirmada lendo o código):** `run()` faz `FileHandle.standardInput.readDataToEndOfFile()` antes de tudo. Rodando `claudebar-hook status` num terminal, o stdin é o tty e o comando **trava esperando EOF**. Despachar `status`/`next` **antes** de ler o stdin.
- `status`: `StatusDirectory.readAll()` já filtra mortos e ordena. Atenção: `readAll` **apaga** arquivos inválidos/mortos. Para um comando "só leitura" é limpeza inofensiva, mas vale documentar. `--json`: reusar `StatusDirectory.encoder` (datas em segundos, chaves ordenadas) → saída estável para scripts/tmux status bar.
- `next`: escolher a sessão `.waiting` mais antiga (`updatedAt` menor) e chamar a mesma navegação de F09. Isso puxa `AppKit` para o `claudebar-hook`. Medi o custo de lançar um binário com `import AppKit` + `NSRunningApplication.current`: ~1 ms a mais por execução (10 execuções: 0,05 s vs 0,06 s). [CONFIRMADO, medido] Logo, não precisa de binário separado.
- Para reusar o código, a navegação precisa sair do target `ClaudeBar` (executável) para `ClaudeBarCore` (ou um target pequeno compartilhado). Executável não pode ser dependência de outro executável no SwiftPM. [SUPOSIÇÃO forte; é a regra do SwiftPM para `executableTarget`]. `ClaudeBarCore` hoje só usa Foundation; colocar ali a parte Darwin (`parentPID`, `ttyPath`, tmux) e deixar o `bringToFront` (AppKit) duplicado em 5 linhas, ou importar AppKit no Core. Decisão do spec.
- Ativação a partir da CLI: o processo da CLI **não é o app ativo** (o terminal é), então `activate(options:)` pode ser recusado pela ativação cooperativa. `NSWorkspace.openApplication` é o caminho que a Apple diz que faz o yield sozinho. Na CLI, o completion handler é assíncrono: segurar o processo (semáforo ou `RunLoop.main.run(until:)`) até ele voltar, senão o processo sai antes. [CONFIRMADO o mecanismo da doc; funcionamento real a partir de CLI **não testado** — testar ativaria apps na tela do usuário]
- Se a sessão `next` está no mesmo tmux do terminal atual, o `switch-client` já basta.

## 6. Armadilhas (Swift 6, MainActor, LSUIElement, ad-hoc, SwiftPM)

- **Swift 6 strict concurrency:** `NSRunningApplication` é `NS_SWIFT_SENDABLE` (ok passar entre tasks). `NSWorkspace.openApplication` tem completion `@Sendable`. `Shell.output` é síncrono → rodar o tmux em `Task.detached` e voltar para `@MainActor` só para ativar. `bringToFront` marcado `@MainActor`.
- **`devname`** devolve buffer estático: usar `devname_r`. A sobrecarga `String(cString: [CChar])` está deprecada no Swift 6.3 (warning); usar o ponteiro devolvido pelo `devname_r`. [CONFIRMADO compilando]
- **`proc_pidinfo` x root:** ver §1. [CONFIRMADO]
- **PID reciclado:** o `pid` do arquivo pode ser de outro processo se o Claude morreu. `ProcessProbe.executablePath` já existe para checar que ainda é um `claude` antes de navegar.
- **LSUIElement:** o ClaudeBar é `.accessory`; ele nunca é o `frontmostApplication` normal, então F14 não se confunde com ele próprio. Ativar outro app a partir de um app accessory é exatamente o caso dos relatos de falha no Sonoma → por isso o fallback `NSWorkspace`. [SUPOSIÇÃO quanto ao resultado]
- **Ad-hoc:** nada desta pesquisa depende de assinatura ou TCC. O que dependeria (Apple Events para aba exata) é F30.
- **Hook em "exec form":** se um dia o install passar a usar `args` (sem shell), `$PPID` não expande; o hook teria de usar `getppid()` (o pai direto do hook seria o `claude`). [CONFIRMADO que exec form não usa shell: doc de hooks]
- **Hook sem terminal:** "command hooks run in their own session without a controlling terminal" → o **hook** não consegue ler o próprio tty; o TTY tem de ser lido do `pid` do `claude` (pelo app, via `e_tdev`). [CONFIRMADO: doc de hooks]
- **Payload do hook não traz pid/tty** (campos comuns: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, …). [CONFIRMADO: doc de hooks]. Nenhum campo novo foi inventado aqui.
- Statusline e settings não são necessários para F09/F10/F14/F26.

## 7. Alternativas consideradas

| Alternativa | Por que não agora |
|---|---|
| AppleScript/`osascript` para focar app ou aba (macos-notify-mcp faz `tell application "X" to activate`) | Apple Events → TCC de Automação, instável com ad-hoc. É F30. |
| `SetFrontProcessWithOptions` (Carbon, citado no fórum 739524) | Deprecado; `NSWorkspace` resolve. |
| `terminal-notifier -activate <bundle>` / `alerter` (claude-tmux-hop, ccnotifs) | Dependência externa; o HUD próprio já existe. |
| Varredura completa `sysctl(KERN_PROC_ALL)` (agentoast `process_tree.rs`) | Só precisamos subir de um pid; `KERN_PROC_PID` basta. |
| `__CFBundleIdentifier` gravado pelo hook | Bom plano B para iTerm2; não documentado pela Apple. Adicionar só se a subida falhar na verificação manual. |

## 8. Recomendação

1. `ProcessProbe` ganha `parentPID` e `ttyPath` (ambos via `sysctl KERN_PROC_PID`).
2. Um `enum SessionNavigator` (sem protocolo): `go(to pid:)` → se ancestral é `tmux`: TTY → `list-panes -a` → `display-message` → `list-clients -t` → `switch-client -c -t %N` → subir de `client_pid`; senão subir de `pid`. Ativar com `activate(options: [])` e cair para `NSWorkspace.openApplication`. Falhou: mensagem honesta + abrir pasta (F11).
3. F10: HUD chama o navigator. F14: `post(..., playSound: !isFront)`. F26: despachar `status`/`next` antes de ler stdin.
4. Testes: árvore falsa no `ProcessProbe` (claude → login → Terminal; claude → tmux server → 1), parsing das saídas do tmux como string. Foco real em cada terminal = verificação manual.

## Fontes

- Apple: https://developer.apple.com/documentation/appkit/nsrunningapplication , …/init(processidentifier:) , …/activate(from:options:) , …/activate(options:) , https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:) , https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation , https://developer.apple.com/documentation/appkit/nsapplication/activationoptions/activateignoringotherapps , https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication , https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/activates
- Fóruns Apple: https://developer.apple.com/forums/thread/739524 , https://developer.apple.com/forums/thread/836619
- Claude Code hooks: https://code.claude.com/docs/en/hooks
- tmux man: https://github.com/tmux/tmux/blob/master/tmux.1
- agentoast (Tauri/Rust, barra de menu, tmux + ativação): https://github.com/shuntaka9576/agentoast — `src-tauri/src/terminal.rs`, `crates/agentoast-cli/src/hooks/mod.rs`, `crates/agentoast-shared/src/tmux.rs`
- macos-notify-mcp (Swift, tmux `switch-client`, `osascript activate`): https://github.com/yuki-yano/macos-notify-mcp — `MacOSNotifyMCP/main.swift`
- ccnotifs (shell, `switch-client` + `select-window` + `select-pane`): https://github.com/polyphilz/ccnotifs
- claude-tmux-hop: https://pypi.org/project/claude-tmux-hop/
- iTerm2 issue com iTermServer: https://gitlab.com/gnachman/iterm2/-/issues/8975
- SDK local: `AppKit.framework/Headers/NSRunningApplication.h`, `NSApplication.h`, `usr/include/sys/sysctl.h`, `sys/proc_info.h`, `_stdlib.h`
