# 1b — Como os concorrentes monitoram uso e limites do Claude Code

Pesquisa feita em 2026-11-15. Claude Code local: v2.1.325. Cada afirmação traz a fonte ao lado. Quando a fonte é um agregador ou uma reportagem e não o projeto, o texto avisa. "Não encontrado" quer dizer que procurei e não achei.

---

## 1. As quatro fontes de dados possíveis

| # | Fonte | Documentada? | Rede? | Credencial? | Lê conversa? |
|---|---|---|---|---|---|
| A | **JSON da statusline** (stdin do comando `statusLine`) | **Sim, oficial** | Não | Não | Não, se o bridge ignorar `transcript_path` |
| B | **Endpoint OAuth** `api.anthropic.com/api/oauth/usage` com o token do Keychain | Não, API interna | Sim | **Sim**, o token OAuth do Claude Code | Não |
| C | **Cookie do claude.ai** (`sessionKey`) em `claude.ai/api/organizations/{orgId}/usage` | Não, API interna | Sim | **Sim**, o cookie de sessão | Não |
| D | **JSONL** em `~/.claude/projects/**/*.jsonl` | Só a existência e a retenção. O formato não é documentado | Não. Pode haver rede para buscar preços | Não | **Sim.** O conteúdo fica na mesma linha que o `usage` |
| E | PTY rodando `claude` e enviando `/usage` | Comando oficial; o parsing da tela não | Indireta (o CLI chama a API) | Usa a sessão do próprio CLI | Não, mas cria uma sessão |
| F | OpenTelemetry (`claude_code.cost.usage`, `claude_code.token.usage`) | Sim, oficial | Precisa de um coletor OTLP (pode ser localhost) | Não | Não por padrão |

### A. Statusline: o que a documentação oficial confirma
Fonte: https://code.claude.com/docs/en/statusline

