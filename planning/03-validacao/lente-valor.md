# Validação: lente PRODUTO / VALOR

Fontes: `README.md`, `01-pesquisa/1a..1d`, `01-pesquisa/IDEIAS.md`, `02-painel/PAINEL.md`, e uma checagem rápida no código (`Sources/ClaudeBar`).

Perguntas aplicadas a cada ideia:
1. Resolve uma dor que o painel citou?
2. Diferencia (ninguém ou quase ninguém tem) ou só iguala (paridade)?
3. Impacto em adoção (alguém instala) e retenção (alguém não desinstala)?

Escala de nota: 5 = sem isso o produto não existe ou ninguém instala; 4 = forte em adoção ou retenção; 3 = útil, custo justificável; 2 = nicho ou valor incerto; 1 = enfeite, ou contradiz a promessa do produto.
Vereditos: **fazer** (entra no plano agora), **depois** (valor real, mas não agora ou depende de outra coisa), **descartar** (o valor não paga o custo ou quebra a promessa).

---

## 1. Tese de produto (o que o painel disse de verdade)

- **Tema único: confiança.** Todos os motivos nº 1 de desinstalação são estado errado (fantasma, "nada esperando" falso), número de limite errado, ou mexer na configuração sem avisar. Qualquer feature que gere um número ou estado em que não dá para confiar é **risco de retenção**, não ganho.
- **Adoção hoje = zero.** As 6 personas responderam "não instalaria". Os bloqueios são de distribuição (compilar, sem assinatura, mexe no `settings.json` sem mostrar). Nenhuma funcionalidade nova importa antes disso.
- **O produto é "me leve até a sessão" (B1 + B2).** 6/6 no top 5. "Ninguém está pedindo mais avisos."
- **Promessa diferenciadora já existente:** sem rede, sem login, não lê conversa. É o único eixo em que o ClaudeBar já ganha de vários concorrentes (Clabar, Perch, claudewatch, CC Notifier usam OAuth, relay ou JSONL). Qualquer ideia que quebre isso tem custo de posicionamento, não só de engenharia.
- **Preço esperado:** grátis e open source. Assinatura = zero para as 6. Logo, nada de feature cujo único sentido é monetização (celular, relay).

### Onde o ClaudeBar pode realmente se diferenciar (e não só igualar)
Pela matriz de `1a` e pelas lacunas de `1c`/`1d`, o espaço livre é:
1. **Limites (D1/D3/D5) sem login e sem rede**, via bridge de statusline. Quem tem limites hoje (Clabar, Perch, claudewatch) usa OAuth/Keychain, que é zona cinzenta pela política da Anthropic e sofre com 429. Ninguém junta "status de sessão + limites + zero rede".
2. **Distinguir permissão de pergunta** + **pergunta pendente em uma linha** + **modo "nunca mostrar conteúdo"**: não encontrado em concorrente, custo baixo, todo o painel aderiu.
3. **Transparência verificável** (página com hooks instalados, diff, remoção exata, sem rede): concorrentes fazem setup automático, mas nenhum vende auditabilidade.
4. **Acessibilidade real (A15 + B9/B10 + H7 `status`/`next`)**: ninguém na matriz cita VoiceOver. Nicho, mas zero concorrência e custo moderado.
5. **Fila de atenção com atalho global** (`B9` "próxima que precisa de você"): não encontrada como atalho global em nenhum concorrente (`1c`).

Tudo o resto que o painel pediu é **paridade**: necessária para não perder, insuficiente para ganhar.

### Achados do código que mudam o valor de algumas ideias
- **C15 (desktop + terminal juntos) já existe em boa parte.** `claude agents --json` já lista sessões do app desktop, e `SessionTerminator` já trata `hostedByApp`. O que falta é rotular a origem e fazer B1 abrir o app Claude. A pesquisa marcou como "novo"; na prática é um ajuste.
- **Limpeza de fantasmas já existe em parte** (`kill(pid, 0)` apaga órfãos; a contagem vem da CLI). O trabalho real é provar com teste os cenários do painel (`tmux kill-server`, janela do Cursor fechada) e corrigir o que falhar. Não é feature nova, é garantia.
- **E1 é bug documentado no README** (som toca com notificações desligadas). Custo trivial.

