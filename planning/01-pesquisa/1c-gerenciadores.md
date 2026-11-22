# 1c — Gerenciadores de múltiplas sessões de agentes de código

Pesquisa feita em 2026-11-15. Fontes ao lado de cada afirmação. Atenção: várias
listas comparativas são escritas pelo próprio fornecedor (amux, Nimbalyst,
AgentsRoom) e se colocam em primeiro lugar. Trate o ranking delas como
propaganda, e só os fatos sobre as funcionalidades como úteis.

## 1. Resumo por ferramenta: o que cada uma faz de melhor

| Ferramenta | Tipo / plataforma | O que faz de melhor | Situação | Fonte |
|---|---|---|---|---|
| **Conductor** (Melty Labs) | App nativo macOS (Apple Silicon) | Fluxo completo de workspace isolado (branch + worktree) → diff viewer com comentários inline que voltam ao agente → aba Checks (git status, CI, comentários, todos) → PR (⌘⇧P) → merge → arquivar e restaurar pelo History | Ativo (versão 0.94.2). Conductor Cloud encerrando, app local segue | conductor.build; conductor.build/docs/workflow; nimbalyst.com/blog/best-session-managers-for-claude-code-and-codex |
| **Nimbalyst** (sucessor do Crystal, Stravu) | App desktop + companion iOS | Kanban de sessões (Backlog, In Progress, Done), barra lateral de arquivos lidos/escritos por sessão, busca full-text nos transcripts, alerta quando o agente termina ou pede permissão, push no iPhone | Ativo, "Free for individuals". A amux diz que é closed source; o site da Nimbalyst diz "open-source". Informação conflitante | nimbalyst.com/features/session-management; amux.io/guides/best-claude-code-session-managers-2026 |
| **Crystal** (Stravu) | Electron | Sessões paralelas de Claude Code e Codex em worktrees | Descontinuado desde fev/2026, substituído pelo Nimbalyst | github.com/stravu/crystal |
| **Claude Squad** | TUI em Go sobre tmux (macOS, Linux) | Simplicidade: lista de sessões no terminal, aba de preview e aba de diff, worktree por sessão, `c` faz commit e pausa, `r` retoma, `s` faz commit e push, `--autoyes` experimental | Ativo, AGPL-3.0 | github.com/smtg-ai/claude-squad; amux.io/... |
| **Vibe Kanban** (Bloop) | Web UI local (`npx vibe-kanban`) | Kanban em que mover um card dispara o agente na própria branch; preview do dev server com devtools; PR com descrição gerada; 10+ agentes | **Sunsetting** (README). A AgentsRoom diz que o encerramento foi anunciado em abr/2026 e que o código ficou com a comunidade | github.com/BloopAI/vibe-kanban; agentsroom.dev/blog/best-multi-agent-coding-tools |
| **ccmanager** | TUI em TypeScript, **sem tmux** (`npx ccmanager`) | Detecção de estado **Idle / Busy / Waiting** por agente (estratégias configuráveis); **hooks de mudança de estado** (ex.: notificação quando entra em Waiting); contador `[active/busy/waiting]` por projeto; restaura sessões após reinício (reexecuta o comando, mas não a conversa); `.worktreeinclude` copia `.env` para worktrees novas; auto-aprovação experimental via Haiku | Ativo, MIT | github.com/kbwo/ccmanager; amux.io/... |
| **Sculptor** (Imbue) | Desktop (Mac Apple Silicon, Linux) | Isolamento forte: cada agente em workspace próprio, com backend de container (Docker) experimental; revisar e fazer merge para main | "Experimental research preview", MIT | github.com/imbue-ai/sculptor; agentsroom.dev/... |
| **Aba Code do Claude Desktop** (Anthropic) | App oficial | Sessões paralelas com worktree opcional; diff com comentário por linha; `/code-review`; monitorar PR com CI, Auto-fix e Merge when ready; **notificação do SO quando a sessão termina e você não está olhando**; painel com Changes, % de contexto e tarefas em background; "Open in" (editor, Finder); Remote Control pelo celular | Ativo. **Não enxerga sessões iniciadas pelo CLI no terminal** nas ferramentas entre sessões | code.claude.com/docs/en/desktop |
| **amux** | Binário Rust + dashboard web (macOS, Linux) | Kanban compartilhado, mensagens entre agentes, **retomada após o limite de uso**, alerta de agente travado, tokens por sessão | MIT + Commons Clause; Cloud a partir de US$39/mês. Página escrita pelo próprio fornecedor | amux.io/guides/best-claude-code-session-managers-2026 |
| **Opcode** (ex-Claudia) | Desktop Tauri | Navegador de projetos e sessões sobre `~/.claude/projects`; dashboard de uso por modelo, projeto e data; timeline de checkpoints | Último release v0.2.0 (ago/2025); sem commits desde out/2025 | amux.io/...; nimbalyst.com/blog/best-session-managers-... |
| **Agent Deck** | Go + tmux | Status running/waiting/idle para 12+ agentes; dashboard de custo; sessão "conductor" que escala via Telegram ou Slack | MIT | amux.io/... |
| **Agent of Empires** | Rust + tmux | TUI + web + visão de celular com aprovar deslizando; diff viewer | MIT | amux.io/... |
| **Herdr** | Rust (substitui o tmux) | Cada painel marcado como working, blocked ou idle; reanexar via SSH | Apache-2.0 | nimbalyst.com/blog/best-session-managers-... |
| **cmux** | Terminal macOS | Barra lateral com branch, **status do PR** e portas por workspace | GPL-3.0+ | nimbalyst.com/blog/best-session-managers-... |
| **Omnara** | iOS, Android, web | Controle remoto pelo celular (aprovar, responder, voz) das sessões existentes | Free + US$9/mês | agentsroom.dev/... |
| **AgentsRoom** | Mac, Win, Linux, mobile | Quadro com um bloco por agente (status, projeto, notificações). Página escrita pelo próprio fornecedor | Proprietário | agentsroom.dev/... |
| **CLI nativo do Claude Code** | — | `claude -c` (continua a última conversa da pasta), `claude -r` (retoma por ID ou nome), `--worktree` | — | nimbalyst.com/blog/best-session-managers-... |

