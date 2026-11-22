# Lente: viabilidade técnica macOS

Validador: viabilidade técnica. Base: código em `Sources/` (cerca de 1.350 linhas), `Package.swift` (SwiftPM, macOS 14, 3 targets e mais os testes), `scripts/build-app.sh` (bundle montado à mão, `codesign --sign -`) e `scripts/install.sh` (usa `jq` e **substitui** os hooks). Também foram lidos `01-pesquisa/*` e `02-painel/PAINEL.md`. Docs de hooks conferidas em https://code.claude.com/docs/en/hooks em 2026-11-15.

Esforço: **P** até 1 dia; **M** de 2 a 5 dias; **G** 1 semana ou mais, ou exige infraestrutura nova (extensão, servidor, conta paga).

## 0. Restrições que valem para tudo

1. **SwiftPM sem Xcode project.** Não gera app extension (`.appex`), não roda o extrator de metadados de App Intents e não monta bundle. Hoje o bundle é montado à mão em `build-app.sh`. Por isso WidgetKit, Control Center, Focus Filter e Atalhos/Siri (H1 a H5) ficam fora do alcance sem migrar para um projeto Xcode ou XcodeGen/Tuist.
2. **Assinatura ad-hoc.** Tem três consequências:
   - O `UNUserNotificationCenter` é negado, como já está documentado no README.
   - O Gatekeeper bloqueia o app baixado da internet. No macOS 15 e posteriores não existe mais o atalho de clique direito e abrir: o usuário precisa ir em Ajustes > Privacidade e Segurança > Abrir mesmo assim.
   - **As permissões de TCC (Automação e Acessibilidade) ficam presas ao cdhash.** Cada rebuild ou atualização gera um binário novo, e o macOS volta a pedir a permissão ou nega em silêncio. Isso pesa diretamente sobre B1 e E3.
3. **Sem sandbox.** O app roda processos (`claude agents --json`, `claude stop`) e lê `~/.claude`, então App Sandbox está fora de cogitação. Daí: não há "entitlement de rede" a provar (ideia nova N16). A garantia de rede zero vem de não linkar nada de rede e pode ser auditada com Little Snitch e `nettop`.
4. **Hooks são a base.** Tudo que vem de hook (estado, tipo de notificação, ferramenta, erro) é barato: um campo a mais no JSON ou um argumento a mais no `claudebar-hook`. Tudo que exige ler JSONL ou a rede custa caro e quebra a promessa de privacidade.
5. **A configuração de hooks atual tem um bug real.** O `install.sh` registra `Notification` **sem matcher**. Pela doc, o Notification dispara para `idle_prompt` (cerca de 60 s ocioso), `auth_success`, `agent_completed`, `quota_auto_resume_*` e outros. Em todos esses casos o hook grava `waiting`, então aparece **"esperando você" falso**. É o "contador mente" que o painel aponta como motivo nº 1 de desinstalação. A correção é registrar o Notification com matchers (`permission_prompt` → `waiting --kind permission`; `elicitation_dialog|agent_needs_input` → `waiting --kind question`; os outros não são registrados). Isso também entrega a ideia nova "distinguir permissão de pergunta" quase de graça. **Não confirmei** que o payload traga `notification_type`, por isso o caminho seguro é passar o tipo por argumento, um matcher por entrada.
6. **Polling de `claude agents --json` a cada 5 s** (`SessionStore.startWatching`) sobe um processo Node a cada 5 s, 24 h por dia. Esse é hoje o maior custo de energia do app (A16), e não a animação.

## 1. Tabela de veredito

Nota = valor dividido pelo custo técnico (5 = faça já).

