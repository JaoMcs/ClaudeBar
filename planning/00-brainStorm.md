# ClaudeBar — Brainstorm de evolução e checklist "ready to ship"

> Data: 2026-11-15. Base: código atual (`main`, ~1250 linhas Swift), `README.md`, `TODO.md` e pesquisa de mercado.
> Fontes da pesquisa no final do arquivo. Detalhes dos concorrentes vêm de READMEs e páginas de listagem, não testei os apps.

---

## 1. Onde o ClaudeBar está hoje

**O que já faz bem (e muitos concorrentes não fazem):**
- Une duas fontes: `claude agents --json` (quais sessões existem) + hooks (estado em ms). Quase todo concorrente usa só hooks e perde sessões que nunca dispararam evento.
- Prioridade de estado clara: `waiting > ready (não visto) > working > idle`.
- Estado "pronto e ainda não visto" (✅ até você marcar). Poucos têm isso.
- Subagentes em background separados (não contam, não tocam som).
- Encerrar sessão com segurança: `claude stop` para background, `SIGTERM` só se `pgid == pid`, checagem de PID reciclado, recusa sessões do app desktop.
- Sons diferentes por tipo de alerta (Glass / Submarine).
- Segurança: sem rede, diretório `0700`, arquivos `0600`, `session_id` sanitizado, nada passa por shell.
- Testes cobrindo merge, contagem, ícone e kill real.

**Limitações atuais (do código/README):**
- Sem ícone de app, sem tela de configurações, sem onboarding.
- Assinatura ad-hoc → sem notificação nativa, Gatekeeper bloqueia em outra máquina.
- Instalação por script que exige `swift`, `jq` e `~/.claude/settings.json` existente.
- `install.sh` **substitui** hooks existentes de `UserPromptSubmit/Stop/Notification/SessionEnd` (destrutivo).
- Toggle "Notificações" desliga o popup mas o **som continua tocando** (`Notifier.post` toca antes de checar).
- Sem "abrir na inicialização" automático (manual em Ajustes do Sistema).
- UI só em português, hardcoded.
- Sem desinstalador (remoção manual dos hooks).
- Só Claude Code.

---

## 2. Estudo de softwares similares

### 2.1 Concorrentes diretos — status de sessão na barra de menu

| App | O que tem de interessante | O ClaudeBar tem? |
|---|---|---|
| **Claude Status Bar** (Homebrew cask, MIT) | Ícone animado enquanto pensa/roda tool, ponto amarelo quando pede permissão, **setup automático de hooks**, distribuído via `brew install --cask` | Ícone estático; setup por script; sem Homebrew |
| **Nudgy** | Notificação nativa ao terminar / pedir permissão / fazer pergunta; estado **error**; sessões com **cor por sessão**; toggles por tipo de notificação | Sem estado de erro, sem cor por sessão, um toggle só |
| **Claude Code Notifier** (pago, Gumroad) | **Webhooks para Slack/Discord** | Não |
| **AgentBar** | Plugin do Claude Code alimenta servidor local; também monitora **GitHub Copilot CLI** | Só Claude (TODO já prevê Gemini/Codex) |
| **Claude Status** | **Um clique foca o app host da sessão** (terminal/IDE) | Não — maior lacuna de UX |
| **claudewatch** | Status de sessão + **rate limits** juntos | Não |
| Pulse, ClaudeDot, Clabar, AgentPulse, vibebar, OpenAgentPeek, Perch | Variações: indicadores ao vivo, analytics, jump-to-terminal | — |

### 2.2 Vizinhos — uso/limites na barra de menu

| App | Destaque |
|---|---|
| **CodexBar** (steipete, open source, macOS 14+) | Medidores de sessão (5h) e semanal com horário de reset, muitos providers, **CLI própria** (`codexbar usage --format json`). Lê credencial do Keychain |
| **AgentLimits** | Limites 5h/semanal + **widgets da Central de Notificações** + custo via `ccusage` |
| **Usagebar / ClaudeUsageBar / TokenBar** | Limites com timer de reset e alerta; TokenBar vende lifetime por ~US$15 |
| **CC Usage Tracker** | Usa **statusline bridge** em vez de ler JSONL |
| **ccusage** (CLI) | Backend padrão para tokens/custo a partir dos JSONL locais; tem extensão Raycast |

### 2.3 Vizinhos — gerenciadores de múltiplas sessões (apps grandes)

