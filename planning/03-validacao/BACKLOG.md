# BACKLOG — ClaudeBar

> Síntese de `01-pesquisa/IDEIAS.md`, `02-painel/PAINEL.md` e das três lentes (`lente-valor.md`, `lente-viabilidade.md`, `lente-risco.md`), conferida contra o código em `main` @ f943cc4.
> Guard rails de `00-PLANO.md` valem para tudo: sem rede, não lê conversa, `0700/0600`, sem shell com interpolação, hook fail-open, nenhuma escrita em `settings.json` sem diff + backup, macOS 14.
> Regra de veto: risco **alto** sem mitigação viável não entra no escopo desta rodada.

Legenda
- **Prioridade:** P0 = bug ou bloqueia lançamento · P1 = paridade com concorrentes · P2 = diferencial novo · P3 = futuro.
- **Esforço:** P ≤ 1 dia · M 2–5 dias · G ≥ 1 semana ou infraestrutura nova.
- **Tipo:** paridade / inovação / bug / qualidade.
- **Veredito:** fazer agora / depois / descartar.
- **Origem:** id da lista de ideias (A1…I5, N1…N23 das lentes).

## Bugs confirmados no código

| Bug | Onde | Confirmação |
|---|---|---|
| Som toca com notificações desligadas | `Sources/ClaudeBar/Notifier.swift`: `play(alert)` (l. 111) antes de `guard isEnabled` (l. 113) | lido no código |
| `install.sh` substitui hooks do usuário | `scripts/install.sh` usa `jq` e reescreve as 4 chaves | lido no código; README admite |
| Caminho do hook quebra se o app for movido | `install.sh` grava `$APP/Contents/MacOS/claudebar-hook` (caminho dentro do bundle) | lido no código |
| Versão fixa 1.0 | `scripts/build-app.sh`: `VERSION="1.0"` em `CFBundleShortVersionString` e `CFBundleVersion` | lido no código |
| "Esperando você" falso | `install.sh` registra `Notification` sem matcher; `idle_prompt`, `auth_success`, `quota_auto_resume_*` etc. viram `waiting` | lente viabilidade §0.5 (doc de hooks) |

---

## Funcionalidades

### P0 — bugs e base de confiança

| Id | Nome | Descrição | Veredito | Por quê (painel + lentes) | Esf. | Depende de | Precisa do usuário? | Tipo |
|---|---|---|---|---|---|---|---|---|
| F01 | Som respeita o toggle | Checar `isEnabled` antes de tocar o som; teste cobrindo "desligado = silêncio". (E1) | fazer agora | Bug documentado; valor 4, viab 5, risco 5. Som com aviso desligado quebra confiança. | P | — | não | bug |
| F02 | Integração de hooks por merge aditivo | Lógica em Swift (Core) que acrescenta só as entradas do ClaudeBar e remove só as dele (identificadas pelo caminho do `claudebar-hook`), valida o JSON, escrita atômica, backup com timestamp, modo `--dry-run` que imprime o diff. Exposta como `claudebar-hook install|uninstall`; `install.sh` passa a chamar isso e deixa de depender de `jq`. Script de desinstalação. (A4 base, A5, TODO housekeeping) | fazer agora | Maior risco atual do código (lente risco). Bloqueio nº 3 de adoção e motivo de desinstalação de c, d, e. Viab 5 / valor 5. `JSONSerialization` reordena chaves: avisar e manter backup. | M | — | não | bug |
| F03 | Hook em caminho estável | Copiar o binário para `~/.claude/claudebar/bin/claudebar-hook` (0700) e registrar esse caminho; na abertura o app detecta binário ausente/antigo e **oferece** reparo, nunca reescreve `settings.json` em silêncio. (A6) | fazer agora | Bug de mover o app. Risco: reparo silencioso = desinstalação (d) → mitigado por "detectar e pedir". Viab 4, valor 3, risco 4. | P | F02 | não | bug |
| F04 | Versão de fonte única | `build-app.sh` lê a versão de um arquivo `VERSION` (ou `git describe`) e grava `CFBundleShortVersionString`; `CFBundleVersion` incremental (contagem de commits). | fazer agora | Bug citado na tarefa; pré-requisito de A1/A13/A14. Trivial. | P | — | não (o número da 1ª release pública é decisão dele, default `0.1.0`) | bug |
| F05 | `Notification` com matchers | Registrar `Notification` só para `permission_prompt` (`waiting --kind permission`) e `elicitation_dialog` (`waiting --kind question`); demais tipos não registrados. `SessionStatus.kind` opcional (decode retrocompatível). | fazer agora | Corrige "esperando" falso = motivo nº 1 de desinstalação ("o contador mente"). Lente viab: payload `notification_type` não confirmado → um matcher por entrada, tipo por argumento. | P | F02 | não | bug |
| F06 | Sessões fantasmas: provar e corrigir | Testes dos cenários do painel (processo morto, PID reciclado, `pid 0`, `sessionId` inválido); checar que o PID ainda é `claude` (`ProcessProbe` já faz) antes de manter o arquivo. Critério conservador. (N5) | fazer agora | Só 3 pontos no ranking, mas motivo nº 1/2 de desinstalação de 5 personas. Já existe em parte (`kill(pid,0)`); a task é garantia com teste. Risco: limpar demais esconde sessão real → critério conservador + teste. | P–M | — | não | bug |