---

## 2. Avaliação por ideia

### A. Produto pronto

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| A1 Instalador fácil | 5 | fazer | Bloqueio nº 1 de adoção para as 6 personas. Paridade (todos os distribuídos têm DMG), mas sem isso a adoção é zero. |
| A2 Assinado e notarizado | 5 | fazer | Bloqueio nº 2 (b, d, e, f); a segurança da empresa barra sem isso. Também desbloqueia notificação nativa. Depende de conta Apple Developer (custo anual e ação do dono): é pendência do usuário, não do agente. |
| A3 Homebrew | 4 | fazer | a e d citam como caminho natural do time; o líder (Claude Status Bar) tem cask oficial. Barato depois de A1/A2 (tap próprio primeiro; cask oficial exige notoriedade). Também resolve atualização (ver A12). |
| A4 Configuração automática com backup | 5 | fazer | Bloqueio nº 3; hoje o install.sh **substitui** hooks existentes, que é exatamente o medo de c e e. Deve fazer merge, não replace, e mostrar o diff antes (página de transparência). Paridade, mas mal feita é motivo de desinstalação. |
| A5 Remover com um clique | 5 | fazer | 4 pontos de 5 personas no ranking final. Funde com a página de transparência: desfazer exatamente o que foi instalado. |
| A6 Reparo automático da conexão | 3 | fazer | Ideia "nova", pequena, e ataca o motivo nº 2 de c ("atualização que estraga os hooks") e o nº 1 de e ("Claude parou e a culpa é do app"). Restrição: **nunca reescrever o `settings.json` em silêncio** (d desinstala). Detectar e oferecer o reparo mostrando o diff, não consertar sozinho. |
| A7 Ícone próprio | 3 | fazer | b e c leem "sem ícone = abandonado". Não diferencia, mas é barato e já está no fluxo do agente de design. |
| A8 Abrir ao iniciar | 3 | fazer | Paridade; `SMAppService.mainApp` é uma linha. Sem ele o app some depois do reboot e o usuário esquece que existe (retenção). |
| A9 Janela de Ajustes | 3 | fazer | Não é valor em si, é o lugar onde moram A8, E2, idioma, "status: tudo ok" e transparência. Manter mínima. Cuidado: virar painel de 30 opções contraria o perfil "leve". |
| A10 Tela de boas-vindas | 3 | fazer | Útil para e (iniciante) e é onde o consentimento de A4 acontece com diff. Manter em 1 tela: o que faz, o que vai mudar, testar alerta. Não fazer tour. |
| A11 Inglês + português | 3 | fazer | Só d se incomoda de fato, mas "só português = projeto pequeno" aparece em 4 personas, e o mercado é majoritariamente em inglês. pt-BR é diferencial raro (só CC Notifier e Clabar). String Catalog torna barato; fazer cedo, antes de multiplicar strings. |
| A12 Atualização automática | 2 | depois | f desinstala com rede não pedida; d desinstala se a atualização mexer no settings. Sparkle introduz rede e quebra o "sem rede verificável". Homebrew já cobre atualização para quem quer. Se vier: verificação manual ou opt-in, nunca instalar sozinho. |
| A13 Tela Sobre | 2 | fazer | Ninguém pediu, mas custa minutos e ajuda a parecer mantido. Pode ser só o painel padrão do macOS (`orderFrontStandardAboutPanel`). Não vale task própria. |
| A14 Copiar diagnóstico | 3 | fazer | Reduz custo de suporte (d não quer virar suporte). f exige prévia e anonimização de caminhos. Juntar com "status: tudo ok" e "testar alerta". |
| A15 VoiceOver | 4 | fazer | Para f é condição de uso (5 pontos) e ninguém na matriz tem: diferencial real com custo moderado (rótulos de acessibilidade + anúncio de mudança de estado). Estado por texto e forma, não só cor, ajuda todos. |
| A16 Leve no processador | 4 | fazer | Requisito, não feature. O líder teve issue de CPU por animação. Regra de produto: medir e não regredir. Retenção silenciosa. |
| A17 macOS 14+ | 3 | fazer | Já é o alvo do Package.swift. Valor é **não perder** isso ao adicionar recursos de 26 (H4, Liquid Glass). Gap do Claude Status (exige 26.2). Restrição de projeto, não task. |

