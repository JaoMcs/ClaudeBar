# Validação — lente RISCO

Avaliador: segurança/privacidade, marca, dependência de interface instável do Claude Code, manutenção e chance de quebrar a sessão do usuário.
Fontes: `README.md`, `scripts/install.sh`, `Sources/ClaudeBar/AgentsProbe.swift`, `planning/01-pesquisa/*`, `planning/02-painel/PAINEL.md`.

## Promessas que servem de régua

1. **Sem rede por padrão.** Qualquer ideia que abra conexão sai do padrão ou é descartada.
2. **Não lê conversas.** Nada de abrir `transcript_path` ou `~/.claude/projects/**/*.jsonl`.
3. **Diretório `~/.claude/claudebar` 0700, arquivos 0600, `sessionId` sanitizado.**
4. **Sem shell com interpolação.** `Process` com argumentos separados.
5. **Hook nunca quebra a sessão** (fail-open, sai limpo).

## Riscos transversais (valem para várias ideias)

| Risco | Onde aparece | Nível | Mitigação |
|---|---|---|---|
| **Marca "Claude" no nome do produto.** A página legal do Claude Code proíbe usar "the Claude Code or Anthropic names or logos as part of your own product … name"; para o resto valem as trademark guidelines da Anthropic. | A1, A3, A7, qualquer distribuição pública | **Alto** para distribuir (Homebrew, .dmg público, site). Baixo para uso pessoal. | **Decisão humana antes de distribuir:** renomear (ex.: nome neutro + "for Claude Code" só na descrição) ou consultar as guidelines. Ícone nunca usa o logotipo/asterisco da Anthropic nem a cor-marca como elemento principal. |
| **`claude agents --json` não é contrato documentado.** O app já depende dele para o contador (`AgentsProbe.swift`). | Contador, subagentes, C6, C15 | Médio (já existe) | Decodificação tolerante (campos opcionais, ignorar desconhecidos), fallback para o estado dos hooks (já existe), teste com fixture de saída real, aviso "fonte indisponível" no status em vez de contador zerado. |
| **Editar `~/.claude/settings.json`.** O `install.sh` atual **substitui** hooks existentes dos 4 eventos e grava o caminho absoluto do bundle no comando. | A4, A5, A6, D1, F1, F4, I5 | **Alto** hoje, médio com mitigação | Merge que só acrescenta entradas próprias (marcadas pelo caminho do `claudebar-hook`), nunca remove as do usuário; validar o JSON antes e depois; escrita atômica; backup com timestamp; mostrar diff e pedir consentimento; nunca editar em atualização sem diff. |
| **Hooks síncronos a mais = latência em cada passo.** Cada hook `command` é um processo por evento; `PreToolUse`/`PostToolUse` disparam em toda chamada de ferramenta. | C4, C11, C12, B6 | Médio | Só os eventos necessários; `async: true` onde não há decisão; binário Swift sem dependências (já é); medir o tempo do hook em teste. |
| **Hook que bloqueia esperando o app** (decisão de permissão). Timeout padrão 600 s. Se o app travar, a sessão fica parada até 10 min. | B6, B7, B8, F3, G1 | **Alto** | Se feito: timeout curto, fail-open devolvendo "sem decisão" (o terminal pergunta normalmente), canal local autenticado. Ver B6. |
| **Canal local (porta HTTP / socket) como superfície de ataque.** Qualquer processo do mesmo usuário poderia forjar eventos ou, pior, aprovar permissões. | B6, B7, F3, H7 | Médio a alto | Manter o canal atual por arquivos 0600 (só leitura do mesmo usuário). Se houver socket: Unix socket em diretório 0700, sem porta TCP. Nunca aceitar decisão por canal sem prova de que veio da UI. |
| **Permissões TCC (Automation, Accessibility).** Prompts assustam o usuário de privacidade e o macOS pode revogar. | B1, B2, B5, E3 | Médio | Caminho base sem permissão (`NSRunningApplication.activate` pelo PID do processo pai); Automation só opt-in, por terminal, explicando por quê; fallback honesto "trouxe a janela, não a aba". |
| **Credenciais/OAuth do Claude Code.** A política diz que terceiros não podem "collect, store, or intermediate Claude.ai credentials or session tokens". Endpoint `/api/oauth/usage` é interno, com 429 persistente relatado e quebra de ACL do Keychain. | Tentação em D1–D6, C9, C13 | **Alto** | Proibido no projeto. Limites só via statusline (documentada, local). |
| **Persistir conteúdo em disco** (caminhos, comandos, mensagens). | E9, I1, I2, A14, N2, N20 | Médio | Estado só em memória ou nos arquivos de sessão que já são apagados no `SessionEnd`; nada de histórico persistente por padrão. |

