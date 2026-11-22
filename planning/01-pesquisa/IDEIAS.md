# Ideias candidatas para o ClaudeBar (lista consolidada)

> Fonte: `00-brainStorm.md` + `01-pesquisa/1a..1d`. Deduplicada, em linguagem de usuário.
> Origem: concorrente(s) que já têm, ou "novo" (não encontrado nos concorrentes pesquisados).

## A. Produto pronto

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| A1 | Instalador fácil (download pronto) | Baixar um arquivo, arrastar para Aplicativos e usar, sem compilar nada nem instalar ferramentas extras. | Claude Status Bar, Perch, Nudgy, VibeBar, AgentBar |
| A2 | App assinado e verificado pela Apple | O Mac abre o app sem alerta de "desenvolvedor não identificado" e as notificações do sistema funcionam. | Claude Status Bar, AgentBar, Perch |
| A3 | Instalar pelo Homebrew | Quem usa Homebrew instala e atualiza com um comando. | Claude Status Bar (oficial), AgentBar, VibeBar |
| A4 | Configuração automática no primeiro uso | O app se conecta ao Claude Code sozinho na primeira vez, sem apagar configurações que você já tinha e guardando uma cópia de segurança. | Claude Status Bar, Nudgy, Clabar, Perch, ClaudeDot |
| A5 | Remover a integração com um clique | Desfaz tudo que o app mudou no Claude Code, deixando suas configurações como eram. | Claude Status Bar, Perch, Claude Status, Nudgy |
| A6 | Reparo automático da conexão | Se você mover o app de pasta ou atualizar, ele percebe que a conexão quebrou e conserta sozinho. | novo |
| A7 | Ícone próprio do app | Um ícone único e reconhecível no Finder, no Launchpad e na barra de menu. | todos os concorrentes distribuídos |
| A8 | Abrir ao iniciar o Mac | Um botão para o app abrir sozinho quando você liga o computador. | Claude Status, AgentPulse, VibeBar, Perch |
| A9 | Janela de Ajustes | Um lugar só para escolher notificações, sons, abrir no login, idioma e ver se a conexão está ok. | Claude Status, Nudgy, AgentBar, VibeBar |
| A10 | Tela de boas-vindas | No primeiro uso, explica o que o app faz, conecta ao Claude Code e mostra um alerta de exemplo. | Claude Status (prompt de instalação), Claude Status Bar |
| A11 | App em inglês (e português) | Interface em inglês por padrão, com português disponível, seguindo o idioma do Mac. | CC Notifier (17 idiomas), Clabar (7), ClaudeDot (8), VibeBar (4) |
| A12 | Atualização automática | O app avisa ou instala sozinho quando sai versão nova. | Clabar, Perch, Claude Status Bar (aviso), VibeBar (aviso) |
| A13 | Tela "Sobre" | Mostra versão, link do projeto e licença. | comum em apps de Mac |
| A14 | Copiar diagnóstico / reportar problema | Um botão copia as informações técnicas para colar num pedido de ajuda. | Perch ("Report an Issue"), AgentBar (doctor), Pulse (doctor) |
| A15 | Leitura por VoiceOver | O ícone e as sessões são lidos em voz alta para quem usa leitor de tela ("2 sessões, 1 esperando você"). | novo |
| A16 | Leve no processador | O app não pesa na bateria nem no processador, mesmo com animação. | requisito (Claude Status Bar teve problema de CPU) |
| A17 | Funcionar em macOS mais antigos | Rodar a partir do macOS 14, sem exigir a versão mais nova do sistema. | gap do Claude Status (exige 26.2) |

## B. Ações a partir do menu

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| B1 | Ir para a sessão com um clique | Clicar na sessão traz para frente o terminal ou editor certo, idealmente a aba exata. | Claude Status (aba/pane/tmux), AgentBar, Nudgy, ClaudeDot, VibeBar, Perch, AgentPulse |
| B2 | Clicar no alerta leva à sessão | Clicar no popup ou na notificação abre a sessão que avisou, em vez de só fechar. | Nudgy ("Go"), AgentBar |
| B3 | Abrir a pasta do projeto | Abre a pasta da sessão no Finder ou no seu editor. | Claude Desktop ("Open in") |
| B4 | Copiar comando para retomar | Copia o comando que continua aquela conversa depois. | AgentBar (Copy command), Clabar |
| B5 | Retomar sessão encerrada | Abre um terminal na pasta certa já continuando a conversa que terminou. | ccmanager, Nimbalyst, Claude Squad |
| B6 | Aprovar ou negar permissão pelo alerta | Quando o Claude pede permissão, você responde "Permitir" ou "Negar" direto no popup, sem ir ao terminal. | Perch, Vibe Notch, AgentPeek, CC Gate, Claude Peek, CC Notifier (celular) |
| B7 | Responder perguntas de ferramentas pelo popup | Quando uma ferramenta conectada pede um dado ou confirmação, o formulário aparece no popup. | novo |
| B8 | Mandar a próxima instrução pelo popup | Quando o Claude termina, você digita "pode seguir" no próprio alerta e ele continua. | CC Notifier (celular); novo no Mac |
| B9 | Atalho de teclado global | Uma tecla abre o menu ou pula direto para a próxima sessão que precisa de você. | AgentBar, Clabar |
| B10 | Navegar pelo teclado no menu | Setas e Enter para escolher e abrir sessões sem mouse. | AgentBar |