### B. Ações a partir do menu

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| B1 Ir para a sessão | 5 | fazer | 24 pontos, 6/6. É o produto. Paridade (quase todos têm), mas os melhores focam a aba/painel exato; "só a janela vale metade" (a, b, c, d). Valor depende da **matriz de terminais publicada** (Terminal.app, iTerm2, Ghostty, tmux, VS Code/Cursor) e de fallback honesto. VS Code/Cursor aba exata é o mais difícil e provavelmente exige extensão: entregar janela + aviso e marcar a aba exata como etapa seguinte. |
| B2 Alerta leva à sessão | 5 | fazer | 21 pontos. Reaproveita B1; custo marginal pequeno. Um popup que só fecha é desperdício. |
| B3 Abrir a pasta | 2 | fazer | Ninguém do painel pediu, mas é um item de submenu com `NSWorkspace.open`. Só vale porque custa quase nada; não priorizar. |
| B4 Copiar comando de retomar | 2 | depois | Não citado pelo painel. `claude --resume <id>` é trivial, mas sem B5 o valor é baixo. Juntar com B5 quando vier. |
| B5 Retomar sessão encerrada | 2 | depois | Não citado. Exige lista de sessões encerradas (o app hoje só conhece as abertas) e abrir terminal novo por app. Caminho para virar gerenciador (fora do posicionamento "monitor"). |
| B6 Aprovar pelo popup | 2 | depois | `1d` diz que é paridade com notch apps, mas o painel rejeitou no MVP (a, c, d, f contra; d saiu da lista por risco de time). A "pergunta pendente em uma linha" entrega metade do valor sem o risco. Se vier: desligado por padrão, comando inteiro, Enter nunca é Permitir, popup fora do cursor, bloqueável por política. Também exige hook bloqueante (`PermissionRequest`), que aumenta o raio de dano se o app travar. |
| B7 Responder elicitação MCP | 1 | descartar | Ninguém pediu; formulário dinâmico por servidor; mesmo risco de B6. |
| B8 Próxima instrução pelo popup | 1 | descartar | Rejeitado por a, c, d, e, f ("prompt às cegas"). `1d` aponta risco técnico alto (entra como system reminder). |
| B9 Atalho global | 3 | fazer | f (bloco com B1/B10), a quer `next`. "Próxima que precisa de você" como atalho global não foi encontrado em concorrente (`1c`): diferencial barato. Fazer junto com H7 `next` (mesma lógica). |
| B10 Teclado no menu | 3 | fazer | Requisito de acessibilidade de f. Verificar quanto o `MenuBarExtra` já dá de graça antes de construir algo; pode ser quase só ajuste. |