## Avaliação por ideia

Escala de nota (1–5) = valor ajustado ao risco/custo. Veredito: **fazer**, **depois**, **descartar**.

### A. Produto pronto

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| A1 Instalador .dmg | Baixo técnico; **alto de marca** se publicado com o nome atual | .dmg sem assinatura reproduz o alerta de Gatekeeper; nome "ClaudeBar" exposto publicamente | Só junto com A2; resolver o nome antes; publicar SHA-256 | 5 | fazer |
| A2 Assinado + notarizado | Baixo | Precisa de Apple Developer ID (US$ 99/ano, conta do usuário); hardened runtime pode afetar `Process`/`proc_pidpath` (testar) | Depende do usuário (conta e certificado); testar hardened runtime com a suíte de kill real | 5 | fazer |
| A3 Homebrew | Médio (marca/colisão de nome, manutenção de cask) | Cask público com "claude" no nome é o ponto mais visível do risco de marca; atualizar cask a cada release | Tap próprio primeiro; só depois de A1/A2 e do nome decidido | 3 | depois |
| A4 Config automática com backup | **Médio** (hoje alto: `install.sh` substitui hooks do usuário) | Pode quebrar hooks/statusline do usuário ou corromper `settings.json`; culpa cai no app (motivo nº 1 de desinstalação da persona e) | Merge aditivo, JSON validado, escrita atômica, backup, diff + consentimento, sem `jq` | 5 | fazer |
| A5 Remover integração | Baixo | Remover só o que é nosso; risco de apagar hook do usuário se o critério for frouxo | Identificar entradas pelo caminho exato do `claudebar-hook`; restaurar `statusLine` encadeado; não restaurar backup inteiro (perderia mudanças posteriores) | 5 | fazer |
| A6 Reparo automático | **Médio** | Reescrever `settings.json` sozinho, sem avisar, é exatamente o que d/c listam como motivo de desinstalação | Eliminar a causa: hook aponta para caminho estável (ex. `~/.claude/claudebar/bin/claudebar-hook`, cópia/atualização pelo app) em vez de dentro do bundle; detectar quebra e **pedir** para consertar, mostrando o diff | 4 | fazer (via caminho estável + detecção, sem reparo silencioso) |
| A7 Ícone próprio | Baixo; médio de marca | Usar o asterisco/logo ou cor-marca da Anthropic | Ícone original, sem logo de terceiros; template image para a barra | 4 | fazer |
| A8 Abrir no login | Baixo | `SMAppService.mainApp` é API pública (macOS 13+) | Padrão desligado; refletir estado real do sistema | 4 | fazer |
| A9 Janela de Ajustes | Baixo | — | Agrupar só os ajustes que existem | 4 | fazer |
| A10 Boas-vindas | Baixo | Vira o lugar do consentimento do A4 | Mostrar o diff aqui; "pular" não instala nada | 4 | fazer |
| A11 Inglês + português | Baixo | String Catalog; manutenção de duas línguas | `Localizable.xcstrings` (SwiftPM suporta recursos) | 4 | fazer |
| A12 Atualização automática | **Médio** | Contradiz "sem rede por padrão"; Sparkle é dependência nova + chave EdDSA para guardar; atualização que mexe em hooks sem aviso = desinstala | Depois do A2; checagem opt-in; ou deixar para o Homebrew; nunca alterar hooks numa atualização sem diff | 2 | depois |
| A13 Tela Sobre | Baixo | — | `orderFrontStandardAboutPanel` | 3 | fazer |
| A14 Copiar diagnóstico | Médio (privacidade) | Vaza caminhos de projetos de clientes ao colar em issue pública | Prévia editável, caminhos anonimizados (`~/…/<hash>`), sem mensagens, nada enviado (só área de transferência) | 4 | fazer |
| A15 VoiceOver | Baixo | — | `accessibilityLabel` por extenso no ícone e nas linhas | 5 | fazer |
| A16 Leve na CPU | Baixo | Polling de 5 s com `claude agents --json` (~150 ms) é o custo real | Medir; pausar polling sem sessões; sem animação contínua | 4 | fazer |
| A17 macOS 14+ | Baixo | Já é o alvo; risco é usar API nova sem `#available` | CI compilando com deployment target 14 | 4 | fazer (manter) |

