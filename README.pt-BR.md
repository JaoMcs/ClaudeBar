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
| `exclamationmark.triangle.fill` | a resposta falhou (erro de API) e você ainda não viu |
| `hand.raised.fill` | Claude pede permissão para usar uma ferramenta |
| `questionmark.bubble.fill` | Claude fez uma pergunta |
| `exclamationmark.bubble.fill` | Claude esperando você (sem motivo conhecido, ou motivos misturados) |

Quando várias coisas acontecem ao mesmo tempo, vale a mais urgente:
**permissão > esperando > pergunta > falhou (não visto) > pronto (não visto) > processando > ocioso**.
"Pergunta" só aparece quando todas as esperas são pergunta; a permissão vence
porque trava uma ferramenta que já está em andamento.

> English version: [README.md](README.md).

## Requisitos

- macOS 14 (Sonoma) ou mais novo
- Toolchain Swift 6 (Xcode 16+) para compilar
- [Claude Code](https://docs.claude.com/claude-code) 2.1.139 ou mais novo instalado
  (CLI `claude`; os hooks usam exec form, `args`). O estado "falhou" precisa
  de uma versão do Claude Code com o hook `StopFailure`; versões sem ele
  mantêm a sessão que falhou como *processando*

## Funcionalidades

### O menu

Clicar no ícone da barra lista todas as sessões, das mais recentes para as mais
antigas, com os subagentes em background agrupados no fim:

```
✅  my-app — pronto (há 2 min)
⏳  ClaudeBar · feat/x — processando (há 10 s)
⚠️  api — falhou (há 1 min)
✋  infra — pede permissão (há 20 s)
❓  docs — fez uma pergunta (há 5 s)
🔸  [subagente] review-pr — aguardando você (há 1 min)
──────────────
Marcar tudo como visto
──────────────
Notificações  ✓
Ver exemplo de popup
Ajustes…                 ⌘,
──────────────
Integração com o Claude Code: ok  ▸
Atualizar
Sair do ClaudeBar        ⌘Q
```

Cada linha de sessão abre um submenu com:

- o caminho completo do projeto,
- **Abrir pasta do projeto**: abre o `cwd` no Finder (só pastas de verdade; um
  `.app` nunca é executado),
- **Ir para a sessão**: traz para a frente o terminal ou app onde a sessão roda
  (veja [Ir para a sessão](#ir-para-a-sessão)); não aparece para subagente
  background,
- quando a resposta falhou, o código e o detalhe do erro da API
  (ex.: `rate_limit — 429 Too Many Requests`),
- **Marcar como visto** — apaga o destaque de "pronto" ou "falhou" na barra
  para aquela sessão (a linha que falhou continua ⚠️ até o próximo prompt),
- **Finalizar** — quando possível (veja [Finalizar uma sessão](#finalizar-uma-sessão)).

O app não tem ícone no Dock nem janela; vive só na barra de menu
(`LSUIElement`).

### Integração com o Claude Code

O submenu **Integração** mostra se os hooks estão no lugar e deixa você cuidar
deles sem o terminal. O título é o estado: `ok`, `hooks não instalados` ou
`⚠︎ precisa de atenção`; a primeira linha lá dentro diz o que está errado.

- **Instalar hooks… / Reinstalar hooks…** — registra os hooks do ClaudeBar e
  copia o executável do hook para `~/.claude/claudebar/bin/`. Também é assim
  que se repara entrada faltando, desatualizada ou no formato antigo.
- **Remover hooks…** — tira só as entradas do ClaudeBar e a cópia do
  executável.
- **Copiar JSON dos hooks** — aparece no lugar de instalar quando o
  `settings.json` é somente leitura (gerado por dotfiles, Nix…): copia o
  executável e põe o JSON do bloco `hooks` na área de transferência, para
  você colar na ferramenta que gera o arquivo.
- **Testar integração** — um teste ponta a ponta e, no fim, o popup de
  exemplo. Responde "por que o ícone não muda?" com ✓/✗ para cada item: hooks
  registrados no `settings.json`; executável do hook presente; executável
  igual ao deste app; e o hook **rodou de verdade e gravou** o arquivo de
  estado (o app roda o hook como o Claude Code rodaria, com uma sessão de
  teste apagada logo em seguida; hook travado é encerrado em 3 s, então o app
  nunca congela). Mostra também quando chegou o último evento real e avisa do
  `disableAllHooks`. O que não dá para ver daqui: `disableAllHooks` em
  settings de projeto e `allowManagedHooksOnly` em settings gerenciado —
  confira o `/hooks` dentro do Claude Code. E o Claude Code retém os hooks até
  você aceitar o diálogo de confiança da pasta: com sessões abertas e nenhum
  evento recebido, o teste avisa.
- **Atualizar** também confere a integração de novo.

Nada é gravado sem um alerta antes. Ele mostra o arquivo de verdade (symlink
resolvido), o diff exato do bloco `hooks` — nunca o resto do arquivo, que pode
ter token em `env` —, onde fica o backup e se o arquivo vai ser reformatado.
Só o botão **Instalar** / **Remover** grava. Se o `settings.json` mudar com o
alerta aberto (o Claude Code também grava nele), você vê uma prévia nova em
vez de uma escrita às cegas.

Na primeira abertura, e sempre que a integração precisar de reparo, o mesmo
alerta aparece sozinho **uma vez**, com **Pular** no lugar de cancelar. Pular
não grava nada e o app não pergunta de novo enquanto o estado não mudar; o
submenu continua lá. Depois de atualizar o `.app`, a cópia do executável fica
mais velha que a do bundle, e o app oferece atualizá-la do mesmo jeito.

Com `settings.json` inválido ou `disableAllHooks: true`, o app só avisa e não
oferece instalar.

### Avisos

Cada aviso tem som próprio: um é informativo, os de espera te bloqueiam e um
conta que a resposta não veio:

| Transição | Aviso | Som | Volume |
|---|---|---|---|
| processando → pronto | "Claude terminou" + nome do projeto | `Glass` (sino claro, padrão) | 100% |
| → permissão | "Claude pede permissão" + a mensagem do Claude | `Submarine` (pulso grave, padrão) | 75% |
| → pergunta | "Claude fez uma pergunta" + mensagem do Claude, ou nome do projeto | `Purr` (ronronar suave, padrão) | 75% |
| → aguardando você (sem motivo conhecido) | "Claude está esperando você" + a mensagem do Claude | `Submarine` (pulso grave, padrão) | 75% |
| processando → falhou | "A resposta do Claude falhou" + projeto e código do erro | `Basso` (som de erro, padrão) | 100% |

- O som sai pelo `NSSound`, não pela notificação: é o único jeito de escolher
  som e volume por tipo de aviso. Dá para saber qual deles aconteceu sem
  olhar a tela.
- A mensagem do aviso de "esperando" é o que o Claude Code manda para o hook
  `Notification` (ex.: *"Claude needs your permission to use Bash"*), limitada
  a 200 caracteres. O Claude Code manda o pedido de permissão depois de alguns
  segundos sem digitar, então o "esperando" pode demorar um pouco a aparecer.
- A pergunta aparece na hora (`PreToolUse` no `AskUserQuestion`). Segundos
  depois o Claude Code manda um pedido de permissão para a mesma tela; ele é
  ignorado enquanto a pergunta está aberta, então a sessão continua em
  "pergunta". Se o motivo mudar durante a espera, o aviso toca de novo.
- O aviso de "falhou" só sai se a sessão estava processando logo antes do
  erro, e não repete enquanto ela continuar em erro.
- Subagente nunca avisa.
- Sem som se o app da sessão já está na frente (o popup continua aparecendo).
  Vale por app: com o Claude desktop na frente, qualquer conversa dele conta;
  dentro do tmux o som sempre toca.
- O item **Notificações** no menu liga e desliga os avisos — popup e som
  juntos. A escolha fica salva no `UserDefaults` e vem ligada por padrão.
- **Ajustes… (⌘,)** abre uma janela de ajustes: liga e desliga cada aviso
  (terminou, esperando você — permissão e pergunta incluídas — e falhou),
  desliga o som mantendo o popup e escolhe o som de cada aviso entre os sons
  do macOS (toca ao escolher). Permissão e "esperando" dividem o mesmo som. O
  item **Notificações** do menu continua sendo o interruptor geral. A janela
  também tem **Sobre o ClaudeBar** (o painel padrão do macOS).

#### Por que o popup é desenhado pelo app

A Central de Notificações do macOS recusa app assinado ad-hoc:

```
requestAuthorization falhou: Notifications are not allowed for this application
status de autorização: 1 (denied)
```

Não é permissão que você negou — é o sistema recusando a API para bundle sem
Developer ID (`TeamIdentifier=not set`); `lsregister` não muda isso. Então o
aviso sai num `NSPanel` flutuante próprio, num canto da tela onde está o
mouse, longe do cursor (superior direito, a não ser que o cursor esteja lá) —
e não depende de assinatura nem de permissão.

"Claude terminou" e "A resposta do Claude falhou" somem em 4 s ou ao clique.
Os três avisos de espera ("Claude está esperando você", "Claude pede
permissão", "Claude fez uma pergunta") ficam até você clicar no popup ou
aquela sessão sair de "esperando" (você respondeu, ela terminou ou foi
fechada). Clicar no popup leva até a sessão (o mesmo que **Ir para a
sessão**); o popup de exemplo só fecha. Um "terminou" ou "falhou" nunca cobre um
popup de espera ainda aberto: você só ouve o som. Com duas sessões esperando,
o popup mostra a última; o ícone da barra continua avisando da outra.

Se algum dia o app for assinado com Developer ID, o `Notifier` passa a usar a
notificação nativa sozinho: ele prefere a nativa e só cai no painel próprio
quando a autorização não existe. O mesmo painel é usado quando o app roda sem
bundle (`swift run`).

Para diagnosticar (`log` é builtin do zsh, use o caminho absoluto):

```bash
/usr/bin/log show --last 5m --info --debug --predicate 'subsystem == "com.joaomarcos.claudebar"'
```

Para contar quantas vezes o CLI é consultado (uma linha por `claude agents --json`):

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.joaomarcos.claudebar" AND category == "agents"'
```

### Ir para a sessão

**Ir para a sessão** sobe a árvore de processos a partir do `claude` da sessão
até o primeiro app comum (terminal, editor, app desktop do Claude) e traz esse
app para a frente. A sessão também fica marcada como vista.

- **tmux:** dentro do tmux a árvore termina no servidor do tmux, então o
  ClaudeBar acha o pane pelo TTY da sessão, troca o cliente anexado usado por
  último para esse pane e traz o terminal desse cliente para a frente. Só o
  socket padrão é suportado, e precisa haver um terminal anexado.
- **Traz a janela, não a aba.** Escolher a aba exata exigiria permissão de
  Automação.
- **Sem permissão nenhuma:** só `sysctl`, `NSRunningApplication` e
  `NSWorkspace`.
- Se o app não for encontrado, um alerta avisa; nada mais é aberto.

| Onde a sessão roda | Status |
|---|---|
| App desktop do Claude | a árvore de processos chega ao app (verificado); ativação não verificada. Traz o app, não a conversa |
| Terminal.app | não verificado |
| Ghostty | não verificado |
| iTerm2 | não verificado |
| VS Code | não verificado |
| Cursor | não verificado |
| Warp | não verificado |
| tmux (socket padrão) | não verificado |

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
  (em evento de hook, na saída de processo    │
   e a cada 60 s; ≤ 1 chamada / 2 s)          │
                                              ├──> ClaudeBar.app ──> 🔸 3
Claude Code ──(hooks)──> claudebar-hook ──────┘
                            │       em que estado cada uma está
                            └─escreve─> ~/.claude/claudebar/<session_id>.json
                                        (DispatchSource: reage em ms)
```

- **`claude agents --json`** lista todas as sessões abertas, inclusive as que
  nunca dispararam um hook — é o que define o **número** na barra. É consultado
  (fora da main thread, ~150 ms por chamada) quando um hook grava, quando o
  processo de uma sessão termina e a cada 60 segundos — no máximo uma vez a
  cada 2 segundos. A saída de processo é observada pelo sistema
  (`DispatchSource`), então sessão morta some na hora, sem esperar a próxima
  consulta.
- **Os hooks** chegam no instante em que o estado muda — é o que define o
  **símbolo**. Mas só conhecem sessões que já dispararam algum evento.

O cruzamento é por `sessionId`: o CLI manda na lista, o hook manda no estado.
Se o CLI não estiver acessível, o app cai de volta para o que os hooks
gravaram, em vez de zerar a lista. Se uma sessão só aparece no CLI, o status
dele (`idle` / `waiting` / `blocked`, ou nenhum = processando) é usado como
reserva.

| Hook | Estado gravado |
|---|---|
| `SessionStart` (`startup`, `resume`, `clear`) | `idle` (sessão nova aparece antes do primeiro prompt) |
| `UserPromptSubmit` | `working` |
| `Stop` | `idle` |
| `StopFailure` | `error` (o turno acabou por erro de API) |
| `PreToolUse` (`AskUserQuestion`) | `waiting --kind question` |
| `Notification` (`permission_prompt`) | `waiting --kind permission` (ignorado enquanto há pergunta aberta) |
| `Notification` (`elicitation_dialog`) | `waiting --kind question` |
| `PostToolUse`, `PostToolUseFailure` | `working`, só se a sessão estava `waiting` (uma permissão acabou de ser aprovada) |
| `SessionEnd` | apaga o arquivo |

Os outros tipos de notificação (lembrete de ociosidade, autenticação, cota…)
não são registrados: o lembrete de ociosidade trocava "pronto" por "esperando"
cerca de um minuto depois de cada resposta.

Um arquivo de estado tem esta cara:

```json
{
  "branch" : "main",
  "cwd" : "/Users/me/code/my-project",
  "kind" : "permission",
  "message" : "Claude needs your permission to use Bash",
  "pid" : 23667,
  "sessionId" : "1f6c…",
  "state" : "waiting",
  "updatedAt" : 1791400000
}
```

A `branch` é lida pelo hook direto do `.git/HEAD` (seguindo o `gitdir:` de um
worktree), sem rodar `git`. HEAD solto aparece como `@sha7`; repositório
reftable, ou pasta fora de git, fica sem branch. Ela é atualizada a cada hook,
então um `git checkout` feito fora do Claude aparece com um turno de atraso.
No menu ela vem ao lado do nome, para distinguir duas sessões do mesmo projeto
em worktrees diferentes.

Duas decisões que evitam problemas clássicos:

- **O hook mora em `~/.claude/claudebar/bin/claudebar-hook`**, cópia do que
  vem no bundle. O `settings.json` aponta para lá, então mover ou apagar o
  `.app` não quebra os hooks.
- **Um arquivo por sessão.** Várias sessões escrevendo no mesmo arquivo daria
  disputa de escrita; separando por `session_id`, o problema deixa de existir.
  A escrita ainda é atômica, para o app nunca ler um JSON pela metade.
- **PID gravado junto.** Sessão que morre por `kill` ou crash nunca dispara o
  `SessionEnd` e deixaria um arquivo eterno dizendo "processando". O app
  apaga o arquivo quando o processo morreu, quando o PID virou outro programa ou
  quando virou outro `claude` que nasceu depois da gravação. Sem essa prova (sem
  informação), o arquivo fica. Sessão com `pid 0` só some da lista quando o CLI
  responde sem ela.

O caminho do `claude` é resolvido em caminhos conhecidos (`~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) e, como último recurso, via
`zsh -lc "command -v claude"`: um app de barra de menu não herda o `PATH` do
seu shell.

## Estrutura

```
Package.swift                 SwiftPM, macOS 14, 3 targets + testes
Sources/ClaudeBarCore/        modelo compartilhado + leitura/escrita do diretório de estado
  GitHead.swift               branch lida do .git/HEAD (pelo hook, nunca roda git)
  HookInstaller.swift         põe/tira só os hooks do ClaudeBar no settings.json (diff, backup)
  SessionNavigator.swift      árvore de processos → app, pane do tmux, ativação
  SessionStatus.swift         estado da sessão (working/idle/waiting/error), PID
  Shell.swift                 execução de processo sem shell (sem injeção)
  StatusDirectory.swift       ~/.claude/claudebar: permissões, escrita atômica, limpeza
Sources/claudebar-hook/       CLI chamado pelos hooks (sem dependência de jq/python)
  main.swift                  lê o JSON do hook no stdin, grava/apaga o arquivo de estado
Sources/ClaudeBar/            app SwiftUI (MenuBarExtra)
  ClaudeBarApp.swift          ponto de entrada, rótulo da barra (símbolo + número)
  MenuContent.swift           o menu
  HookSetup.swift             estado da integração, alerta com o diff, instala/remove no clique
  SessionStore.swift          liga as origens às regras e detecta transições
  SessionMerge.swift          as regras, em funções puras (é o que os testes cobrem)
  SessionRow.swift            linha do menu: cruzamento das duas origens
  AgentsProbe.swift           chama `claude agents --json` e traduz o status
  DirectoryWatcher.swift      DispatchSource observando o diretório de estado
  ProcessExitWatcher.swift    DispatchSource observando a saída dos processos de sessão
  SessionTerminator.swift     escolha do alvo (SIGTERM ou `claude stop`) e execução
  ProcessProbe.swift          topologia do processo: lidera o grupo? ainda é claude?
  Notifier.swift              som por tipo de aviso, toggle, nativa vs. popup próprio
  StatusHUD.swift             o popup próprio (NSPanel flutuante)
  SettingsWindow.swift        janela de Ajustes (NSWindow, não a cena Settings)
Tests/ClaudeBarTests/         subagente, contagem, ícone, precedência, o kill real e rede zero
Resources/AppIcon.icns        ícone do app, copiado para o bundle pelo build-app.sh
scripts/build-app.sh          monta build/ClaudeBar.app (LSUIElement, assinado ad-hoc)
scripts/install.sh            instala em ~/Applications e registra os hooks
scripts/uninstall.sh          remove os hooks (só os nossos) e o app
VERSION                       versão do app (X.Y.Z), lida pelo build-app.sh
```

## Instalação

```bash
./scripts/install.sh
```

O script:

1. compila o app em release (`scripts/build-app.sh`),
2. copia para `~/Applications/ClaudeBar.app`,
3. mostra o diff do bloco `hooks` do `~/.claude/settings.json` e pergunta
   antes de aplicar (`claudebar-hook install`),
4. abre o app.

Bom saber:

- Só as entradas do ClaudeBar mudam. Hooks seus nos mesmos eventos ficam,
  inclusive no mesmo grupo. Rodar de novo diz que não há nada a mudar.
- Antes de toda escrita, o arquivo antigo vai para um backup (`0600`) em
  `~/.claude/claudebar/backups/`. Se o `settings.json` não existe, ele é
  criado.
- O arquivo é reformatado (ordem das chaves, espaços); fora de `"hooks"` o
  conteúdo não muda.
- O Claude Code recarrega o `settings.json`, então sessões abertas já pegam os
  hooks (as pastas precisam ser confiáveis).

Para rodar no login: Ajustes do Sistema → Geral → Itens de Início → adicionar
`~/Applications/ClaudeBar.app`.

### Mover ou atualizar o app

Os hooks não apontam para dentro do `.app`: rodam uma cópia em
`~/.claude/claudebar/bin/claudebar-hook`. Mover, renomear ou apagar o
`ClaudeBar.app` não os quebra. Depois de atualizar o app, a cópia fica mais
velha que a do bundle; o app detecta isso (e entradas ausentes, legadas ou
desatualizadas, `settings.json` somente leitura, `disableAllHooks`) sem
gravar nada, e oferece o reparo uma vez (veja
[Integração com o Claude Code](#integração-com-o-claude-code)).

## Desenvolvimento

```bash
swift build                  # compila
swift test                   # regras de merge, contagem, ícone, avisos, finalização
./scripts/build-app.sh       # monta o .app

# muda o estado de uma sessão real (a primeira do CLI com pid)
s=$(claude agents --json | jq -c '[.[] | select(.pid)][0]')
echo "$s" | jq -c '{session_id: .sessionId, cwd}' | \
  build/ClaudeBar.app/Contents/MacOS/claudebar-hook waiting --kind permission --pid "$(echo "$s" | jq .pid)"
```

PID inventado não funciona: o app apaga o arquivo cujo PID não é um `claude`
rodando (o PID 1 é o `launchd`).

A versão fica em `VERSION` (X.Y.Z). O número de build é a contagem de commits
(`git rev-list --count HEAD`); clones rasos reiniciam a contagem.

Uso do CLI do hook:

```
claudebar-hook <working|idle|waiting|error|end> [--kind <permission|question>] [--if-waiting] [--pid <pid do claude>]
claudebar-hook install|uninstall [--dry-run]
claudebar-hook status [--json]
claudebar-hook next
```

Ele lê o payload do hook (`session_id`, `cwd`, `message`; com `error`,
`error` e `error_details` no lugar de `message`) no stdin. Sem
`session_id`, não grava nada e sai 0. Se falhar
ao gravar, só registra no stderr e sai normalmente — um hook nunca deve
derrubar a sessão do Claude. Sem `--pid` (exec form não tem `$PPID`) ele usa o
processo pai, mas só se for um executável `claude`; senão grava `pid: 0`.
`--kind` só vale com `waiting`; valor desconhecido é descartado (espera genérica).
`--if-waiting` só grava se o arquivo da sessão estiver em `waiting`; senão (ou
sem arquivo) sai 0 sem tocar nele.
Estado ausente ou inválido sai com **1**, nunca 2: no Claude Code, exit 2
bloqueia o prompt.

`install`/`uninstall` mostram o diff do bloco `hooks` e aplicam com backup;
`--dry-run` só mostra. O `install` também se copia para
`~/.claude/claudebar/bin/claudebar-hook`; o `uninstall` apaga essa cópia.

### Linha de comando

`status` e `next` são para você digitar (ou usar em script); não leem o stdin
e não mudam nada nas suas sessões.

```bash
alias cb=~/.claude/claudebar/bin/claudebar-hook

cb status          # uma sessão por linha: estado<TAB>projeto<TAB>pasta
cb status --json   # os mesmos dados, no formato dos arquivos de estado
cb next            # traz para a frente a sessão que espera há mais tempo
```

O `next` imprime o nome do projeto e sai 0; sem sessão esperando (ou quando
não acha o app que a hospeda) diz o motivo e sai 1. Dentro do tmux ele troca o
cliente para o pane da sessão, como o "ir para a sessão" do menu.

Na barra do tmux, o número de sessões esperando você:

```
set -g status-right '#(~/.claude/claudebar/bin/claudebar-hook status | grep -c ^waiting)'
```

O `status` só vê sessões que já dispararam algum hook: ele lê os arquivos de
estado e não chama o `claude agents`. Como o app, apaga arquivo de estado
inválido ou cujo processo não existe mais.

`swift run ClaudeBar` também funciona. Sem bundle não há notificação nativa,
então o app usa o popup próprio e o som.

Os testes de finalização usam processos de verdade: sobem processos filhos,
conferem a detecção de grupo de processos, mandam `SIGTERM` e garantem que
encerrar uma sessão não derruba a irmã.

## Segurança

- **Sem segredo nenhum no projeto.** O app não fala com rede (veja
  [Confira você mesmo](#confira-você-mesmo)), não autentica em nada e não lê o
  histórico das conversas — só caminhos de projeto, `sessionId`, o estado da
  sessão, a branch do git e a mensagem de notificação do hook.
- **O único arquivo lido dentro do seu projeto é o `.git/HEAD`** (ou o arquivo
  `.git` de um worktree), pelo hook, nunca pelo app, e o `git` nunca é
  executado.
- **`~/.claude/claudebar` é `0700`, os arquivos `0600`.** O conteúdo revela em
  que projetos você trabalha, então fica fora do alcance de outros usuários da
  máquina.
- **`sessionId` é sanitizado** antes de virar nome de arquivo: só
  `[A-Za-z0-9-_]`, o resto vira `-`. Um `session_id` malicioso com `../` não
  escapa do diretório.
- **Nenhum comando passa por shell.** O `claude` e o `tmux` são invocados via
  `Process`, por caminho conhecido e com argumentos separados — não há
  interpolação, então não há injeção. A única exceção é o
  `zsh -lc "command -v claude"`, usado apenas como último recurso quando o
  binário não está nos caminhos conhecidos.
- **`message` é truncada em 200 caracteres** antes de ser exibida. Em falha,
  só o código e o detalhe do erro da API são gravados, nunca a resposta do
  Claude (`last_assistant_message` não é lido em estado nenhum). Para
  perguntas só fica gravado o fato de o Claude ter perguntado, nunca o texto
  da pergunta (`tool_input` não é lido).
- **Caminhos nunca vão em claro para o log.** Linha de log com caminho, `cwd`,
  `sessionId` ou mensagem do hook usa `privacy: .private(mask: .hash)`; nunca
  `.public`.
- **Hooks rodam sem shell.** São registrados em exec form (`command` +
  `args`), e o instalador não precisa de `jq`: é o próprio binário do hook, em
  Swift. Os backups do `settings.json` são `0600`.

### Confira você mesmo

O ClaudeBar não abre conexão de rede. Um teste (`NoNetworkTests`) faz o
`swift test` falhar se entrar código de rede em `Sources/`. Para conferir o
app rodando:

    lsof -i -a -c ClaudeBar                     # não imprime nada
    nettop -p ClaudeBar -L 0 -t external -n     # só a linha de cabeçalho CSV; Ctrl-C para parar

Com o Little Snitch: abra o Network Monitor e busque "ClaudeBar". Não deve
aparecer conexão nenhuma.

Atenção: o ClaudeBar roda `claude agents --json` (e `claude stop` quando você
encerra um subagente), além de comandos locais do `tmux` quando você vai até
uma sessão dentro do tmux. Qualquer tráfego dos comandos do `claude` aparece
como `claude`, não como ClaudeBar: é do Claude Code e segue as configurações
dele
(https://code.claude.com/docs/en/data-usage#telemetry-services).

## Desinstalar

```bash
./scripts/uninstall.sh
```

Tira só os hooks do ClaudeBar do `settings.json` (com backup), fecha o app e
apaga `~/Applications/ClaudeBar.app`. Sem o repositório:
`~/.claude/claudebar/bin/claudebar-hook uninstall`. Estado e backups ficam em
`~/.claude/claudebar`; apague a pasta à mão se quiser.
