# Relatório final — evolução do ClaudeBar

> Só para você. Não commitar (sugestão: pôr `RELATORIO-FINAL.md` no `.git/info/exclude`).
> Período: 15 a 22/11/2026. `main` @ 27826cf.

## Resultado

- 35 tasks em 36 PRs mergeados (#1 é a CI). Nenhuma bloqueada.
- Testes: **34 → 155** (`swift test`). Nenhum teste removido para passar.
- Sem rede, sem leitura de conversa, `0700`/`0600`, hook fail-open: tudo mantido. O `NoNetworkTests` agora garante a parte da rede.
- App em inglês e português, ícone próprio, DMG universal por script (`scripts/make-dmg.sh`).

## Tasks

Modelo: Fable = T09–T23, T15 e T32; Opus = resto. Revisão: B = bloqueante, S = sugestão, N = nit.

| Id | Título | PR | Modelo | Revisão | Ficou sem verificar |
|---|---|---|---|---|---|
| T01 | Som respeita o toggle | #2 | Opus | 1 N recusado | — |
| T02 | Versão de fonte única (`VERSION`) | #3 | Opus | sem achados | — |
| T03 | Merge aditivo dos hooks (funções puras) | #4 | Opus | teste do `lineDiff`, helpers private, e-mail noreply | — |
| T04 | Prévia, backup e escrita segura do settings.json | #5 | Opus | 2 S + 1 N aplicados (teste 0444, pasta ausente) | — |
| T05 | `claudebar-hook install/uninstall`, `install.sh` sem jq | #7 | Opus | B (conflito) aplicado; 1 N recusado | sessão real com hooks em exec form; `install.sh`/`uninstall.sh` ponta a ponta |
| T06 | Detectar estado da integração | #8 | Opus | S (pasta ausente ≠ somente leitura) aplicado | — |
| T07 | `Notification` com matchers + `kind` | #9 | Opus | 1 N aplicado | matchers disparando de verdade |
| T08 | Sessões fantasmas | #11 | Opus | B (frase quebrada no README) aplicado | PID reciclado, `kill -9`, app desktop |
| T09 | Aprovação tira de "esperando" | #12 | Fable | 1 N | aprovar/negar real; `PostToolUseFailure` no `/hooks` |
| T10 | Instalar/remover hooks pelo app | #13 | Fable | S (gate manual) recusado; 2 N aplicados | todo o passo manual 1–7 (alerta na frente, 1º launch) |
| T11 | Testar integração + `Shell` com prazo | #14 | Fable | **B (✓ falso) aplicado**; S (comparar bytes) aplicado; S (manual) recusado | alerta com 4 ✓, selftest sem sobra, quarentena |
| T12 | Estado de erro (`StopFailure`) | #15 | Fable | S aplicada (rearme virou função pura + teste); manual recusado | triângulo na barra; `StopFailure` real. **Incidente**, ver abaixo |
| T13 | Aviso de falha com som próprio | #16 | Fable | sem achados | popup vermelho + Basso |
| T14 | Polling leve | #17 | Fable | B (números) aplicado em parte | números com sessões simuladas; manual 3–8, `/compact` |
| T15 | Rede zero verificável | #6 | Fable | sem achados | `nettop` por 30 s, Little Snitch |
| T16 | Permissão × pergunta | #18 | Fable | S (reaviso com teste) aplicado; S (manual) recusado | ❓ real, `ExitPlanMode`, sons |
| T17 | Popup de espera persistente | #19 | Fable | **B (1/2 cliques, Space) recusado** | os 7 passos manuais |
| T18 | Abrir pasta do projeto | #20 | Fable | sem achados | Finder na frente, TCC em `~/Documents` |
| T19 | Ir para a sessão | #21 | Fable | S (timeout no tmux) + 3 N aplicados | todos os terminais; tmux nem estava instalado |
| T20 | Clique no popup leva à sessão | #22 | Fable | sem achados | clique real |
| T21 | Sem som se já está olhando | #23 | Fable | sem achados | som real por terminal |
| T22 | CLI `status` / `next` | #24 | Fable | 2 N aplicados | `next` com sessão real e no tmux |
| T23 | Branch ao lado do nome | #25 | Fable | S (parar no 1º `.git`, symlink) aplicado; N (TCC) recusado | menu real; TCC em `~/Documents` |
| T24 | Janela de Ajustes | #26 | Opus | 2 N aplicados | janela na frente, layout, prévia de som |
| T25 | Abrir no login | #27 | Opus | **B (gate manual) recusado; mergeado mesmo assim** | gate inteiro (ad-hoc, rebuild, logout/login) |
| T26 | Lembrete único de espera | #28 | Opus | sem achados | popup/som do lembrete |
| T27 | Modo sem conteúdo | #29 | Opus | 1 N aplicado | popup real, `log show` |
| T28 | Limites via statusline | #30 | Opus | B (CI vermelho) aplicado: causa real era fila global sem thread no runner | encadeamento real; conta Pro/Max |
| T29 | Limites no menu | #31 | Opus | B (CI) aplicado; S (manual) recusado, README ajustado | menu real |
| T30 | Instalar/remover statusLine | #32 | Opus | 2 S + 1 N aplicados (0600 sem janela, executável órfão) | ida e volta no settings real |
| T31 | VoiceOver + legenda | #33 | Opus | S (teste pegar `⚠️`) aplicado | VoiceOver ouvido |
| T32 | Ícone do app | #10 | Fable | sem achados | ícone em Finder/Spotlight |
| T33 | DMG universal + SHA-256 | #34 | Opus | sem achados | outro Mac, Intel, "Abrir Mesmo Assim" |
| T34 | i18n: base, menu, barra, avisos | #35 | Opus | sem achados | render com `-AppleLanguages` |
| T35 | i18n: diálogos, Ajustes, integração | #36 | Opus | S (manual) recusado; 1 N aplicado | render com `-AppleLanguages` |

## Lacunas confirmadas

1. **T25 (#27): mergeado com o bloqueante aberto.** O revisor pediu o gate manual (`SMAppService.mainApp.register()` com assinatura ad-hoc, rebuild, logout/login). O corretor recusou (mexe em estado real da máquina) e o merge saiu igual. Primeiro item do `docs/TESTE-MANUAL.md`.
2. **T14 (#17): em parte.** Os números **foram** medidos e estão no PR: 10 consultas em 10 min (critério ≤ 15; antes 120), CPU 1,79 s contra 20,72 s (8,6%, critério ≤ 20%). Mas com 2 sessões simuladas num home temporário. Faltam os passos 3–8 com sessões reais, principalmente o `/compact` não gravar ocioso.
3. **T17 (#19): bloqueante recusado.** Não se sabe se o popup fecha com 1 ou 2 cliques nem se some ao trocar de Space. Planos B prontos na spec, não aplicados.
4. **T11 (#14): corrigido. Sim.** Conferido em `Sources/ClaudeBar/HookSetup.swift`: "Hooks registrados" só dá ✓ em `.ok`, `.binaryMissing`, `.binaryOutdated`; `.invalidSettings` e `.hooksDisabled` dão `?` (não verificado); `.readOnlySettings` e o resto dão ✗. "Executável igual" compara os bytes direto.
5. **Outros bloqueantes:** T05, T08, T28 e T29 tinham bloqueante e foram resolvidos. Não há outro bloqueante recusado além de T17 e T25 (T14 em parte). Sugestões de "rodar o manual antes do merge" foram recusadas em T10, T11, T12, T16, T29 e T35; tudo isso está no roteiro manual.
6. `activate(ignoringOtherApps:)`: 2 usos em `SessionStore.swift` (linhas 263 e 272), no `TODO.md`.

### Incidente na T12 (precisa de você)

Na correção da T12 um agente rodou `claudebar-hook install` com só `HOME=<tmp>`, que o `NSHomeDirectory()` ignora. Gravou no seu `~/.claude/settings.json` real por ~30 s. Restaurou byte a byte pelo backup. Sobraram, e **ainda existem**:
- `~/.claude/claudebar/bin/claudebar-hook` (binário daquela branch; nada aponta para ele hoje).
- `~/.claude/claudebar/backups/settings.json.20261116-202432-958` (cópia do seu settings original).

Seu `settings.json` hoje tem os hooks no **formato antigo** (4 eventos apontando para dentro de `~/Applications/ClaudeBar.app`, sem `statusLine`). Ao abrir o app novo ele vai oferecer a migração. Pode apagar o binário de `bin/`: a reinstalação pelo menu recria. Guarde o backup até terminar o roteiro.

## Processo

- **Loop por task:** implementador em worktree → PR → revisor sem contexto → corretor (até 2 rodadas) → merge squash. Sequencial; T15 e T32 rodaram em paralelo cedo porque não tocavam arquivos quentes.
- **CI como gate:** `swift test` + `build-app.sh` em todo PR, runner macos-15. Pegou dois problemas reais (T28: pool de threads no runner de 3 vCPU; T29: `@MainActor` em teste). T05 ficou sem CI até o rebase (conflito).
- **Revisão como comentário:** o GitHub não deixa a mesma conta aprovar o próprio PR. O merge dependeu de CI verde, não da revisão. Por isso T17 e T25 entraram com bloqueante aberto. Para a próxima: o merge devia parar quando houver bloqueante recusado.
- **Fable ficou sem crédito na T24.** De T24 em diante foi Opus. Vários commits da fase Fable saíram com trailer `Co-Authored-By: Claude Fable 5.2` em vez de Opus.
- **Lições:** `timeout` não existe no macOS; branch presa em outro worktree trava o corretor (resolvido com `git switch --detach`); `planning/` não existe nos worktrees; `CFFIXED_USER_HOME`, nunca só `HOME`.

## Triagem da `planning/`

| O quê | Para onde foi |
|---|---|
| Pendências do dono (seção 7 do handoff, "Precisa do usuário" do BACKLOG) | `PENDENCIAS.md` |
| "Não verificado" de todas as tasks e as verificações manuais das specs (G03, G05, G07–G12) | `docs/TESTE-MANUAL.md` |
| BACKLOG F28–F50 que valem, itens adiados das specs (iTerm2 plano B, `elicitation_url_dialog`, `nm`, glifo, Liquid Glass), descartadas com motivo, decisões técnicas | `ROADMAP.md` |
| Conceito do ícone, paleta, notas de HIG, script gerador | `docs/design/README.md` + `docs/design/render-icon.swift` (copiado igual) |
| Tasks, PRs, revisões, incidente, processo | este arquivo |

**Pode apagar:** `00-PLANO.md`, `00-brainStorm.md`, `RETOMAR.md`, `CONTEXTO-HANDOFF.md`, `todo-deprecated.patch`, `01-pesquisa/`, `02-painel/`, `03-validacao/`, `04-como-fazer/`, `06-tasks/`, `08-reviews/` (vazia), `07-design/it1..it3`, `07-design/preview.swift`, `07-design/final/` (o `.icns` já está em `Resources/`; o resto o script regera).

**Segure até rodar o roteiro manual:** `05-specs/G09-popup-lembrete.md` (código do `FirstClickHostingView`), `05-specs/G10-ajustes-privacidade.md` (código do plano B do login) e `05-specs/G07-ir-para-sessao.md` (detalhe do plano B do iTerm2). O `ROADMAP.md` resume os três, mas o código pronto está só ali. Depois do roteiro, apague.

Os journals dos workflows (fora do repo, na pasta de projetos do Claude Code) só servem para auditoria; este relatório já tirou o que importa.