### B. Ir até a sessão / agir

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| B1 Ir para a sessão | **Médio** | Foco na aba exata depende de AppleScript/Accessibility por terminal (TCC), APIs de terminais mudam (Ghostty, iTerm2); tmux exige rodar `tmux` | Base sem permissão: subir árvore de processos até o app e `activate`; tmux via `Process` com argumentos (`select-window -t`, alvo validado); AppleScript só opt-in e com valores passados como parâmetros, nunca concatenados; matriz de suporte publicada | 5 | fazer |
| B2 Alerta leva à sessão | Baixo (herda B1) | Clique acidental no popup | Reusa B1; popup não-ativador, longe do cursor | 5 | fazer |
| B3 Abrir pasta | Baixo | `cwd` vem do hook (dado externo) | `NSWorkspace.open(URL(fileURLWithPath:))`, checar que é diretório existente | 3 | fazer |
| B4 Copiar comando de retomar | Baixo | `sessionId` vira texto colado no shell do usuário | Whitelist `[A-Za-z0-9-]` (UUID) antes de montar `claude --resume <id>`; `cd` com quoting seguro | 3 | fazer |
| B5 Retomar sessão encerrada | **Médio** | Abrir terminal e executar comando = construir script com caminho do usuário → injeção se interpolado | Só Terminal.app via `open -a` + arquivo `.command` 0700 temporário com quoting POSIX; ou deixar B4 cobrir | 2 | depois |
| B6 Aprovar pelo popup | **Alto** | Aprovação no automático, clique acidental (Zoom), hook bloqueando até 600 s se o app travar, canal local que aprova permissões é alvo de outros processos | Fora do MVP. Se vier: desligado por padrão, comando inteiro, Enter nunca é Permitir, timeout curto com fail-open ("sem decisão"), Unix socket 0700, nunca `updatedPermissions` | 2 | depois |
| B7 Responder elicitation | **Alto** | Mesmo risco do B6 + formulário pode pedir segredo (token) que passaria pelo app | Não fazer; mostrar "ferramenta X pede dados" e ir à sessão (B1) | 1 | descartar |
| B8 Próxima instrução pelo popup | **Alto** | `Stop` com `decision: block` injeta texto como continuação; digitar no popup sem ver o contexto; prompt injection local | Não fazer | 1 | descartar |
| B9 Atalho global | Baixo | `NSEvent` global monitor exige Accessibility; `RegisterEventHotKey` (Carbon) não | Carbon hotkey, configurável, desligado por padrão | 3 | depois |
| B10 Teclado no menu | Baixo | Menu nativo já navega com setas | Verificar o que já funciona antes de codar | 3 | fazer (só se faltar) |

