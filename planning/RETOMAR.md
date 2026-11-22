# RETOMAR — estado em 2026-11-15

Leia isto primeiro ao voltar. O plano completo está em `00-PLANO.md` (prompt refinado, guard rails, miniprompts).

## Onde paramos
- ✅ Pesquisa (`01-pesquisa/`), painel de usuários (`02-painel/PAINEL.md`), validação + backlog (`03-validacao/BACKLOG.md`)
- ✅ Como fazer (`04-como-fazer/`, 14 grupos) e specs técnicas macOS (`05-specs/`, 14 grupos)
- ✅ 35 tasks em `06-tasks/` (`INDEX.md` = ordem de execução, dependências, arquivos)
- ✅ Ícone final pronto em `07-design/final/` (ainda NÃO integrado — é a T32)
- ✅ CI no GitHub mergeado (PR #1): `swift test` + `scripts/build-app.sh` em cada PR, runner macos-15
- ⏸ **Loop PAUSADO de novo em 2026-11-16 a pedido do usuário**, logo após o merge da T03.
  - Feitas e mergeadas: T01 (#2), T02 (#3), T03 (#4). `main` = b15bf9b, 44 testes passando.
  - **T04: PR #5 aberto em RASCUNHO, sem revisão** (implementador abriu antes da pausa). Ao retomar: `gh pr ready 5`, rodar revisor → corretor → merge só para ela, depois seguir o loop a partir da T05.
  - Script do loop já corrigido (sem `timeout`, libera branch com `git switch --detach`, experimentos nunca em ~/.claude): <pasta da sessão do Claude Code> (args: {"tasks": ["T05-hooks-cli-install", ...]}).
  - Worktrees limpos; `.claude/` está no `.git/info/exclude`.

## Pendente localmente
- Nota do `TODO.md` ("Deprecated APIs") já entrou na `main` pelo PR da T01.
- `planning/` está fora do git via `.git/info/exclude`. Não commitar essa pasta.

## Próximos passos (em ordem)
1. Confirmar com o usuário que pode retomar o loop.
2. Rodar o loop task a task, seguindo `06-tasks/INDEX.md` (T01 → T35), uma por vez:
   1. **Implementador** (worktree isolado): `git fetch && git switch -c <branch da task> origin/main`, implementa seguindo `06-tasks/Txx-*.md`, `swift build && swift test` (e `scripts/build-app.sh` se mexer em bundle/scripts), atualiza README/README.pt-BR se mudar comportamento, commit com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, push, `gh pr create` (título em pt "tipo: descrição", corpo terminando com o rodapé do Claude Code).
   2. Esperar o CI (`gh pr checks <n> --watch`).
   3. **Revisor sem contexto** (só PR + task): lê o diff, posta `gh pr review <n> --comment` com severidade (bloqueante/sugestão/nit). A mesma conta não pode aprovar o próprio PR, então a revisão sai como comentário.
   4. **Corretor:** aplica o que fizer sentido, responde no PR o que não aplicou, gates, push, espera o CI.
   5. CI verde + revisão resolvida → `gh pr merge <n> --squash --delete-branch` → `git switch main && git pull` → marca a task como FEITA no INDEX.
   6. Falhou 2 rodadas de correção → task BLOQUEADA, PR fica aberto, segue para a próxima que não dependa dela.
   - Dá para automatizar com um Workflow (implementador → CI → revisor → corretor → merge) passando a lista de tasks em `args`, sequencial.
3. Regras que valem em toda task: não usar `activate(ignoringOtherApps:)`; sem rede; não ler conversas; `0700`/`0600`; nada via shell com interpolação; hook nunca quebra a sessão (fail-open); nunca mexer no `~/.claude/settings.json` real do usuário durante testes (usar diretório temporário).
4. Perguntar ao usuário se quer revisar pessoalmente antes do merge os PRs que mexem no `settings.json` (T03 a T07, T10, T30).
5. Depois do loop: escrever `PENDENCIAS.md` permanente (itens que dependem do usuário, ver abaixo), relatório final com tasks e PRs, triagem crítica de `planning/` (guardar só o essencial em docs permanentes, ex.: ROADMAP curto) e apagar `planning/`.

## O que depende do usuário (não bloqueia o loop)
- Conta Apple Developer (US$ 99/ano) + Developer ID → assinatura/notarização, notificação nativa, Homebrew
- Nome definitivo sem "Claude" + bundle id (`ClaudeBar` colide com outro app; "Claude" no nome é vedado pela marca)
- Licença (repo público sem LICENSE)
- Repositório do tap do Homebrew, publicar release, GIF do README
- Testar Automação por terminal (aba exata) e capturar um payload real de pausa por limite
- Defaults já assumidos: idioma segue o sistema com fallback inglês; 1ª versão pública `0.1.0`

---

## PAUSA 2026-11-22 (stepback pedido pelo usuário)

- **As 35 tasks estão na `main`** (PRs #2–#36, `main` @ 27826cf, 155 testes). Nenhum loop rodando.
- **Fechamento escrito e NÃO commitado:** `PENDENCIAS.md`, `ROADMAP.md`, `docs/TESTE-MANUAL.md`, `docs/design/` (script do ícone + README) estão untracked na raiz do repo. `RELATORIO-FINAL.md` está na raiz e no `.git/info/exclude`.
- **Falta:** revisar esses arquivos → PR → merge; rodar o `docs/TESTE-MANUAL.md` (usuário); só então apagar `planning/`.
- **Não apagar ainda:** `05-specs/G07`, `G09` e `G10` (planos B de iTerm2, clique no popup e abrir no login).
- **Lacunas:** T25 (gate do login ad-hoc não rodado), T17 (1 ou 2 cliques, troca de Space), T14 (medido só com sessões simuladas). T11 corrigido.
- **Incidente T12:** um agente gravou ~30 s no `~/.claude/settings.json` real e restaurou. Sobras confirmadas: `~/.claude/claudebar/bin/claudebar-hook` e `~/.claude/claudebar/backups/settings.json.20261116-202432-958`. O settings atual tem os 4 hooks antigos (apontando para o app instalado), sem `statusLine`. Nada foi limpo; decisão do usuário.
- Fable ficou sem créditos na T24; o resto rodou no Opus.
