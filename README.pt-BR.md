# ClaudeBar

App nativo de barra de menu do macOS que mostra se o Claude Code terminou de
processar — em todas as sessões abertas ao mesmo tempo.

```
🔸 2      ← duas sessões abertas, alguma querendo sua atenção
```

O número mostra quantas sessões do Claude Code estão abertas. O símbolo ao
lado diz o que está acontecendo nelas:

| Símbolo (SF Symbol) | Significado |
|---|---|
| `circle.dotted` | nenhuma sessão ativa |
| `ellipsis.circle` | Claude processando |
| `checkmark.circle.fill` | resposta pronta (você ainda não viu) |
| `exclamationmark.bubble.fill` | Claude esperando você (permissão, escolha) |

Quando várias coisas acontecem ao mesmo tempo, vale a mais urgente:
**esperando > pronto (não visto) > processando > ocioso**.

> English version: [README.md](README.md).

## Requisitos

- macOS 14 (Sonoma) ou mais novo
- Toolchain Swift 6 (Xcode 16+) para compilar
- [Claude Code](https://docs.claude.com/claude-code) instalado (CLI `claude`)
- `jq`, só para o script de instalação (`brew install jq`)

## Funcionalidades

### O menu

Clicar no ícone da barra lista todas as sessões, das mais recentes para as mais
antigas, com os subagentes em background agrupados no fim:

```
✅  my-app — pronto (há 2 min)
⏳  ClaudeBar — processando (há 10 s)
🔸  [subagente] review-pr — aguardando você (há 1 min)
──────────────
Marcar tudo como visto
──────────────
Notificações  ✓
Ver exemplo de popup
──────────────
Atualizar
Sair do ClaudeBar        ⌘Q
```

Cada linha de sessão abre um submenu com:

- o caminho completo do projeto,
- **Marcar como visto** — apaga o estado verde de "pronto" daquela sessão,
- **Finalizar** — quando possível (veja [Finalizar uma sessão](#finalizar-uma-sessão)).

O app não tem ícone no Dock nem janela; vive só na barra de menu
(`LSUIElement`).

### Avisos

São dois avisos, cada um com som próprio, porque um é informativo e o outro te
bloqueia:

| Transição | Aviso | Som | Volume |
|---|---|---|---|
| processando → pronto | "Claude terminou" + nome do projeto | `Glass` (sino claro) | 100% |
| → aguardando você | "Claude está esperando você" + a mensagem do Claude | `Submarine` (pulso grave) | 75% |

- O som sai pelo `NSSound`, não pela notificação: é o único jeito de escolher
  som e volume por tipo de aviso. Dá para saber qual dos dois aconteceu sem
  olhar a tela.
- A mensagem do aviso de "esperando" é o que o Claude Code manda para o hook
  `Notification` (ex.: *"Claude needs your permission to use Bash"*), limitada
  a 200 caracteres.
- Subagente nunca avisa.
- O item **Notificações** no menu liga e desliga o popup. A escolha fica salva
  no `UserDefaults` e vem ligada por padrão. Atenção: no código atual o som
  continua tocando com o item desligado (`Notifier.post` toca o som antes de
  checar o toggle).

#### Por que o popup é desenhado pelo app

A Central de Notificações do macOS recusa app assinado ad-hoc:

```
requestAuthorization falhou: Notifications are not allowed for this application
status de autorização: 1 (denied)
```

Não é permissão que você negou — é o sistema recusando a API para bundle sem
Developer ID (`TeamIdentifier=not set`); `lsregister` não muda isso. Então o
aviso sai num `NSPanel` flutuante próprio, no canto superior direito da tela
onde está o mouse, que some em 4s ou ao clique — e não depende de assinatura
nem de permissão.

Se algum dia o app for assinado com Developer ID, o `Notifier` passa a usar a
notificação nativa sozinho: ele prefere a nativa e só cai no painel próprio
quando a autorização não existe. O mesmo painel é usado quando o app roda sem
bundle (`swift run`).

Para diagnosticar (`log` é builtin do zsh, use o caminho absoluto):

```bash
/usr/bin/log show --last 5m --info --debug --predicate 'subsystem == "com.joaomarcos.claudebar"'
```

### Finalizar uma sessão

O jeito certo de encerrar depende do tipo de sessão, então o alvo é escolhido
por linha:

| Situação | Ação | Efeito |
|---|---|---|
| Subagente background | `claude stop <id>` | Encerramento oficial, retomável com `claude attach <id>` |
| Sessão de terminal (`pgid == pid`) | `SIGTERM` no processo | Conversa salva (volte com `claude --resume`), mas o que estava rodando para na hora e o terminal fica com um shell vazio |
| **Sessão do app desktop** | nenhuma — o menu explica | Feche pelo próprio app |
| PID reciclado ou inexistente | nenhuma | — |

Toda finalização passa por uma confirmação que diz exatamente o que vai
acontecer, porque o menu se reordena conforme as sessões mudam de estado e um
clique errado mataria a sessão errada.

#### Por que a sessão do app desktop não é encerrável daqui

Ela não lidera o próprio grupo de processos: roda dentro do grupo do
`Claude.app`, junto do app e das sessões irmãs.

```
pessoal-55 (terminal)   pid=23667  pgid=23667   <- grupo próprio
code-26    (desktop)    pid=35282  pgid=16958   <- grupo do Claude.app (15 processos)
```

Encerrar por ali derrubava mais de uma sessão de uma vez. O app agora usa
`pgid == pid` como discriminador e simplesmente não oferece a opção para sessão
hospedada — mostra o motivo no lugar do botão.

Outras guardas no mesmo caminho:

- **`SIGTERM`, não `SIGKILL`**: o Claude Code ainda fecha o transcript e roda o
  hook de saída.
- **PID é reciclado pelo sistema.** Antes de sinalizar, o app confere via
  `proc_pidpath` que aquele PID ainda é um processo do Claude — um estado velho
  não pode matar processo alheio que herdou o número.
- **`pid: 0`** (o que o hook grava quando não recebeu `--pid`) é tratado como
  ausente: sinalizar `0` atingiria o grupo de processos inteiro.

### Subagentes

Agente despachado em background aparece no menu com a tag `[subagente]`, mas
**não** entra no contador, **não** muda o ícone e **não** toca som — é trabalho
que você delegou, não sessão sua esperando resposta. Encerra-se por
`claude stop`.

Subagente in-process (a ferramenta Task) não aparece de forma alguma: ele roda
dentro do processo da sessão que o criou, e o `claude agents --json` só lista
`kind: "interactive"` e `kind: "background"`.

## Como funciona

Duas origens, cada uma boa no que a outra é ruim:

```
                        quais sessões existem
claude agents --json ─────────────────────────┐
  (poll de 5s, ~150ms por chamada)            │
                                              ├──> ClaudeBar.app ──> 🔸 3
Claude Code ──(hooks)──> claudebar-hook ──────┘
                            │       em que estado cada uma está
                            └─escreve─> ~/.claude/claudebar/<session_id>.json
                                        (DispatchSource: reage em ms)
```

- **`claude agents --json`** lista todas as sessões abertas, inclusive as que
  nunca dispararam um hook — é o que define o **número** na barra. Só é
  consultado a cada 5 segundos (fora da main thread), então não serve para
  reagir a mudanças.
- **Os hooks** chegam no instante em que o estado muda — é o que define o
  **símbolo**. Mas só conhecem sessões que já dispararam algum evento.

O cruzamento é por `sessionId`: o CLI manda na lista, o hook manda no estado.
Se o CLI não estiver acessível, o app cai de volta para o que os hooks
gravaram, em vez de zerar a lista. Se uma sessão só aparece no CLI, o status
dele (`idle` / `waiting` / `blocked`, ou nenhum = processando) é usado como
reserva.

| Hook | Estado gravado |
|---|---|
| `UserPromptSubmit` | `working` |
| `Stop` | `idle` |
| `Notification` | `waiting` |
| `SessionEnd` | apaga o arquivo |

Um arquivo de estado tem esta cara:

```json
{
  "cwd" : "/Users/me/code/my-project",
  "message" : "Claude needs your permission to use Bash",
  "pid" : 23667,
  "sessionId" : "1f6c…",
  "state" : "waiting",
  "updatedAt" : 1791400000
}
```

Duas decisões que evitam problemas clássicos:

- **Um arquivo por sessão.** Várias sessões escrevendo no mesmo arquivo daria
  disputa de escrita; separando por `session_id`, o problema deixa de existir.
  A escrita ainda é atômica, para o app nunca ler um JSON pela metade.
- **PID gravado junto.** Sessão que morre por `kill` ou crash nunca dispara o
  `SessionEnd` e deixaria um arquivo eterno dizendo "processando". O app checa
  `kill(pid, 0)` e apaga o que ficou órfão.

O caminho do `claude` é resolvido em caminhos conhecidos (`~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) e, como último recurso, via
`zsh -lc "command -v claude"`: um app de barra de menu não herda o `PATH` do
seu shell.

## Estrutura

```
Package.swift                 SwiftPM, macOS 14, 3 targets + testes
Sources/ClaudeBarCore/        modelo compartilhado + leitura/escrita do diretório de estado
  SessionStatus.swift         estado da sessão (working/idle/waiting), PID vivo
  StatusDirectory.swift       ~/.claude/claudebar: permissões, escrita atômica, limpeza
Sources/claudebar-hook/       CLI chamado pelos hooks (sem dependência de jq/python)
  main.swift                  lê o JSON do hook no stdin, grava/apaga o arquivo de estado
Sources/ClaudeBar/            app SwiftUI (MenuBarExtra)
  ClaudeBarApp.swift          ponto de entrada, rótulo da barra (símbolo + número)
  MenuContent.swift           o menu
  SessionStore.swift          liga as origens às regras e detecta transições
  SessionMerge.swift          as regras, em funções puras (é o que os testes cobrem)
  SessionRow.swift            linha do menu: cruzamento das duas origens
  AgentsProbe.swift           chama `claude agents --json` e traduz o status
  DirectoryWatcher.swift      DispatchSource observando o diretório de estado
  SessionTerminator.swift     escolha do alvo (SIGTERM ou `claude stop`) e execução
  ProcessProbe.swift          topologia do processo: lidera o grupo? ainda é claude?
  Notifier.swift              som por tipo de aviso, toggle, nativa vs. popup próprio
  StatusHUD.swift             o popup próprio (NSPanel flutuante)
  Shell.swift                 execução de processo sem shell (sem injeção)
Tests/ClaudeBarTests/         subagente, contagem, ícone, precedência e o kill real
scripts/build-app.sh          monta build/ClaudeBar.app (LSUIElement, assinado ad-hoc)
scripts/install.sh            instala em ~/Applications e registra os hooks
```

## Instalação

```bash
./scripts/install.sh
```

O script:

1. compila o app em release (`scripts/build-app.sh`),
2. copia para `~/Applications/ClaudeBar.app`,
3. faz backup do `~/.claude/settings.json` em `settings.json.bak.<timestamp>`,
4. registra os quatro hooks, passando `--pid $PPID` para o app saber qual
   processo do Claude disparou cada um,
5. abre o app.

Bom saber:

- O `~/.claude/settings.json` precisa já existir.
- O resto do `settings.json` é preservado, mas hooks que você já tinha em
  `UserPromptSubmit`, `Stop`, `Notification` ou `SessionEnd` são
  **substituídos**. Recupere do backup se precisar.
- Os hooks valem a partir das **novas** sessões do Claude Code.

Para rodar no login: Ajustes do Sistema → Geral → Itens de Início → adicionar
`~/Applications/ClaudeBar.app`.

## Desenvolvimento

```bash
swift build                  # compila
swift test                   # regras de merge, contagem, ícone, avisos, finalização
./scripts/build-app.sh       # monta o .app

# simula uma sessão sem precisar do Claude
echo '{"session_id":"teste","cwd":"/tmp"}' | \
  build/ClaudeBar.app/Contents/MacOS/claudebar-hook working --pid 1
```

Uso do CLI do hook:

```
claudebar-hook <working|idle|waiting|end> [--pid <pid do claude>]
```

Ele lê o payload do hook (`session_id`, `cwd`, `message`) no stdin. Se falhar
ao gravar, só registra no stderr e sai normalmente — um hook nunca deve
derrubar a sessão do Claude.

`swift run ClaudeBar` também funciona. Sem bundle não há notificação nativa,
então o app usa o popup próprio e o som.

Os testes de finalização usam processos de verdade: sobem processos filhos,
conferem a detecção de grupo de processos, mandam `SIGTERM` e garantem que
encerrar uma sessão não derruba a irmã.

## Segurança

- **Sem segredo nenhum no projeto.** O app não fala com rede, não autentica em
  nada e não lê o histórico das conversas — só caminhos de projeto,
  `sessionId`, o estado da sessão e a mensagem de notificação do hook.
- **`~/.claude/claudebar` é `0700`, os arquivos `0600`.** O conteúdo revela em
  que projetos você trabalha, então fica fora do alcance de outros usuários da
  máquina.
- **`sessionId` é sanitizado** antes de virar nome de arquivo: só
  `[A-Za-z0-9-_]`, o resto vira `-`. Um `session_id` malicioso com `../` não
  escapa do diretório.
- **Nenhum comando passa por shell.** O `claude` é invocado via `Process` com
  argumentos separados — não há interpolação, então não há injeção. A única
  exceção é o `zsh -lc "command -v claude"`, usado apenas como último recurso
  quando o binário não está nos caminhos conhecidos.
- **`message` é truncada em 200 caracteres** antes de ser exibida.

## Desinstalar

```bash
pkill -f ClaudeBar.app
rm -rf ~/Applications/ClaudeBar.app ~/.claude/claudebar
# e remover as quatro entradas do claudebar-hook em "hooks" no ~/.claude/settings.json
```