- **Rate limits: sim.** Campos `rate_limits.five_hour.used_percentage` e `rate_limits.seven_day.used_percentage` (0–100), e `rate_limits.five_hour.resets_at` e `rate_limits.seven_day.resets_at` (epoch em segundos).
- **Gateway:** `rate_limits.spend_limit.{used_percentage,resets_at,used_usd,limit_usd,period}`. Atrás de um Claude apps gateway; requer v2.1.251+ (dólares só a partir de v2.1.284+).
- **Quando aparece:** `rate_limits` "appears only for claude.ai Pro, Max, and Ultra subscribers, or behind a Claude apps gateway…". Só aparece depois da primeira resposta da API na sessão. Cada janela pode estar ausente sozinha. O Claude Code descarta a janela quando passa o `resets_at`.
- **Custo: sim.** `cost.total_cost_usd`, que é uma estimativa calculada no cliente a preço de tabela, "May differ from your actual bill", e volta a $0 no `/clear`. Também há `cost.total_duration_ms`, `cost.total_api_duration_ms` e `cost.total_lines_added/removed`.
- **Contexto:** `context_window.used_percentage`, `remaining_percentage`, `context_window_size`, `total_input_tokens`, `total_output_tokens` e `current_usage`.
- Também traz `session_id`, `transcript_path`, `model.*`, `workspace.*`, `prompt_cache` (v2.1.251+), `effort.level` e `pr.*`.
- **Quando roda:** no início ou no resume da sessão, a cada nova mensagem do assistente, depois do `/compact`, quando muda o modo de permissão, quando um `refreshInterval` expira e quando uma janela de rate limit chega ao `resets_at`. Há debounce de 300 ms e o script em execução é cancelado se outro update chega. A documentação avisa que esses gatilhos "can go quiet when the main session is idle".
- "The status line runs locally and does not consume API tokens."
- **Limitação estrutural:** existe um único `statusLine.command`. Quem já tem statusline precisa de encadeamento: o bridge repassa o stdin ao comando anterior e devolve o stdout dele. É o que o CC Usage Tracker faz (ver §2.6).
- **Hooks não servem para isso.** Os campos comuns de input dos hooks são `session_id`, `prompt_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `permission_mode`, `effort` e `hook_event_name`. Nenhum campo de rate limit, custo ou tokens foi encontrado nos primeiros 100 mil caracteres da página (https://code.claude.com/docs/en/hooks). Implicação: o `claudebar-hook` atual do projeto (em `Sources/claudebar-hook/main.swift`) não recebe limites. É preciso um bridge de statusline separado.

### B. Endpoint OAuth (`/api/oauth/usage`)
- **Endpoint e headers:** `GET https://api.anthropic.com/api/oauth/usage?cedar_ember=1`, com `Authorization: Bearer <access_token>` e `anthropic-beta: oauth-2025-04-20`. O token precisa do escopo `user:profile`. As credenciais vêm de `~/.claude/.credentials.json` ou do item de Keychain `Claude Code-credentials`. Documentado pelo CodexBar em https://github.com/steipete/CodexBar/blob/main/docs/claude.md
- **Política oficial da Anthropic:** "developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow". E: "Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice." (https://code.claude.com/docs/en/legal-and-compliance). Ler o token do Keychain e mandá-lo a um endpoint é, no mínimo, zona cinzenta diante desse texto.
- **Contexto (reportagens, não fonte primária):** checagens no servidor contra tokens de assinatura usados fora das ferramentas oficiais começaram em jan/2026, os termos foram formalizados em fev/2026 e a aplicação começou em abr/2026. Fontes: https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access e https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/. O foco era o uso para inferência ("harnesses"). Não encontrei menção específica a apps que só leem o uso.
- **Estabilidade:** há issues sobre 429 persistente nesse endpoint, inclusive com `retry-after: 0` (relatos de usuários espelhados em claudeissues.com; o original não foi verificado):
  - https://claudeissues.com/issue/30930-bug-api-oauth-usage-endpoint-returns-persistent-429-for-claude-max-users-retry-a
  - https://claudeissues.com/issue/31637-bug-api-oauth-usage-endpoint-aggressively-rate-limits-making-usage-monitoring-un
  - https://claudeissues.com/issue/31021-oauth-usage-api-api-oauth-usage-returns-persistent-429-rate-limit
- **Keychain:** o Claude Code reescreve o próprio item de credencial, e isso pode remover a autorização de partição do app terceiro. Então "Always Allow" não garante acesso (CodexBar #3798, citado em docs/claude.md). Na v2.1.x o item pode ter só `mcpOAuth`, sem `claudeAiOauth` (#1844, mesma fonte).
- **Contas sem limite:** em contas Free, `five_hour` e `seven_day` voltam `null`. Alguns planos Education ou gerenciados por organização não trazem campos numéricos (mesma fonte).

### C. Cookie do claude.ai
- Endpoints `https://claude.ai/api/organizations` e `.../organizations/{orgId}/usage?cedar_ember=1`, além de `overage_spend_limit`, `prepaid/credits`, `/api/account` e `subscription_details` (CodexBar docs/claude.md).
- **Riscos:** exige o cookie de sessão completo do navegador, que é uma credencial de conta inteira. É exatamente o "collect, store … session tokens" proibido pela política citada em §B. O Cloudflare às vezes mostra um challenge (CodexBar docs/claude.md). Em Linux não há importação automática de cookie.

### D. JSONL em `~/.claude/projects`
- **Documentação oficial:** "Claude Code clients store session transcripts locally in plaintext under `~/.claude/projects/` for 30 days by default … Adjust the period with `cleanupPeriodDays`" (https://code.claude.com/docs/en/data-usage). Por padrão, o histórico de custo tem no máximo cerca de 30 dias.
- **Verificação local (v2.1.325):**
  - Cada linha `type:"assistant"` tem `message.usage` (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `cache_creation.ephemeral_1h/5m`, `server_tool_use`, `service_tier`, `iterations`) e **também `message.content`**, o texto da conversa, na mesma linha JSON.
  - Também existe uma linha `type:"cost-state"` com `totalCostUSD`, `modelUsage`, `totalAPIDuration` e `totalLinesAdded`. Esse tipo de linha **não é documentado**.
  - Nenhum campo de rate limit foi encontrado no JSONL.
- **Precisão:** o arquivo só tem tokens. O custo é estimado com tabela de preços. Ferramentas deduplicam chunks de streaming por `message.id + requestId` (CodexBar docs/claude.md). ccusage avisa: "Costs are estimates and may not reflect actual billing" e "API calls for tools like Web Search are not included" (https://ccusage.com/guide/). Não dá para obter o **% do limite de 5h/7d** porque a Anthropic não publica o teto em tokens.
- **Conflito com a promessa:** para ler `usage` é preciso abrir e decodificar uma linha que contém a conversa. Mesmo descartando `content`, o app "lê suas conversas" em sentido técnico.

### E. PTY com `/usage`
- O CodexBar roda `claude` num PTY com `--allowed-tools ""` e `--strict-mcp-config`, envia `/usage`, faz o parsing da tela e apaga os `.jsonl` gerados no diretório de sondagem (docs/claude.md).
- **Issues:** timeout de 20 s em planos que só têm limite semanal (#5066), e um watchdog com race de `setpgid` (#4829) (https://github.com/steipete/CodexBar/issues?q=is%3Aissue+claude).
- É frágil, porque depende do layout da TUI, e cria sessões do CLI.

### F. OpenTelemetry
- Métricas `claude_code.cost.usage` (USD) e `claude_code.token.usage` (por tipo), habilitadas com `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp` e `OTEL_EXPORTER_OTLP_ENDPOINT` (https://code.claude.com/docs/en/monitoring-usage).
- O prompt não é registrado por padrão (`OTEL_LOG_USER_PROMPTS`).
- Não encontrei métrica de rate limit (5h/7d) na parte lida da página.
- Exige que o usuário exporte variáveis de ambiente e que o app mantenha um receptor OTLP local. Cobre custo, não limite.

---

## 2. Concorrentes, um a um

### 2.1 CodexBar (steipete)
https://github.com/steipete/CodexBar · MIT · macOS 14+ · Swift 6.2 · tem CLI e app Linux (Qt)
- **Fontes:** no app, a ordem é OAuth (B), depois PTY (E), depois Web (C). No CLI, Web e depois PTY. Com Admin API key, ela tem precedência. Custo vem do JSONL (D) com cache em `~/Library/Caches/CodexBar/cost-usage/claude-v6.json` (docs/claude.md).
- **Privacidade declarada:** não varre o disco. Cookies são opt-in. O acesso ao Keychain em background "fails or skips rather than prompting", e existe "Disable Keychain access" (README).
- **Funções:** burndown, countdown de reset, notificações, widgets, `codexbar cost --provider claude`, vários provedores.
- **Issues de Claude** (https://github.com/steipete/CodexBar/issues?q=is%3Aissue+claude):
  - Credenciais: token OAuth em cache vencido gera 401 em loop (#5018); `.credentials.json` vazio mascara o item válido do Keychain (#5043); prompts repetidos de Chrome Safe Storage (#4912); uma falha com Keychain desligado trava o background (#4907).
  - Pedidos: "Show Claude limit resets" (#5073), custo por sessão (#4930), previsão de ritmo/pace (#4850).
  - Uma issue chamada "Get Claude working and stop adding new features" (#5056) indica que a **confiabilidade da fonte Claude é a dor nº 1**.
- **Precisão:** % vindo do servidor (OAuth/Web) é exato. O custo é estimado.

### 2.2 AgentLimits (Nihondo)
https://github.com/Nihondo/AgentLimits · MIT · macOS Sonoma+ · "In Development"
- **Fontes:** `https://claude.ai/api/organizations/{orgId}/usage` (C), com login num WebView embutido. Tokens e custo vêm de `npx -y ccusage@latest claude daily` (D, mais download via npm). Oferece um script de statusline que **lê o snapshot do app** (direção inversa: o app alimenta a statusline).
- **Avisos do próprio README:** internal APIs "may change without notice"; "Claude Code logins may require multiple attempts".
- **Extras:** "Pacemaker" (uso versus tempo decorrido da janela) e "Wake Up scheduler", que roda `claude -p "hello"` para iniciar a janela de 5h.
- **Issues** (https://github.com/Nihondo/AgentLimits/issues?q=is%3Aissue):
  - Bugs: weekly preso em 0 (#27), limites sem atualizar no menu bar (#15), sem dado de 5h (#14), CPU alta do claude.ai (#17), confusão entre usado e restante, "93% but not 7%" (#10).
  - Pedidos: esconder o 5h quando indisponível (#26), contraste do texto no menu bar (#16, #5), widget parecido com o site oficial (#12), customizar o comando ccusage (#22), mais provedores (#21).

### 2.3 Usagebar
https://usagebar.com · fechado · US$9 vitalício, com tier grátis · lançado no Product Hunt em 23/01/2026 (https://www.producthunt.com/products/usagebar)
- **Fonte:** "reads the OAuth credentials Claude Code already stores in your macOS Keychain and calls Anthropic's usage endpoint" (B). Usa logs locais .json como fallback e para usuários de API (resumo da busca a partir do Product Hunt e de https://feedbagel.com/post/usagebar-macos-menu-bar-app-for-tracking-claude-code-usage-limits).
- **Privacidade declarada:** "no data leaves your machine other than the call to Anthropic" (usagebar.com).
- **Relato de usuário:** um comentário no Product Hunt diz que a % no menu bar parou de atualizar (resumo da busca; não consegui ver o comentário original).

### 2.4 ClaudeUsageBar
O nome é ambíguo, com vários repositórios (resultado de busca):
- **Artzainnn/ClaudeUsageBar** (https://github.com/Artzainnn/ClaudeUsageBar) · MIT · macOS 12+
  - **Fonte:** o usuário copia **o header Cookie inteiro** da requisição "usage" no DevTools de claude.ai/settings/usage (C). O README diz que usa "Claude.ai's internal API endpoints which may change without notice".
  - **Onde o cookie fica guardado:** não encontrado.
  - **Funções:** atualiza a cada 5 min; ícone verde, amarelo ou vermelho; notificações em 25/50/75/90%; atalho Cmd+U; uso semanal do Sonnet.
- **sam-pop/ClaudeUsageBar:** lê credenciais do Keychain (B). Só via resumo de busca, não verifiquei.
- **Blimp-Labs/claude-usage-bar** e **mnapoli/claude-usage-bar** (pip): 5h e 7d. O mnapoli "authenticates through your existing Claude Code login" (resumo de busca).

### 2.5 TokenBar
O nome também é ambíguo:
- **shrivara/token-bar** (https://github.com/shrivara/token-bar) · MIT · macOS 14+
  - **Fonte:** lê `~/.claude/projects/**/*.jsonl` (D) com watcher e fallback de 60 s. Preços vêm de um snapshot do models.dev embutido; **não busca preço online**. Mostra custo "API-equivalent, not your subscription bill" e marca com `~` os modelos sem preço.
  - **Rede e privacidade:** "does not upload usage data or send telemetry". Tem modo SSH opcional, e o cache remoto "can include session text".
  - Não mostra % de limite.
- **tokenbar.site** (fechado, US$15): a página não explica de onde vêm os dados (https://tokenbar.site).

### 2.6 CC Usage Tracker (pedroprates/claude-code-usage)
https://github.com/pedroprates/claude-code-usage · alpha · macOS 14+ · requer `jq`
- **Fonte:** **statusline bridge (A)**. O bridge fica em `~/.claude/cc-usage-bridge.sh`, lê `rate_limits.five_hour` e `rate_limits.seven_day`, grava de forma atômica em `~/.claude/cc-usage-tracker/state.json`, **repassa o payload ao statusline anterior e devolve o stdout dele**, e só grava quando `rate_limits` vem no payload. Com várias sessões, mantém o maior % por janela, casando pelo `resets_at`.
- "does not parse JSONL logs". O % vem do `used_percentage` da Anthropic sem alteração.
- **Rede:** só um fetch opcional do saldo do OpenRouter. A chave fica no Keychain do próprio app.
- **Ressalvas do README:** os percentuais são "approximations, not authoritative cutoff signals". O README diz MIT, mas "No `LICENSE` file exists".
- **É o modelo mais próximo da promessa do ClaudeBar.**

### 2.7 ccusage (CLI)
https://github.com/ryoppippi/ccusage · https://ccusage.com/guide/
- **Fonte:** JSONL (D) em `~/.config/claude/projects/` e `~/.claude/`. Aceita `CLAUDE_CONFIG_DIR` com vários caminhos separados por vírgula (guias não oficiais; o README não confirma).
- **Comandos:** `daily`, `weekly`, `monthly`, `session`, `blocks` (janelas de 5h estimadas localmente) e `statusline` (beta).
- **Flags:** `--offline` ("pre-cached pricing data"), `--json`, `--since/--until`, `--breakdown`, `--instances`, `--project` (README).
- **Rede:** preços vêm do LiteLLM. Builds embutem um snapshot; segundo fontes secundárias, há atualização em runtime, a menos que se use `--offline`. **Não confirmei na fonte primária.**
- **Precisão:** "Costs are estimates…", e não inclui Web Search.
- **Limites (%):** o `blocks` estima a janela; não é o % oficial.

### 2.8 Extensão Raycast "Claude Code Usage (ccusage)" (nyatinte)
https://www.raycast.com/nyatinte/ccusage · 14.985 instalações
- **Fontes:** roda ccusage via `npx` (D; precisa de internet no primeiro uso). "Usage Limits" (5h, 7d e por modelo) lê o token OAuth do Keychain e de `~/.claude/.credentials.json` e chama o endpoint de uso (B). Respeita `retry-after`.
- O changelog de 04/11/2026 traz "Support plans without a 5-hour limit".
- Outras extensões, citadas só em resultado de busca e não verificadas: ClaudeCast (qazi0), Claude Usage Tracker (Ahmosys, Keychain), Tokemon.

### 2.9 Homônimo: tddworks/ClaudeBar
https://github.com/tddworks/ClaudeBar
- Apache-2.0, cerca de 1,6 mil estrelas, macOS 15+, `brew install --cask claudebar`. Multi-provedor, com forecasts, notch, webhooks e o URL scheme `claudebar://`.
- A fonte de dados de Claude não aparece no README.
- Há outros repositórios chamados "ClaudeBar" (BBerthod, chiliec, EtanHey), segundo a busca.
- **Risco de nome:** colisão no Homebrew e no URL scheme. Além disso, a página oficial diz que não se pode usar "the Claude Code or Anthropic names or logos as part of your own product … name" (https://code.claude.com/docs/en/legal-and-compliance). O trecho trata de produtos que embarcam o Claude Code; para o resto vale https://www.anthropic.com/legal/trademark-guidelines. Precisa de decisão humana.

---

## 3. O que os usuários pedem (consolidado das issues)
1. **Confiabilidade acima de features:** CodexBar #5056, #5018, #5043; AgentLimits #15, #27; o relato do Usagebar.
2. **Lidar com janelas ausentes:** plano sem 5h ou só semanal (AgentLimits #26; CodexBar #5066; changelog do Raycast de 04/11/2026). Exibir "indisponível" em vez de 0%.
3. **Reset e countdown visíveis:** CodexBar #5073; AgentLimits #4.
4. **Ritmo e previsão (pace):** CodexBar #4850; o "Pacemaker" do AgentLimits; os forecasts do tddworks.
5. **Usado versus restante sem ambiguidade:** AgentLimits #10.
6. **Legibilidade no menu bar:** contraste e cor (AgentLimits #16, #5).
7. **Custo por sessão:** CodexBar #4930.
8. **Zero prompts de Keychain:** CodexBar #4912, #4907.

---

## 4. Conclusão: a abordagem mais segura e estável para "sem rede por padrão e não lê suas conversas"

**Recomendação: statusline bridge (fonte A) como única fonte padrão.**

Por quê:
- É o **único caminho documentado oficialmente** que entrega o % de 5h e 7d e o `resets_at` exatos, vindos do servidor (https://code.claude.com/docs/en/statusline).
- **Zero rede, zero credencial, zero Keychain.** Não esbarra na proibição de "collect, store, or intermediate … credentials or session tokens" (https://code.claude.com/docs/en/legal-and-compliance).
- **Não lê conversa:** o bridge recebe só o JSON da statusline. Deve ignorar `transcript_path` e nunca abri-lo.
- Também traz `cost.total_cost_usd` e `session_id`, o que dá custo por sessão (pedido do CodexBar #4930) **sem abrir JSONL**: basta acumular por `session_id`, sabendo que zera no `/clear`.
- Já tem precedente funcionando: CC Usage Tracker (§2.6).

Cuidados obrigatórios no design:
1. **Encadear o statusline existente:** salvar o `statusLine.command` anterior, repassar o stdin e devolver o stdout. Fazer backup e permitir desinstalar restaurando o original. Pedir consentimento antes de editar `~/.claude/settings.json`.
2. **Dados velhos:** só atualiza com sessão ativa. Mostrar "atualizado há X min". Após o `resets_at`, mostrar a janela como resetada (o Claude Code também descarta a janela nesse momento). Sugerir `refreshInterval` como opcional.
3. **Ausência:** API key, Free ou primeira chamada ainda não feita significam sem `rate_limits`. Mostrar "indisponível, com motivo", não 0%.
4. **Várias sessões:** usar o maior % por janela, agrupando por `resets_at` (mesma estratégia do CC Usage Tracker).
5. **Bridge rápido e à prova de falha:** o Claude Code cancela o script se outro update chega, então a escrita precisa ser atômica (tmp + rename). Sem `jq` como dependência: usar um binário Swift, como o `claudebar-hook` atual.
6. **Versão mínima:** `rate_limits` exige uma versão recente do Claude Code (a versão exata em que o campo surgiu não foi encontrada). Detectar e avisar.

Fontes que **não** devem ser padrão:
- **B (OAuth/Keychain) e C (cookie):** API não documentada, que viola o espírito ou a letra da política de credenciais, exige rede, gera prompts e quebra de ACL no Keychain, e sofre com 429 persistente. Se algum dia entrar, que seja opt-in explícito, com aviso.
- **D (JSONL):** contradiz "não lê suas conversas", porque `content` está na mesma linha que `usage`; o custo é só estimado e o histórico é cortado em cerca de 30 dias. Se entrar para histórico de custo, deve ser **opt-in**, com parsing que descarta `content` sem guardá-lo, preços embutidos (como o token-bar, sem rede) e texto honesto na UI.
- **E (PTY `/usage`):** frágil e cria sessões. Evitar.
- **F (OTel):** só como opt-in avançado. Não traz limites.

---

## 5. Pontos não encontrados ou não verificados
- A versão exata do Claude Code que introduziu `statusline.rate_limits`: não encontrado.
- Se o ccusage busca preços online por padrão: só fontes secundárias.
- Onde o Artzainnn/ClaudeUsageBar guarda o cookie: não encontrado.
- A fonte de dados do tddworks/ClaudeBar e do tokenbar.site: não encontrado no README nem no site.
- Uma posição oficial da Anthropic sobre apps que **só leem uso** com token OAuth: não encontrado. Só existe a regra geral sobre credenciais.
- Os 429 do `/api/oauth/usage`: vistos só via espelho claudeissues.com; o issue original no GitHub não foi aberto.