### P1 — paridade

| Id | Nome | Descrição | Veredito | Por quê | Esf. | Depende de | Precisa do usuário? | Tipo |
|---|---|---|---|---|---|---|---|---|
| F07 | Estado de erro | Hook `StopFailure` → estado/flag `error` com símbolo próprio; resposta que falhou não aparece como "pronto". (C5) | fazer agora | Estado falso de novo. Evento documentado, P. Valor 3, viab 4, risco 4. | P | F02 | não | paridade |
| F08 | Polling leve | Trocar o `claude agents --json` a cada 5 s por: consulta ao abrir o menu e a cada evento de hook + polling lento (30–60 s) para sessões fechadas sem hook. Medir antes/depois. (A16) | fazer agora | Maior custo de energia hoje (processo Node a cada 5 s, 24 h). Requisito, não feature. Risco: fantasma demorar mais → coberto por F06. | P | F06 | não | paridade |
| F09 | Ir para a sessão — camada 1 + tmux | Subir a árvore de processos do `pid` do Claude até o app GUI e `NSRunningApplication.activate()` (sem permissão TCC). tmux: `tmux list-panes -a` casando pelo TTY + `select-window`/`select-pane` via `Process` com argumentos. Fallback honesto: "trouxe a janela, não a aba". Matriz de suporte no README. (B1 camada 1, N9 parcial) | fazer agora | O produto (24 pts, 6/6 no top 5). Aba exata via AppleScript exige TCC instável com assinatura ad-hoc → vai para F30. Risco médio, mitigado (sem permissão, sem shell). | M | — | não | paridade |
| F10 | Alerta leva à sessão | Clique no popup chama F09 para aquela sessão em vez de só fechar. (B2) | fazer agora | 21 pts. Custo marginal pequeno sobre F09. | P | F09 | não | paridade |
| F11 | Abrir pasta do projeto | Item no submenu: `NSWorkspace.open` do `cwd` (validar que é diretório existente). Também fallback do F09. (B3) | fazer agora | Quase de graça; risco baixo. | P | — | não | paridade |
| F12 | Popup persistente para "esperando" | `StatusHUD`: alerta `waiting` não some por timer (fecha no clique ou na transição); "terminou" continua com 4 s; não abrir sob o cursor. (N8) | fazer agora | f, a, e: aviso perdido enquanto digita = dor nº 1. Mudança pequena. | P | — | não | paridade |
| F13 | Lembrete de espera | Sessão em `waiting` há N min (padrão 5) recebe 1 lembrete; cancela na transição; desligável. (E5) | fazer agora | 10 pts, top 5 de 5 personas ("ignoro o primeiro aviso"). P. | P | F15 (toggle) | não | paridade |
| F14 | Não avisar se já está olhando (nível app) | Se o app ancestral da sessão (F09) é o `frontmostApplication`, suprimir só o som. (E3) | fazer agora | Top 5 de a, c, e; nº 2 de desinstalação de b. Versão sem permissão reusa F09. Nível aba fica para F30. | P | F09 | não | paridade |
| F15 | Ajustes mínimos | Cena `Settings` (SwiftUI, macOS 14) com: avisar "terminou" / "esperando" / som (E2), escolha do som, abrir no login via `SMAppService.mainApp` (A8, padrão desligado, reflete estado real), lembrete (F13). Sobre via `orderFrontStandardAboutPanel` (A13). App `.accessory` precisa `NSApp.activate`. (A9) | fazer agora | Lugar de E2/A8/A13; paridade com Nudgy, AgentBar, Claude Status. Manter curta (perfil "leve"). | M | F01 | não | paridade |
| F16 | Integração no app (transparência) | Tela que mostra os hooks instalados, o JSON exato que será gravado, caminho do backup, botão Instalar (com consentimento) e Remover. No 1º uso, um `NSAlert` leva até ela; "Pular" não instala nada. Usa a lógica do F02. (A4, A5, A10, **N4**) | fazer agora | 17 pts (N4) + A5 17 pts. Diferencial de confiança: concorrentes instalam, nenhum mostra. Risco médio mitigado por diff + consentimento + backup. | M | F02, F03, F15 | não | inovação (N4) |
| F17 | Status "tudo ok" + testar alerta | No menu/Ajustes: hooks registrados? binário existe e é executável? último evento recebido há X? + "testar alerta" (já existe o exemplo de popup). (N6) | fazer agora | Motivo nº 1 de e ("a culpa cai no app") e nº 2 de c (hooks quebrados por atualização). P. | P | F03, F16 | não | paridade |
| F18 | Ícone do app e da barra | Integrar `AppIcon.icns` de `planning/07-design/final` em `Contents/Resources` + `CFBundleIconFile` no `build-app.sh`. Ícone da barra continua SF Symbol (template) salvo decisão de design em contrário. (A7) | fazer agora | b, c: "sem ícone = abandonado". Asset pronto; sem logo/cor-marca da Anthropic (guard rail). | P | entrega do agente de design | não | paridade |
| F19 | VoiceOver + legenda dos estados | `accessibilityLabel` por extenso no item da barra ("2 sessões, 1 esperando você"), linhas com rótulo em vez de emoji, anúncio no popup (`NSAccessibility.post(.announcementRequested)`), legenda dos símbolos no menu. (A15, N7) | fazer agora | f: condição de uso; nenhum concorrente cita VoiceOver. Risco baixo. | P | — | não | paridade (com diferencial) |
| F20 | Nome da sessão e branch | Nome já exibido (`AgentSession.name`); falta a branch, lida de `.git/HEAD` pelo hook (tolerando `gitdir:` de worktree), sem rodar `git`. (C6) | fazer agora | Dor de a, b, c, e (abas "zsh" iguais, dois worktrees). P, risco baixo: ler no app traria prompt TCC em ~/Documents; lido no hook. | P | — | não | paridade |
| F21 | Inglês + português | `Localizable.strings` em `en.lproj` e `pt-BR.lproj` copiados pelo `build-app.sh` para `Contents/Resources` (usar `Bundle.main`); remover `Locale("pt_BR")` fixo; segue o idioma do Mac, fallback inglês. (A11) | fazer agora (última do loop, depois que as strings estabilizarem) | Bloqueio de d; "só português = projeto pequeno" para 4 personas. M. | M | todas as tasks de UI | confirmar default inglês (proposto: segue o sistema, fallback `en`) | paridade |
| F22 | Limites 5 h e semanal (sem rede) | `claudebar-hook statusline`: lê o stdin do statusline, grava `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` em `~/.claude/claudebar/limits.json` (0600, atômico) e **encadeia** o `statusLine.command` anterior (repassa stdin, devolve stdout, timeout, fail-open). Menu mostra %, hora de renovação e idade do dado; "indisponível" em vez de 0%. Ignora `transcript_path`. Instalação/remoção via F16 restaurando o statusline original. (D1 + hora de reset do D5) | fazer agora | 15 pts; motivo nº 1 de d para procurar o app. Paridade de função com Clabar/Perch/claudewatch, mas eles usam OAuth/Keychain (proibido aqui); fazer sem login e sem rede é o maior diferencial. Risco médio com mitigação clara. **Nunca** OAuth/Keychain/cookie. | M | F02, F16 | não | paridade (método inédito) |
| F23 | DMG universal + SHA-256 | `scripts/make-dmg.sh`: build `arm64` + `x86_64`, `hdiutil create`, `shasum -a 256`. Sem assinatura ainda; README explica o "Abrir mesmo assim". Não publica nada. (A1, N15) | fazer agora (só o script) | Bloqueio nº 1 de adoção. Publicar com o nome atual é risco alto de marca → publicação fica fora (F28/F47). | P | F04, F18 | não para o script; sim para publicar | paridade |

