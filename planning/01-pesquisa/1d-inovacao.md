# 1d — Pesquisa de Inovação (ClaudeBar)

Data da pesquisa: 2026-11-15. Escopo: app de barra de menu macOS que monitora sessões de agentes de código.
Regra: toda afirmação tem fonte ao lado. Quando não achei, está escrito **"não encontrado"**.

Contexto do projeto (lido no repo): ClaudeBar hoje é um app de menu bar (macOS 14+, Swift 6) com um binário `claudebar-hook` que grava o status por sessão; mostra ícone com estados idle/working/ready/waiting, popup HUD e notificações (`<repo>/README.md`, `Sources/`).

---

## 1. Hooks do Claude Code (doc oficial)

Fonte principal: https://code.claude.com/docs/en/hooks

### 1.1 Eventos atuais

| Evento | Quando dispara | Campos relevantes do payload |
|---|---|---|
| `SessionStart` | início/retomada | `source` (`startup`/`resume`/`clear`/`compact`/`fork`), `model?`, `agent_type?`, `session_title?`; em resume/fork: `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd` (v2.1.251+) |
| `Setup` | `--init-only` / `--init` / `--maintenance` | matcher `init`/`maintenance` |
| `UserPromptSubmit` | prompt enviado | (prompt) |
| `UserPromptExpansion` | comando vira prompt | matcher = nome do comando |
| `PreToolUse` | antes de uma tool | `tool_name`, `tool_input`, `tool_use_id` |
| `PermissionRequest` | tool precisa de permissão | `tool_name`, `tool_input`, `mcp_server?`, `permission_suggestions[]` (sem `tool_use_id`) |
| `PermissionDenied` | modo auto negou | campos da tool; pode devolver `retry` |
| `PostToolUse` / `PostToolUseFailure` | depois da tool | campos da tool |
| `PostToolBatch` | após lote paralelo de tools | não detalhado no trecho lido |
| `Notification` | Claude Code notifica | matcher = tipo: `permission_prompt`, `idle_prompt`, `auth_success`, `auth_storage_failure`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`, `plugin_notification`; campo `message` |
| `MessageDisplay` | texto do assistente exibido | timeout 10 s |
| `SubagentStart` / `SubagentStop` | subagente nasce/termina | `agent_id`, `agent_type`; Stop traz `last_assistant_message` |
| `TaskCreated` / `TaskCompleted` | tarefas (TaskCreate) | — |
| `Stop` | Claude terminou a resposta | `last_assistant_message` |
| `StopFailure` | turno acabou por erro de API | matcher = tipo de erro |
| `TeammateIdle` | colega de agent-team ficará ocioso | — |
| `InstructionsLoaded`, `ConfigChange`, `CwdChanged` (`cwd`), `DirectoryAdded`, `FileChanged` | ambiente/config | — |
| `WorktreeCreate` / `WorktreeRemove` | worktrees | — |
| `PreCompact` / `PostCompact` | compactação | matcher `manual`/`auto` |
| `PreModelSwitch` / `PostModelSwitch` | troca de modelo | `from_model`, `to_model` |
| `Elicitation` / `ElicitationResult` | MCP pede input do usuário | matcher = servidor MCP |
| `SessionEnd` | sessão termina | `reason`: `clear`/`resume`/`logout`/`prompt_input_exit`/`other`; orçamento total 1,5 s |

Campos comuns a todos: `session_id`, `transcript_path`, `cwd`, `permission_mode` (`default`/`plan`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`), `hook_event_name`, `prompt_id`, `effort`, e `agent_id`/`agent_type` dentro de subagentes — https://code.claude.com/docs/en/hooks

Payload exato de `Stop`, `SessionEnd`, `PreCompact` e campos `title`/`notification_type` do `Notification`: **não encontrado** no trecho lido da doc (página tem ~290 mil caracteres; li 0–200k).

### 1.2 Hooks que devolvem decisão (chave para "responder pelo popup")