## 2. Padrões que se repetem (o que o mercado considera básico)

1. **Status por sessão em 3 ou 4 estados** (working, waiting ou blocked, idle, e às vezes "done"): ccmanager, Agent Deck, Herdr e Nimbalyst. O ClaudeBar já tem isso (processando, esperando, pronto, ocioso).
2. **Notificação quando termina ou pede permissão**: Claude Desktop, Nimbalyst e ccmanager (via hook). O ClaudeBar já tem.
3. **Worktree por sessão + diff + PR**: Conductor, Claude Squad, Vibe Kanban, Crystal/Nimbalyst, Sculptor e Claude Desktop. É o centro desses produtos, que **viram IDE**.
4. **Retomar sessão**: ccmanager (relança o comando), Nimbalyst (conversa), Claude Squad (pausa e retoma) e CLI (`claude -r`).
5. **Lista de arquivos alterados por sessão**: Nimbalyst (files-edited sidebar) e Claude Desktop (card Changes `+12 -1`).
6. **Custo e tokens por sessão**: amux, Agent Deck e Opcode.
7. **Status de PR/CI ao lado da sessão**: cmux, Conductor e Claude Desktop.

## 3. O que cabe num app LEVE de barra de menu (sem virar IDE)

Critério: só **lê** dados que já existem (hooks, `~/.claude/projects`, transcripts, `git`) e **delega** a ação a um app que o usuário já usa (terminal, editor, Finder, navegador). Não hospeda terminal, não renderiza diff, não gerencia agentes.

| Prioridade | Funcionalidade | Inspirado em | Por que cabe |
|---|---|---|---|
| Alta | **Focar o terminal da sessão** (trazer para frente a janela ou aba do Terminal, iTerm, Ghostty ou VS Code onde a sessão roda) | Claude Squad (`↵` attach); Conductor (abrir no terminal ou IDE) | 1 clique. Resolve o "qual janela era?", que é a dor real de quem tem várias sessões. Não exige UI nova |
| Alta | **Abrir projeto** em editor, Finder ou terminal novo | Claude Desktop "Open in" / "show in Finder" | Um `NSWorkspace.open` ou um `open -a`. Trivial |
| Alta | **Retomar sessão encerrada** (abrir um terminal com `claude -r <id>` na pasta certa) | CLI `claude -r`; ccmanager (restaurar); Nimbalyst (resume) | O ID da sessão já está no transcript. Só abre um terminal |
| Alta | **Resumo do que mudou**: contagem `+N −M` e lista de arquivos tocados por sessão (via `git diff --stat` na pasta da sessão, ou via tool calls Edit/Write no transcript) | Nimbalyst files-edited; card Changes do Claude Desktop | Texto curto no submenu; clicar no arquivo abre no editor. Não precisa de diff viewer |
| Média | **Hook ou ação customizável na mudança de estado** (rodar um comando quando a sessão entra em "esperando") | Status hooks do ccmanager | Generaliza a notificação. Pode ficar só no config, sem UI |
| Média | **Agrupar por projeto com contador `[ativas/processando/esperando]`** | Modo multiprojeto do ccmanager | Organiza o menu quando há muitas sessões |
| Média | **% de contexto e tokens da sessão** (lidos do transcript) | Card Context do Claude Desktop; amux/Agent Deck (tokens) | Um número na linha. Útil para saber quando compactar |
| Média | **Alerta de sessão travada** (processando há mais de X min sem atividade no transcript) | "stalled-agent alerts" da amux | Usa o mesmo mecanismo de estado; não precisa de UI nova |
| Baixa | **Branch atual e status do PR** da pasta da sessão (`git branch`, `gh pr view`) | cmux; Checks do Conductor | Informativo. Depende do `gh`, então é opcional |
| Baixa | **Busca nas sessões recentes** (título ou primeira mensagem) | Busca full-text da Nimbalyst | Só se a lista ficar longa. Um campo de busca no popover |