| App | Destaque |
|---|---|
| **Conductor** | App Mac: várias sessões em worktrees isoladas, diff, checks, PR. Agora com Conductor Cloud |
| **Crystal → Nimbalyst** | Sessões paralelas em worktrees; Crystal teria sido descontinuado em favor do Nimbalyst (fonte única) |
| **Claude Squad / ccmanager** | TUI em tmux para alternar entre agentes Claude/Codex |
| **Vibe Kanban, Sculptor** | Kanban de tarefas de agentes |
| **Claude desktop (aba Code)** | Já gerencia sessões por projeto oficialmente |

### 2.4 Leitura do mercado

- O nicho "status na barra de menu" está **lotado** (10+ apps). Diferencial não pode ser "mostra se o Claude terminou".
- Os gerenciadores grandes (Conductor etc.) são pesados; ninguém quer trocar de ferramenta só pra saber o estado.
- **Posicionamento possível do ClaudeBar:** *o painel leve e confiável de todas as suas sessões de agentes, onde quer que rodem (terminal, desktop, background), com ação rápida.* Os trunfos são a precisão (CLI + hooks), o "não visto" e o encerramento seguro.
- Recursos que aparecem em vários concorrentes e viraram **expectativa**: setup automático, Homebrew, notificação nativa, focar o terminal, limites de uso.

---

## 3. Brainstorm de ideias

Legenda de esforço: **P** pequeno (horas) · **M** médio (1–3 dias) · **G** grande (semana+)
Legenda de valor: ⭐ a ⭐⭐⭐

### 3.1 Ação a partir do menu (maior lacuna)
- ⭐⭐⭐ **M — Focar a sessão**: clicar na linha traz para frente o terminal/IDE certo. Caminho: pelo PID, subir a árvore de processos até achar o app (Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor, Claude.app) e ativar com `NSRunningApplication`. Para Terminal/iTerm, AppleScript pode até selecionar a aba pelo `tty`.
- ⭐⭐ **P — Abrir pasta do projeto** no Finder / no editor (`open -a`).
- ⭐⭐ **P — Copiar `claude --resume <id>`** para o clipboard.
- ⭐⭐ **M — Responder permissão pelo popup** ("Permitir / Negar"). Precisa ver se o hook `PreToolUse`/`PermissionRequest` deixa devolver decisão; se deixar, é um diferencial forte. Validar na doc antes.
- ⭐ **P — Clique no popup HUD foca a sessão** (hoje só fecha).

### 3.2 Informação na barra / no menu
- ⭐⭐⭐ **M — Limites de uso** (5h e semanal, com reset), como CodexBar/Usagebar. Pode vir da statusline do Claude Code (bridge, sem Keychain) ou do `ccusage`. Junta "status" + "limites" num app só, o que poucos fazem.
- ⭐⭐ **P — Ícone animado enquanto trabalha** (SF Symbol com `.symbolEffect(.pulse)` / `.variableColor`).
- ⭐⭐ **P — Tempo trabalhando** na linha ("processando há 4 min") e duração da última resposta no alerta "Claude terminou (3m12s)".
- ⭐⭐ **P — Estado de erro** (hook `StopFailure` / falha de API, se existir) com ícone próprio.
- ⭐ **P — Nome da sessão/branch git** na linha, além da pasta.
- ⭐ **M — Última ferramenta em uso** ("rodando Bash", "editando X") via `PreToolUse`.
- ⭐ **M — Custo/tokens da sessão** (`ccusage` ou JSONL). Cuidado: ler transcript quebra a promessa atual "não lê histórico". Deixar opt-in.

### 3.3 Notificações
- ⭐⭐⭐ **P — Corrigir o bug do som com notificações desligadas.**
- ⭐⭐ **P — Toggles separados**: popup "terminou", popup "esperando", som, e escolha do som/volume.
- ⭐⭐ **P — Não alertar se a sessão já está em foco** (o terminal dela é o app ativo).
- ⭐⭐ **P — Modo silencioso respeitando Foco/Não Perturbe** do macOS.
- ⭐ **P — Lembrete**: se ficar "esperando você" por N minutos, alerta de novo.
- ⭐ **M — Webhook / ntfy.sh / Pushover** para ser avisado no celular quando longe do Mac (Claude Code Notifier cobra por isso).

### 3.4 Multi-agente (já está no TODO)
- ⭐⭐⭐ **M — Gemini CLI e Codex CLI** via campo `agent` + `claudebar-hook --agent`. Ícone por agente na linha.
- ⭐ **M — Copilot CLI, OpenCode, Cursor CLI** depois, se tiverem hooks.
- Se isso entrar, repensar o **nome** (ver seção 5).