- **`PermissionRequest`** → `hookSpecificOutput.decision.behavior: "allow" | "deny"`; em allow aceita `updatedInput` e `updatedPermissions` (regras persistentes, destino `session`/`localSettings`/`projectSettings`/`userSettings`, ou `setMode`); em deny aceita `message` e `interrupt`. Pode ecoar um item de `permission_suggestions` como `updatedPermissions` ("sempre permitir"). — https://code.claude.com/docs/en/hooks
- **`PreToolUse`** → `hookSpecificOutput.permissionDecision: allow | deny | ask | defer` + `permissionDecisionReason`. — mesma fonte
- **`Stop`/`SubagentStop`** → `{"decision":"block","reason":...}` faz o Claude continuar trabalhando. — mesma fonte
- **`Elicitation`** → devolve `action` (`accept`/`decline`/`cancel`) e `content`. — mesma fonte
- `Notification`, `SessionStart`, `SessionEnd` **não** bloqueiam. — mesma fonte

Mecânica útil:
- Hook tipo `http` (POST JSON para uma URL, ex. `http://localhost:PORT`), resposta 2xx com JSON usa o mesmo schema. Dispensa binário intermediário. — https://code.claude.com/docs/en/hooks
- Timeout padrão de `command`/`http` = 600 s → um hook de `PermissionRequest` pode esperar o clique do usuário por até 10 min. — mesma fonte
- `async: true` e `asyncRewake: true` (roda em background; exit 2 acorda o Claude e o stderr entra como system reminder). Async não devolve decisão. — mesma fonte

**Conclusão:** sim, responder permissão pelo popup é suportado oficialmente via `PermissionRequest` (ou `PreToolUse`).

## 2. Outros agentes

### Codex CLI (OpenAI)
Fonte: https://learn.chatgpt.com/docs/hooks.md (redirect de https://developers.openai.com/codex/hooks)
- Eventos: `SessionStart`, `SessionEnd`, `SubagentStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreModelRequest`, `PostModelRequest`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, `Stop`, `Interrupt`.
- Comuns: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`.
- Decisão: `PermissionRequest` → `hookSpecificOutput.decision.behavior: allow|deny` (mesmo formato do Claude); `PreToolUse` deny/allow + `updatedInput` (`ask` ainda não suportado); `Stop` block continua o turno.
- Config: `~/.codex/hooks.json` ou `[hooks]` inline em `~/.codex/config.toml`; repo `.codex/` só se o projeto for confiável; hooks não gerenciados exigem revisão de confiança em `/hooks`.
- `PostModelRequest` traz `token_usage` → dá para mostrar consumo por sessão.
- Setting legado `notify`: dispara no fim do turno com JSON incluindo a última mensagem — fonte de terceiro: https://simonalford.substack.com/p/my-setup-for-claude-code-codex-notifications (não confirmado na doc oficial).
- Hooks estáveis desde v0.124 (abr/2026) — terceiro: https://codex.danielvaughan.com/2026/04/23/codex-cli-hooks-graduate-stable-v0124-mcp-observation-inline-config/

### Gemini CLI
Fonte: https://geminicli.com/docs/hooks/reference/
- Eventos: `BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `BeforeModel`, `BeforeToolSelection`, `AfterModel`, `SessionStart`, `SessionEnd`, `Notification`, `PreCompress`.
- `Notification` tem `notification_type: "ToolPermission"` mas **não pode responder a permissão** (só observabilidade). Para bloquear, usar `BeforeTool` com `deny`.
- Comuns: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`.
- Config em `settings.json` (`.gemini/`, `~/.gemini/`, `/etc/gemini-cli/`) — https://geminicli.com/docs/hooks/

### GitHub Copilot CLI
Fonte: https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference
- Eventos: `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `userPromptTransformed`, `preToolUse` (`permissionDecision` allow/deny/ask), `permissionRequest` (`behavior` allow/deny, `message`, `interrupt` — só CLI), `postToolUse`, `postToolUseFailure`, `agentStop`, `subagentStart`, `subagentStop`, `errorOccurred`, `preCompact`, `notification` (`message`, `title?`, `notification_type`).
- Payload em camelCase (`sessionId`, `toolName`), com aliases PascalCase/snake_case.
- Config: `.github/hooks/*.json` (repo) e `~/.copilot/hooks/` (usuário), com `"version": 1` — https://code.visualstudio.com/docs/copilot/customization/hooks

