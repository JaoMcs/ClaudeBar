# Finalização do Awaitbar 0.1.0 (sem Apple)

Este arquivo tem três partes: **(A)** os resultados dos testes que o dono preenche, **(B)** as tasks que faltam para o 0.1.0, **(C)** as instruções para o agente que vai executá-las.

Decisão do dono (28 nov 2026): **nada de Apple por enquanto**. Sem Developer ID, sem notarização, sem Mac App Store. O app sai como DMG assinado ad-hoc num release do GitHub; na primeira abertura o usuário libera em Ajustes do Sistema → Privacidade e Segurança → "Abrir Mesmo Assim" (o README já explica).

---

## A. Resultados dos testes do dono

O dono roda `docs/TESTE-MANUAL.md` no Awaitbar instalado e preenche a coluna **Resultado**. O agente **não** testa na tela e **não** inventa resultado: se a célula estiver vazia, a task que depende dela fica **ESPERANDO**.

| Teste | Seção do roteiro | Resultado (`passou` / `falhou: <sintoma>` / vazio) |
|---|---|---|
| Abrir no login: liga, aparece em Itens de Início, abre depois de logout/login | 1 | |
| Abrir no login: continua ligado depois de rodar `./scripts/build-app.sh` de novo | 1 | |
| Popup de espera fecha com **1** clique | 6 | |
| Popup de espera continua visível ao trocar de Space | 6 | |
| Ir para a sessão — Terminal.app | 5 | |
| Ir para a sessão — Ghostty | 5 | |
| Ir para a sessão — iTerm2 | 5 | |
| Ir para a sessão — VS Code | 5 | |
| Ir para a sessão — Cursor | 5 | |
| Ir para a sessão — Warp | 5 | |
| Ir para a sessão — tmux | 5 | |
| Percentual do limite no menu bate com o `/status` do Claude Code | 3 | |
| Sessão do app desktop do Claude muda de estado (trabalhando → pronto) | 4 | |
| GIF de ~10 s do app em uso (caminho do arquivo) | — | |

---

## B. Tasks

Ordem: F1 e F2 primeiro (não dependem de teste). F3 a F6 só com a linha correspondente de A preenchida. F7 por último.

### F1 — Pendências sem Apple
- **Depende de:** nada · **Branch:** `docs/pendencias-sem-apple` · **PR:** `docs: pendências do 0.1.0 sem Apple`
- **Fazer:** em `PENDENCIAS.md`, mover Developer ID, notarização, Tap do Homebrew e "Automação por terminal" para uma seção nova **"Futuro (com Apple)"**, com uma linha explicando a decisão de 28 nov 2026. Deixar no topo só o que bloqueia o 0.1.0: os testes da parte A e o release (F7). Em `ROADMAP.md`, uma linha dizendo que a Mac App Store exige sandbox e o app, como é hoje (lê `~/.claude`, roda o `claude`, encerra processos), não passaria: seria um projeto à parte.
- **Aceite:** nenhum item removido, só movido; `scripts/dev/docs-check.sh` e `scripts/dev/pii-check.sh` ok.

### F2 — side-pr.sh não deixa branch local para trás
- **Depende de:** nada · **Branch:** `chore/side-pr-limpa-branch` · **PR:** `chore: side-pr apaga a branch local quando desiste`
- **Fazer:** em `scripts/dev/side-pr.sh`, quando o script sai sem ter aberto o PR (pii suspeito, commit ou push falhando), o `trap` também apaga a branch local criada (`git branch -D <branch>`). Quando o PR abre, a branch fica.
- **Aceite:** teste num repo em `mktemp -d` com um arquivo contendo um e-mail montado no próprio teste: o script sai 1 e `git branch --list <branch>` fica vazio. `bash -n` ok; bash 3.2 do macOS.

### F3 — Abrir no login: aplicar o resultado do teste
- **Depende de:** as 2 linhas "Abrir no login" da parte A · **Branch:** `fix/abrir-no-login-resultado` · **PR:** `fix: abrir no login conforme o teste com assinatura ad-hoc`
- **Se passou nas duas:** tirar dos dois READMEs a frase "After rebuilding the app, turn it on again" / equivalente em português; tirar o #27 de `PENDENCIAS.md`.
- **Se passou na primeira e falhou na segunda:** manter o toggle e a frase do README; no `PENDENCIAS.md`, trocar a linha do #27 por "funciona; desliga a cada build ad-hoc".
- **Se falhou na primeira:** plano B de `planning/05-specs/G10-ajustes-privacidade.md` (seção do F15.2, "Falhou"): no lugar do toggle em `Sources/ClaudeBar/SettingsWindow.swift`, só o botão "Abrir Itens de Início…"; README com o passo manual; `PENDENCIAS.md` em "Futuro (com Apple)" com o sintoma anotado.
- **Aceite:** `scripts/dev/gates.sh` → `gates=ok`; "Não verificado" no PR para o que mudou na tela.

### F4 — Popup: aplicar o resultado do teste
- **Depende de:** as 2 linhas "Popup" da parte A · **Branch:** `fix/popup-resultado-teste` · **PR:** `fix: popup de espera conforme o teste na tela`
- **1 clique e não some no Space:** só tirar o #19 de `PENDENCIAS.md`.
- **Precisa de 2 cliques:** aplicar o `FirstClickHostingView` de `planning/05-specs/G09-popup-lembrete.md` (linhas ~430–435) em `Sources/ClaudeBar/StatusHUD.swift`.
- **Some ao trocar de Space** (mesmo depois da T36): em `makePanel()` de `StatusHUD.swift`, testar `.stationary` no `collectionBehavior` e explicar no PR.
- **Aceite:** gates ok.