### P2 — diferenciais novos (escolhidos para esta rodada)

| Id | Nome | Descrição | Veredito | Por quê | Esf. | Depende de | Precisa do usuário? | Tipo |
|---|---|---|---|---|---|---|---|---|
| F24 | Permissão × pergunta | Símbolo, texto e som distintos para "esperando permissão" e "esperando resposta", a partir do `kind` do F05. (N1) | fazer agora | Adotado pelas 6 personas; não encontrado em concorrente; valor 5, viab 5, risco 4. Quase de graça após F05. | P | F05 | não | inovação |
| F25 | Modo "nunca mostrar conteúdo" | Um toggle que troca `message` por "<projeto> precisa de você" no menu e no popup (compartilhamento de tela). (N3) | fazer agora | f (condição), a, b, c, d aderiram; risco 5 (reduz risco). Pré-requisito de qualquer exibição de conteúdo futura (F38). | P | F15 | não | inovação |
| F26 | CLI `status` / `next` | `claudebar-hook status [--json]` lê `StatusDirectory` (Core) sem o app aberto; `next` ativa a próxima sessão esperando (reusa F09). Nenhuma ação destrutiva. (H7, N10) | fazer agora | a, c, d, f; para f é acessibilidade, para a é a barra do tmux. Só CodexBar tem CLI. P, risco baixo. | P | F09 (para `next`) | não | inovação |
| F27 | Rede zero verificável | Teste que falha se `Sources/` passar a usar `URLSession`, `Network`, `NWConnection`, `CFSocket`; README documenta como verificar com `nettop`/Little Snitch; logs com `privacy: .private` para caminhos. (N16, N14) | fazer agora | Motivo nº 1 de desinstalação de f; protege o único diferencial já existente. P. | P | — | não | qualidade |

