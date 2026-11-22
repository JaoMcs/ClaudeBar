# Contexto para o próximo agente — ClaudeBar

> **Leia este arquivo inteiro antes de reiniciar qualquer processo.** Estado em 2026-11-16, loop pausado pelo usuário.
> Tudo em `planning/` é temporário (fora do git via `.git/info/exclude`) e será apagado no fim, depois de uma triagem crítica.
> Retomada rápida: `RETOMAR.md`. Este arquivo é o contexto completo.

---

## 1. O que é o projeto

ClaudeBar: app macOS só de barra de menu (SwiftUI `MenuBarExtra`, `LSUIElement`), SwiftPM sem projeto Xcode, macOS 14+, Swift 6, assinado ad-hoc por `scripts/build-app.sh`. Mostra quantas sessões do Claude Code estão abertas e o estado mais urgente (esperando você > pronto não visto > trabalhando > ocioso), com som e popup próprio (`NSPanel`) por transição.

Duas fontes de dado, juntadas por `sessionId`:
- `claude agents --json` (polling, hoje a cada 5 s) → quais sessões existem.
- Hooks do Claude Code → binário `claudebar-hook` grava `~/.claude/claudebar/<sessionId>.json` (0600, atômico); o app observa o diretório (`DispatchSource`).

Repo: `github.com/JaoMcs/ClaudeBar` (**público**). Branch principal `main`. Conta `gh` logada: JaoMcs.

### Layout atual (`main` @ b15bf9b)
```
Sources/ClaudeBarCore/   SessionStatus.swift, StatusDirectory.swift, HookInstaller.swift (novo, T03)
Sources/claudebar-hook/  main.swift
Sources/ClaudeBar/       ClaudeBarApp, MenuContent, SessionStore, SessionMerge, SessionRow, AgentsProbe,
                         DirectoryWatcher, SessionTerminator, ProcessProbe, Notifier, StatusHUD, Shell
Tests/ClaudeBarTests/    AlertTests, HookInstallerTests (novo), SessionMergeTests, SessionTerminatorTests
scripts/                 build-app.sh (lê VERSION), install.sh (ainda usa jq — muda na T05)
VERSION                  0.1.0
.github/workflows/ci.yml swift test + build-app.sh, macos-15, fetch-depth 0, timeout 15 min
```
Baseline: `swift test` = **44 testes passando** em 9 suítes.

---

## 2. O que o usuário pediu (resumo do pedido original)

1. Estudo de concorrentes e de inovação → ✅
2. Painel de subagentes "usuários" sem contexto debatendo melhorias → ✅
3. Validação das funcionalidades por outros subagentes → ✅
4. Pesquisa detalhada de **como fazer** cada funcionalidade → ✅
5. Markdowns com tudo isso → ✅ (pastas `01` a `05`)
6. Especialista macOS refinando a nível técnico (tasks, código, passo a passo) → ✅ (`05-specs/`)
7. Gestor quebrando em tasks e subtasks `.md` → ✅ (`06-tasks/`, 35 tasks)
8. **Loop por task:** branch → PR → revisor independente comenta → corrigir o que fizer sentido → merge na `main`, até acabar → ⏸ **em andamento, pausado** (3 de 35 feitas)
9. Agente de design em background até o ícone final → ✅ ícone pronto (integração = T32)
10. Levantar o que falta e o que depende do usuário → parcial (seção 7)
11. Relatório final com tasks e o que foi feito; triagem crítica dos `.md` temporários (guardar só o essencial em docs permanentes) e apagar `planning/` → ⏳ no fim