| ID | Nota | Veredito | Esforço | Permissões | Resumo técnico |
|---|---|---|---|---|---|
| A1 | 4 | fazer | P | — | `hdiutil create` no script, build universal (`--arch arm64 --arch x86_64`). Sem A2 o usuário ainda passa pelo "Abrir mesmo assim" |
| A2 | 5 | fazer (bloqueado: conta Apple) | M | — | Developer ID (US$ 99/ano), `codesign --options runtime --timestamp` no hook e no app, `notarytool submit --wait`, `stapler staple`. Destrava notificações nativas, TCC estável e Homebrew |
| A3 | 3 | depois | P | — | Tap próprio (`homebrew-tap`) com cask. O cask oficial `claudebar` **já existe** (tddworks), então o nome colide. Homebrew está apertando o cerco a casks sem notarização: só depois de A2 |
| A4 | 5 | fazer | M | — | Portar o `jq` para Swift no app: `JSONSerialization`, **acrescentar** em vez de substituir, backup, mostrar o diff antes de aplicar e confirmar. Remove a dependência de `jq` |
| A5 | 5 | fazer | P | — | Remove só as entradas cujo `command` contém `claudebar-hook`. Sai junto com A4 |
| A6 | 4 | fazer | P | — | Na abertura, comparar o caminho registrado com `Bundle.main`. Melhor ainda: copiar o hook para um caminho estável (`~/.claude/claudebar/bin/claudebar-hook`) e registrar esse caminho, que não quebra quando o app muda de lugar |
| A7 | 5 | fazer | P | — | `.icns` pronto em `planning/07-design/final`. Copiar para Resources e adicionar `CFBundleIconFile`; ícone de barra como template image |
| A8 | 5 | fazer | P | — | `SMAppService.mainApp.register()` (macOS 13+). Toggle no menu ou em Ajustes. Sem permissão extra |
| A9 | 4 | fazer | M | — | Cena `Settings` do SwiftUI e `SettingsLink`/`openSettings` (14+). App `.accessory` precisa de `NSApp.activate` para a janela vir à frente. Agrupa E2, A8, A13, status da conexão e a "página de transparência" |
| A10 | 2 | depois | P | — | No primeiro uso basta um `NSAlert` que chama A4 e o exemplo de popup que já existe. Tela própria é exagero |
| A11 | 4 | fazer | M | — | `Localizable.strings` em `en.lproj`/`pt-BR.lproj` copiados pelo `build-app.sh` para `Contents/Resources` (assim `Bundle.main` funciona; evitar `Bundle.module` em executável). `CFBundleDevelopmentRegion=en`, `CFBundleLocalizations`. Tirar o `Locale("pt_BR")` fixo de `MenuContent` |
| A12 | 2 | depois | G | rede | Sparkle via SPM exige embutir e assinar o `.framework` à mão, chave EdDSA, appcast e hospedagem. Contradiz o "sem rede" (teria de ser opt-in). Quem usa Homebrew já tem atualização. Reavaliar depois de A2/A3 |
| A13 | 4 | fazer | P | — | `NSApp.orderFrontStandardAboutPanel(options:)`, uma linha. Ler versão e licença do Info.plist |
| A14 | 3 | depois | P | — | `NSPasteboard` com versão, macOS, caminho do hook, hooks registrados e contagem de arquivos de estado. Mostrar prévia, sem caminhos de projeto. Fazer junto com A9 se sobrar tempo |
| A15 | 5 | fazer | P | — | `accessibilityLabel` no label do `MenuBarExtra` ("2 sessões, uma esperando você"). Linhas sem emoji, ou com rótulo por extenso. O HUD precisa de `accessibilityElement` e de anúncio (`NSAccessibility.post(.announcementRequested)`) |
| A16 | 4 | fazer | P | — | Medir antes. Trocar o polling fixo de 5 s por: consulta quando o menu abre e a cada hook, mais polling lento (30 a 60 s) só para pegar sessões fechadas sem hook |
| A17 | 3 | descartar (já atendido) | — | — | `Package.swift` e `LSMinimumSystemVersion` já são 14. Manter como restrição: nada de API só do 15 ou 26 sem `#available` |
| B1 | 5 | fazer (em camadas) | M→G | Automação por terminal | **Camada 1 (P, sem permissão):** subir a árvore de processos desde o `pid` do Claude (`proc_pidinfo`/`sysctl KERN_PROC`) até o app GUI e chamar `NSRunningApplication.activate()`. **Camada 2:** TTY do processo (`ps -o tty=`) → Terminal.app (`tty of tab`) e iTerm2 (`tty of session`) via AppleScript; tmux via `tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}'` + `select-window`/`select-pane` (CLI, sem permissão); Ghostty 1.3+ tem dicionário AppleScript (`select tab`, `focus`), mas não expõe PID nem TTY e o casamento por cwd é frágil. VS Code/Cursor: só a janela (`code -r <cwd>`); aba exata exigiria extensão. Requer `NSAppleEventsUsageDescription` no Info.plist (sem ela o Tahoe nega em silêncio). Com ad-hoc, a permissão de Automação é pedida de novo a cada build |
| B2 | 5 | fazer | P (após B1) | idem B1 | O HUD já é clicável (`onTap` → `dismiss`). Passar o `sessionId` e chamar B1. Notificação nativa (pós-A2): `userInfo` + delegate |
| B3 | 4 | fazer | P | — | `NSWorkspace.shared.open(URL(fileURLWithPath: cwd))`, ou `open -a <editor>`. Também serve de fallback de B1 |
| B4 | 4 | fazer | P | — | Copiar `cd '<cwd>' && claude --resume <sessionId>` para o pasteboard, com quoting correto. Só para sessão interativa |
| B5 | 2 | depois | M | Automação (Terminal) | Sessão encerrada some (o `SessionEnd` apaga o arquivo), então exigiria guardar histórico. Abrir sem permissão é possível via arquivo `.command` + `open`. B4 entrega 80% disso |
| B6 | 2 | depois | G | — | Viável: o hook `PermissionRequest` recebe `tool_name`/`tool_input` e devolve `hookSpecificOutput.decision.behavior` (allow/deny), com timeout padrão de 600 s. Exige IPC bloqueante entre hook e app e cuidado com corrida contra a resposta no terminal. Alto risco de segurança e UX; o painel tirou do MVP |
| B7 | 1 | descartar | G | — | Existe o hook `Elicitation` (devolve `accept`/`content`), mas gerar formulário dinâmico a partir do schema MCP num popup é G e raro |
| B8 | 1 | descartar | M | — | Daria para fazer com `Stop` + `decision:"block"` + `reason`, mas é um abuso do hook: o app passaria a injetar prompt. Rejeitado pelo painel |
| B9 | 3 | depois | P/M | — | `RegisterEventHotKey` (Carbon) dispensa Acessibilidade. Não dá para abrir programaticamente o menu do `MenuBarExtra(.menu)`, então a tecla deveria fazer "ir à próxima sessão esperando" (B1). Depende de B1 |
| B10 | 2 | descartar (já existe) | — | — | `.menuBarExtraStyle(.menu)` é um `NSMenu` nativo: setas e Enter já funcionam com o menu aberto |
| C1 | 1 | descartar | M | — | Timer trocando o `Image` do label a cada frame acorda a CPU e contradiz A16. O painel rejeitou |
| C2 | 1 | descartar | P | — | Pouco valor |
| C3 | 3 | depois | P | — | Já existe "há X min". A duração da última resposta sai de guardar `startedAt` em `working` e calcular no `idle` |
| C4 | 2 | depois | P/M | — | Hook `PreToolUse` gravando `tool_name`. Isso dispara um processo por chamada de ferramenta (latência e muitas escritas) e põe conteúdo sensível em disco. Só o nome da ferramenta, se vier |
| C5 | 4 | fazer | P | — | Hook `StopFailure` existe (matchers `rate_limit`, `overloaded`, `authentication_failed`…). Novo estado `error`, ou `idle` + flag. Hoje um erro parece "terminou bem" |
| C6 | 4 | fazer | P | — | `AgentSession.name` **já é decodificado** e não é exibido. Para a branch, ler `.git/HEAD` (ou `gitdir:` em worktree) direto, sem processo |
| C7 | 3 | depois | M | — | Só pelo bridge de statusline (`model`, `context_window.used_percentage`). Fazer junto com D1, que já cria o bridge |
| C8 | 1 | descartar | P | — | Hook `PreCompact`/`PostCompact`; valor baixo |
| C9 | 1 | descartar | P | — | `cost.total_cost_usd` no statusline é estimativa e todo mundo usa assinatura. O painel rejeitou |
| C10 | 3 | depois | P | — | Agrupar por repositório/worktree (C6 primeiro). `Section` no menu |
| C11 | 2 | depois | M | — | `SubagentStart`/`SubagentStop`, `TaskCreated`/`TaskCompleted` existem. Mais hooks, mais escrita |
| C12 | 1 | descartar | M | — | Linhas vêm do statusline, arquivos exigiriam `PostToolUse`. Isso é o papel do git |
| C13 | 1 | descartar | P | rede | Usa a rede e quebra a promessa |
| C14 | 1 | descartar | — | — | Não existe API pública para detectar overflow da barra; o macOS esconde o item sozinho |
| C15 | 2 | depois | — | — | Sessões do app desktop já aparecem via `claude agents` (`hostedByApp` em `SessionTerminator`). Falta só confirmar que os hooks disparam lá |
| D1 | 4 | fazer | M | — | Bridge de statusline: `claudebar-hook statusline` lê o stdin, grava `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` atomicamente em `~/.claude/claudebar/limits.json` e **encadeia** o `statusLine.command` anterior (repassa stdin e devolve stdout). O dado só aparece em planos Pro/Max e depois da 1ª resposta; mostrar "sem dado" com honestidade. Mexe em `settings.json` (usa A4) |
| D2 | 3 | depois | P | — | Limiar em `UserDefaults` e reuso de `Notifier`. Fazer logo depois de D1 |
| D3 | 3 | fazer (com D1) | P | — | Projeção linear: % usado ÷ fração da janela decorrida. Mostrar como faixa e só depois de X% da janela, para não errar feio |
| D4 | 1 | descartar | P | — | Ruído |
| D5 | 3 | depois | P | — | `StopFailure` com matcher `rate_limit` + `resets_at` do D1. Vem quase de graça depois de C5 e D1 |
| D6 | 1 | descartar | P | — | Nicho |
| E1 | 5 | fazer | P | — | Bug: em `Notifier.post`, `play(alert)` vem antes de `guard isEnabled`. Mover o guard (ou separar a opção de som em E2) |
| E2 | 4 | fazer | P | — | Opções em `UserDefaults` para terminou, esperando e som, e escolha do `NSSound(named:)`. Mora em A9 |
| E3 | 3 | depois | M | Automação | Nível app: `NSWorkspace.frontmostApplication` == app ancestral (B1 camada 1), sem permissão. Nível aba exige AppleScript. Fazer depois de B1, reusando o código |
| E4 | 2 | depois | P | — | Foco do sistema: `INFocusStatusCenter` exige entitlement e assinatura, e com A2 a notificação nativa já respeita Foco sozinha. Horário silencioso próprio é P, mas cabe depois |
| E5 | 4 | fazer | P | — | `Timer` por sessão em `waiting`, repete a cada N min, cancela na transição. Ver o detalhe no `SessionStore.notifyTransitions` |
| E6 | 2 | depois | M | — | Silenciar por sessão é P (um `Set` em memória); adiar no HUD exige botões no painel |
| E7 | 1 | descartar | M | — | Detectar "sem progresso" exige `PostToolUse` ou heurística e gera falso positivo |
| E8 | 2 | depois | P | — | Duração mínima (C3), sai junto com E2 |
| E9 | 2 | depois | P | — | Buffer em memória dos últimos N alertas no menu. Gravar em disco contradiz a retenção mínima |
| E10 | 1 | descartar | G | rede | Push exige servidor ou serviço de terceiros |
| E11 | 1 | descartar | G | rede | Idem, mais B6 |
| E12 | 1 | descartar | P | rede | Coberto por I5 (o usuário roda `curl` do jeito dele) |
| F1 | 3 | depois | M | — | O `TODO.md` já desenha o caminho (campo `agent` opcional, `--agent`). `AgentsProbe` e `SessionTerminator` continuam só para Claude. Depois de B1 |
| F2 | 1 | descartar | M | — | Copilot CLI sem modelo de hooks equivalente confirmado |
| F3 | 1 | descartar | G | — | Depende de B6 multiagente |
| F4 | 2 | depois | M | — | `CLAUDE_CONFIG_DIR`: os hooks teriam de ir para cada `settings.json` e o diretório de estado é fixo em `~/.claude`. Nicho |
| G1 | 1 | descartar | M | — | Falsa segurança; é papel do Claude Code |
| G2 | 1 | descartar | M | — | Escrever regras de permissão no `settings.json` do usuário é um risco alto para pouco valor |
| H1 | 1 | descartar | G | — | WidgetKit exige `.appex`, que SwiftPM não gera, além de App Group e assinatura |
| H2 | 1 | descartar | G | — | Depende de H1 |
| H3 | 2 | depois | G | — | App Intents exige o processamento de metadados do Xcode. H7 (CLI) atende automações via "Executar Script de Shell" |
| H4 | 1 | descartar | G | — | ControlWidget: extensão e macOS 26 |
| H5 | 1 | descartar | G | — | `SetFocusFilterIntent` é App Intents |
| H6 | 1 | descartar | G | — | Sem API pública para o notch; hack de janela |
| H7 | 4 | fazer | P | — | Subcomando `claudebar-hook status [--json]` / `next` que lê `StatusDirectory.readAll()` (já no Core). Não precisa do app aberto |
| H8 | 2 | depois | P | — | Hook `SessionStart` com `open -g -b com.joaomarcos.claudebar`. A8 cobre quase tudo; seria mais um hook no `settings.json` |
| I1 | 1 | descartar | G | — | Exige ler a conversa |
| I2 | 2 | depois | P | — | Contadores em memória a partir das transições |
| I3 | 1 | descartar | M | — | Lê JSONL (conversa) |
| I4 | 1 | descartar | M | — | Idem, mais preços |
| I5 | 3 | depois | P | — | Rodar um comando configurado via `Process` com argumentos e variáveis de ambiente (`CLAUDEBAR_STATE`, `CLAUDEBAR_CWD`), sem shell. Opt-in |

