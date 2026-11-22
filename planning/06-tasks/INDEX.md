# Tasks — ordem de execução

> Gerado a partir de `00-PLANO.md`, `03-validacao/BACKLOG.md` e de todas as specs em `05-specs/` (G01–G14), conferido contra `main` @ 80768db (`Sources/` igual a f943cc4; baseline 34 testes).
> Uma task = um PR pequeno (idealmente < 400 linhas alteradas), `squash merge`, branch apagada depois.
> Nada nesta rodada depende do usuário para ser **feito**. O que só ele pode **verificar** (VoiceOver ouvido, tela, logout/login, conta Pro/Max, outro Mac) vai como "não verificado" no PR.

## Regras de ordem aplicadas

1. Bugs P0 primeiro (F01, F04, F02, F03, F05, F06 e o pré-requisito H0).
2. Dependências antes de quem depende delas.
3. Tasks que tocam os mesmos arquivos ficam em sequência. Os arquivos quentes são `claudebar-hook/main.swift`, `HookInstaller.swift`, `SessionStore.swift`, `MenuContent.swift`, `Notifier.swift`, `StatusHUD.swift`, `scripts/build-app.sh` e os dois READMEs. **Nenhuma task roda em paralelo com outra.**
4. Ícone (T32) e DMG (T33) perto do fim. i18n (T34, T35) por último, porque reescreve strings de todas as telas.
5. Itens "Fora desta rodada" do BACKLOG (F28–F50) não viram task.

## Decisões de gestão que mudam as specs (valem para quem implementa)

- **Instalador único.** Depois de T05 não existe mais `jq` no `install.sh`. Toda entrada de hook nova (F05, H0, F07, F08, F24) vai em `HookInstaller.entries`, nunca no `jq`. As variantes `jq` das specs G04, G05, G06 e G09 **não** se aplicam.
- **`exit(1)` e `getppid()`** entram em T05 (G03). T07 (F05) mantém o fallback de `getppid()` ao trocar `parsePID` por `value(after:)`.
- **`PostToolUse:AskUserQuestion → working` (G04) não é registrado.** O `PostToolUse` sem matcher com `--if-waiting` do H0 (T09) já cobre esse caso. O F24 (T16) só registra o `PreToolUse:AskUserQuestion`.
- **`readAll` muda de assinatura em T08** (`readAll(in:isAlive:)`). T11 (F17) usa `ProcessProbe.live.isAlive`. T22 (F26, no CLI, sem `ProcessProbe`) usa só a prova de `ESRCH`.
- **`Shell` ganha `input`/`timeout` em T11 e muda para o Core em T19** (sai de `Sources/ClaudeBar/`, vira `public`).
- **Popup persistente (T17)** vale para os três avisos de espera (`.waiting`, `.permission`, `.question`). `.finished` e `.failed` somem em 4 s.
- **Ajustes (T24)** já nascem com os 5 tipos de aviso de `Alert`. O lembrete (T26) entra na janela de Ajustes, não no menu (G10 sobre G09).
- **Assinatura final de `Notifier.post`** depois de T21: `post(_:body:sessionId:playSound:onOpen:)`.

## Tabela