**Resumo de paridade:** Claude, Codex e Copilot permitem responder permissão por hook; Gemini só notifica (dá para negar via `BeforeTool`, não para "aprovar o prompt").

## 3. Recursos do macOS 14–26

| Recurso | Situação | Fonte |
|---|---|---|
| Controles de Control Center/menu bar de terceiros (`ControlWidget`, WidgetKit) | Anunciado no macOS 26; controles de apps macOS podem ficar no Control Center ou na menu bar. MacStories relatou falta de suporte de terceiros no lançamento — **confirmar disponibilidade exata no SDK** | https://wwdcnotes.com/documentation/wwdc25-278-whats-new-in-widgets/ , https://9to5mac.com/2025/06/28/new-macos-tahoe-feature-solves-common-complaint/ , https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3 , https://developer.apple.com/documentation/widgetkit/controls-collection |
| Widgets interativos (botões/toggles com App Intents) na mesa do Mac | macOS 14+ (Sonoma) — **não confirmei na doc nesta pesquisa** (conhecimento prévio; validar) | não encontrado (fonte) |
| App Intents / Atalhos | Expor ações ao app Atalhos/Spotlight — **sem fonte buscada nesta rodada** | não encontrado (fonte) |
| Focus filters (`SetFocusFilterIntent`) | **sem fonte buscada nesta rodada** | não encontrado (fonte) |
| Live Activities no Mac | No macOS 26 só aparecem Live Activities **vindas do iPhone** (via iPhone Mirroring); apps Mac não têm Live Activity nativa | https://www.igeeksblog.com/how-to-use-live-activities-on-ipad-mac/ , https://9to5mac.com/2025/06/13/live-activities-are-coming-to-ipad-and-mac-heres-how-theyll-work/ |
| Notificações com ações (`UNNotificationAction`, `UNTextInputNotificationAction`) | API UserNotifications padrão — **sem fonte buscada nesta rodada** | não encontrado (fonte) |

## 4. Ponte para iPhone / Apple Watch sem servidor próprio

- **ntfy**: publicar com `curl -d "msg" ntfy.sh/<topico>`; headers `Title`, `Priority` (1–5), `Tags`; até 3 botões de ação: `view`, `http` (faz requisição — POST por padrão — ao tocar), `broadcast` (só Android), `copy`. Sem cadastro; "o tópico é essencialmente uma senha". Suporte de botões no app iOS: **não encontrado** na página lida. Self-host possível. — https://docs.ntfy.sh/publish/
  - Truque sem servidor: o botão `http` pode fazer POST para **outro tópico ntfy** (tópico de resposta); o Mac assina esse tópico e recebe "allow/deny". Viável pela doc; **não testado**.
- **Pushover**: não pesquisado nesta rodada — **não encontrado**.
- **iCloud KVS**: não pesquisado nesta rodada — **não encontrado**. (Exigiria app iOS companheiro.)
- Concorrente que já faz ponte para celular: **Pushary Isle** (pago, a partir de US$ 9,99/mês, exige conta) — https://pushary.com/ar/mac-notch-app , https://chatgate.ai/en/post/pushary-2

## 5. O que concorrentes JÁ fazem (para não chamar de "novo")