### Depois (fora desta rodada)

| Id | Nome | Veredito | Por quê | Prio | Esf. | Depende de | Precisa do usuário? | Tipo |
|---|---|---|---|---|---|---|---|---|
| F28 | Assinatura Developer ID + notarização (A2) | depois | 18 pts, bloqueio de b, d, e, f; destrava notificação nativa, Gatekeeper e TCC estável. Exige conta paga. Script com credenciais via env só quando der para verificar. | P0 | M | F04, F23 | **sim**: Apple Developer Program (US$ 99/ano) + certificado Developer ID | paridade |
| F29 | Homebrew (tap próprio) (A3) | depois | Cask `claudebar` já existe (tddworks) e Homebrew aperta casks sem notarização. | P1 | P | F28, F47 | **sim**: nome do cask, repositório do tap | paridade |
| F30 | Ir para a sessão — aba exata (Terminal, iTerm2, Ghostty via AppleScript) (B1 camada 2, N9) | depois | Exige `NSAppleEventsUsageDescription` + permissão de Automação; com ad-hoc a permissão é pedida de novo a cada build. Verificação manual por terminal. | P1 | G | F09, F28 | **sim**: conceder Automação e testar em cada terminal | paridade |
| F31 | Alerta perto do limite (D2) | depois | Barato, mas só após F22 provar que o número é confiável. | P1 | P | F22 | não | paridade |
| F32 | Previsão de ritmo (D3) | depois | 13 pts, mas previsão errada 2x = desinstalação (d). Só com F22 estável e amostras suficientes. | P2 | P | F22 | não | inovação |
| F33 | Pausa por limite com motivo (D5 completo) | depois | Semântica de `quota_auto_resume_*` pouco documentada; precisa de payload real. Hora de renovação já sai no F22. | P2 | P | F07, F22 | **sim**: capturar um payload real ao bater o limite | inovação |
| F34 | Atalho global "próxima sessão" (B9) | depois | `RegisterEventHotKey` sem Acessibilidade; só faz sentido com F09/F26 maduros. | P2 | P | F26 | não | inovação |
| F35 | Copiar diagnóstico anonimizado (A14) | depois | Útil para suporte; exige prévia e anonimização de caminhos. | P1 | P | F17 | não | paridade |
| F36 | Cronômetro "esperando há X" + som só para respostas longas (C3, E8) | depois | Lentes divididas (valor fazer, viab/risco depois); baixo valor marginal sobre F13. | P2 | P | F15 | não | paridade |
| F37 | Codex e Gemini (F1, TODO.md) | depois | Só c pediu; dobra a manutenção (TOML sem parser, formatos diferentes). Deixar `SessionStatus` tolerante a campo `agent` futuro. | P3 | M | F02, F09 | sim: decidir nome (F47) antes de virar multiagente | paridade |
| F38 | Pergunta pendente em uma linha (N2) | depois | Precisa do `tool_input` do `PermissionRequest` gravado em disco (pode conter segredo). Só atrás do F25, truncado, no menu. | P2 | M | F25 | não | inovação |
| F39 | Copiar comando de retomar / retomar sessão (B4, B5) | depois | Painel não pediu; B5 exige histórico de sessões encerradas. | P3 | P/M | — | não | paridade |
| F40 | Atualização automática (A12) | depois | Contradiz "sem rede"; Homebrew cobre. Só opt-in e após F28. | P3 | G | F28 | sim (chave EdDSA, hospedagem) | paridade |
| F41 | Rótulo de origem desktop × terminal (C15) | depois | Já listado via `agents --json`; falta confirmar que os hooks disparam no app desktop. | P2 | P | — | não | inovação |
| F42 | Agrupar por worktree/branch (C10, N12) | depois | Só ajuda com muitas sessões. | P3 | P | F20 | não | paridade |
| F43 | Modelo e contexto usado (C7) | depois | Subproduto do bridge do F22. | P3 | P | F22 | não | paridade |
| F44 | Várias contas / `CLAUDE_CONFIG_DIR` (F4) | depois | Nicho; vários `settings.json` para editar e desfazer. | P3 | M | F02 | não | paridade |
| F45 | Ação customizada por mudança de estado (I5) | depois | Cobre E12/Slack sem o app ter rede; executável + args fixos, dados via env. | P3 | P | — | não | inovação |
| F46 | Aprovar permissão pelo popup (B6) | depois (vetado nesta rodada) | Risco **alto**: hook bloqueante até 600 s, clique acidental, canal local que aprova comandos. Mitigação existe, mas é G e o painel tirou do MVP. | P3 | G | F09, F25 | não | paridade |
| F47 | Nome definitivo, bundle id e diretório de estado | depois | "Claude" no nome do produto é vedado pela página legal do Claude Code; `ClaudeBar` colide com tddworks. Bloqueia qualquer distribuição pública. | P0 (para lançar) | P–M | — | **sim**: decisão de nome/marca e bundle id | — |
| F48 | Licença | depois | Repo público sem arquivo `LICENSE`; código aberto ajuda na revisão de segurança (d, f). | P0 (para lançar) | P | — | **sim**: escolher a licença | — |
| F49 | README com GIF de 10 s (N17) | depois | b, e: "é o que me faz instalar". Gravar a barra de menu real não é confiável por agente. | P1 | P | F18, F09 | sim: gravar o GIF (ou aprovar um gerado) | paridade |
| F50 | Baixa prioridade agrupada: Foco/horário silencioso (E4), adiar/silenciar por sessão (E6), histórico em memória (E9), estatísticas do dia (I2), Atalhos/Siri (H3), ação atual (C4), subagentes/tarefas (C11), config exportável (N13), "deu errado, e agora?" (N18), SSH/devcontainer (N19), limites Team/Enterprise (N22), texto adaptável (C14), compactações (C8) | depois | Valor baixo ou incerto, ou depende de A2/migração para projeto Xcode. Reavaliar com uso real. | P3 | — | vários | H3: precisa projeto Xcode + F28 | — |