### C. O que a sessão está fazendo

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| C1 Ícone animado | Baixo risco, custo de CPU/a11y | Rejeitado pelo painel; Reduce Motion | — | 1 | descartar |
| C2 Estilo/cor do ícone | Baixo | Sem demanda | — | 1 | descartar |
| C3 Cronômetro | Baixo | Usa `updatedAt` já gravado | Só exibição | 3 | depois |
| C4 Ação atual | Médio | Exige `PreToolUse`/`PostToolUse` em toda ferramenta (latência) e `tool_input` (comandos/arquivos = conteúdo sensível na tela) | `async: true`, gravar só `tool_name`; respeitar modo "nunca mostrar conteúdo" | 2 | depois |
| C5 Estado de erro | Baixo | `StopFailure` é evento documentado | Hook adicional pequeno, só tipo de erro | 4 | fazer |
| C6 Nome e branch | Baixo | Branch lendo `.git/HEAD` (arquivo, sem rodar git); nome da sessão pode vir só de `agents --json` (instável) | Leitura de arquivo, tolerar worktree (`.git` arquivo); nome opcional | 4 | fazer |
| C7 Modelo e contexto | Médio | Exige o bridge de statusline (D1) | Só depois do D1, mesmo bridge | 2 | depois |
| C8 Compactações | Baixo | Hook `PreCompact`; valor baixo | — | 2 | depois |
| C9 Custo da sessão | Baixo técnico, alto de confiança | Usuários de assinatura; número "custo" estimado engana | — | 1 | descartar |
| C10 Agrupar | Baixo | — | Por worktree/branch (painel) | 3 | depois |
| C11 Subagentes e tarefas | Médio | Mais hooks (`SubagentStart`, `TaskCreated`); conteúdo das tarefas | — | 2 | depois |
| C12 Resumo do que mudou | Médio | Rodar `git diff` = ler o código do usuário; processo extra | — | 1 | descartar |
| C13 Status Anthropic | **Alto para a promessa** | Abre rede | Se um dia, opt-in explícito | 1 | descartar |
| C14 Texto adaptável | Baixo | macOS já esconde itens; valor baixo | — | 2 | depois |
| C15 Terminal + desktop juntos | Médio | Sessões do app desktop vêm de `agents --json` e de topologia interna do `Claude.app` (não documentadas); "Encerrar" já foi perigoso | Só listar, nunca encerrar; tolerar ausência | 3 | depois |

### D. Limites de uso

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| D1 Limites 5h/semanal | **Médio** | Só existe um `statusLine.command`: o bridge assume o statusline do usuário; bug no bridge quebra a barra dele (não a sessão); campo ausente em API key/Free; versão mínima desconhecida | Fonte única: statusline (documentada, local). Encadear o comando anterior (repassar stdin, devolver stdout, timeout), fail-open, ignorar `transcript_path`, "indisponível" em vez de 0%, backup e A5 restaurando. **Nunca** OAuth/Keychain/cookie | 5 | fazer |
| D2 Alerta perto do limite | Baixo (sobre D1) | — | Limiar configurável, uma vez por janela | 4 | fazer |
| D3 Previsão de ritmo | Médio (confiança) | Previsão errada 2x = desinstalação (persona d) | Linguagem prudente, só com amostras suficientes, sem extrapolar após reset | 3 | depois (após D1 estável) |
| D4 Aproveite antes de renovar | Baixo técnico | Incentiva uso; rejeitado | — | 1 | descartar |
| D5 Pausa por limite + hora de volta | Médio | `resets_at` é documentado; tipos `quota_auto_resume_*` do `Notification` têm semântica pouco documentada | Hora vem do `resets_at` do D1; tipos de notificação só como reforço | 4 | fazer |
| D6 Cache esfriando | Médio/alto | TTL do cache é detalhe interno (5 min / 1 h) e muda; número errado | — | 1 | descartar |

### E. Alertas

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| E1 Desligar notificação desliga som | Baixo | Bug real (`Notifier.post` toca antes de checar) | Checar o toggle antes do som; teste | 5 | fazer |
| E2 Escolher o que avisa | Baixo | — | `UserDefaults` | 4 | fazer |
| E3 Não avisar se já está olhando | Médio | Saber a aba da frente exige Accessibility/Automation | Versão sem permissão: app do terminal da sessão está na frente → só suprime o som; reusa B1 | 3 | depois |
| E4 Foco/horário silencioso | Baixo | Notificação nativa (A2) já respeita Foco; o `NSSound` próprio não | Com A2, usar o som da notificação quando nativa; horário silencioso simples | 2 | depois |
| E5 Lembrete de espera | Baixo | Pode irritar | Desligável, 1 lembrete, intervalo configurável | 4 | fazer |
| E6 Adiar/silenciar por sessão | Baixo | — | Em memória | 2 | depois |
| E7 Sessão travada | Médio | Heurística sem sinal de "progresso" gera falso alarme | Precisa de C4 | 1 | descartar |
| E8 Som só para respostas longas | Baixo | — | Limiar com `updatedAt` | 3 | depois |
| E9 Histórico de alertas | Médio (privacidade) | Persistir caminho e mensagem em disco (persona f) | Só em memória, limpa ao sair | 2 | depois |
| E10 Aviso no celular | **Alto** | Rede + serviço de terceiros (ntfy: tópico = senha), conteúdo sai da máquina | — (I5 permite o usuário fazer por conta própria) | 1 | descartar |
| E11 Aprovar pelo celular | **Alto** | Aprovação remota de comandos sem autenticação forte | — | 1 | descartar |
| E12 Slack/Discord | **Alto para a promessa** | Rede + segredo de webhook armazenado | Coberto por I5 | 1 | descartar |