## C. Informação na barra e no menu

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| C1 | Ícone animado enquanto trabalha | O ícone se mexe enquanto o Claude pensa, e para quando termina. | Claude Status Bar, ClaudeDot, Pulse, VibeBar |
| C2 | Escolher estilo e cor do ícone | Opções de desenho e cor (monocromático ou colorido) para o ícone da barra. | Claude Status Bar, Perch, VibeBar |
| C3 | Cronômetro da sessão | Mostra há quanto tempo está trabalhando ou esperando você, e quanto durou a última resposta. | Claude Status Bar, AgentBar, Pulse, VibeBar |
| C4 | O que está fazendo agora | Mostra a ação atual ("editando arquivo", "rodando comando"). | Claude Status Bar, AgentBar, Pulse, Perch |
| C5 | Estado de erro | Ícone próprio quando a resposta falhou por erro, em vez de parecer que terminou bem. | Nudgy, Clabar, Pulse |
| C6 | Nome da sessão e branch | Mostra o nome que você deu à sessão e a branch, não só a pasta. | Claude Status, VibeBar, Pulse |
| C7 | Modelo, modo e contexto usado | Mostra qual modelo a sessão usa e quanto da memória da conversa já foi ocupado, com aviso perto do limite. | AgentBar, Perch, claudewatch, OpenAgentPeek |
| C8 | Contador de compactações | Avisa quando a conversa já foi resumida várias vezes e talvez seja hora de começar outra. | novo |
| C9 | Custo da sessão | Mostra uma estimativa de quanto a sessão custou. | Perch, claudewatch, Nudgy, VibeBar |
| C10 | Agrupar por projeto | Sessões do mesmo projeto ficam juntas, com contagem de quantas estão ativas ou esperando. | VibeBar, ccmanager, claudewatch |
| C11 | Subagentes e tarefas visíveis | Mostra os ajudantes e a lista de tarefas da sessão dentro dela. | Perch, Pulse |
| C12 | Resumo do que mudou | Mostra quantas linhas e quais arquivos a sessão alterou; clicar abre o arquivo. | Nimbalyst, Claude Desktop |
| C13 | Status do serviço Anthropic | Avisa quando o serviço do Claude está com instabilidade. | Clabar, claudewatch |
| C14 | Texto da barra que se adapta | Quando a barra está cheia, o app mostra só o ícone para não cobrir outros itens. | gap do Claude Status Bar |
| C15 | Sessões do terminal e do app desktop juntas | Uma lista só com tudo que roda no terminal, no editor e no app Claude. | novo (Claude Desktop não vê sessões do terminal) |

## D. Limites de uso

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| D1 | Limites de 5 horas e semanal | Mostra quanto do seu limite já usou e quando ele renova, sem login e sem mandar dados pela internet. | Clabar, Perch, claudewatch, CodexBar, AgentLimits, CC Usage Tracker |
| D2 | Alerta perto do limite | Avisa quando passa de um certo percentual (ex.: 85%). | Clabar, ClaudeUsageBar |
| D3 | Previsão de ritmo | Diz se, no ritmo atual, você vai bater o limite antes de renovar. | AgentLimits, tddworks ClaudeBar |
| D4 | Lembrete de "aproveite antes de renovar" | Avisa quando sobra muito limite perto da renovação. | Clabar |
| D5 | Aviso de pausa por limite | Quando a sessão para por ter batido o limite, mostra isso e a hora em que volta sozinha. | novo |
| D6 | Aviso de cache esfriando | Depois que o Claude responde, mostra quanto tempo você tem para continuar sem que o próximo passo fique mais caro. | novo |