### C. Informação na barra e no menu

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| C1 Ícone animado | 1 | descartar | Rejeitado pelas 6 (distrai, CPU, Reduce Motion). O líder pagou caro em CPU. No máximo opcional desligado, e nem isso justifica o custo agora. |
| C2 Estilo e cor do ícone | 1 | descartar | "Perfumaria" para todos. |
| C3 Cronômetro | 3 | fazer | O app já mostra "há 2 min"; o valor é "esperando você há 14 min", que conversa com E5 e com a dor nº 1 ("parada há 20 min sem eu ver"). Paridade, barato com os timestamps que já existem. |
| C4 O que está fazendo agora | 2 | depois | Não citado pelo painel. Exige `PreToolUse`/`PostToolUse` (mais hooks no settings, mais escrita por evento). Paridade com valor baixo para este público. |
| C5 Estado de erro | 3 | fazer | Ataca "contador mentir": resposta que falhou aparecendo como "pronto" é estado falso. `StopFailure` existe. Pequeno. Juntar com D5 (mesmo evento). |
| C6 Nome da sessão e branch | 4 | fazer | Dor citada por a, b, c, e (4–6 abas "zsh", dois worktrees no mesmo repo). Barato (`git` na pasta + nome de `claude -n`). Pré-requisito para agrupar por worktree/branch. |
| C7 Modelo e contexto | 2 | depois | Só e citou contexto. O bridge de statusline (D1) já traz `context_window.used_percentage` de graça; entra depois como subproduto de D1, sem task própria agora. |
| C8 Contador de compactações | 1 | descartar | b: "técnico demais". Valor especulativo; pode voltar como subproduto de C7. |
| C9 Custo da sessão | 1 | descartar | Rejeitado por todos (usam assinatura; "US$ me deixa ansioso"). Se algo, "% do limite", não dólar. |
| C10 Agrupar por projeto | 2 | depois | O painel preferiu worktree/branch (a, c). Só vale com muitas sessões; depende de C6. |
| C11 Subagentes e tarefas | 2 | depois | Não citado. O app já lista subagentes em background; tarefas exigiriam ler transcript ou mais hooks. |
| C12 Resumo do que mudou | 1 | descartar | Ninguém pediu; f vê como leitura de conteúdo. `git diff --stat` é viável, mas vira produto de outro tipo (Nimbalyst/Desktop). |
| C13 Status Anthropic | 1 | descartar | Exige rede (quebra a promessa); c: "existe a página de status". |
| C14 Texto da barra adaptativo | 2 | depois | Issue real do líder, mas o ClaudeBar mostra só símbolo + número, que já é curto. Valor baixo até a barra ganhar mais texto (ex.: % de limite). |
| C15 Desktop + terminal juntos | 3 | fazer | b põe em top 3 e d confirma (metade do time no desktop). **Já existe em grande parte** via `claude agents --json`. O que falta: rótulo de origem e B1 abrir o app Claude. Custo baixo; comunicar como diferencial (o próprio Claude Desktop não vê o CLI). |

### D. Limites de uso

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| D1 Limites 5 h e semanal | 5 | fazer | 15 pontos; motivo nº 1 de d para procurar o app. **Maior diferencial do plano**: limites sem login e sem rede via statusline bridge (`1b`), enquanto Clabar, Perch e claudewatch usam OAuth. Riscos de retenção: encadear o statusline existente (não sequestrar), mostrar "atualizado há X min" e "indisponível, motivo" em vez de 0%. Número errado = desinstalação (d). |
| D2 Alerta perto do limite | 3 | fazer | d (2 pontos). Barato depois de D1. Um limiar, um alerta por janela; não virar spam. |
| D3 Previsão de ritmo | 4 | fazer | 13 pontos; "60% não muda nada, 16h40 muda" (a, b, c, d). Diferencial (só AgentLimits e o homônimo tddworks têm). **Maior risco de retenção do plano**: previsão errada duas vezes = d desinstala e manda o time desinstalar. Fazer com linguagem conservadora ("no ritmo da última hora"), esconder quando os dados forem poucos ou velhos. |
| D4 "Aproveite antes de renovar" | 1 | descartar | a: "um app me incentivando a usar mais? Não." Ninguém defendeu. |
| D5 Aviso de pausa por limite | 4 | fazer | 7 pontos; e: "volta em 10 min ou 4 h?". "Novo" segundo a pesquisa. Payload exato dos matchers de cota não foi capturado (`1d`): primeiro capturar exemplo real; se não vier, derivar de `resets_at` do D1. Também corrige estado falso (sessão parada parecendo travada). |
| D6 Cache esfriando | 1 | descartar | b e d: "ansiedade gratuita"; TTL é estimativa. Valor só para quem paga por token, que não é o público. |

