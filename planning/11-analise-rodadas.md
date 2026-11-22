# Análise das rodadas T36–T45 (22 nov 2026)

Fonte: `scripts/dev/wf-report.sh` sobre os registros locais dos workflows. Mesma régua para os dois sistemas: tokens ponderados = entrada + 1,25×cache escrito + 0,1×cache lido + 5×saída. Tokens não são preço (Haiku custa menos por token).

## Entregue

| Rodada | Tasks | PRs | Modelo |
|---|---|---|---|
| Nome e popup | T36, T37 | #39, #40 | Haiku→Sonnet (2ª tentativa), Sonnet |
| Trilha A | T38, T40 | #43, #49 | Haiku, Opus |
| Trilha B | T39, T43, T44 | #44, #48, #52 | Haiku, Sonnet, Opus |
| Trilha C | T41, T42, T45 | #45, #47, #50 | Sonnet ×3 |
| Processo | rebase em conflito, wt-prune, análise, T46 | #46, #51, #53 | — |

10 tasks de produto em ~1 h de relógio com 3 trilhas paralelas (antes: ~9 min por task em série). Nenhum conflito de merge entre trilhas: o caminho de rebase não precisou rodar.

## Custo por papel

| Papel | Antigo (T04–T35, 33 tasks) média | Novo (T36–T45, 10 tasks) média | Variação |
|---|---|---|---|
| Implementador | 567 mil | 614 mil | +8% |
| Revisor | 210 mil | 73 mil | **−65%** |
| Corretor | 278 mil; 0,73 rodada por task (24/33) | 280 mil; 0,5 rodada por task (5/10) | **−31% em rodadas por task** |
| Merge | 99 mil | 13 mil | **−87%** |
| **Total por task** | **~1,08 mi** (567+210+202+99) | **~0,84 mi** (614+73+140+13) | **−22%** |

O implementador virou ~73% do custo. Revisor, corretor e merge já estão baratos.

## Achados

1. **Haiku não economiza token em task pequena.** T38 (Haiku) 546 mil e T39 (Haiku) 687 mil, contra T45 (Sonnet) 217 mil e T43 (Sonnet) 304 mil. O Haiku dá mais voltas e relê mais. Em preço ainda pode sair mais barato, mas em tempo e tokens não.
2. **Desvio de foco:** a 1ª tentativa da T36 (Haiku) atendeu um pedido do dono que chegou no meio e abriu o app. Corrigido: regra de foco no `implementer.md` e branch/título prontos no brief (T46).
3. **Critério errado escrito pelo orquestrador:** a T46 pedia `node --check` sem `export`/`return`, o que quebraria o workflow. O revisor marcou e o corretor foi avisado a tempo. Lição: critério de task também precisa de lint.
4. **Revisão pegou bug real em processo:** bloqueante do `wt-prune.sh` (`--force` apagaria worktree com trabalho), `$PPID` na T44 (shell com variável), regex de BL que casava com "problema".

## Feito agora (scripts sem IA)

| Script | Substitui |
|---|---|
| `wf-report.sh` | os trechos Python que o orquestrador escrevia para somar tokens |
| `pii-check.sh` | os `grep` manuais por caminho da máquina e e-mail antes de publicar |
| `side-pr.sh` | worktree + cópia + commit + PR feitos à mão para não trocar a branch do checkout |
| `install-local.sh` | build + Lixo + `ditto` + `open` para o dono testar |
| `wt-prune.sh` (#51) | limpeza manual de worktrees |

Skills: `install-local`, `wf-report`, `side-pr`. A T46 (#53) traz `task-meta`, `task-lint`, `overlap`, `rebase-auto`, `docs-check`, `index-mark` e o corretor só com BL.

## Próximas economias (não feitas)

| Ideia | Por quê |
|---|---|
| Rotear task pequena para Sonnet, não Haiku | achado 1; mudar a faixa 0–1 do `route.sh` depois de mais amostras |
| `ctx.sh <task.md>`: entregar ao implementador as assinaturas e trechos dos arquivos da tabela | o implementador é 75% do custo e passa muito tempo lendo |
| `pii-check.sh` dentro do `pr-open.sh` | hoje só o `side-pr.sh` chama (o `pr-open.sh` está na T46) |
| Lint dos critérios de aceite (comandos citados existem e rodam) | achado 3 |