### Ideias novas do painel

| ID | Nota | Veredito | Esforço | Resumo técnico |
|---|---|---|---|---|
| N1 Página de transparência / diff dos hooks | 5 | fazer | P (com A4) | Parte de A4/A9: mostrar o JSON exato que será gravado, o caminho do backup e o botão Remover (A5) |
| N2 Distinguir permissão de pergunta | 5 | fazer | P | Matchers do `Notification` (ver §0.5). **Corrige o "esperando" falso do `idle_prompt`.** `SessionStatus` ganha um `kind` opcional (decode retrocompatível) |
| N3 Pergunta pendente em uma linha | 3 | depois | M | O `message` do Notification já é exibido. Mostrar "Bash: npm run migrate" exigiria o hook `PermissionRequest` gravando `tool_input` em disco (sensível). Só com N4 |
| N4 Modo "nunca mostrar conteúdo" | 3 | depois | P | Toggle que substitui `message` pelo nome do projeto. Obrigatório se N3 entrar |
| N5 Limpeza de sessões fantasmas | 5 | fazer | P | Já existe `kill(pid,0)`. Falta: (a) PID reciclado (comparar o início do processo, `proc_pidinfo` `pbi_start_tvsec`, com o `updatedAt`/primeiro registro, ou checar se ainda é `claude`, como o `ProcessProbe` já faz); (b) arquivos com `pid 0` ou `sessionId "unknown"`; (c) teste com `tmux kill-server` |
| N6 "Tudo ok" + testar alerta | 4 | fazer | P | O "Ver exemplo de popup" já existe. Somar a checagem de A6 (hooks registrados apontam para um binário executável) |
| N7 Legenda dos estados | 3 | depois | P | Sai com A15 |
| N8 Popup persistente para "esperando" | 4 | fazer | P | Em `StatusHUD.show`, não agendar `dismissTask` quando `alert == .waiting` (fecha no clique ou na transição). Posicionar longe do cursor |
| N9 tmux `sessão:janela.painel` | 3 | depois | P | Sai do B1 camada 2 |
| N11 Uso por sessão em % do limite | 1 | descartar | — | O statusline dá % da conta, não por sessão; não dá para medir sem JSONL |
| N13 Config exportável / MDM | 2 | depois | P | `defaults write` já funciona; documentar |
| N14 Não gravar caminho em disco | 1 | descartar | — | O app precisa do `cwd` vindo do hook (outro processo); os arquivos já são 0600 e apagados no fim |
| N15 Hash publicado | 3 | depois | P | `shasum -a 256` no release, junto com A1 |
| N16 Sem entitlement de rede | 1 | descartar | — | Sem sandbox não existe esse entitlement. Documentar "zero rede" e verificar com `nettop` |
| N17 README com GIF | 4 | fazer | P | Não é código |