### E. Notificações

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| E1 Desligar notificação desliga o som | 4 | fazer | Bug documentado no README. Custo trivial; um app que toca som com o aviso desligado quebra confiança. |
| E2 Escolher o que avisa | 3 | fazer | Não está no top de ninguém, mas é o mecanismo de saída para quem ia "desligar tudo em uma semana" (b, c). Três toggles e escolha de som; não mais. |
| E3 Não avisar se você já está olhando | 4 | fazer | Top 5 de a, c, e; "logo atrás" do motivo nº 1 de b. Paridade com os bons (Nudgy, CC Notifier, AgentBar). Reaproveita a detecção de janela/aba do B1; por isso vem depois de B1. Começar por "app do terminal da sessão está na frente" e refinar para aba exata. |
| E4 Foco / horário silencioso | 2 | depois | Não está no top de ninguém. Silenciar no Foco pode ser só respeitar o sistema; com notificação nativa (A2) o macOS já faz isso. Reavaliar depois de A2. |
| E5 Lembrete de espera | 5 | fazer | 10 pontos, top 5 de 5 personas; "eu ignoro o primeiro aviso" (b, c, e, f). Barato (timer no estado `waiting`). Paridade com CC Notifier, mas ataca diretamente a dor nº 1. Um lembrete, intervalo configurável, para quando a sessão sai de `waiting`. |
| E6 Adiar e silenciar por sessão | 2 | depois | Não citado. E5 + E2 cobrem a maior parte. |
| E7 Sessão travada | 2 | depois | a citou na rodada 1, sumiu na rodada 2. Detectar "sem progresso" sem ler transcript exige mais hooks (`PostToolUse`); falso positivo vira ruído. |
| E8 Som só para respostas longas | 3 | fazer | Issue no líder; conversa com "aviso à toa = desligo o som". Custo mínimo (já há timestamp de início do turno). |
| E9 Histórico de alertas | 1 | descartar | Ninguém pediu; f é contra gravar caminhos em disco. |
| E10 Aviso no celular | 1 | descartar | Rejeitado pelas 6; exige relay (contradiz "sem rede"); é onde os concorrentes monetizam, e o público rejeita assinatura. O Remote Control do Claude já cobre. |
| E11 Aprovar pelo celular sem conta | 1 | descartar | Mesmo motivo; aprovar remoto foi visto como perigoso. |
| E12 Slack/Discord | 1 | descartar | d: "canal de spam"; a: problema com segurança. I5 cobre quem quiser montar isso sozinho. |

### F. Vários agentes

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| F1 Codex e Gemini | 2 | depois | Só c (4 pontos), mas forte para ele ("contador mente"). Paridade com VibeBar/Perch/OpenAgentPeek. Painel: depois de B1 funcionar, desligado por padrão. Também conflita com o nome/foco "ClaudeBar". Deixar o modelo de dados sem acoplamento ao Claude, sem implementar. |
| F2 Copilot e outros | 1 | descartar | Ninguém usa no painel. |
| F3 Fila única de permissões | 1 | descartar | Depende de F1 + B6, ambos adiados. |
| F4 Várias contas | 2 | depois | Lacuna real (líder recusou `CLAUDE_CONFIG_DIR`), mas ninguém do painel pediu. Respeitar `CLAUDE_CONFIG_DIR` ao localizar arquivos é higiene barata; suporte multi-conta completo, depois. |

### G. Segurança e controle

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| G1 Radar de comandos perigosos | 1 | descartar | Rejeitado por todos: falsa segurança, papel das permissões do Claude Code. Se falhar, a culpa vira do app. A versão útil é a de e: destacar em vermelho `rm`/`--force` na **pergunta pendente**, sem bloquear nada. |
| G2 Sugerir "sempre permitir" | 1 | descartar | e e f contra ("ia aceitar sem entender"); incentiva relaxar segurança. |

### H. Integrações com o Mac

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| H1 Widget | 1 | descartar | d: "ninguém olha widget". Exige migrar de SPM para bundle com extensão. |
| H2 Botões no widget | 1 | descartar | Depende de H1. |
| H3 Atalhos/Siri | 1 | descartar | "Enfeite" (b, e). H7 entrega automação sem App Intents. |
| H4 Central de Controle | 1 | descartar | Rejeitado; só macOS 26; conflita com A17. |
| H5 Filtros de Foco | 1 | descartar | Ninguém pediu; E4 cobre depois, se necessário. |
| H6 Modo notch | 1 | descartar | Rejeitado por todos; é o produto inteiro de outros apps. |
| H7 CLI `status` / `next` | 4 | fazer | Defendido por a, c, d, f; para f é acessibilidade (texto que o VoiceOver lê); para a é a barra do tmux. Barato: o binário `claudebar-hook` já lê o diretório de estado. Base de B9. Diferencial em relação à maioria (só CodexBar tem CLI). |
| H8 Abrir quando a sessão começa | 1 | descartar | c: "é só A8". Exige o hook disparar `open`, mais acoplamento sem ganho. |