### F. Outros agentes

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| F1 Codex e Gemini | Médio | Editar `~/.codex/config.toml`/`hooks.json` e `~/.gemini/settings.json` (mais formatos, TOML sem parser na stdlib), revisão de confiança do Codex, dobra a manutenção | Modelo de dados com campo `agent` desde já; integração depois, opt-in | 2 | depois |
| F2 Copilot | Médio | Idem, terceiro formato | — | 1 | descartar (por ora) |
| F3 Fila única de permissões | **Alto** | B6 multiplicado por N agentes | — | 1 | descartar |
| F4 Várias contas | Médio | `CLAUDE_CONFIG_DIR` múltiplos = vários `settings.json` para editar e desfazer | Detectar e oferecer por diretório, com A5 cobrindo todos | 2 | depois |

### G. Segurança ativa

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| G1 Radar de comandos perigosos | **Alto** | Falsa segurança (regex não pega variações), hook bloqueante, responsabilidade pelo que passa | Papel do Claude Code/permissões nativas | 1 | descartar |
| G2 Sugerir regra "sempre permitir" | **Alto** | O app passa a ampliar permissões no `settings.json`; incentiva aprovar sem ler | — | 1 | descartar |

### H. Superfícies do sistema

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| H1 Widget | Médio (manutenção) | Extensão WidgetKit + App Group exigem projeto Xcode e assinatura (A2); SwiftPM puro não basta | Só após A2 e migração de build | 2 | depois |
| H2 Botões no widget | Médio | Idem + App Intents | — | 1 | descartar |
| H3 Atalhos/Siri | Baixo/médio | App Intents; ações só de leitura e "marcar visto" | Nunca expor "aprovar" | 2 | depois |
| H4 Central de Controle | Médio | Só macOS 26, suporte de terceiros incerto | — | 1 | descartar |
| H5 Filtros de Foco | Médio | `SetFocusFilterIntent` exige App Intents + assinatura; valor coberto por E4 | — | 1 | descartar |
| H6 Modo notch | Médio | Janela desenhada sobre a área do notch, frágil entre modelos/versões | — | 1 | descartar |
| H7 CLI de estado | Baixo | Só lê os arquivos 0600 do mesmo usuário; saída JSON | Leitura apenas; `next` só ativa (reusa B1); nenhuma ação destrutiva | 4 | fazer |
| H8 Abrir quando sessão começa | Médio | `open -a` dentro de hook `SessionStart`: latência e reabre app que o usuário fechou de propósito | A8 cobre | 1 | descartar |

### I. Histórico e automação

| Id | Risco | Por quê | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| I1 Resumo enquanto fora | **Alto (privacidade)** | Exige ler conversa ou guardar `last_assistant_message` | — | 1 | descartar |
| I2 Estatísticas do dia | Baixo/médio | Persistir timestamps; valor baixo | Em memória, sem caminhos | 2 | depois |
| I3 Busca nas sessões | **Alto (privacidade)** | Ler JSONL = ler conversas | — | 1 | descartar |
| I4 Histórico de tokens/custo | **Alto (privacidade)** | JSONL tem `content` na mesma linha do `usage`; custo estimado | — | 1 | descartar |
| I5 Ação customizada | Médio | Executar comando do usuário a cada mudança: injeção se interpolar dados do hook; comando lento | Comando configurado como executável + argumentos fixos; dados via variáveis de ambiente/stdin (nunca no texto do comando); timeout; desligado por padrão | 2 | depois |

## Ideias novas do painel