| Id | Título | Fxx | Épico | Depende de | Arquivos principais | Esforço | Status |
|---|---|---|---|---|---|---|---|
| [T01](T01-som-respeita-toggle.md) | Som respeita o toggle de notificações | F01 | Base/Bugs | — | `Notifier.swift`, `AlertTests.swift`, READMEs | 0,5 h | FEITA (#2) |
| [T02](T02-versao-fonte-unica.md) | Versão de fonte única (`VERSION`) | F04 | Base/Bugs | — | `VERSION`, `scripts/build-app.sh`, `ci.yml`, READMEs | 0,5 h | FEITA (#3) |
| [T03](T03-hooks-merge-puro.md) | Merge aditivo dos hooks: funções puras no Core | F02 (1/3) | Hooks | — | `ClaudeBarCore/HookInstaller.swift` (novo), `HookInstallerTests.swift` (novo) | 1,5 h | FEITA (#4) |
| [T04](T04-hooks-previa-escrita.md) | Prévia, backup e escrita segura do `settings.json` + cópia estável do binário | F02 (2/3), F03 (cópia) | Hooks | T03 | `HookInstaller.swift`, `HookInstallerTests.swift` | 1,5 h | FEITA (#5) |
| [T05](T05-hooks-cli-install.md) | `claudebar-hook install/uninstall`, `install.sh` sem `jq`, `uninstall.sh`, exit 1 | F02 (3/3), F03 (registro estável) | Hooks | T04 | `claudebar-hook/main.swift`, `SessionStatus.swift`, `ProcessProbe.swift`, `scripts/install.sh`, `scripts/uninstall.sh` (novo), READMEs, `TODO.md` | 1,5 h | FEITA (#7) |
| [T06](T06-hooks-deteccao.md) | Detectar o estado da integração (`IntegrationState`) | F03 | Hooks | T05 | `HookInstaller.swift`, `HookInstallerTests.swift`, READMEs | 1,5 h | FEITA (#8) |
| [T07](T07-notification-matchers.md) | `Notification` só para permissão e formulário + `kind` no arquivo | F05 | Hooks | T05, T06 | `HookInstaller.swift`, `SessionStatus.swift`, `main.swift`, `SessionStatusTests.swift` (novo), READMEs | 1,5 h | FEITA (#9) |
| [T08](T08-sessoes-fantasmas.md) | Sessões fantasmas: regra de vida conservadora | F06 | Base/Bugs | T05 | `SessionStatus.swift`, `StatusDirectory.swift`, `ProcessProbe.swift`, `SessionMerge.swift`, `SessionStore.swift`, `main.swift`, `GhostSessionTests.swift` (novo), READMEs | 3 h | FEITA (#11) |
| [T09](T09-aprovacao-sai-de-esperando.md) | Permissão aprovada tira a sessão de "esperando" (`PostToolUse --if-waiting`) | H0 (pré-requisito de F12/F13) | Hooks | T07, T08 | `HookInstaller.swift`, `main.swift`, `HookInstallerTests.swift`, READMEs | 1 h | FEITA (#12) |
| [T10](T10-integracao-transparente.md) | Instalar/remover hooks pelo app, com diff e consentimento | F16 | Hooks | T06, T09 | `ClaudeBar/HookSetup.swift` (novo), `SessionStore.swift`, `MenuContent.swift`, READMEs | 3 h | FEITA (#13) |
| [T11](T11-testar-integracao.md) | "Testar integração" ponta a ponta + `Shell` com prazo | F17 | Hooks | T10, T08 | `HookSetup.swift`, `Shell.swift`, `MenuContent.swift`, `SessionTerminatorTests.swift`, READMEs | 2 h | FEITA (#14) |
| [T12](T12-estado-erro.md) | Estado de erro (`StopFailure`, `failed` do CLI) | F07 (1/2) | Hooks | T07 | `SessionStatus.swift`, `main.swift`, `HookInstaller.swift`, `SessionStore.swift`, `SessionMerge.swift`, `AgentsProbe.swift`, `MenuContent.swift`, `SessionMergeTests.swift`, READMEs | 2,5 h | FEITA (#15) |
| [T13](T13-aviso-falha.md) | Aviso com som próprio quando a resposta falha | F07 (2/2) | Notificações | T12, T01 | `Notifier.swift`, `StatusHUD.swift`, `SessionStore.swift`, `AlertTests.swift`, READMEs | 1 h | FEITA (#16) |
| [T14](T14-polling-leve.md) | Polling leve: `.exit` por PID, throttle, 60 s, `SessionStart` | F08 | Base/Bugs | T08, T10 | `ProcessExitWatcher.swift` (novo), `SessionStore.swift`, `AgentsProbe.swift`, `HookInstaller.swift`, `HookSetup.swift`, `ProcessExitWatcherTests.swift` (novo), READMEs | 3,5 h | FEITA (#17) |
| [T15](T15-rede-zero.md) | Rede zero verificável (`NoNetworkTests`) + "Verify it yourself" | F27 | Qualidade | — | `NoNetworkTests.swift` (novo), READMEs | 1 h | FEITA (#6) |
| [T16](T16-permissao-x-pergunta.md) | Permissão × pergunta: símbolo, texto e som distintos | F24 | Notificações | T07, T09, T12, T13 | `SessionStatus.swift`, `main.swift`, `HookInstaller.swift`, `SessionRow.swift`, `SessionMerge.swift`, `SessionStore.swift`, `MenuContent.swift`, `Notifier.swift`, `StatusHUD.swift`, 3 arquivos de teste, READMEs | 2,5 h | FEITA (#18) |
| [T17](T17-popup-persistente.md) | Popup de espera fica até o clique ou a transição; canto longe do cursor | F12 | Notificações | T09, T16 | `StatusHUD.swift`, `Notifier.swift`, `SessionStore.swift`, `AlertTests.swift`, READMEs | 2 h | FEITA (#19) |
| [T18](T18-abrir-pasta.md) | Abrir pasta do projeto | F11 | Navegação | — | `SessionStore.swift`, `MenuContent.swift`, `OpenFolderTests.swift` (novo), READMEs | 1 h | FEITA (#20) |
| [T19](T19-ir-para-sessao.md) | Ir para a sessão (árvore de processos + tmux) | F09 | Navegação | T11, T18 | `ClaudeBarCore/SessionNavigator.swift` (novo), `Shell.swift` → Core, `SessionStore.swift`, `MenuContent.swift`, `SessionNavigatorTests.swift` (novo), READMEs | 3 h | FEITA (#21) |
| [T20](T20-alerta-leva-a-sessao.md) | Clique no popup leva à sessão | F10 | Navegação | T19, T17 | `StatusHUD.swift`, `Notifier.swift`, `SessionStore.swift`, READMEs | 1 h | FEITA (#22) |
| [T21](T21-sem-som-se-olhando.md) | Sem som se o app da sessão já está na frente | F14 | Notificações | T19, T20, T01 | `Notifier.swift`, `SessionStore.swift`, READMEs | 1 h | FEITA (#23) |
| [T22](T22-cli-status-next.md) | CLI `claudebar-hook status` / `next` | F26 | Navegação | T19, T08 | `claudebar-hook/main.swift`, READMEs | 1,5 h | FEITA (#24) |
| [T23](T23-nome-e-branch.md) | Branch ao lado do nome da sessão | F20 | UI/Ajustes | T16 | `ClaudeBarCore/GitHead.swift` (novo), `SessionStatus.swift`, `main.swift`, `SessionRow.swift`, `SessionMerge.swift`, `MenuContent.swift`, `GitHeadTests.swift` (novo), `SessionMergeTests.swift`, READMEs | 2,5 h | FEITA (#25) |
| [T24](T24-janela-ajustes.md) | Janela de Ajustes: avisar por tipo, som, Sobre | F15 (1/2) | UI/Ajustes | T01, T13, T16, T21 | `ClaudeBar/SettingsWindow.swift` (novo), `Notifier.swift`, `MenuContent.swift`, `AlertTests.swift`, READMEs | 2,5 h | FEITA (#26) |
| [T25](T25-abrir-no-login.md) | Abrir no login (`SMAppService.mainApp`) | F15 (2/2) | UI/Ajustes | T24 | `SettingsWindow.swift`, READMEs (+ `PENDENCIAS.md` no plano B) | 1,5 h | FEITA (#27) |
| [T26](T26-lembrete-espera.md) | Lembrete único de espera | F13 | Notificações | T24, T17, T20, T21 | `SessionMerge.swift`, `SessionStore.swift`, `Notifier.swift`, `SettingsWindow.swift`, `SessionMergeTests.swift`, READMEs | 1,5 h | FEITA (#28) |
| [T27](T27-modo-sem-conteudo.md) | Modo "nunca mostrar conteúdo" | F25 | UI/Ajustes | T24, T26 | `SessionRow.swift`, `SessionStore.swift`, `Notifier.swift`, `SettingsWindow.swift`, `AlertTests.swift`, READMEs | 1 h | FEITA (#29) |
| [T28](T28-limites-statusline.md) | Limites: `claudebar-hook statusline` (grava `limits.json`, encadeia o original) | F22 (1/3) | Limites | T08, T22 | `ClaudeBarCore/RateLimits.swift` (novo), `ClaudeBarCore/StatusLineChain.swift` (novo), `StatusDirectory.swift`, `main.swift`, `RateLimitsTests.swift` (novo), READMEs | 2,5 h | FEITA (#30) |
| [T29](T29-limites-no-menu.md) | Limites 5 h e semanal no menu | F22 (2/3) | Limites | T28 | `SessionStore.swift`, `MenuContent.swift`, `RateLimitsTests.swift`, READMEs | 1 h | FEITA (#31) |
| [T30](T30-instalar-statusline.md) | Instalar/remover o `statusLine` (opt-in próprio) | F22 (3/3) | Limites | T28, T10, T06 | `ClaudeBarCore/StatusLineInstall.swift` (novo), `HookInstaller.swift`, `HookSetup.swift`, `MenuContent.swift`, `main.swift`, `RateLimitsTests.swift`, READMEs | 2 h | FEITA (#32) |
| [T31](T31-voiceover-legenda.md) | VoiceOver + legenda dos estados | F19 | i18n/a11y | T16, T23, T29 | `ClaudeBarApp.swift`, `SessionStore.swift` (`BarState`), `MenuContent.swift`, `StatusHUD.swift`, `AccessibilityTests.swift` (novo), READMEs | 2 h | FEITA (#33) |
| [T32](T32-icone-app.md) | Ícone do app (`AppIcon.icns`) | F18 | Distribuição | T02 | `Resources/AppIcon.icns` (novo), `scripts/build-app.sh`, `ci.yml`, READMEs | 0,5 h | FEITA (#10) |
| [T33](T33-dmg-universal.md) | DMG universal + SHA-256 (só o script) | F23 | Distribuição | T02, T32, T10 | `scripts/build-app.sh`, `scripts/make-dmg.sh` (novo), `.gitignore`, READMEs | 1,5 h | FEITA (#34) |
| [T34](T34-i18n-base-e-menu.md) | Inglês + português: base, menu, barra e avisos | F21 (1/2) | i18n/a11y | T32 e todas as tasks de UI (T01–T31) | `Resources/{en,pt-BR}.lproj/Localizable.strings` (novos), `scripts/build-app.sh`, `MenuContent.swift`, `SessionStore.swift` (`BarState`), `Notifier.swift`, `LocalizationTests.swift` (novo), testes que comparam texto, READMEs | 2 h | FEITA (#35) |
| [T35](T35-i18n-dialogos-e-janelas.md) | Inglês + português: diálogos, Ajustes, integração e limites | F21 (2/2) | i18n/a11y | T34 | `SessionStore.swift` (alertas), `SessionTerminator.swift`, `HookSetup.swift`, `HookInstaller.swift` (erros), `SettingsWindow.swift`, `MenuContent.swift` (limites), `.strings`, testes, READMEs | 1,5 h | FEITA (#36) |

| [T36](T36-popup-entre-spaces.md) | Popup de espera não some ao trocar de Space | F12 | Notificações | T17 | `StatusHUD.swift`, READMEs | 0,5 h | TODO |
| [T37](T37-nome-awaitbar.md) | O app passa a se chamar Awaitbar | F47 | Distribuição | — | `scripts/*.sh`, textos, `.strings`, `ci.yml`, READMEs | 2 h | TODO |
Total: 35 tasks, ~58 h. Nenhuma BLOQUEADA.

## Gates de todo PR (repetidos em cada task)

- `swift build` sem aviso novo; `swift test` verde; **nenhum teste removido, desabilitado ou afrouxado** para passar.
- Mexeu em `scripts/`, `Resources/`, `Info.plist` ou assinatura: `bash -n scripts/*.sh` e `./scripts/build-app.sh` (a CI também roda).
- Garantias do README não regridem: sem rede, `0700`/`0600`, nada de shell com interpolação de dado nosso, não ler conversa, hook fail-open (nunca `exit 2`), nenhuma escrita no `settings.json` sem prévia + backup.
- README **e** README.pt-BR atualizados quando o comportamento muda.
- Repo público: nada de dado pessoal, caminho de máquina ou e-mail no PR. Commit termina com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; descrição do PR com o rodapé do Claude Code.
- O que não deu para verificar vai no PR como "não verificado", com o motivo.

## Fora da rodada (não viram task)

F28–F50 e as descartadas do BACKLOG. Itens novos que as specs levantaram e ficam para depois: F27.3 (`nm` no `build-app.sh`, entra junto da primeira dependência SwiftPM), `elicitation_url_dialog → question`, glifo próprio na barra (`MenuBarIcon-*.png`), plano B do iTerm2 (`__CFBundleIdentifier`) se a verificação do T19 mostrar falha.

> **Nota do usuário (2026-11-15):** não usar `activate(ignoringOtherApps:)` em nenhuma task (vai ser descontinuada). Ver TODO.md, "Deprecated APIs".