## E. Notificações

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| E1 | Desligar notificações desliga o som também | Corrige o som que toca mesmo com notificações desligadas. | bug do próprio app |
| E2 | Escolher o que avisa | Liga e desliga separadamente "terminou", "esperando você", som, e escolhe qual som. | Nudgy, AgentBar |
| E3 | Não avisar se você já está olhando | Se o terminal da sessão já está na frente, o app não interrompe. | CC Notifier, Nudgy |
| E4 | Respeitar Foco / Não Perturbe e horário silencioso | Fica quieto nos horários ou modos de Foco que você escolher. | AgentBar, CC Notifier |
| E5 | Lembrete de espera | Se a sessão ficar te esperando por vários minutos, avisa de novo. | CC Notifier |
| E6 | Adiar e silenciar por sessão | "Lembrar em 10 min" no alerta e silenciar uma sessão específica. | AgentBar |
| E7 | Alerta de sessão travada | Avisa quando uma sessão está "trabalhando" há muito tempo sem nenhum progresso. | Pulse, amux |
| E8 | Som só para respostas longas | Não toca som para respostas rápidas de poucos segundos. | pedido em issue do Claude Status Bar |
| E9 | Histórico de alertas | Uma lista dos avisos anteriores, para ver o que perdeu. | Clabar, CC Notifier, AgentBar |
| E10 | Aviso no celular | Recebe no iPhone quando o Claude termina ou precisa de você, mesmo longe do Mac. | CC Notifier (pago), Perch, Pushary |
| E11 | Aprovar pelo celular sem conta | Responde permissões pelo iPhone sem criar conta nem pagar assinatura. | novo (concorrentes exigem conta/servidor) |
| E12 | Avisar no Slack/Discord | Manda o aviso para um canal de chat. | CC Notifier |

## F. Vários agentes

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| F1 | Acompanhar Codex e Gemini | Ver sessões de outros assistentes de código no mesmo menu, com ícone de cada um. | VibeBar, Perch, OpenAgentPeek |
| F2 | Acompanhar Copilot e outros | Suporte a GitHub Copilot CLI e similares. | AgentBar, VibeBar |
| F3 | Fila única de permissões | Todos os pedidos de permissão de todos os agentes numa fila só. | novo |
| F4 | Várias contas do Claude | Funciona com mais de uma conta/perfil do Claude Code no mesmo Mac. | Claude Status, AgentBar, VibeBar |

## G. Segurança e controle

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| G1 | Radar de comandos perigosos | Avisa ou pede confirmação antes de comandos destrutivos (apagar tudo, forçar push), mesmo em modo automático. | Pulse |
| G2 | Sugerir regra "sempre permitir" | Depois de aprovar o mesmo pedido várias vezes, o app oferece transformar em regra, mostrando o texto exato antes. | novo |

## H. Integrações com o Mac

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| H1 | Widget na mesa | Um widget mostra as sessões (e limites) sem abrir o menu. | Claude Status, AgentLimits |
| H2 | Botões no widget | Marcar como visto ou abrir o terminal direto do widget. | novo |
| H3 | Ações no app Atalhos/Siri | "Quantas sessões me esperam?", "marcar tudo como visto" em automações. | novo |
| H4 | Controle na Central de Controle | Botões rápidos do app na Central de Controle do macOS 26. | novo |
| H5 | Filtros de Foco | Cada modo de Foco do Mac define que avisos o app mostra. | novo |
| H6 | Modo notch | Mostrar as sessões em volta do entalhe da tela dos MacBooks. | VibeBar, Vibe Notch, Vibe Island |
| H7 | Comando de terminal / link para scripts | Outros programas (tmux, barras customizadas) consultam o estado das sessões. | CodexBar (CLI), tddworks ClaudeBar (`claudebar://`) |
| H8 | Abrir quando uma sessão começa | O app se abre sozinho quando você inicia o Claude Code. | Claude Status Bar |

## I. Histórico e produtividade

| # | Ideia | O que o usuário ganha | Origem |
|---|---|---|---|
| I1 | Resumo "enquanto você estava fora" | Ao voltar ao Mac, um cartão mostra o que cada sessão fez na sua ausência. | novo |
| I2 | Estatísticas do dia | Quantas respostas, tempo trabalhando e tempo que o Claude ficou esperando você. | Claude Status, CC Notifier, Pulse |
| I3 | Busca nas sessões | Procurar uma conversa antiga pelo título ou texto e retomá-la. | Clabar, Nimbalyst |
| I4 | Histórico de tokens e custo | Gráfico de uso por dia e por modelo (opcional, pois exige ler o histórico local). | VibeBar, Opcode, ccusage |
| I5 | Ação customizada na mudança de estado | Rodar um comando seu quando uma sessão passa a esperar você. | ccmanager |

## Descartadas (fora do escopo "leve")
Gerenciar worktrees/branches/PR, visualizador de diff, terminal embutido, kanban de tarefas, iniciar e orquestrar agentes, auto-aprovação por IA, sandbox em container, app iOS próprio com servidor, sincronização na nuvem, ler conversas inteiras por padrão.