### 3.5 Integrações com o sistema
- ⭐⭐ **M — Widget** (WidgetKit) com sessões e limites.
- ⭐⭐ **M — Atalho global** para abrir o menu / pular para a próxima sessão "esperando".
- ⭐⭐ **M — App Intents / Atalhos** ("quantas sessões estão esperando?") — vem de graça com Raycast/Spotlight.
- ⭐ **P — Deep link `claudebar://`** para scripts.
- ⭐ **P — CLI de leitura** (`claudebar-hook status --json`) para tmux/statusline/sketchybar.

### 3.6 Histórico e produtividade (mais longe)
- ⭐ **M — Histórico do dia**: quantas respostas, tempo total trabalhando, tempo que você deixou o Claude esperando.
- ⭐ **G — Iniciar nova sessão** a partir do menu (escolher pasta → abre terminal com `claude`). Começa a virar Conductor; avaliar se vale.

### 3.7 Ideias descartadas / com ressalva
- Gerenciar worktrees, diff, PR → território do Conductor/Claude desktop, foge do "leve".
- Ler conversas inteiras → contraria a proposta de privacidade.
- Sync na nuvem / conta → sem necessidade, adiciona superfície de ataque.

---

## 4. Ready to ship — o que falta para lançar

### 4.1 Bloqueadores (sem isso não dá pra distribuir)
- [ ] **Ícone do app** (`AppIcon.icns`, 16→1024 px) + ícone para o `.dmg`. Hoje não existe nenhum. Também revisar o ícone da barra (template image monocromática própria, não só SF Symbol genérico).
- [ ] **Assinatura Developer ID + notarização** (`codesign --options runtime` + `notarytool` + `stapler`). Sem isso: Gatekeeper bloqueia na máquina dos outros e não há notificação nativa. Custa a conta Apple Developer (US$ 99/ano).
- [ ] **Distribuição em binário**: `.dmg` ou `.zip` no GitHub Releases, e depois **Homebrew cask**. Usuário final não deve precisar de Swift/Xcode/jq.
- [ ] **Instalação dos hooks pelo próprio app** (primeiro uso): detectar `~/.claude/settings.json`, criar se não existir, **fazer merge** sem apagar hooks do usuário, mostrar o diff e pedir confirmação. Tira a dependência de `jq` e resolve o bug destrutivo do `install.sh`.
- [ ] **Desinstalar hooks** pelo menu (remove só as entradas `claudebar-hook`).
- [ ] **Caminho do hook estável**: hoje o comando aponta para `~/Applications/ClaudeBar.app/...`. Se o usuário mover o app para `/Applications`, os hooks quebram em silêncio. Detectar e reparar no launch.
- [ ] **Corrigir som tocando com notificações desligadas.**
- [ ] **Abrir no login** via `SMAppService.mainApp.register()` com toggle no menu.

### 4.2 Esperado em um app de verdade
- [ ] **Janela de Ajustes** (`Settings` scene): notificações, sons/volume, abrir no login, status dos hooks (instalados / desatualizados / reparar), idioma.
- [ ] **Onboarding** de 1 tela no primeiro uso: o que o app faz → instalar hooks → testar com o popup de exemplo.
- [ ] **Localização** (`Localizable.xcstrings`): inglês como base + pt-BR. README já é em inglês; o app só em português limita o público.
- [ ] **Auto-update** com Sparkle (padrão para apps fora da App Store) ou, no mínimo, aviso de nova versão via GitHub Releases.
- [ ] **Sobre**: versão, link do repositório, licença.
- [ ] **Versão vinda de git tag** no `build-app.sh` (hoje `VERSION="1.0"` fixo).
- [ ] **Diagnóstico**: item "Copiar diagnóstico" (versão, macOS, caminho do `claude`, hooks ok?, nº de arquivos de estado) para issues.
- [ ] **Acessibilidade**: labels de VoiceOver no ícone da barra ("2 sessões, 1 esperando você") e nas linhas.

### 4.3 Repositório / projeto
- [ ] **LICENSE** (MIT é o padrão no nicho).
- [ ] **CI no GitHub Actions**: `swift build` + `swift test` em PR; job de release que assina, notariza e publica o `.dmg` quando cria tag.
- [ ] **Screenshots/GIF** no README (menu aberto, popup). Concorrentes todos têm.
- [ ] **CHANGELOG.md** e versionamento semântico.
- [ ] Trocar o bundle id `com.joaomarcos.claudebar` por algo definitivo antes do 1.0 (mudar depois quebra preferências e login item).
- [ ] Template de issue / CONTRIBUTING curto.

