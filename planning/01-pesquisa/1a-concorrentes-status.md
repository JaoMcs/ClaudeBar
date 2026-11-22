# 1a. Concorrentes: apps de status de agentes na barra de menu do macOS

Pesquisa feita em 2026-11-15. Fontes: README, issues (abertas e fechadas), releases via GitHub API (`gh`), PyPI JSON API e páginas de produto. Quando algo não foi encontrado, está marcado como **não encontrado**. "⭐" = estrelas no GitHub na data da pesquisa.

Glossário rápido de eventos de hook do Claude Code citados: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `PermissionRequest`, `PermissionDenied`, `Stop`, `StopFailure`, `SubagentStart/Stop`, `PreCompact/PostCompact`, `Elicitation`, `TaskCreated/Completed` etc. ([docs de hooks](https://code.claude.com/docs/en/hooks)).

---

## 1. Claude Status Bar (m1ckc3s/claude-status-bar)

- **Fonte principal:** https://github.com/m1ckc3s/claude-status-bar (⭐ 731, MIT, Swift, último release v0.4.5 em 2026-09-18)
- **Funcionalidades** ([README](https://github.com/m1ckc3s/claude-status-bar)):
  - Ícone animado enquanto o Claude pensa ou roda ferramenta, com cronômetro do turno (`1m 1s`).
  - Rótulo curto da ferramenta em uso (`Editing`, `Reading`, `Running command`…), que pode ser desligado (modo só ícone).
  - Ponto amarelo de "aguardando permissão" (CLI e Desktop app, aba Code).
  - 4 estilos de animação (Spark, Unicode, Clawd crab em pixel-art, Orbit); cor Laranja ou Sistema (monocromático adaptativo).
  - Multi-sessão: o ícone mostra a sessão de maior prioridade (permissão nunca fica escondida atrás de "pensando"); dropdown lista todas as sessões ([#8](https://github.com/m1ckc3s/claude-status-bar/issues/8)).
  - Foco no terminal ao clicar; foco exato na aba/janela é opt-in e precisa da permissão "Automation" ([#19](https://github.com/m1ckc3s/claude-status-bar/issues/19), [#22](https://github.com/m1ckc3s/claude-status-bar/issues/22)).
  - Som de conclusão: foi removido e depois devolvido a pedido dos usuários ([#42](https://github.com/m1ckc3s/claude-status-bar/issues/42)).
  - Auto-lançamento: abre sozinho quando uma sessão começa e fecha quando nenhuma está ativa ([README](https://github.com/m1ckc3s/claude-status-bar)).
  - Aviso de atualização no menu, com botão "copiar comando brew" ou "Switch to Homebrew" ([README](https://github.com/m1ckc3s/claude-status-bar)).
  - Rastreia CLI, Desktop (aba Code) e a extensão do Claude Code no Cursor; não rastreia Chat/Cowork ([README](https://github.com/m1ckc3s/claude-status-bar)).
- **Detecção de estado:** hooks de comando em Node.js. Os eventos em [`hooks/hooks.json`](https://github.com/m1ckc3s/claude-status-bar/blob/main/hooks/hooks.json) são `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `PermissionRequest` e `Stop`. O app "polls those updates" (consulta periódica de arquivos de estado `state.d/`, citado em [#44](https://github.com/m1ckc3s/claude-status-bar/issues/44)). Também lê um marcador no transcript JSONL para se recuperar de uma interrupção com Esc ([#22](https://github.com/m1ckc3s/claude-status-bar/issues/22)).
- **Instalação:** `brew install --cask claude-status-bar` (cask **oficial** do Homebrew, macOS ≥ 12, [formulae.brew.sh](https://formulae.brew.sh/api/cask/claude-status-bar.json)) ou DMG. No primeiro lançamento ele **faz o merge automático dos hooks** em `~/.claude/settings.json`, com backup. A desinstalação remove só os próprios hooks, e `brew uninstall --zap` limpa tudo ([README](https://github.com/m1ckc3s/claude-status-bar)). Requer Node.js.
- **Distribuição/assinatura:** DMG **assinado e notarizado pela Apple** ([README](https://github.com/m1ckc3s/claude-status-bar)).
- **Preço:** grátis ("I'm not monetizing it") ([README](https://github.com/m1ckc3s/claude-status-bar)).
- **Idioma:** só inglês (nenhuma localização mencionada; não encontrado).
- **Pontos fracos e pedidos em issues:**
  - CPU alta, 25–27% num M3 Max, por redesenhar a cada frame de animação mais IPC síncrono a cada 0,4 s. Corrigido na v0.4.4 ([#53](https://github.com/m1ckc3s/claude-status-bar/issues/53)).
  - O rótulo se sobrepõe a outros itens quando a barra está cheia; o pedido é recolher para só ícone ([#51](https://github.com/m1ckc3s/claude-status-bar/issues/51)).
  - Linhas de sessão mostram o nome da pasta (cwd), não o nome da sessão (`claude -n`) ([#47](https://github.com/m1ckc3s/claude-status-bar/issues/47)).
  - Suporte a múltiplas contas (`CLAUDE_CONFIG_DIR`): recusado como "power user" ([#41](https://github.com/m1ckc3s/claude-status-bar/issues/41)).
  - Opção de deixar de rastrear o Cursor ([#49](https://github.com/m1ckc3s/claude-status-bar/issues/49)).
  - Pedido de impedir o sono do Mac enquanto o Claude roda: recusado ([#35](https://github.com/m1ckc3s/claude-status-bar/issues/35), [#60](https://github.com/m1ckc3s/claude-status-bar/issues/60)).
  - Som em "aguardando permissão" ([#61](https://github.com/m1ckc3s/claude-status-bar/issues/61)) e som de conclusão só para turnos com mais de 5 s ([#52](https://github.com/m1ckc3s/claude-status-bar/issues/52)).
  - O app se fecha sozinho cerca de 8 s após a primeira instalação se já havia uma sessão aberta ([#44](https://github.com/m1ckc3s/claude-status-bar/issues/44)).
  - Upgrade de DMG após o rename da 0.4.0 deixava uma cópia antiga ativa ([#45](https://github.com/m1ckc3s/claude-status-bar/issues/45)).
  - Ícone fica preso em "thinking" ao interromper na fase de raciocínio, pois não há hook nem escrita no transcript; o teto é de 15 min ([#22](https://github.com/m1ckc3s/claude-status-bar/issues/22)).
  - Desktop app: deep-link `claude://resume` duplica a sessão ([#22](https://github.com/m1ckc3s/claude-status-bar/issues/22), [#58](https://github.com/m1ckc3s/claude-status-bar/issues/58)).

## 2. Nudgy (Hamma111/nudgy)

- **Fonte:** https://github.com/Hamma111/nudgy (⭐ 12, MIT, Swift, v0.6.3 em 2026-09-03)
- **Funcionalidades** ([README](https://github.com/Hamma111/nudgy)):
  - Popups flutuantes com 5 presets visuais (Minimal, Pill, Glass, Card, Banner) e posição na tela configurável.
  - Rastreador de sessões no menu com pontos coloridos e botão "Go" para pular ao terminal.
  - Supressão inteligente contra fadiga de notificação.
  - Sons diferentes por tipo de evento e toggles por tipo de notificação.
  - Contagem de tokens por sessão (parse do JSONL).
  - Cota de uso opcional via API da Anthropic (desligada por padrão).
- **Detecção:** hooks do tipo **`http`**, que fazem POST para um servidor `NWListener` em `127.0.0.1:9847` com token por instalação guardado no Keychain. Eventos: `Stop`, `StopFailure`, `Notification`, `PermissionRequest`, `SessionStart`, `SessionEnd`. Também lê o transcript JSONL para os tokens ([README](https://github.com/Hamma111/nudgy)).
- **Instalação:** DMG; **instala os hooks automaticamente** no primeiro lançamento, renova o token a cada lançamento e remove os hooks ao sair ([README](https://github.com/Hamma111/nudgy)). macOS 14+.
- **Assinatura:** não encontrado (o release tem só `Nudgy-0.6.3.dmg`, [release](https://github.com/Hamma111/nudgy/releases/tag/v0.6.3)).
- **Preço:** grátis/MIT. **Idioma:** inglês (não encontrado outro).
- **Pontos fracos e issues:** popup não some sozinho e não tem botão de fechar ([#1](https://github.com/Hamma111/nudgy/issues/1)); botão de dispensar invisível em monitor externo ([#4](https://github.com/Hamma111/nudgy/issues/4)); a v0.6.3 corrigiu a leitura de campos reais do payload dos hooks ([release](https://github.com/Hamma111/nudgy/releases/tag/v0.6.3)), o que indica que antes os campos estavam errados.

## 3. AgentBar (jreed91/agentbar)

- **Fonte:** https://github.com/jreed91/agentbar (⭐ 0, MIT, Swift, v1.15.3 em 2026-10-02, releases automáticos via semantic-release)
- **Funcionalidades** ([README](https://github.com/jreed91/agentbar)):
  - Dashboard multi-agente com contagem `need you / working / idle` e grupos `NEEDS YOU / WORKING / IDLE`.
  - Cada linha mostra **modelo**, **modo de permissão** e **uso de contexto** (`ctx 48k · 24%`, ficando âmbar e depois vermelho).
  - Atividade atual (última ferramenta), cronômetro "working" e "waiting", e "finished in 2m 13s".
  - Trilha de atividade por sessão, log de atividade recente e filtro "só ao vivo".
  - Notificações com ações: Dismiss, **Snooze 10 min** e **Copy command**.
  - Mute por sessão, **Do Not Disturb** por faixa de horário, sons distintos por tipo de evento, auto-dismiss configurável e log de debug.
  - Teclado completo no popover (↑↓/jk, ↵, d, m, t) e atalho global "focus needs me".
  - Foco na janela exata via Accessibility (casando o cwd com o título da janela), com fallback para ativar o app.
  - Roster lido dos transcripts mesmo para sessões sem hook.
  - **Banda dentro do Claude Code** listando as *outras* sessões que esperam você, com ação "Jump".
  - Também acompanha o GitHub Copilot CLI.
  - Responder prompts pelo menu foi **removido** no plugin 1.4.0 para o plugin poder entrar no diretório oficial ([README](https://github.com/jreed91/agentbar), [#56](https://github.com/jreed91/agentbar/issues/56)).
- **Detecção:** um *Claude Code mod* (TypeScript) observa `UserPromptSubmit`, `AskUserQuestion`, `PermissionRequest`, `PermissionDenied`, `Elicitation`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `Stop`, `SubagentStop`, `SessionEnd` e `StopFailure`. Ele faz POST para um servidor HTTP local (`127.0.0.1`, porta efêmera, bearer token em `server.json`) e funciona em modo fail-open. Os transcripts `~/.claude/projects/**/*.jsonl` (respeitando `CLAUDE_CONFIG_DIR`) são lidos para o roster. Prompts respondidos são limpos sozinhos quando chega `PostToolUse`/`PermissionDenied`/`Stop` ([README](https://github.com/jreed91/agentbar)).
- **Instalação:** app via `brew tap jreed91/agentbar … && brew install --cask agentbar`; plugin via `/plugin marketplace add` + `/plugin install` (Claude Code ≥ 2.1.287). Para o Copilot, `make install-copilot`. Tem `make doctor` e `agentbar-hook --selftest` ([README](https://github.com/jreed91/agentbar)).
- **Assinatura:** o pipeline de release "builds, signs, notarizes" ([README](https://github.com/jreed91/agentbar)).
- **Preço:** grátis/MIT. **Idioma:** inglês.
- **Pontos fracos:** instalação em duas metades (app + plugin), com atualização manual do plugin em 3 comandos ([README](https://github.com/jreed91/agentbar)); no Desktop (aba Code) o mod não consegue abrir o app; não responde prompts; os screenshots são "renderizados do design, não do app real" ([README](https://github.com/jreed91/agentbar)). As issues são só ideias do próprio autor ([#56](https://github.com/jreed91/agentbar/issues/56), [#57](https://github.com/jreed91/agentbar/issues/57)).

## 4. Claude Code Notifier (TouchTap Ltd)

- **Fontes:** [Gumroad](https://touchtap.gumroad.com/l/claude-code-notifier), [site](https://ccnotifier-website.pages.dev/) (domínio oficial claudecodenotifier.com, citado pela App Store), [DEV post](https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji), [App Store companion](https://apps.apple.com/app/id6757701908)
- **Funcionalidades:**
  - App de menu que avisa quando o Claude espera input, com contagem de sessões esperando.
  - **Supressão quando o terminal está em primeiro plano** (15+ terminais suportados).
  - Lembretes configuráveis, **quiet hours** e analytics de sessão (tempo de resposta, duração, estatísticas diárias) ([DEV](https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji)).
  - **Webhooks para Slack, Discord e endpoints próprios** ([DEV](https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji)).
  - Companion iOS/Android que **aprova ou nega permissões, responde perguntas e manda a próxima instrução** pelo celular. O Claude espera a resposta do celular até um limite e para de esperar quando você volta ao teclado ([site](https://ccnotifier-website.pages.dev/)).
  - Histórico de notificações e vários computadores pareados ([App Store](https://apps.apple.com/app/id6757701908)).
- **Detecção:** hooks instalados automaticamente em `~/.claude/settings.json` (um one-liner Python) que enviam o payload, enriquecido com contexto do terminal, para um **socket Unix** `/tmp/ccn-{uid}.sock` ([DEV](https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji)). A versão nova, `ccn`, é um binário de hook que roda por alguns ms e sai ([site](https://ccnotifier-website.pages.dev/)). Quais eventos exatos: **não encontrado**.
- **Instalação:** Mac app pelo Gumroad, com botão "Install Hook" no menu ([Gumroad](https://touchtap.gumroad.com/l/claude-code-notifier)); CLI `ccn` via `curl … install.sh | sh`, Homebrew ou npx, e pareamento com `ccn pair CODE` ([site](https://ccnotifier-website.pages.dev/)). macOS 15+, binário universal ([Gumroad](https://touchtap.gumroad.com/l/claude-code-notifier)).
- **Assinatura:** não encontrado.
- **Preço:**
  - Mac/CLI: grátis (Gumroad "£0+").
  - Pro: **US$ 39,99/ano** ou **US$ 49,99 vitalício**.
  - Pelas lojas: US$ 6,99/mês ([site](https://ccnotifier-website.pages.dev/), [App Store](https://apps.apple.com/app/id6757701908)).
  - O site também chegou a falar em "compra única" para o Mac app, o que gera conflito de fontes ([busca](https://ccnotifier-website.pages.dev/)).
- **Idioma:** site e app em **17 idiomas, incluindo pt-BR** ([site](https://ccnotifier-website.pages.dev/), [App Store](https://apps.apple.com/app/id6757701908)).
- **Pontos fracos:** fechado (não é open source); o relay passa pelo servidor deles, com exclusão em 48 h; uma review reclama que o app é inútil sem um Mac ([App Store](https://apps.apple.com/app/id6757701908)); o modelo de assinatura cobra pelas respostas no celular. Issues públicas: **não encontrado**.

## 5. Claude Status (gmr/claude-status, listado no tomevault)

- **Fontes:** https://github.com/gmr/claude-status (⭐ 65, BSD-3, v1.4.0 em 2026-07-29); listagem no [tomevault](https://tomevault.io/tome/gmr/claude-status), que retornou 503 no fetch (conteúdo confirmado via [busca](https://tomevault.io/tome/gmr/claude-status))
- **Funcionalidades** ([README](https://github.com/gmr/claude-status)):
  - Indicador agregado com estados ativo, esperando, **compactando** e ocioso, no estilo emoji ou ponto colorido.
  - **Foco em 1 clique na janela/aba/pane exata**: VS Code, Zed, Xcode, IDEs JetBrains, iTerm2 (AppleScript), Terminal, Warp, Alacritty, Kitty, WezTerm, Ghostty e **tmux** (seleciona a janela e o pane).
  - Analytics: tempo gasto em cada estado e concorrência de sessões ao longo do dia.
  - Slash command `/name-session` para nomear sessões.
  - **Widgets de desktop (WidgetKit)**, launch at login e app sem ícone no Dock.
  - Suporte a múltiplos perfis na v1.4.0 ([#23](https://github.com/gmr/claude-status/issues/23)).
- **Detecção:** um plugin Claude Code (em Rust) com hooks `SessionStart`, `SessionEnd`, `PermissionRequest`, `Notification` e `PreCompact` ([hooks.json](https://github.com/gmr/claude-status-plugin/blob/main/plugins/claude-status/hooks/hooks.json)). Ele escreve `~/.claude/projects/<proj>/<session>.cstatus` e envia uma **Darwin notification**. O app escuta por Darwin notification, com file watching de backup e polling de 5 s de fallback. Também valida se o processo está vivo e percorre a árvore de processos para classificar terminal, IDE ou tmux ([README](https://github.com/gmr/claude-status)). O plugin inclui um crate `jsonl-analyzer` para análise do transcript ([repo do plugin](https://github.com/gmr/claude-status-plugin)).
- **Instalação:** download do release e mover para /Applications. No primeiro lançamento ele **pede para instalar o plugin hook**, que também pode ser instalado ou removido em Settings ([README](https://github.com/gmr/claude-status)). Requer **macOS 26.2+**.
- **Assinatura:** não encontrado. **Preço:** grátis (BSD-3). **Idioma:** inglês.
- **Issues:**
  - Pedido de suporte a macOS 14/15, porque a exigência de 26.2 exclui usuários ([#20](https://github.com/gmr/claude-status/issues/20), aberta).
  - Pedido de **uso semanal** ([#19](https://github.com/gmr/claude-status/issues/19), aberta).
  - Widgets mostram conteúdo errado em background ([#21](https://github.com/gmr/claude-status/issues/21), aberta).
  - Sessões tmux no mesmo diretório acompanham sempre a primeira ([#10](https://github.com/gmr/claude-status/issues/10)).
  - O estado "idle" ignorava agentes em background ([#8](https://github.com/gmr/claude-status/issues/8), corrigido na 1.2.0).

## 6. Pulse (sayantan94/pulse)

- **Fonte:** https://github.com/sayantan94/pulse (⭐ 3, MIT, Swift, sem releases)
- **Funcionalidades** ([README](https://github.com/sayantan94/pulse)):
  - Ícone com estados por cor: cinza, trabalhando, pronto (azul), amarelo (permissão), laranja (arriscado/ocioso) e vermelho (bloqueado/travado).
  - Cards por sessão com modelo, modo de permissão, duração, último prompt, **progresso de tarefas**, **estatísticas de uso por ferramenta** e timeline dos últimos 20 eventos.
  - **Avisar ou bloquear comandos arriscados** com regex configurável (`rm -rf`, `git push`, `sudo`…), via UI ou em `~/.pulse/hooks/risky-patterns.json`.
  - Detecção de ociosidade/travamento: permissão parada há 60 s ou trabalho parado há 120 s viram laranja; 3+ falhas de ferramenta viram "stuck".
  - Nome de sessão via `CLAUDE_SESSION_NAME`.
- **Detecção:** registra **os 26 eventos de hook**, todos com o mesmo script shell (`pulse-hook.sh`, com jq). O script escreve arquivos em `/tmp/pulse/`, e o app observa o diretório ([README](https://github.com/sayantan94/pulse)).
- **Instalação:** só a partir do código: `git clone && ./pulse setup && ./pulse start`. O setup compila e instala jq via brew; há também `./pulse doctor` e `./pulse remove` ([README](https://github.com/sayantan94/pulse)).
- **Assinatura:** não se aplica (build local). **Preço:** grátis. **Idioma:** inglês.
- **Pontos fracos:** exige Swift toolchain e jq; usa `/tmp`, que se perde no reboot; sessão identificada pelo diretório de trabalho; sem distribuição binária. Issues: **nenhuma**.

## 7. ClaudeDot (poorfish/ClaudeDot)

- **Fonte:** https://github.com/poorfish/ClaudeDot (⭐ 13, MIT segundo o README, v2.0.0 em 2026-04-10)
- **Funcionalidades** ([README](https://github.com/poorfish/ClaudeDot)):
  - Ponto colorido com 6 estados: desconectado, ocioso, **thinking**, **responding**, tool active e needs attention, cada um com animação própria.
  - Sons (chime para atenção, pop para conclusão).
  - Multi-sessão.
  - Clique esquerdo pula para o terminal; clique direito abre o painel.
  - Terminais suportados: Ghostty, iTerm2, Warp e Terminal.app.
  - **8 idiomas** automáticos (a lista não foi encontrada).
- **Detecção:** configura sozinho no primeiro lançamento um **`statusLine`** (consulta o estado a cada 3 s) e um hook **`Notification`** (permissão) ([README](https://github.com/poorfish/ClaudeDot)).
- **Instalação:** DMG **não assinado**; o README manda rodar `xattr -cr` ([README](https://github.com/poorfish/ClaudeDot)). macOS 13+.
- **Preço:** grátis. **Pontos fracos:** sem assinatura; sequestra o `statusLine` do usuário (possível conflito com um statusline próprio, inferido do mecanismo); sem atividade desde abril de 2026. Issues: **nenhuma**.

## 8. Clabar (Magir/clabar)

- **Fonte:** https://github.com/Magir/clabar (⭐ 4, BSD-2, v0.2.3 em 2026-10-13)
- **Funcionalidades** ([README](https://github.com/Magir/clabar)):
  - **Limites de uso**: janela de 5 h, semanal e por modelo, com gráfico de histórico de 1 h a 30 d e mini barras e porcentagens no ícone.
  - Notificações nativas de permissão, pergunta, **plano pronto**, conclusão e falha.
  - **Histórico de notificações** em janela própria, com filtros e busca.
  - **Busca full-text nas sessões** (`~/.claude/projects`) com morfologia em ru/en/es/pt/fr/de; o clique copia `claude --resume`.
  - Lembrete "**burn the limit**" (pouco uso perto do reset) e aviso "**running low**" (acima de 85%).
  - Hotkey global ⌘U e **status de saúde do status.claude.com**.
  - Setup de **DevContainer** em 1 clique.
- **Detecção:** hooks `Notification`, `Stop`, `PermissionRequest`, `PreToolUse` (para `AskUserQuestion` e `ExitPlanMode`) e `PostToolUseFailure`, todos `async`. O script `clabar-hook.sh` faz POST para `127.0.0.1:8737/event`. O uso vem da API da Anthropic, com login OAuth ([README](https://github.com/Magir/clabar)).
- **Instalação:** `curl … install.sh | sh`, que evita o atributo de quarentena, ou zip; os hooks são instalados automaticamente com backup, e `CLABAR_NO_AUTOINSTALL=1` desliga isso ([README](https://github.com/Magir/clabar)).
- **Assinatura:** **ad-hoc, não notarizado**; atualizações via **Sparkle** com assinatura EdDSA ([README](https://github.com/Magir/clabar)).
- **Preço:** grátis (botão Buy Me a Coffee). **Idioma:** **7 idiomas, incluindo Português**, com override manual ([README](https://github.com/Magir/clabar)).
- **Pontos fracos:** não mostra estado "trabalhando" ao vivo (os hooks são só de eventos de atenção); exige login OAuth para os limites; sem notarização. Issues: **nenhuma**.

## 9. AgentPulse (fanook/agentpulse)

- **Fonte:** https://github.com/fanook/agentpulse (⭐ 0, MIT, v0.1.2 em 2026-04-14)
- **Funcionalidades** ([README](https://github.com/fanook/agentpulse)):
  - "Cápsula" que desce do ícone "AP" com todas as sessões; clicar numa linha pula ao terminal/IDE.
  - Badge com contagem de sessões esperando.
  - **Abre a cápsula automaticamente por 5 s** quando há permissão pendente.
  - Launch at login.
  - Arquitetura de adaptadores para outros agentes ([developing.md](https://github.com/fanook/agentpulse/blob/main/docs/developing.md)).
- **Detecção:** hooks `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification` e `Stop` ([install.sh](https://github.com/fanook/agentpulse/blob/main/hooks/claude/install.sh)). O script `report.sh` faz POST com token para `127.0.0.1:9876` (com fallback entre 9876 e 9895; a porta fica em `~/.pulse/port`) ([developing.md](https://github.com/fanook/agentpulse/blob/main/docs/developing.md)).
- **Instalação:** DMG **não assinado** (clique direito → Abrir), seguido de "Connect" em Settings; ou script `curl | bash` que compila do código e já liga os hooks ([README](https://github.com/fanook/agentpulse)).
- **Preço:** grátis. **Idioma:** inglês. **Pontos fracos:** sem assinatura, projeto parado desde abril; conflita com o Pulse no diretório `~/.pulse/`. Issues: **nenhuma**.

## 10. VibeBar (yelog/vibebar)

- **Fonte:** https://github.com/yelog/vibebar (⭐ 30, MIT, v1.3.7 estável e v1.3.8-beta)
- **Funcionalidades** ([README](https://github.com/yelog/vibebar)):
  - **Multi-agente**: Claude Code, Codex, OpenCode, Aider, Gemini CLI, Copilot e Pi.
  - **Modo notch** em MacBooks.
  - Estados `running/awaiting_input/idle/stopped/unknown`.
  - **Resposta inline** a permissões, perguntas e planos (no Codex, pelo menu ou notch).
  - **Uso de tokens e custo em USD** com heatmap estilo GitHub, gráficos de barra e linha, agrupados por ferramenta ou modelo.
  - Gestão de plugins pelo próprio app, vários estilos de ícone e temas, launch at login e verificação de update.
  - Agrupamento por projeto, último prompt do usuário, suporte a tmux/zellij/WezTerm por pane ([release v1.3.7](https://github.com/yelog/vibebar/releases/tag/v1.3.7)).
- **Detecção:** 4 canais:
  1. Wrapper PTY `vibebar`.
  2. Plugin, com eventos enviados por **socket Unix** (`vibebar-agent`). No Claude os hooks são `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `PermissionRequest`, `Elicitation`, `Stop` e `TaskCompleted` ([hooks.json](https://github.com/yelog/vibebar/blob/main/plugins/claude-vibebar-plugin/hooks/hooks.json)).
  3. Arquivos de sessão (JSONL).
  4. Fallback por `ps` ([README](https://github.com/yelog/vibebar)).
- **Instalação:** DMG universal (clique direito → Abrir, portanto não notarizado) ou `brew install --cask yelog/tap/vibebar` ([README](https://github.com/yelog/vibebar)).
- **Preço:** grátis. **Idioma:** **EN, 中文, 日本語, 한국어** (sem português).
- **Issues:**
  - Falso positivo no scan de `ps` com nomes truncados ([#4](https://github.com/yelog/vibebar/issues/4), aberta).
  - Pedido de nomes de sessão do Codex ([#3](https://github.com/yelog/vibebar/issues/3), aberta).
  - Pedido de **notificação ao entrar em estado ocioso** ([#1](https://github.com/yelog/vibebar/issues/1)).
  - Status do OpenCode sem plugin ([#2](https://github.com/yelog/vibebar/issues/2)).
  - O próprio README admite testes mínimos e heurísticas sem plugin.

## 11. OpenAgentPeek (zuoxu3310/openagentpeek)

- **Fonte:** https://github.com/zuoxu3310/openagentpeek (⭐ 1, MIT, v0.1.0 em 2026-05-24); clone aberto do comercial AgentPeek ([site AgentPeek](https://agentpeek-web.pages.dev/menu-bar/))
- **Funcionalidades:**
  - Semáforo na barra (🟡 esperando, 🔵 trabalhando, 🟢 quieto) com contagem de sessões não ociosas.
  - Clique para pular a uma aba do Terminal, janela do VS Code ou o app do Codex.
  - % de contexto por sessão.
  - Claude e Codex lado a lado ([README](https://github.com/zuoxu3310/openagentpeek)).
- **Detecção:** **sem hooks**. Lê em modo tail os JSONL de `~/.claude/projects` e `~/.codex/sessions`, publica um snapshot por segundo e acha o processo pelo cwd ([README](https://github.com/zuoxu3310/openagentpeek)).
- **Instalação:** DMG **não assinado**; só Apple Silicon; feito em Tauri 2 + React ([README](https://github.com/zuoxu3310/openagentpeek)).
- **Preço:** grátis. **Idioma:** README em EN e zh-CN.
- **Pontos fracos:** sem notificações; jump só para Terminal/VS Code (iTerm2, Ghostty e WezTerm ficam como "futuro"); estado inferido só pelo log (sem permissão em tempo real); projeto parado. Issues: **nenhuma**.

## 12. Perch (ik-labs/perch)

- **Fonte:** https://github.com/ik-labs/perch (⭐ 0, sem licença open source, v0.5.141 em 2026-11-04, com releases quase diários)
- **Funcionalidades** ([README](https://github.com/ik-labs/perch)):
  - Sessões de Claude Code e Codex agrupadas por "o que precisa de você"; **subagentes aninhados sob o pai**; checklists de tarefas.
  - Comando ao vivo, modelo (incluindo 1M de contexto), **reasoning effort**, % de contexto e **custo**.
  - **Allow/Deny direto na notificação**.
  - **Companion iPhone**: pareamento por QR, conexão direta na Wi-Fi local ou por Tailscale fora de casa, e push via relay próprio (opcional).
  - Limites de 5 h e 7 d com timers de reset.
  - Jump ao terminal; escolha de ícone (pássaro, spark, logo do Claude, caranguejo; mono ou laranja).
  - Botão "**Remove Perch integration**", que restaura o `settings.json` anterior.
  - "Report an Issue…" no app.
- **Detecção:** altera `~/.claude/settings.json` (o README fala em "restores your previous settings.json"). O mecanismo exato **não foi documentado**. Que os limites venham do status line é inferência a partir de "numbers Claude Code only reports to its status line" ([README](https://github.com/ik-labs/perch)).
- **Instalação/assinatura:** DMG/zip **assinado e notarizado** (Developer ID Inkryptis Labs LLP), com auto-update assinado; só Apple Silicon, macOS 13+ ([README](https://github.com/ik-labs/perch)).
- **Preço:** **pago, com chave de licença**; o valor **não foi encontrado** ([README](https://github.com/ik-labs/perch)). **Idioma:** inglês.
- **Pontos fracos:** fechado e pago; sem screenshots ("landing shortly"); o push passa pelo relay deles. Issues públicas: **nenhuma**.

## 13. claudewatch (PyPI, hendrickmelo/claudewatch)

- **Fontes:** [PyPI JSON](https://pypi.org/pypi/claudewatch/json) (v0.1.0, publicada em 2026-04-16, requer Python ≥ 3.10 e `rumps`), repo https://github.com/hendrickmelo/claudewatch (⭐ 0, MIT)
- **Funcionalidades:**
  - Uso do rate limit com **cor por burn-rate** e countdown para o reset de 5 h.
  - Alertas do status.anthropic.com.
  - Dropdown com limites de 5 h e 7 d, sessões agrupadas por projeto (com títulos de thread do T3 Code) e modelo, contexto, custo e tokens por sessão ([PyPI](https://pypi.org/pypi/claudewatch/json)).
- **Detecção:**
  - API OAuth de uso, consultada a cada minuto.
  - **Hook `statusLine`**, que escreve arquivos de status por sessão e permite encadear um statusline já existente com `--chain`.
  - Transcripts JSONL, o SQLite do T3 e a página de status ([PyPI](https://pypi.org/pypi/claudewatch/json)).
- **Instalação:** `pip install claudewatch` ou `uv tool install`, depois `claudewatch install` para o hook. Requer jq ([PyPI](https://pypi.org/pypi/claudewatch/json)).
- **Assinatura:** não se aplica (pacote Python). **Preço:** grátis. **Idioma:** inglês.
- **Pontos fracos (auto-declarados):** alfa experimental, cerca de 55 MB de RAM (Python + PyObjC), limites só para assinantes Max, sem notificações ([PyPI](https://pypi.org/pypi/claudewatch/json)). Issues: **nenhuma**.

---

## Matriz funcionalidade × app

Legenda: ✅ sim · ◐ parcial/opt-in · ❌ não · ? não encontrado

| Funcionalidade | StatusBar (m1ckc3s) | Nudgy | AgentBar | CC Notifier | Claude Status (gmr) | Pulse | ClaudeDot | Clabar | AgentPulse | VibeBar | OpenAgentPeek | Perch | claudewatch |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Estado ao vivo no ícone (working/waiting/idle) | ✅ | ✅ | ✅ | ◐ (contagem) | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ◐ |
| Animação no ícone | ✅ | ? | ? | ? | ❌ | ✅ | ✅ | ❌ | ? | ✅ | ❌ | ? | ❌ |
| Cronômetro do turno/espera | ✅ | ❌ | ✅ | ? | ❌ | ✅ | ❌ | ❌ | ? | ✅ | ❌ | ? | ❌ |
| Rótulo da ferramenta atual | ✅ | ◐ | ✅ | ? | ❌ | ✅ | ◐ | ❌ | ? | ◐ | ❌ | ✅ | ❌ |
| Multi-sessão com lista | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Prioridade "precisa de você" no topo | ✅ | ✅ | ✅ | ? | ✅ | ✅ | ✅ | — | ✅ | ✅ | ✅ | ✅ | ❌ |
| Notificação nativa/popup | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ◐ (auto-abrir) | ✅ | ❌ | ✅ | ❌ |
| Som por evento | ✅ | ✅ | ✅ | ? | ❌ | ❌ | ✅ | ? | ? | ? | ❌ | ? | ❌ |
| Suprimir quando terminal em foco / DND | ❌ | ✅ | ✅ (DND, mute) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ? | ❌ |
| Pular para o terminal | ◐ | ✅ | ✅ | ? | ✅ (aba/pane/tmux) | ✅ | ✅ | ✅ | ✅ | ✅ | ◐ | ✅ | ❌ |
| Responder permissão/pergunta fora do terminal | ❌ | ❌ | ❌ (removido) | ✅ (celular) | ❌ | ❌ | ❌ | ❌ | ❌ | ◐ (Codex) | ❌ | ✅ | ❌ |
| Modelo / modo / % contexto por sessão | ❌ | ❌ | ✅ | ? | ❌ | ◐ (modelo, modo) | ❌ | ❌ | ❌ | ? | ◐ (contexto) | ✅ | ✅ |
| Tokens / custo | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (heatmap) | ❌ | ✅ | ✅ |
| Limites 5 h / semanal | ❌ | ◐ (opt-in) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Status do serviço Anthropic | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Histórico/log de eventos | ❌ | ❌ | ✅ | ✅ | ◐ (analytics) | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ? | ❌ |
| Nome de sessão customizado | ❌ | ❌ | ◐ (1º prompt) | ? | ✅ | ✅ (env) | ❌ | ◐ | ❌ | ✅ | ❌ | ? | ◐ (T3) |
| Subagentes / tarefas | ❌ | ❌ | ◐ | ? | ◐ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Guard de comandos arriscados | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Multi-agente (Codex etc.) | ❌ | ❌ | ✅ (Copilot) | ❌ | ❌ | ❌ | ❌ | ❌ | ◐ (arquitetura) | ✅ | ✅ | ✅ | ❌ |
| Widgets / notch | ❌ | ❌ | ❌ | ❌ | ✅ widget | ❌ | ❌ | ❌ | ❌ | ✅ notch | ❌ | ❌ | ❌ |
| Companion iPhone / push | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Webhooks (Slack/Discord) | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Atalho global / teclado | ❌ | ❌ | ✅ | ? | ❌ | ❌ | ❌ | ✅ | ◐ (Esc) | ❌ | ❌ | ? | ❌ |
| Setup automático de hooks no 1º launch | ✅ | ✅ | ◐ (plugin) | ✅ (botão) | ◐ (prompt) | ◐ (script) | ✅ | ✅ | ◐ (botão) | ◐ (in-app) | n/a (sem hooks) | ✅ | ◐ (CLI) |
| Desinstalação limpa dos hooks | ✅ | ✅ | ✅ | ? | ✅ | ✅ | ? | ? | ✅ | ✅ | n/a | ✅ | ✅ |
| Homebrew cask | ✅ oficial | ❌ | ◐ tap | ◐ (CLI) | ❌ | ❌ | ❌ | ❌ | ❌ | ◐ tap | ❌ | ❌ | ❌ (pip) |
| Assinado + notarizado | ✅ | ? | ✅ | ? | ? | n/a | ❌ | ❌ (ad-hoc) | ❌ | ❌ | ❌ | ✅ | n/a |
| Auto-update | ◐ (aviso) | ? | ◐ (brew) | ? | ? | ❌ | ? | ✅ Sparkle | ❌ | ◐ (check) | ❌ | ✅ | ❌ |
| Launch at login / auto-start | ✅ (via hook) | ? | ? | ? | ✅ | ❌ | ? | ? | ✅ | ✅ | ? | ✅ | ❌ |
| Localização (multi-idioma) | ❌ | ❌ | ❌ | ✅ 17 (pt-BR) | ❌ | ❌ | ✅ 8 | ✅ 7 (pt) | ❌ | ✅ 4 | ◐ docs | ❌ | ❌ |
| Preço | grátis | grátis | grátis | freemium (US$ 39,99/ano Pro) | grátis | grátis | grátis | grátis | grátis | grátis | grátis | pago | grátis |

### Mecanismo de transporte (resumo)

| App | Hooks | Transporte até o app | Lê JSONL? | Outros |
|---|---|---|---|---|
| Claude Status Bar | 8 eventos (command, Node) | arquivos de estado + polling | sim (marcador de interrupção) | auto-lança o app pelo hook |
| Nudgy | 6 eventos (tipo `http`) | HTTP 127.0.0.1:9847 + token no Keychain | sim (tokens) | — |
| AgentBar | 12 eventos via Claude Code mod | HTTP 127.0.0.1 com porta efêmera + bearer | sim (roster) | lê `~/.copilot/session-state` |
| CC Notifier | ? (hook `ccn`) | socket Unix `/tmp/ccn-{uid}.sock` | ? | relay em nuvem para o celular |
| Claude Status (gmr) | 5 eventos (plugin Rust) | arquivo `.cstatus` + **Darwin notification** + FSEvents + polling de 5 s | sim (jsonl-analyzer) | árvore de processos |
| Pulse | 26 eventos (shell + jq) | arquivos em `/tmp/pulse` observados pelo app | não | — |
| ClaudeDot | `Notification` + **statusLine** | ? | não | — |
| Clabar | 5 eventos (async) | HTTP 127.0.0.1:8737 | sim (busca) | API OAuth de uso |
| AgentPulse | 7 eventos | HTTP 127.0.0.1:9876+ com token | não | — |
| VibeBar | 11 eventos (plugin) | socket Unix (`vibebar-agent`) | sim | wrapper PTY + `ps` |
| OpenAgentPeek | nenhum | — | sim (tail a cada 1 s) | processo pelo cwd |
| Perch | ? (altera settings.json) | ? | ? | rede local/Tailscale para iOS |
| claudewatch | statusLine | arquivos | sim | OAuth API + SQLite do T3 |

---

## Funcionalidades que viraram padrão de mercado

Estão presentes na maioria (7 ou mais de 13) ou em todos os líderes por estrelas (Claude Status Bar, Claude Status gmr e VibeBar):

1. **Estado agregado no ícone** com pelo menos 3 estados (trabalhando / esperando você / ocioso) e cor ou ícone distinto para "precisa de você".
2. **Multi-sessão com lista no dropdown**, com quem precisa de você ordenado primeiro (prioridade permissão > trabalhando > ocioso).
3. **Clique na sessão para focar o terminal/IDE** de origem; os melhores focam a aba, o pane ou o tmux exatos (gmr, VibeBar) e usam Accessibility/AppleScript.
4. **Instalação automática dos hooks no primeiro lançamento**, com merge seguro em `~/.claude/settings.json`, **backup** e **remoção limpa** na desinstalação.
5. **Detecção por hooks do Claude Code** (`SessionStart`/`End`, `UserPromptSubmit`, `Pre`/`PostToolUse`, `Notification`, `PermissionRequest`, `Stop`), complementada por **leitura dos JSONL** em `~/.claude/projects`, respeitando `CLAUDE_CONFIG_DIR`.
6. **Transporte local sem rede externa** (HTTP em 127.0.0.1 com token, ou socket Unix) e discurso de **privacidade e sem telemetria**.
7. **Alerta sonoro ou notificação** em permissão e conclusão; os usuários pedem som explicitamente ([#42](https://github.com/m1ckc3s/claude-status-bar/issues/42), [#61](https://github.com/m1ckc3s/claude-status-bar/issues/61)).
8. **Detalhes por sessão**: nome do projeto ou cwd, ferramenta atual ou último prompt, tempo decorrido; cada vez mais também modelo e **% de contexto**.
9. **App de menu puro** (sem Dock), com **launch at login**.
10. **Distribuição por DMG**; os líderes também oferecem **Homebrew cask** e **assinatura e notarização** (os não assinados recebem críticas por causa do `xattr`).

### Tendências emergentes (diferenciais de quem está à frente)

- **Limites de uso de 5 h e semanal** no mesmo app (Clabar, Perch, claudewatch); pedido em issue do gmr ([#19](https://github.com/gmr/claude-status/issues/19)).
- **Responder permissão fora do terminal** (Perch na notificação, CC Notifier pelo celular, VibeBar no Codex). AgentBar mostra o risco: a política do diretório de plugins proíbe isso ([README](https://github.com/jreed91/agentbar)).
- **Companion mobile e push** (Perch, CC Notifier): é aí que está a monetização.
- **Multi-agente** (Codex, Copilot, Gemini…): VibeBar, Perch, OpenAgentPeek e AgentBar.
- **Supressão inteligente / DND / snooze / mute por sessão** (CC Notifier, AgentBar, Nudgy).
- **Subagentes e tarefas visíveis** (Perch, Pulse); o gmr teve bug de "idle" com agente em background ([#8](https://github.com/gmr/claude-status/issues/8)).
- **Nome de sessão real** (`claude -n`) em vez do cwd ([#47](https://github.com/m1ckc3s/claude-status-bar/issues/47)).
- **Eficiência de CPU** como requisito, pois a animação na barra custou caro ao líder ([#53](https://github.com/m1ckc3s/claude-status-bar/issues/53)).
- **Localização**: só CC Notifier (pt-BR) e Clabar (pt) têm português, o que deixa espaço para um app pt-BR nativo.

### Lacunas observadas (oportunidades)

- Ninguém trata bem a **interrupção durante o raciocínio**: não há hook, e o ícone fica preso ([#22](https://github.com/m1ckc3s/claude-status-bar/issues/22)).
- **Múltiplas contas (`CLAUDE_CONFIG_DIR`)** foram recusadas pelo líder ([#41](https://github.com/m1ckc3s/claude-status-bar/issues/41)); AgentBar e VibeBar respeitam a variável.
- **Rótulo que se adapta à barra cheia** ([#51](https://github.com/m1ckc3s/claude-status-bar/issues/51)).
- **Notificação ao ficar ocioso ou travado** ([VibeBar #1](https://github.com/yelog/vibebar/issues/1)); o Pulse resolve com timers de 60 e 120 s.
- **Suporte a macOS mais antigo** que o gmr (exige 26.2, [#20](https://github.com/gmr/claude-status/issues/20)).