## 2. Ordem recomendada (dependências técnicas)

1. **Confiança no estado:** N2 (matchers do Notification), N5 (fantasmas), E1, C5 (StopFailure), A16 (polling).
2. **Instalação dentro do app:** A6 (hook em caminho estável), A4 + N1 + A5, A7, A8, A13, A11, A15.
3. **Ir até a sessão:** B1 camada 1, B2, B3, B4, depois B1 camada 2 (tmux → iTerm2 → Terminal → Ghostty), N8, E5.
4. **Ajustes:** A9 juntando E2, A8, N6, A13.
5. **Limites:** D1 + D3 (bridge de statusline encadeado), depois D2/D5/C7.
6. **Distribuição:** A1 (DMG universal), A2 (bloqueado pela conta Apple Developer), A3 (tap próprio) e N17.
7. Extras baratos: H7, C6.

## 3. O que precisa do João

- **A2:** conta Apple Developer Program (US$ 99/ano) e certificado Developer ID Application. Sem isso não há notificação nativa, Gatekeeper limpo nem TCC estável para B1 camada 2.
- **A3:** nome do cask (colide com `claudebar` do tddworks) e repositório do tap.
- **A11:** decidir se o inglês vira o idioma padrão (`CFBundleDevelopmentRegion`).
- **Nome/bundle id:** `com.joaomarcos.claudebar` e o nome "ClaudeBar" colidem com um app existente e usam a marca "Claude". Vale decidir antes de publicar.

## 4. Riscos que o plano precisa registrar

- Permissões de TCC com assinatura ad-hoc se perdem a cada build. Testar a camada 2 de B1 só com o binário final, e avisar no README.
- O bridge de statusline (D1) entra no caminho crítico de render do Claude Code. Precisa ser rápido, nunca falhar e repassar o comando anterior com exatidão. A remoção (A5) tem de restaurar o `statusLine` original.
- `JSONSerialization` reordena as chaves do `settings.json`. O diff mostrado precisa ser semântico, ou é preciso aceitar a reformatação e avisar. O backup é obrigatório.
- O payload `notification_type` não foi confirmado; usar matchers por entrada.

Fontes: https://code.claude.com/docs/en/hooks, https://ghostty.org/docs/features/applescript, issue #113 de claude-notifications-go (Tahoe sem `NSAppleEventsUsageDescription`), `01-pesquisa/1b-limites-uso.md` (statusline `rate_limits`).