### I. Histórico e produtividade

| # | Nota | Veredito | Análise |
|---|:-:|---|---|
| I1 Resumo enquanto estava fora | 1 | descartar | Exige ler conversa; contradiz o ponto forte. A versão curta de a ("3 terminaram, 1 esperando") já é o próprio menu. |
| I2 Estatísticas do dia | 1 | descartar | b: "produtividade de vitrine, olharia uma vez". |
| I3 Busca nas sessões | 1 | descartar | Lê transcripts; vira gerenciador. |
| I4 Histórico de tokens e custo | 1 | descartar | Rejeitado (custo em US$, lê JSONL). |
| I5 Ação customizada | 2 | depois | Ninguém do painel pediu explicitamente, mas cobre E12 e casos de entusiasta sem o app ter rede. Uma chave no config, sem UI. Fazer só se H7 não bastar. |

### Ideias novas do painel

| Ideia | Nota | Veredito | Análise |
|---|:-:|---|---|
| N1 Distinguir "esperando permissão" de "esperando pergunta" | 5 | fazer | Adotada pelas 6. O evento do hook já diz qual é (`notification_type` / `PermissionRequest`). Custo baixo, não encontrada em concorrente. Símbolo, som e texto distintos (f). |
| N2 Pergunta pendente em uma linha no menu | 4 | fazer | a, b, d, e. "Resolve metade do B6 sem o risco" (d). O texto já vem no hook. Só no menu; popup com conteúdo é opcional. Destaque de `rm`/`--force` aqui substitui G1. |
| N3 Modo "nunca mostrar conteúdo" | 4 | fazer | f (condição), a, b, c, d aderiram. É o que torna N2 aceitável. Um toggle; o popup mostra só "projeto X precisa de você". |
| N4 Página de transparência (hooks instalados, texto, diff, desfazer) | 5 | fazer | 17 pontos, empatado em 4º. Diferencial de confiança: concorrentes instalam, mas não mostram. Funde com A4/A5/A10 numa única tela. Pré-requisito para segurança de empresa (d). |
| N5 Limpeza de sessões fantasmas | 5 | fazer | 3 pontos, mas motivo nº 1/2 de desinstalação para 5 personas. Já existe em parte (`kill(pid,0)`, contagem pela CLI): a task é **provar com teste** os cenários `tmux kill-server`, janela do Cursor fechada, terminal morto, e corrigir o que falhar. |
| N6 "Status: tudo ok" + "testar alerta" sempre disponível | 4 | fazer | e, b, c. Responde ao motivo nº 1 de e ("Claude parou e culpo o app") e ao nº 2 de c (hooks quebrados por atualização). Funde com A6 (detectar), A9 e A14. "Ver exemplo de popup" já existe no menu: é extensão. |
| N7 Legenda dos estados com rótulo por extenso | 3 | fazer | e, b, c, f. Custo mínimo; mesmo trabalho dos rótulos do A15. |
| N8 Popup persistente para permissão | 4 | fazer | f, a, e. Popup que some em 4 s enquanto o usuário digita = aviso perdido = dor nº 1. Mudança pequena no `StatusHUD`: persistir para `waiting`, sumir para "terminou". Também evitar abrir sob o cursor (f). |
| N9 Identificação tmux `sessão:janela.painel` | 3 | depois | Só a. Sai como subproduto do B1-tmux (precisa descobrir o painel para focar); mostrar na linha quando já se tem o dado. |
| N10 `claudebar next` | 4 | fazer | Parte de H7; a, c, f. |
| N11 Uso por sessão em % do limite | 2 | depois | d, a, c. O statusline não dá a fatia de cada sessão no limite; estimar pelo custo é aproximação, e número errado é o motivo nº 1 de d. Depois de D1 estabilizar. |
| N12 Agrupar por worktree/branch | 2 | depois | a, c. Depende de C6; só ajuda com muitas sessões. |
| N13 Configuração exportável para time / MDM | 2 | depois | Só d, "abaixo dos cinco". Arquivo de defaults legível é barato, mas sem usuários de time ainda não há quem valide. |
| N14 Retenção mínima (não gravar caminho/comando além do necessário) | 4 | fazer | Motivo nº 1 de f. É princípio, não feature: o estado de sessão já fica em `0700/0600` e é apagado no `SessionEnd`; garantir que logs (`os_log`) marquem caminhos e comandos como `private` e que nada novo grave histórico. Custo baixo, protege o diferencial. |
| N15 Build reproduzível / hash publicado | 2 | depois | Só f. Publicar SHA-256 no release é barato e entra junto com A1; build reproduzível de verdade, depois. |
| N16 Sem rede verificável | 4 | fazer | f desinstala no primeiro acesso de rede. Diferencial já existente; a "task" é não quebrá-lo (decisão de produto que rejeita A12 com Sparkle, C13, E10–E12) e documentar como verificar. |
| N17 README com GIF de 10 s | 4 | fazer | b, e: "é o que me faz instalar". Adoção pura, custo baixo, mas depende de ter o app gravável (pós B1/ícone). |
| N18 Página "deu errado, e agora?" | 2 | depois | e. Uma seção de troubleshooting no README basta; vira task quando houver issues reais. |
| N19 Documentar SSH/devcontainer | 2 | depois | Só a. Documentação, sem código; quando houver demanda. |
| N20 Prévia de 2 linhas da última resposta / último prompt | 1 | descartar | b, c. Exige conteúdo da conversa (ou campo do `Stop` que precisaria ser verificado); f é contra. N2 cobre o caso que importa. |
| N21 Limites de outras ferramentas ("quem tem fôlego") | 1 | descartar | c; d: "diferencial, mas não agora". Depende de F1 e de fontes de limite de Codex/Gemini. |
| N22 Limites Team/Enterprise | 2 | depois | d. Depende do que o statusline expõe; D1 deve mostrar "indisponível, motivo" em vez de errar. |
| N23 Aviso de sessão esquecida aberta | 1 | descartar | d: ensina errado (sessão ociosa não consome limite). |