| Id | Ideia | Risco | Mitigação | Nota | Veredito |
|---|---|---|---|---|---|
| N1 | Distinguir "esperando permissão" de "esperando pergunta" | Baixo/médio: depende do tipo do `Notification` (`permission_prompt`, `idle_prompt`, `elicitation_dialog`); nome exato do campo não confirmado na doc lida | Verificar o payload real; fallback para "esperando você" | 4 | fazer |
| N2 | Pergunta pendente em uma linha ("Bash: npm run migrate") | Médio: `tool_input` pode conter segredo (`cat .env`, tokens em URL) e aparece em compartilhamento de tela | Só no menu, truncado, desligável, obedece N3; nunca no popup por padrão | 3 | fazer (atrás do N3) |
| N3 | Modo "nunca mostrar conteúdo" | Baixo | Um toggle que esconde `message`/comando em menu e popup | 5 | fazer |
| N4 | Página de transparência (hooks, texto exato, diff, desfazer) | Baixo, reduz risco de todo o grupo A | Mesmo código do A4/A5 | 5 | fazer |
| N5 | Limpeza de sessões fantasmas | Médio: limpar demais esconde sessão real | Critério conservador (`kill(pid,0)` + `proc_pidpath` + ausente no `agents --json`) com teste | 5 | fazer |
| N6 | "Status: tudo ok" + testar alerta | Baixo | Checar hooks registrados, binário existe e executável, último evento recebido | 4 | fazer |
| N7 | Legenda dos estados + rótulo acessível | Baixo | Junto com A15 | 4 | fazer |
| N8 | Popup persistente para permissão | Baixo/médio: popup sob o cursor, clique acidental | Sem botões de ação, não ativa o app, posição fixa longe do cursor | 4 | fazer |
| N9 | Mostrar `sessão:janela.painel` do tmux | Baixo | Parte do B1 (mesma consulta ao tmux) | 3 | depois (com B1) |
| N10 | `claudebar next` | Baixo | Parte do H7 | 3 | fazer (com H7) |
| N11 | Uso por sessão em % do limite | Médio: não existe dado oficial por sessão; estimar = número mentiroso | — | 1 | descartar |
| N12 | Agrupar por worktree/branch | Baixo | = C10 | 3 | depois |
| N13 | Configuração exportável / MDM | Baixo/médio | Arquivo de preferências auditável | 2 | depois |
| N14 | Retenção mínima em disco | Baixo; reforça a promessa | Regra de projeto: nenhum dado novo persistente; arquivos de sessão apagados no fim (já) | 4 | fazer (como regra) |
| N15 | Hash publicado / build reproduzível | Baixo | SHA-256 na release (fazer); reproduzível depois | 3 | fazer (só o hash) |
| N16 | Rede zero verificável | Baixo | App não é sandboxed (precisa ler `~/.claude` e rodar `claude`), então "entitlement de rede" não se aplica; em vez disso: checagem em CI que falha se aparecer `URLSession`/`Network`/`NWConnection` no código + documentar | 4 | fazer |
| N17 | README com GIF | Baixo | — | 3 | fazer |
| N18 | Página "deu errado, e agora?" | Baixo | Inclui como desfazer (A5) | 3 | fazer |
| N19 | Encaminhar eventos via SSH/contêiner | Médio: abrir canal de rede ou montar diretório | Só documentar | 1 | depois |
| N20 | Prévia de 2 linhas da última resposta | Médio: conteúdo da conversa na tela e em memória | Opt-in, obedece N3, nunca gravar em disco | 2 | depois |
| N21 | Limites de outras ferramentas | Médio | — | 1 | descartar |
| N22 | Limites Team/Enterprise | Baixo (campos `spend_limit` da statusline) | Ler se vier no payload do D1 | 2 | depois |

## Bloqueios que dependem do usuário

1. **Nome/marca** antes de qualquer distribuição pública (A1, A3, A7).
2. **Conta Apple Developer e certificado Developer ID** para A2 (e por consequência A1, A12, H1, H3).
3. **Consentimento explícito na UI** antes de editar `settings.json` (A4, A6, D1): é decisão de produto, não técnica.

## Resumo

- **Fazer agora (risco controlável, alto valor):** E1, A4+A5+N4 (merge aditivo, diff, desfazer), A6 via caminho estável, N5, N3, N1, B1+B2 (base sem permissão), D1 por statusline encadeada, A15/N7, N6, H7.
- **Nunca:** OAuth/Keychain/cookie para limites, ler JSONL/conversa, qualquer rede por padrão, aprovar/responder pelo popup (B7, B8, F3, G1, G2, E11).
- **Maior risco atual no código:** `install.sh` substitui hooks existentes e grava caminho dentro do bundle. É o primeiro a corrigir.