### Ideias "novas" (não encontrei em nenhum dos concorrentes como app de barra de menu)

- **Ver sessões de CLI e Desktop juntas.** O Claude Desktop não enxerga sessões do CLI (code.claude.com/docs/en/desktop). Um app de barra de menu que lê hooks e `~/.claude` enxerga as duas. Não encontrado em nenhum concorrente como recurso explícito.
- **Responder ou aprovar a partir da notificação** (botão de ação na notificação que foca o terminal certo). Omnara e Agent of Empires fazem algo parecido no celular; não encontrado em app de barra de menu.
- **"Fila de atenção"**: ordenar pela urgência (esperando > pronto > processando) e um atalho global que pula para a próxima sessão que precisa do usuário. Não encontrado como atalho global em nenhum concorrente.

## 4. O que seria exagero para o ClaudeBar (cada um é o produto inteiro de outro app)

- **Criar e gerenciar worktrees, branches, merge e PR**: é o núcleo do Conductor, Claude Squad, Crystal/Nimbalyst, Vibe Kanban e Sculptor. Exige UI de criação, tratamento de conflito e limpeza.
- **Diff viewer com comentário inline que volta para o agente**: Conductor, Claude Desktop e Vibe Kanban. É um editor de código.
- **Terminal embutido ou grade de painéis**: Nimbalyst (terminal Metal), Claude Desktop. Vira terminal ou IDE.
- **Kanban de tarefas e dispatch de agentes**: Vibe Kanban, Nimbalyst, amux. Muda o produto de "monitor" para "orquestrador".
- **Iniciar e orquestrar agentes, mensagens entre agentes, scheduler**: amux, Agent Deck "conductor".
- **Auto-aprovação de prompts** (ccmanager com Haiku, `--autoyes` do Claude Squad): risco de segurança e responsabilidade. Um monitor não deve aprovar nada sozinho.
- **Sandbox em container**: Sculptor, Agent of Empires.
- **Preview de dev server ou navegador embutido**: Vibe Kanban, Claude Desktop.
- **App de celular, relay remoto ou dashboard web**: Omnara, Nimbalyst iOS, amux. Exige servidor e conta. O Remote Control do Claude já cobre isso.
- **Monitorar CI e consertar PR automaticamente** (Auto-fix do Claude Desktop, Conductor). Mostrar o status do PR já basta.
- **Dashboard de custo completo** por modelo, projeto e data (Opcode). No máximo um número por sessão.

## 5. Posicionamento sugerido

Os concorrentes se dividem em (a) **orquestradores e IDEs** (Conductor, Nimbalyst, Vibe Kanban, Sculptor, Claude Desktop), que são pesados e tomam conta do fluxo, e (b) **TUIs de terminal** (Claude Squad, ccmanager, Agent Deck), que exigem ficar numa janela de terminal. O espaço livre é o **monitor passivo e ubíquo**: está sempre visível, enxerga qualquer sessão (CLI, IDE ou Desktop), avisa e **leva você até a sessão** em 1 clique. A paridade com os concorrentes, sem virar IDE, é: focar terminal, abrir projeto, retomar sessão e resumo do que mudou, mais os hooks de estado e o alerta de sessão travada.

## 6. Não encontrado / lacunas

- Preço do Conductor: não encontrado nas páginas lidas.
- Licença exata do Nimbalyst: as fontes se contradizem (closed source segundo a amux; "open-source" segundo o site da Nimbalyst).
- Detalhes de notificação e scripts de setup/run do Conductor: não encontrados nas páginas de docs lidas.
- Como o Claude Desktop retoma sessões criadas no CLI: não encontrado (o trecho lido só diz que as ferramentas entre sessões não as enxergam).
- Detalhes do Sculptor sobre "pairing mode" e sync: não encontrados no README atual.

## Fontes

- https://amux.io/guides/best-claude-code-session-managers-2026
- https://agentsroom.dev/blog/best-multi-agent-coding-tools
- https://www.nimbalyst.com/blog/best-session-managers-for-claude-code-and-codex/
- https://nimbalyst.com/features/session-management/
- https://www.conductor.build/ , https://www.conductor.build/docs/ , https://www.conductor.build/docs/workflow
- https://github.com/smtg-ai/claude-squad
- https://github.com/kbwo/ccmanager
- https://github.com/BloopAI/vibe-kanban
- https://github.com/imbue-ai/sculptor
- https://github.com/stravu/crystal
- https://code.claude.com/docs/en/desktop