Pedidos do usuário durante o processo (valem até o fim):
- **Não usar `NSApplication.activate(ignoringOtherApps:)`**: vai ser descontinuada numa versão futura do macOS (`API_TO_BE_DEPRECATED`). Já está anotado no `TODO.md` (seção "Deprecated APIs"). A pesquisa da substituta fica para depois. Código novo não pode usá-la; os dois usos em `SessionStore.swift` continuam até alguém tratar isso.
- O usuário pausa e retoma o loop. **Só retomar quando ele pedir.** Quando ele pedir para pausar "ao finalizar o PR atual", esperar o merge e parar o workflow (TaskStop) antes da próxima task avançar.
- O usuário aceitou que os PRs sejam mergeados por mim depois de revisor + CI verde (o GitHub não deixa a mesma conta aprovar o próprio PR, então a revisão sai como comentário).

---

## 3. Guard rails (valem para toda task)

- **Ponytail:** menor código que resolve; sem abstração especulativa; deleção antes de adição.
- **Sem rede.** Nenhum `URLSession`/`Network`/sockets (a T15 vai pôr um teste que garante isso).
- **Não ler conversas** do usuário (nada de JSONL/transcript).
- Diretório de estado `0700`, arquivos `0600`, escrita atômica.
- Nada via shell com interpolação: `Process` com argumentos separados.
- **Hook fail-open:** nunca quebrar a sessão do Claude (nunca `exit 2`; erro só em stderr).
- **Nenhuma escrita no `settings.json` sem prévia (diff) + backup + consentimento.**
- **Nunca tocar no `~/.claude/settings.json` real nem no `~/.claude/claudebar` real em testes ou experimentos.** Usar `mktemp -d` / injeção de caminho. (Na fase de specs, dois agentes escreveram arquivos de teste no diretório real; os arquivos já tinham sido apagados e o `settings.json` está intacto, mas não pode repetir.)
- Swift 6 strict concurrency; comentários em português, como no código atual.
- README.md **e** README.pt-BR.md atualizados quando o comportamento muda.
- **Repo público:** nada de caminho da máquina do usuário, e-mail ou dado pessoal em PR, commit ou comentário.
- Commit: mensagem em pt "tipo: descrição" + linha `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR termina com `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- O que não dá para verificar por agente (tela, VoiceOver ouvido, logout/login, conta Pro/Max, outro Mac, foco em cada terminal) vai no PR como "Não verificado".

---

## 4. Tasks já feitas (mergeadas na `main`)

| Task | PR | O que entrou | Revisão |
|---|---|---|---|
| CI | #1 | `.github/workflows/ci.yml`: `swift test` + `build-app.sh`, `permissions: contents: read`, `concurrency` (cancela runs antigos só em PR), `timeout-minutes: 15` | 4 de 6 pontos aplicados; o teste com processo neto (~1s) pode ficar instável em runner carregado, só mexer se acontecer |
| T01 som respeita toggle | #2 (548ba76) | `Notifier.post`: `guard isEnabled` é a primeira instrução (sem som nem popup quando desligado). `Notifier.init(defaults:playSound:)` injetável para teste. Teste `desligadoNaoTocaSom`. READMEs atualizados. Também entrou a seção "Deprecated APIs" no `TODO.md` | 1 nit recusado (com resposta no PR) |
| T02 versão de fonte única | #3 (541e695) | Arquivo `VERSION` = `0.1.0`; `build-app.sh` valida X.Y.Z e sai com 1 se inválido; `CFBundleVersion` = `git rev-list --count HEAD` (0 sem git); CI com `fetch-depth: 0` | sem achados |
| T03 merge aditivo (puro) | #4 (b15bf9b) | `ClaudeBarCore/HookInstaller.swift`: `HookAction`, `HookInstallError`, `HookInstaller` (settingsURL, stableBinary, backupsURL, legacySuffix, Entry/entries, isOurs, strip, install, parse, serialize, lineDiff; `hooksOnly`/`handlers` private). Sem plan/apply/IO ainda. `HookInstallerTests` (`HookMergeTests`, 9 testes, incluindo `diffPorLinha`) | aplicados: teste do `lineDiff`, helpers private, commit com e-mail noreply |