### F5 — Tabela de terminais do "Ir para a sessão"
- **Depende de:** pelo menos uma linha "Ir para a sessão" da parte A · **Branch:** `docs/terminais-verificados` · **PR:** `docs: terminais verificados no Ir para a sessão`
- **Fazer:** na tabela de terminais de `README.md` (seção "Going to a session") e de `README.pt-BR.md`, trocar "not verified"/"não verificado" pelo resultado de cada terminal testado. Os não testados continuam "não verificado".
- **Se iTerm2 falhou:** **não** implementar aqui. Abrir task nova com o plano B de `planning/05-specs/G07-ir-para-sessao.md` (campo opcional `__CFBundleIdentifier` no estado da sessão) e anotar no relatório.
- **Aceite:** `scripts/dev/docs-check.sh` ok.

### F6 — Verificações de dado real
- **Depende de:** linhas "Percentual do limite" e "Sessão do app desktop" · **Branch:** `docs/verificacoes-reais` · **PR:** `docs: limites e sessões do app desktop verificados`
- **Fazer:** atualizar `PENDENCIAS.md` e READMEs com o resultado. Se o percentual **não** bate: o aviso de limite (T41) continua desligado por padrão e o README diz que o número é aproximado. Se a sessão do app desktop **não** muda de estado: README diz que, no app desktop, o Awaitbar só mostra que a sessão existe.
- **Aceite:** docs-check e pii-check ok.

### F7 — Release 0.1.0 em rascunho
- **Depende de:** F1 a F6 mergeadas (ou ESPERANDO anotado) · **Branch:** `chore/release-0.1.0` · **PR:** `chore: notas da versão 0.1.0`
- **Fazer:**
  1. `CHANGELOG.md` (novo) com a seção `0.1.0`: o que o app faz, agrupado (estados e avisos, navegação, limites, integração com Claude/Gemini/Codex, privacidade, idiomas), mais "Limitações conhecidas" (assinatura ad-hoc e "Abrir Mesmo Assim", o que ficou não verificado na parte A).
  2. Merge do PR do changelog.
  3. Na `main` atualizada: `./scripts/make-dmg.sh` → `dist/Awaitbar-0.1.0.dmg` e `.sha256`; conferir com `cd dist && shasum -c Awaitbar-0.1.0.dmg.sha256`.
  4. `gh release create v0.1.0 dist/Awaitbar-0.1.0.dmg dist/Awaitbar-0.1.0.dmg.sha256 --draft --title "Awaitbar 0.1.0" --notes-file <seção 0.1.0 do CHANGELOG>`.
  5. **Só rascunho.** Nunca `--draft=false`, nunca `gh release edit --draft=false`: publicar é decisão do dono.
- **Aceite:** release em rascunho com os dois arquivos; link no relatório.

---

## C. Instruções para o agente

Você executa as tasks da parte B **uma por vez, em loop**. Outro agente (Claude) revisa e faz merge dos PRs de código; você não faz merge, exceto no passo 2 da F7 se o dono pedir.

### Regras que não podem quebrar
1. **Nunca tocar em `~/.claude`, `~/.gemini`, `~/.codex` reais.** Teste: `mktemp -d` + `CFFIXED_USER_HOME=<tmp>`.
2. Sem rede no app; nada de shell com interpolação (`Process` com argumentos separados); hook nunca sai com `exit 2`.
3. Não usar `NSApplication.activate(ignoringOtherApps:)`.
4. Repo público: nada de caminho da máquina, e-mail ou dado pessoal em commit, PR, comentário ou notas de release. Rode `scripts/dev/pii-check.sh` antes de cada PR.
5. Não remover nem afrouxar teste. Não mexer em `.claude/workflows/`.
6. **Não inventar resultado de teste de tela.** Task cuja linha da parte A está vazia: pule e marque ESPERANDO no relatório.
7. Release só em rascunho.
8. Só a task atual; pedido fora dela, anote e siga.

### Passo a passo de cada task
1. Ler a task na parte B e os arquivos que ela cita. Se `scripts/dev/ctx.sh` servir, use para mapear os arquivos antes de ler inteiros.
2. `git fetch -q origin && git switch -c <Branch> origin/main`.
3. Implementar o mínimo. README.md **e** README.pt-BR.md juntos. Comentários e commits em português.
4. `scripts/dev/gates.sh` até `gates=ok` (3 falhas seguidas pelo mesmo motivo: PR em rascunho com o erro, siga para a próxima).
5. Commit `tipo: descrição` terminando com `Co-Authored-By: <modelo que de fato rodou> <noreply@...>`.
6. PR: corpo num arquivo temporário (o que muda, por quê, como testar, **"Não verificado"**). Se você é o Claude Code: `scripts/dev/pr-open.sh "<PR>" <corpo.md>`. Outro agente: `scripts/dev/pii-check.sh && scripts/dev/pii-check.sh <corpo.md> && git push -u origin <branch> && gh pr create --base main --title "<PR>" --body-file <corpo.md>`, com a última linha do corpo dizendo qual agente gerou.
7. `scripts/dev/ci-wait.sh <pr>`; vermelho: corrigir na mesma branch, no máximo 2 vezes.
8. `git switch main && git pull --ff-only`; próxima task.

### Se o `gh` falhar por permissão
O `gh` pode estar ativo em outra conta. **Não troque a conta ativa.** Rode o comando com o token da conta dona do repositório só para ele (`GH_TOKEN=$(gh auth token -u <conta-dona>) gh ...`) ou pare e avise.

### Relatório final
| Task | Estado (PR aberto / mergeado / ESPERANDO / rascunho por erro) | PR ou link | Não verificado | Observações |
|---|---|---|---|---|