### Descartadas

| Origem | Nome | Por quê |
|---|---|---|
| C1, C2 | Ícone animado; estilo/cor do ícone | Rejeitados pelas 6 personas; CPU e Reduce Motion. |
| C9, I4, N11 | Custo em US$ / histórico de tokens / uso por sessão em % | Todos usam assinatura; exige JSONL (lê conversa) ou estimativa enganosa. |
| C12 | Resumo do que mudou | Lê código do usuário; papel do git. |
| C13 | Status Anthropic | Abre rede (quebra promessa). |
| D4, D6 | "Aproveite antes de renovar"; cache esfriando | Ruído / TTL interno que muda. |
| E7 | Sessão travada | Heurística sem sinal de progresso = falso alarme. |
| E10, E11, E12 | Celular, aprovar pelo celular, Slack/Discord | Risco alto (rede, relay, segredos), sem mitigação compatível com "sem rede". I5 (F45) cobre o caso de entusiasta. |
| B7, B8 | Responder elicitation; próxima instrução pelo popup | Risco alto (injeção de prompt, segredos no popup); sem mitigação viável. |
| F2, F3 | Copilot; fila única de permissões | Sem demanda; F3 é B6 × N agentes (risco alto). |
| G1, G2 | Radar de comandos perigosos; sugerir "sempre permitir" | Falsa segurança; o app ampliaria permissões. Risco alto. |
| H1, H2, H4, H5, H6, H8 | Widget, botões no widget, Central de Controle, Filtros de Foco, notch, abrir quando sessão começa | Exigem `.appex`/App Intents (SwiftPM não gera) ou hacks; painel rejeitou; A8 cobre H8. |
| I1, I3, N20 | Resumo enquanto fora; busca nas sessões; prévia da última resposta | Exigem ler conversa. |
| A10 (tela própria), B10, A17 | Tour de boas-vindas; teclado no menu; macOS 14+ | A10 vira um `NSAlert` dentro do F16; B10 já funciona (`NSMenu` nativo); A17 já atendido e vira restrição. |
| N21, N23 | Limites de outras ferramentas; aviso de sessão esquecida | Depende de F37; ensina errado (sessão ociosa não consome limite). |