### 4.4 Riscos para avaliar antes do lançamento
- **Nome "ClaudeBar"**: usa a marca "Claude" no nome do produto. Vários concorrentes fazem isso, mas é risco de marca, ainda mais se virar multi-agente. Alternativas genéricas: *AgentBar* (já existe), *Pinglet*, *Nudge*, *Dotwatch*... pesquisar disponibilidade antes.
- **Dependência de `claude agents --json`**: comando/formato pode mudar entre versões do Claude Code. Fallback já existe (só hooks), mas vale um teste de contrato e mensagem clara no menu quando o formato muda.
- **Sessões do Claude desktop**: não dá pra encerrar, e focar pode ser limitado. Deixar explícito.

---

## 5. Roadmap sugerido

| Versão | Foco | Itens |
|---|---|---|
| **0.9 — Arrumar a casa** | Bugs + base | Bug do som, merge de hooks, abrir no login, versão por tag, LICENSE, CI |
| **1.0 — Ready to ship** | Distribuição | Ícone, Developer ID + notarização, `.dmg` em Releases, instalação/remoção de hooks pelo app, onboarding, Ajustes, inglês + pt-BR, screenshots |
| **1.1 — Diferencial** | UX | **Focar sessão no clique**, ícone animado, tempo trabalhando, toggles por alerta, não alertar sessão em foco |
| **1.2 — Limites** | Valor extra | Limites 5h/semanal na barra e no menu, alerta perto do limite |
| **1.3 — Multi-agente** | Alcance | Gemini + Codex, ícone por agente, (decidir nome) |
| **Depois** | — | Homebrew cask, Sparkle, widget, atalho global, webhook/celular, responder permissão pelo popup |

### Top 5 se for fazer só cinco coisas
1. Ícone + assinatura/notarização + `.dmg` (sem isso ninguém instala).
2. Instalar/remover hooks pelo app com merge seguro.
3. Focar a sessão ao clicar (maior ganho de UX, poucos concorrentes têm).
4. Ajustes + abrir no login + correção do som.
5. Limites de uso na barra (junta os dois nichos num app só).

---

## Fontes
- [claudewatch (PyPI)](https://pypi.org/project/claudewatch/)
- [Claude Status Bar](https://github.com/m1ckc3s/claude-status-bar) · [mirror](https://sourceforge.net/mirror/claude-status-bar/)
- [Nudgy](https://github.com/Hamma111/nudgy)
- [Clabar](https://github.com/Magir/clabar)
- [AgentBar](https://github.com/jreed91/agentbar)
- [vibebar](https://awesome.ecosyste.ms/projects/github.com%2Fyelog%2Fvibebar)
- [OpenAgentPeek](https://awesome.ecosyste.ms/projects/github.com%2Fzuoxu3310%2Fopenagentpeek)
- [claudecode-macmenu](https://awesome.ecosyste.ms/projects/github.com%2FPiXeL16%2Fclaudecode-macmenu)
- [Pulse](https://github.com/sayantan94/pulse)
- [Claude Code Notifier](https://touchtap.gumroad.com/l/claude-code-notifier)
- [ClaudeDot](https://github.com/poorfish/ClaudeDot)
- [claude-statistics](https://github.com/sj719045032/claude-statistics)
- [Perch](https://github.com/ik-labs/perch)
- [AgentPulse](https://github.com/fanook/agentpulse)
- [Claude Status (tomevault)](https://tomevault.io/tome/gmr/claude-status)
- [CodexBar (docs)](https://www.mintlify.com/steipete/codexbar) · [project-awesome](https://project-awesome.org/r/steipete-CodexBar)
- [AgentLimits](https://github.com/Nihondo/AgentLimits/wiki)
- [CC Usage Tracker](https://github.com/pedroprates/claude-code-usage)
- [Usagebar](https://feedbagel.com/post/usagebar-macos-menu-bar-app-for-tracking-claude-code-usage-limits)
- [TokenBar](https://www.hackingwithswift.com/forums/app-announcements/tokenbar-mac-menu-bar-for-claude-codex-cursor-usage-limits-15-lifetime/31198)
- [ccusage (Raycast)](https://www.raycast.com/nyatinte/ccusage)
- [Conductor](https://www.conductor.build/workflows/run-parallel-claude-codes)
- [Crystal](https://github.com/ianva/crystal) · [Crystal → Nimbalyst](https://hn.jakechampion.name/reader/https://stravu.com/crystal)
- [Best Session Managers for Claude Code & Codex](https://nimbalyst-website.pages.dev/blog/best-session-managers-for-claude-code-and-codex/)
- [Best Claude Code Session Managers in 2026](https://amux.io/guides/best-claude-code-session-managers-2026/)
- [Best tools to run multiple coding agents in 2026](https://agentsroom.dev/blog/best-multi-agent-coding-tools)
- [Claude Squad](https://www.opensourcealternatives.to/item/claude-squad)
- [ccmanager](https://x-cmd.com/install/ccmanager/)