---

## 3. Recomendação de ordem (por valor, não por esforço)

1. **Confiança e adoção (sem isso nada importa):** A1, A2, A3, A4 + A5 + N4 (uma tela), N5 (provar fantasmas), E1, N16/N14 como restrições.
2. **O produto:** B1 + B2 com matriz de terminais e fallback honesto; C6; E3 (reusa B1).
3. **Não perder a sessão parada:** N1, N2, N3, N8, E5, C3, E8.
4. **Diferencial forte:** D1 → D5 → D2 → D3 (D3 por último, só com dados suficientes).
5. **Acessibilidade e teclado:** A15, N7, B10, H7 + N10, B9.
6. **Acabamento:** A7, A8, A9, A10, A11, A13, A14 + N6, A6, C5, C15 (rótulo), B3, E2, A16 (medir), N17.

Restrições de produto que valem para todas as tasks:
- Nenhuma conexão de rede.
- Nada lê `transcript_path` nem JSONL.
- Nenhuma escrita no `settings.json` sem mostrar o diff e guardar backup.
- macOS 14 continua suportado.
- Qualquer número ou estado que possa estar errado mostra a idade do dado ou "indisponível", nunca um valor inventado.

## 4. Pendências que dependem do dono do projeto
- **A2:** conta Apple Developer (Developer ID + notarização). Sem ela, A1 sai como DMG ad-hoc com instrução de `xattr`, o que mantém o bloqueio de b, d, e, f.
- **A3 cask oficial:** exige notoriedade mínima no Homebrew; começar com tap próprio.
- **D5:** capturar um payload real de pausa por cota (só acontece batendo o limite).
- Decidir licença (A13) e se o nome "ClaudeBar" segue (existe o homônimo tddworks/ClaudeBar, e o nome usa a marca "Claude").
