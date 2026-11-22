# Roadmap

Ideias ainda válidas e decisões que valem lembrar. Itens que dependem do dono (nome, licença, notarização, release) estão no [`PENDENCIAS.md`](PENDENCIAS.md). Multiagente (Codex, Gemini) e a API `activate(ignoringOtherApps:)` estão no [`TODO.md`](TODO.md).

## Próximos, por valor

| Ideia | Por quê | Depende de |
|---|---|---|
| Ir para a aba exata (Terminal, iTerm2, Ghostty via AppleScript) | Hoje traz a janela, não a aba. | Developer ID: com ad-hoc o macOS pede Automação de novo a cada build. Precisa de `NSAppleEventsUsageDescription`. |
| Aviso perto do limite (ex.: 80% da janela de 5 h) | Barato com os limites já no menu. | Confirmar que o número do statusline é confiável. |
| Pausa por limite com motivo | Dizer "pausado até 14h" em vez de "falhou". | Um payload real ao bater o limite (`PENDENCIAS.md`). |
| Atalho global "próxima sessão esperando" | Já existe `claudebar-hook next`; falta a tecla. `RegisterEventHotKey` não pede Acessibilidade. | — |
| Copiar diagnóstico anonimizado | Suporte sem pedir print. Precisa de prévia e caminhos anonimizados. | — |
| Rótulo "app desktop" × "terminal" na linha | Falta confirmar que os hooks disparam no app desktop. | — |
| Homebrew | Instalar e atualizar com um comando. Serve de auto-update, sem abrir rede no app. | Nome, licença, notarização. |

Depois, se alguém pedir: previsão de ritmo dos limites (só com amostras suficientes; previsão errada faz desinstalar), cronômetro "esperando há X", pergunta pendente em uma linha (só atrás do modo sem conteúdo, truncada), agrupar por worktree, modelo/contexto da sessão, várias contas (`CLAUDE_CONFIG_DIR`), ação customizada por mudança de estado (executável + args fixos, dados via env).

## Adiados pelas specs

- **Glifo próprio na barra.** Decisão: a barra continua com SF Symbols. Os PNGs do design cobrem só 4 estados e hoje são 7 (permissão, pergunta e falha entraram depois). Por isso os PNGs **não** foram copiados. O script que gera tudo está em [`docs/design/`](docs/design/README.md); se um dia quiser o glifo, estenda o script para os 7 estados e carregue de `Bundle.main` com fallback para o SF Symbol.
- **Plano B do iTerm2.** Se "Ir para a sessão" falhar no iTerm2 (o `iTermServer` pode ter o `launchd` como pai, e a subida da árvore não acha o app): o hook grava `__CFBundleIdentifier` do ambiente como campo **opcional** no arquivo de estado, e o app usa esse id quando a subida falhar. PR próprio, só com a falha confirmada.
- **tmux com socket não padrão** (`-L`, `TMUX_TMPDIR`): sem suporte. Mesmo caminho: gravar `TMUX` no arquivo, só se alguém pedir.
- **`elicitation_url_dialog` → pergunta.** Basta trocar o matcher do `Notification` para `elicitation_dialog|elicitation_url_dialog` no `HookInstaller.entries`.
- **Checagem de rede no binário** (`nm` no `build-app.sh`): entra junto com a primeira dependência SwiftPM. Hoje o `NoNetworkTests` já varre `Sources/`.
- **Ícone com variantes Liquid Glass** (macOS 26): montar no Icon Composer a partir das camadas fundo + chevron + ponto.

## Descartado (e por quê)

Não reabrir sem fato novo:

- **Aprovar permissão pelo popup** e **responder pelo popup**: risco alto (clique acidental aprova comando, injeção de prompt, segredo na tela).
- **Celular, Slack, Discord, status da Anthropic, auto-update próprio**: abrem rede, quebram a promessa "sem rede".
- **Custo em US$, histórico de tokens, resumo do que a sessão fez, busca nas sessões**: exigem ler a conversa.
- **Ícone animado**: rejeitado no painel de usuários (CPU, Reduce Motion).
- **Widget, Central de Controle, Filtros de Foco, Atalhos**: exigem extensão ou projeto Xcode; SwiftPM não gera.
- **"Sessão travada"**: sem sinal de progresso vira falso alarme.

## Decisões técnicas que valem lembrar

- Duas fontes juntadas por `sessionId`: `claude agents --json` (quem existe) + hooks (estado na hora). O CLI é consultado por evento e a cada 60 s, não em polling curto. Com o menu aberto, só `RunLoop.main.perform(inModes: [.common])` roda; não existe "consultar ao abrir o menu".
- Toda escrita no `settings.json` passa por prévia + backup + clique. Um instalador só (`HookInstaller`), sem `jq`.
- Hook sempre fail-open (nunca `exit 2`). Testes nunca tocam o `~/.claude` real: use `CFFIXED_USER_HOME` (o `HOME` sozinho não basta, o `NSHomeDirectory()` ignora).
- Popup próprio (`NSPanel`) porque a Central de Notificações recusa app ad-hoc. Notificação nativa volta a ser opção com o Developer ID.