---

## Escopo desta rodada

Critério: executável por agentes sem ação do usuário, verificável com `swift build`/`swift test`/`build-app.sh`, paridade + 4 inovações de alto valor e baixo risco. Nada com risco alto. Ordem sugerida (tasks que tocam os mesmos arquivos em sequência):

| Ordem | Id | Nome | Prio | Esf. | Tipo |
|---|---|---|---|---|---|
| 1 | F01 | Som respeita o toggle | P0 | P | bug |
| 2 | F04 | Versão de fonte única | P0 | P | bug |
| 3 | F02 | Integração de hooks por merge aditivo | P0 | M | bug |
| 4 | F03 | Hook em caminho estável | P0 | P | bug |
| 5 | F05 | `Notification` com matchers | P0 | P | bug |
| 6 | F06 | Sessões fantasmas: provar e corrigir | P0 | P–M | bug |
| 7 | F07 | Estado de erro (`StopFailure`) | P1 | P | paridade |
| 8 | F08 | Polling leve | P1 | P | paridade |
| 9 | F27 | Rede zero verificável | P2 | P | qualidade |
| 10 | F24 | Permissão × pergunta | P2 | P | inovação |
| 11 | F12 | Popup persistente para "esperando" | P1 | P | paridade |
| 12 | F09 | Ir para a sessão — camada 1 + tmux | P1 | M | paridade |
| 13 | F10 | Alerta leva à sessão | P1 | P | paridade |
| 14 | F11 | Abrir pasta do projeto | P1 | P | paridade |
| 15 | F14 | Não avisar se já está olhando (nível app) | P1 | P | paridade |
| 16 | F26 | CLI `status` / `next` | P2 | P | inovação |
| 17 | F20 | Nome da sessão e branch | P1 | P | paridade |
| 18 | F15 | Ajustes mínimos (E2, A8, A13) | P1 | M | paridade |
| 19 | F13 | Lembrete de espera | P1 | P | paridade |
| 20 | F25 | Modo "nunca mostrar conteúdo" | P2 | P | inovação |
| 21 | F16 | Integração no app (transparência) | P1 | M | inovação |
| 22 | F17 | Status "tudo ok" + testar alerta | P1 | P | paridade |
| 23 | F22 | Limites 5 h e semanal (sem rede) | P1 | M | paridade (método inédito) |
| 24 | F19 | VoiceOver + legenda | P1 | P | paridade |
| 25 | F18 | Ícone do app | P1 | P | paridade |
| 26 | F23 | DMG universal + SHA-256 (script) | P1 | P | paridade |
| 27 | F21 | Inglês + português | P1 | M | paridade |