Aprovar/negar permissão pelo popup/notch **não é inovação** — já existe em:
Vibe Notch (https://docsearch.algolia.com/mcp/docs/repo/farouqaldori/vibe-notch), CC Gate (https://awesome.ecosyste.ms/projects/github.com%2Fai-fresh%2Fccgate), Claude Peek — hook bloqueante via Unix socket (https://gh.r-mj.com/teambrilliant/claude-peek), AgentPeek — Claude+Codex, "Always Allow" (https://www.producthunt.com/posts/agentpeek-2), Redlight Greenlight — atalhos de teclado (https://www.producthunt.com/products/redlight-greenlight-for-claude-code), Vibe Island (https://vibeisland.app/claude-code/), Checkpoint via PreToolUse (https://monitoring-git.chickenkiller.com/DouweBos/Checkpoint).
→ Para o ClaudeBar isso é **paridade obrigatória**, não diferencial.

Não verifiquei recurso por recurso de Claude Status Bar, Nudgy, AgentBar e CodexBar; as ideias abaixo foram checadas só contra os resultados acima. "Nenhum concorrente tem" = **não encontrado nas buscas**, não prova de ausência.

---

## 6. Ideias novas (16)

Esforço: P (≤2 dias), M (≤1 semana), G (>1 semana).

### 6.1 Cronômetro de cache do prompt ("responda antes de esfriar")
- **Descrição:** após `Stop`, mostra contagem regressiva na linha da sessão até o cache de prompt provavelmente expirar; ao retomar, mostra quanto custou o "re-aquecimento".
- **Dor:** voltar a uma sessão depois do intervalo encarece o próximo turno sem o usuário saber.
- **Como:** timestamp do `Stop` + TTL configurável; na retomada, ler `prompt_cache_likely_expired` e `estimated_cache_write_usd` do `SessionStart` (`source: resume`) — https://code.claude.com/docs/en/hooks
- **Esforço:** P. **Risco:** TTL real do cache não está no payload — a contagem é estimativa (deixar ajustável); campos exigem v2.1.251+.

### 6.2 Responder ao Claude pelo popup (sem voltar ao terminal)
- **Descrição:** campo de texto no popup/notificação "pronto": o usuário digita a próxima instrução e o Claude continua.
- **Dor:** trocar de janela só para digitar "pode seguir" / "roda os testes".
- **Como:** hook `Stop` com `asyncRewake: true` que espera uma mensagem da fila do app; ao chegar, sai com código 2 e o texto no stderr, acordando o Claude — https://code.claude.com/docs/en/hooks. Notificação com `UNTextInputNotificationAction` (fonte não buscada).
- **Esforço:** M. **Risco:** alto — o texto entra como *system reminder*, não como mensagem do usuário (semântica diferente); precisa protótipo. Processo em background por sessão.

### 6.3 Caixa de entrada unificada de permissões multi-agente
- **Descrição:** uma fila só de pedidos de permissão de Claude, Codex e Copilot, com atalho de teclado global.
- **Dor:** vários agentes em terminais diferentes, cada um travado esperando.
- **Como:** os três têm `PermissionRequest` com `decision.behavior` allow/deny (Claude: https://code.claude.com/docs/en/hooks ; Codex: https://learn.chatgpt.com/docs/hooks.md ; Copilot: https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference). Gemini: só aviso (`Notification` ToolPermission) — https://geminicli.com/docs/hooks/reference/
- **Esforço:** G. **Risco:** formatos ligeiramente diferentes (camelCase no Copilot); AgentPeek já cobre Claude+Codex — diferencial é Copilot + fila única.

### 6.4 Sugestão inteligente de regra permanente
- **Descrição:** depois de aprovar o mesmo padrão N vezes (ex.: `Bash(npm test)`), o app sugere "transformar em regra" e grava com um clique.
- **Dor:** fadiga de aprovação.
- **Como:** contar aprovações por `tool_name`+padrão; aplicar via `updatedPermissions` (`addRules`, destino `localSettings`/`projectSettings`) ecoando `permission_suggestions` — https://code.claude.com/docs/en/hooks
- **Esforço:** M. **Risco:** médio — regra ampla demais = brecha de segurança; mostrar o texto exato da regra antes de gravar.

### 6.5 Radar de comandos perigosos
- **Descrição:** marca em vermelho e exige confirmação no Mac para `rm -rf`, `git push --force`, `DROP TABLE`, mesmo em modos permissivos.
- **Dor:** agente em `acceptEdits`/auto fazendo algo irreversível sem você olhar.
- **Como:** `PreToolUse` → `permissionDecision: "ask"`/`"deny"` com lista de padrões; `permission_mode` vem no payload — https://code.claude.com/docs/en/hooks
- **Esforço:** P. **Risco:** falsos positivos; regex é heurística (`ponytail:` lista fixa, evoluir para configurável).

### 6.6 Resumo de ausência ("enquanto você estava fora")
- **Descrição:** ao desbloquear o Mac/voltar da tela de descanso, um card mostra o que cada sessão fez (tools usadas, arquivos editados, última mensagem).
- **Dor:** voltar do almoço com 4 sessões e não saber o estado de nenhuma.
- **Como:** acumular `PostToolUse` (tool + arquivo) e `last_assistant_message` do `Stop` — https://code.claude.com/docs/en/hooks ; disparo via notificações de sessão/tela do `NSWorkspace` (fonte não buscada).
- **Esforço:** M. **Risco:** baixo; volume de eventos (limitar por sessão).

### 6.7 Alerta de cota com hora de retomada
- **Descrição:** ícone muda para "pausado por cota" e mostra quando a sessão volta sozinha.
- **Dor:** achar que a sessão travou quando na verdade bateu limite.
- **Como:** `Notification` com matchers `quota_auto_resume_fired` / `quota_auto_resume_stale` / `quota_auto_resume_disabled`; `StopFailure` com tipo de erro — https://code.claude.com/docs/en/hooks
- **Esforço:** P. **Risco:** payload exato desses tipos **não encontrado**; precisa capturar exemplo real.

### 6.8 Responder elicitações MCP pelo popup
- **Descrição:** quando um servidor MCP pede um dado (ex.: escolher conta, confirmar), o formulário aparece no popup.
- **Dor:** elicitações travam a sessão em silêncio.
- **Como:** hook `Elicitation` devolvendo `action: accept` + `content` — https://code.claude.com/docs/en/hooks
- **Esforço:** M. **Risco:** schema do formulário varia por servidor; renderizar dinamicamente.

### 6.9 Medidor de contexto e compactações
- **Descrição:** barra de "contexto usado" por sessão e contador de compactações (aviso "compactou 3x — considere nova sessão").
- **Dor:** qualidade cai após várias compactações e o usuário não percebe.
- **Como:** `PreCompact`/`PostCompact` (`manual`/`auto`) e `context_tokens` no `SessionStart` de resume — https://code.claude.com/docs/en/hooks ; para Codex, `token_usage` no `PostModelRequest` — https://learn.chatgpt.com/docs/hooks.md
- **Esforço:** P. **Risco:** contexto contínuo só existe em resume (Claude); valor em tempo real **não encontrado** nos hooks.

### 6.10 Focus filter: "Modo Reunião / Modo Foco"
- **Descrição:** no Foco "Trabalho Profundo" só permissões tocam; no "Reunião" tudo vira silencioso e entra no resumo de ausência.
- **Dor:** notificações de "pronto" interrompendo.
- **Como:** App Intents `SetFocusFilterIntent` (fonte não buscada — validar disponibilidade no macOS 14).
- **Esforço:** M. **Risco:** exige target com App Intents; app SPM puro pode precisar de bundle/Xcode project.

### 6.11 Controle no Control Center / menu bar (macOS 26)
- **Descrição:** toggle "Piloto automático para leituras" e botão "Aprovar próximo pedido" no Control Center.
- **Dor:** acesso rápido sem abrir menu.
- **Como:** `ControlWidget` (WidgetKit) — controles de apps macOS no Control Center ou menu bar — https://wwdcnotes.com/documentation/wwdc25-278-whats-new-in-widgets/ , https://developer.apple.com/documentation/widgetkit/controls-collection
- **Esforço:** M. **Risco:** alto — exige extensão WidgetKit (app bundle assinado, não SPM puro); disponibilidade de terceiros no lançamento questionada — https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3

### 6.12 Widget interativo de mesa
- **Descrição:** widget com lista de sessões e botões "Marcar visto"/"Abrir terminal".
- **Dor:** status visível sem clicar no menu.
- **Como:** WidgetKit + App Intents com botões (macOS 14+; fonte não buscada).
- **Esforço:** M. **Risco:** mesmo do 6.11 (extensão + App Group para compartilhar estado).

### 6.13 Atalhos (App Intents): "Quantas sessões me esperam?"
- **Descrição:** ações no app Atalhos/Siri: listar sessões aguardando, aprovar a última permissão, marcar tudo como visto; usar em automações.
- **Dor:** integrar com rotinas (ex.: Stream Deck, automação ao conectar fone).
- **Como:** `AppIntent` + `AppShortcutsProvider` (fonte não buscada).
- **Esforço:** P–M. **Risco:** aprovar permissão por Siri sem ver o comando = risco de segurança; restringir a ações de leitura ou exigir confirmação.

### 6.14 Aprovar pelo iPhone/Watch sem servidor e sem conta (ntfy)
- **Descrição:** pedido de permissão vira notificação no celular com botões Permitir/Negar; resposta volta ao Mac.
- **Dor:** saiu de perto do Mac e o agente travou. Concorrente equivalente (Pushary) é pago e exige conta — https://pushary.com/ar/mac-notch-app
- **Como:** publicar em `ntfy.sh/<topico-secreto>` com ação `http` que faz POST em `ntfy.sh/<topico-resposta>`; o Mac assina o tópico de resposta e devolve `decision.behavior` ao hook (timeout de 600 s) — https://docs.ntfy.sh/publish/ , https://code.claude.com/docs/en/hooks
- **Esforço:** M. **Risco:** alto — tópico público = qualquer um que adivinhe pode aprovar: assinar resposta com HMAC/nonce por pedido; suporte a botões no app iOS **não encontrado**; Watch só se a notificação espelhar com ações (não verificado). Opt-in, desligado por padrão.

### 6.15 Live Activity no Mac via iPhone (futuro, depende de app iOS)
- **Descrição:** sessão longa vira Live Activity no iPhone, que o macOS 26 mostra na menu bar do Mac e no Watch.
- **Dor:** acompanhar progresso fora do Mac.
- **Como:** só possível com app iOS companheiro; macOS 26 exibe Live Activities do iPhone na menu bar via iPhone Mirroring — https://www.igeeksblog.com/how-to-use-live-activities-on-ipad-mac/
- **Esforço:** G. **Risco:** alto (novo app iOS, push ActivityKit exige servidor APNs). Provavelmente fora de escopo — registrar e não fazer agora.

### 6.16 Hook HTTP direto (sem binário)
- **Descrição:** ClaudeBar abre um servidor `localhost` e o `settings.json` usa `type: "http"`; elimina o `claudebar-hook` para eventos não bloqueantes e simplifica instalação.
- **Dor:** instalação/atualização do binário de hook.
- **Como:** `{"type":"http","url":"http://localhost:PORT/..."}`; 2xx vazio = sucesso; falha de conexão = erro não bloqueante (app fechado não trava o Claude) — https://code.claude.com/docs/en/hooks
- **Esforço:** M. **Risco:** médio — porta local exposta a outros processos (exigir token via `headers` + `allowedEnvVars`); quando o app está fechado, o estado em arquivo (modelo atual) se perde — talvez manter o binário como fallback. Não é ideia visível ao usuário, mas habilita 6.2/6.3/6.8.

---

## 7. Priorização sugerida (inovação × esforço)

1. Quick wins (P): 6.1 cache, 6.5 radar, 6.7 cota, 6.9 contexto.
2. Diferenciais fortes (M): 6.2 responder pelo popup (prototipar primeiro), 6.4 regra inteligente, 6.6 resumo de ausência, 6.14 ntfy.
3. Plataforma Apple (M, exige bundle com extensões): 6.10, 6.11, 6.12, 6.13 — decidir antes se o projeto sai de SPM puro para app bundle com targets de extensão.
4. Adiar: 6.15 (precisa app iOS + APNs), 6.3 completo (Copilot/Gemini) até haver usuários desses CLIs.

Paridade obrigatória antes de inovar: aprovar/negar permissão pelo popup (`PermissionRequest`) — todos os concorrentes notch já têm (seção 5).

## 8. Lacunas desta pesquisa (validar antes de implementar)
- Payload exato de `Stop`, `SessionEnd`, `PreCompact` e campos `title`/`notification_type` do `Notification` (Claude): ler offset 200000+ de https://code.claude.com/docs/en/hooks
- Disponibilidade mínima de `ControlWidget` no macOS e widgets interativos/Focus filters: doc Apple não retornou conteúdo via fetch.
- Suporte a botões de ação no ntfy para iOS; Pushover; iCloud KVS.
- Recursos detalhados de Claude Status Bar, Nudgy, AgentBar, CodexBar (não verificados um a um).