### Em aberto
- **T04 — PR #5 em RASCUNHO, sem revisão.** Branch `feat/hooks-previa-escrita`, 1 commit, +214 linhas (`HookInstaller.swift`, `HookInstallerTests.swift`). O implementador abriu antes da pausa. **Primeiro passo ao retomar:** `gh pr ready 5`, rodar revisor → corretor → merge só para ela, e então seguir o loop a partir da T05.

---

## 5. Tasks que faltam (ordem de execução, uma por vez)

Detalhe completo em `06-tasks/T<nn>-*.md` (subtasks, código de referência, testes, critérios de aceite, branch, título do PR). Specs em `05-specs/G01..G14`. Pesquisa em `04-como-fazer/`.

| Id | Título | Depende de |
|---|---|---|
| T04 | Prévia, backup e escrita segura do `settings.json` + cópia estável do binário | T03 (PR #5 aberto) |
| T05 | `claudebar-hook install/uninstall`, `install.sh` sem `jq`, `uninstall.sh`, exit 1 | T04 |
| T06 | Detectar o estado da integração (`IntegrationState`) | T05 |
| T07 | `Notification` só para permissão e formulário + `kind` no arquivo | T05, T06 |
| T08 | Sessões fantasmas: regra de vida conservadora | T05 |
| T09 | Permissão aprovada tira a sessão de "esperando" (`PostToolUse --if-waiting`) | T07, T08 |
| T10 | Instalar/remover hooks pelo app, com diff e consentimento | T06, T09 |
| T11 | "Testar integração" ponta a ponta + `Shell` com prazo | T10, T08 |
| T12 | Estado de erro (`StopFailure`, `failed` do CLI) | T07 |
| T13 | Aviso com som próprio quando a resposta falha | T12, T01 |
| T14 | Polling leve: `.exit` por PID, throttle, 60 s, `SessionStart` | T08, T10 |
| T15 | Rede zero verificável (`NoNetworkTests`) | — |
| T16 | Permissão × pergunta: símbolo, texto e som distintos | T07, T09, T12, T13 |
| T17 | Popup de espera persistente; canto longe do cursor | T09, T16 |
| T18 | Abrir pasta do projeto | — |
| T19 | Ir para a sessão (árvore de processos + tmux) | T11, T18 |
| T20 | Clique no popup leva à sessão | T19, T17 |
| T21 | Sem som se o app da sessão já está na frente | T19, T20, T01 |
| T22 | CLI `claudebar-hook status` / `next` | T19, T08 |
| T23 | Branch ao lado do nome da sessão | T16 |
| T24 | Janela de Ajustes: avisar por tipo, som, Sobre | T01, T13, T16, T21 |
| T25 | Abrir no login (`SMAppService.mainApp`) | T24 |
| T26 | Lembrete único de espera | T24, T17, T20, T21 |
| T27 | Modo "nunca mostrar conteúdo" | T24, T26 |
| T28 | Limites: `claudebar-hook statusline` (grava `limits.json`, encadeia o original) | T08, T22 |
| T29 | Limites 5 h e semanal no menu | T28 |
| T30 | Instalar/remover o `statusLine` (opt-in próprio) | T28, T10, T06 |
| T31 | VoiceOver + legenda dos estados | T16, T23, T29 |
| T32 | Ícone do app (`AppIcon.icns` de `07-design/final/`) | T02 |
| T33 | DMG universal + SHA-256 (só o script, não publica) | T02, T32, T10 |
| T34 | Inglês + português: base, menu, barra e avisos | T32 + todas de UI |
| T35 | Inglês + português: diálogos, Ajustes, integração e limites | T34 |

Lotes planejados: 1 = T01–T08 (parado após T03), 2 = T09–T17, 3 = T18–T27, 4 = T28–T35.

### Decisões de gestão que mudam as specs (do `06-tasks/INDEX.md`)
- **Instalador único:** depois da T05 não existe mais `jq` no `install.sh`. Todo hook novo vai em `HookInstaller.entries`. As variantes com `jq` das specs G04, G05, G06 e G09 **não** se aplicam.
- `exit(1)` e `getppid()` entram na T05. A T07 mantém o fallback de `getppid()` ao trocar `parsePID` por `value(after:)`.
- `PostToolUse:AskUserQuestion → working` **não** é registrado; o `PostToolUse --if-waiting` da T09 cobre. A T16 só registra `PreToolUse:AskUserQuestion`.
- `readAll` muda para `readAll(in:isAlive:)` na T08. A T11 usa `ProcessProbe.live.isAlive`; a T22 (CLI, sem ProcessProbe) usa só a prova de `ESRCH`.
- `Shell` ganha `input`/`timeout` na T11 e vai para o Core (público) na T19.
- O popup persistente (T17) vale para `.waiting`, `.permission` e `.question`; `.finished` e `.failed` somem em 4 s.
- Os Ajustes (T24) nascem com os 5 tipos de `Alert`; o lembrete (T26) fica na janela de Ajustes, não no menu.
- A assinatura final de `Notifier.post` depois da T21 é `post(_:body:sessionId:playSound:onOpen:)`.
- T28: o hook do statusline só regrava `limits.json` quando o número muda ou quando o dado tem 60 s ou mais (evita acordar o app a cada atualização do rodapé).
- Medição da fase de specs (G05): com o menu aberto, `DispatchQueue.main.async` e `Task { @MainActor }` só rodam **depois** que o menu fecha; só `RunLoop.main.perform(inModes: [.common])` roda. Por isso **não** existe "consultar ao abrir o menu" na T14.
- Ícone: a barra de menu **continua com SF Symbols** por estado. O glifo próprio (`MenuBarIcon-*.png` em `07-design/final/`) fica como opção futura. A T32 integra só o `AppIcon.icns`.

---

## 6. Como o loop roda (e lições aprendidas)

Workflow `claudebar-impl-loop`, sequencial. Script já corrigido em
`<pasta da sessão do Claude Code>`
(args: `{"tasks": ["T05-hooks-cli-install", "T06-hooks-deteccao", ...]}`; os ids são os nomes dos arquivos sem `.md`). Se o arquivo não existir mais, reescrever com a mesma estrutura:

1. **Implementador** (`isolation: 'worktree'`): `git fetch origin && git switch -c <branch> origin/main`, implementa a task, roda os gates (`swift build && swift test`, e `./scripts/build-app.sh` se mexer em scripts/bundle), commit, push, `gh pr create`. Ao terminar, `git switch --detach` para liberar a branch.
2. **Revisor sem contexto** (só PR + arquivo da task): espera o CI (`gh pr checks <n> --watch`), lê o diff inteiro, posta **uma** revisão com `gh pr review <n> --comment` e severidade [bloqueante]/[sugestão]/[nit].
3. **Corretor** (worktree): aplica o que fizer sentido, responde no PR o que não aplicou, roda os gates, faz push e espera o CI. No máximo 2 rodadas.
4. **Merge** (effort low): checks pass + OPEN/MERGEABLE → `gh pr merge <n> --squash --delete-branch`, marca `FEITA (#n)` no `INDEX.md`. Não mexe no checkout local.
5. Se a implementação falhar, se o CI não ficar verde depois de 2 rodadas ou se o merge falhar: a task fica BLOQUEADA, o PR fica aberto e o lote para.

Lições (já corrigidas no script):
- **`timeout` não existe no macOS.** Os revisores da T01 e da T03 tentaram usar e deu `exit 127`. Usar `gh pr checks --watch` direto.
- **Branch presa em outro worktree** impede o corretor de dar `switch`. Solução: o implementador termina com `git switch --detach`; o corretor usa `git switch -C <branch> origin/<branch> --ignore-other-worktrees` se precisar.
- **Experimentos só em `mktemp -d`**, nunca em `~/.claude`.
- **Arquivos de `planning/` não existem nos worktrees** (pasta excluída do git). Sempre passar o caminho absoluto `planning/...`.
- Muitos "exit code 1" de agentes são `grep` sem match em comandos encadeados. Não é falha real; o app do Claude mostra como falha.
- Entre lotes: `git worktree list`, remover os worktrees de tasks já mergeadas (`git worktree remove`), `git worktree prune`, `git pull` na `main` local e `swift test`.
- Pausa "ao fim do PR atual": vigiar `gh pr view <n> --json state` até `MERGED` e dar `TaskStop` no workflow na hora. O implementador seguinte pode já ter aberto PR; nesse caso, deixar esse PR em rascunho com um comentário e anotar no INDEX/RETOMAR.

### Ponto a decidir com o usuário
- O revisor da T03 apontou que os commits saem com o e-mail pessoal configurado no git, num repo público. Na correção da T03 o agente usou o e-mail noreply do GitHub só naquele commit (via `-c`, sem mudar a config global). **Decidido pelo usuário (2026-11-16): noreply só neste repo.** Aplicado `git config --local user.email 43441696+JaoMcs@users.noreply.github.com` (vale para os worktrees). Config global intacta. Não usar `-c user.email`. O revisor não deve mais apontar isso como problema.

---

## 7. O que depende do usuário (não bloqueia o loop)

| Item | Bloqueia | Passo |
|---|---|---|
| Conta Apple Developer (US$ 99/ano) + certificado Developer ID | assinatura/notarização, notificação nativa, Gatekeeper limpo, Homebrew, Automação estável | assinar o programa, criar o certificado, credenciais do `notarytool` |
| Nome definitivo **sem "Claude"** + bundle id | distribuição pública, Homebrew, multiagente | "Claude" no nome do produto é vetado pela página legal do Claude Code; `ClaudeBar` colide com o app da tddworks |
| Licença | qualquer distribuição | o repo é público e não tem `LICENSE` (sugestão: MIT) |
| Tap do Homebrew | F29 | criar `homebrew-tap` e escolher o nome do cask |
| Publicar release (DMG + SHA-256) | distribuição | depois de nome + licença (de preferência depois da assinatura) |
| Testar Automação por terminal (aba exata) | F30 | aprovar os prompts no Terminal, iTerm2 e Ghostty |
| Payload real de pausa por limite | F33 | capturar o JSON ao bater o limite |
| GIF do README | F49 | gravar 10 s do app em uso |
| E-mail dos commits | decidido: noreply local no repo (aplicado) | seção 6 |
| Defaults assumidos | — | idioma segue o sistema com fallback inglês; 1ª versão pública `0.1.0` (já no `VERSION`) |

Fora desta rodada (não viram task): F28–F50 do `03-validacao/BACKLOG.md` (assinatura, Homebrew, aba exata via AppleScript, alertas/previsão de limite, atalho global, Codex/Gemini, auto-update etc.) e as ideias descartadas.

---

## 8. Mapa da pasta `planning/`

| Caminho | Conteúdo |
|---|---|
| `00-PLANO.md` | prompt refinado, guard rails, step-by-step, miniprompts |
| `00-brainStorm.md` | brainstorm inicial (primeira conversa) |
| `01-pesquisa/` | concorrentes de status, limites/uso, gerenciadores, inovação, `IDEIAS.md` |
| `02-painel/PAINEL.md` | painel de 6 personas (transcrição, ranking, consensos, bloqueios) |
| `03-validacao/` | três lentes (valor, viabilidade, risco) + **`BACKLOG.md`** (F01–F50, escopo, pendências) |
| `04-como-fazer/G01..G14` | pesquisa de implementação com fontes (CONFIRMADO × SUPOSIÇÃO) |
| `05-specs/G01..G14` | specs técnicas do especialista macOS (código, testes, critérios) |
| `06-tasks/` | **`INDEX.md`** (ordem, dependências, status) + `T01..T35` |
| `07-design/` | ícone: conceitos, iterações, `final/` (AppIcon.icns, iconset, MenuBarIcon-*.png, README de integração) |
| `RETOMAR.md` | checklist curto de retomada |
| `CONTEXTO-HANDOFF.md` | este arquivo |
| `todo-deprecated.patch` | já aplicado (T01); pode apagar |

---

## 9. Checklist do próximo agente

1. Ler este arquivo, `RETOMAR.md` e `06-tasks/INDEX.md`.
2. Conferir o estado real: `git -C <repo> status`, `git log --oneline -6`, `gh pr list --state open`, `git worktree list`, `swift test` (esperado: 44 testes).
3. **Esperar o usuário pedir para retomar.**
4. Ao retomar: terminar a T04 (PR #5: ready → revisão → correção → merge) e seguir o loop a partir da T05, em lotes, avisando o usuário entre lotes.
5. E-mail dos commits: noreply local já aplicado (seção 6). Revisão pessoal dos PRs do settings.json: usuário dispensou (merge automático).
6. No fim: `PENDENCIAS.md` permanente, relatório final (tasks, PRs, o que ficou não verificado), triagem crítica de `planning/` (o essencial vai para docs permanentes, ex.: ROADMAP curto) e apagar `planning/`.

---

## PAUSA 2026-11-22 (stepback pedido pelo usuário)

- **As 35 tasks estão na `main`** (PRs #2–#36, `main` @ 27826cf, 155 testes). Nenhum loop rodando.
- **Fechamento escrito e NÃO commitado:** `PENDENCIAS.md`, `ROADMAP.md`, `docs/TESTE-MANUAL.md`, `docs/design/` (script do ícone + README) estão untracked na raiz do repo. `RELATORIO-FINAL.md` está na raiz e no `.git/info/exclude`.
- **Falta:** revisar esses arquivos → PR → merge; rodar o `docs/TESTE-MANUAL.md` (usuário); só então apagar `planning/`.
- **Não apagar ainda:** `05-specs/G07`, `G09` e `G10` (planos B de iTerm2, clique no popup e abrir no login).
- **Lacunas:** T25 (gate do login ad-hoc não rodado), T17 (1 ou 2 cliques, troca de Space), T14 (medido só com sessões simuladas). T11 corrigido.
- **Incidente T12:** um agente gravou ~30 s no `~/.claude/settings.json` real e restaurou. Sobras confirmadas: `~/.claude/claudebar/bin/claudebar-hook` e `~/.claude/claudebar/backups/settings.json.20261116-202432-958`. O settings atual tem os 4 hooks antigos (apontando para o app instalado), sem `statusLine`. Nada foi limpo; decisão do usuário.
- Fable ficou sem créditos na T24; o resto rodou no Opus.


---

## Decisões do dono (22 nov 2026, pelo painel)

- Nome: **Awaitbar** (T37, PR #40). `claudebar-hook` e `~/.claude/claudebar` mudam só com o multiagente.
- Licença: **MIT** (PR #38).
- Developer ID: **vai assinar**; o script de assinatura/notarização espera o certificado.
- `/compact` não dispara "terminou": nada a mudar.
- Popup sumia ao trocar de Space: corrigido (T36, PR #39).
- Sobras da T12 em `~/.claude/claudebar`: movidas para o Lixo.
- **Ainda pendentes:** abrir no login (gate manual), 1 ou 2 cliques no popup, tabela de terminais do "Ir para a sessão", ferramentas opcionais (swift-lsp, skills AvdLee, hook Stop), certificado do Developer ID.
- Novas tasks T38–T45 (ROADMAP + TODO), rodadas 1–4 com o `impl-loop`.