Inovações da rodada: **F24** (permissão × pergunta), **F25** (modo sem conteúdo), **F16** (transparência dos hooks, N4), **F26** (CLI `status`/`next`). F22 é paridade de função, mas o método (statusline, sem login/rede) não existe em concorrente.

Não verificável por agente (registrar como "não verificado" no relatório): aparência real do menu e do popup, VoiceOver ouvido de fato, foco em cada terminal (F09), statusline com conta Pro/Max real (F22), DMG em outro Mac.

## Fora desta rodada

F28 (assinatura/notarização), F29 (Homebrew), F30 (aba exata via AppleScript), F31 (alerta perto do limite), F32 (previsão de ritmo), F33 (pausa por limite completa), F34 (atalho global), F35 (diagnóstico), F36 (cronômetro/som longo), F37 (Codex/Gemini), F38 (pergunta pendente), F39 (retomar), F40 (auto-update), F41 (rótulo desktop), F42 (agrupar), F43 (modelo/contexto), F44 (várias contas), F45 (ação customizada), F46 (aprovar pelo popup — vetado por risco alto), F47 (nome/bundle id), F48 (licença), F49 (GIF), F50 (baixa prioridade agrupada) e todas as descartadas.

## Precisa do usuário

| Item | Bloqueia | Passo exato |
|---|---|---|
| Conta Apple Developer + certificado Developer ID Application | F28 → F29, F30, F40, notificação nativa, Gatekeeper limpo | Assinar o Apple Developer Program (US$ 99/ano), criar o certificado, gerar app-specific password/API key para `notarytool` |
| Nome definitivo, bundle id e diretório de estado | F47 → F23 (publicar), F29, F37 | Decidir nome sem "Claude" como nome do produto (ex.: nome neutro + "for Claude Code" na descrição) e o bundle id |
| Licença | F48 → qualquer distribuição | Escolher (ex.: MIT/Apache-2.0) |
| Repositório do tap Homebrew | F29 | Criar `homebrew-tap` e escolher nome do cask |
| Publicar release (DMG + SHA-256) | distribuição | Após F47/F48 (e idealmente F28) |
| Testar e conceder Automação por terminal | F30 | Rodar o build final e aprovar o prompt de Automação em Terminal/iTerm2/Ghostty |
| Payload real de pausa por cota | F33 | Capturar o JSON do `Notification`/`StopFailure` ao bater o limite |
| GIF do README | F49 | Gravar 10 s do app em uso |
| Confirmar idioma padrão | F21 (não bloqueia; default proposto: segue o sistema, fallback inglês) | Vetar se quiser pt-BR como padrão |
| Número da 1ª versão pública | F04 (não bloqueia; default `0.1.0`) | Confirmar ou trocar |
