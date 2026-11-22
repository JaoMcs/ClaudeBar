# 10 — Análise do processo com agentes (22 nov)

Fontes: `journal.jsonl` + `agent-*.jsonl` de 14 workflows (205 agentes; 165 de implementação/revisão/correção/merge, o resto é pesquisa/spec), `gh pr list --state merged --limit 50`, `AGENTS.md`, `impl-loop.js`, `scripts/dev/*`, `.claude/agents/*`. Uso por agente = soma do campo `usage` das mensagens `assistant` do `agent-*.jsonl` (dedupe por id). Duração = último − primeiro timestamp do agente (tempo ativo, não relógio do lote).

**Convenções**
- **tok pond.** = input + 1,25·cache_write + 0,1·cache_read + 5·output. É ESTIMATIVA: pesos genéricos de preço, sem diferenciar modelo (haiku real é mais barato que o número mostra). Serve para comparar, não para cobrar.
- Antigo = wf c2f5fb50, eb7b1d22, cb88729e, dd40d909, 4def238e, 21bf5952, ce50e716, c9901590 (T01–T35; 130 agentes úteis). Novo = c6bedbb9 (T36, T37) + 8498f8ee (T38), 3455ee78 (T39), 9d3fd37f (T41) ainda rodando (só 10 agentes terminados). **Amostra nova é pequena e de tasks pequenas (PR #39 = 3 linhas): não conclui nada sozinha.**
- c9901590 (T01–T04) não estava na lista do pedido; entra no antigo (mesmo desenho). 7bebbff6 e 4a29492a (pesquisa/spec) ficam fora.

## 1. Tokens e tempo por papel

Média por agente. out/cw/cr = output / cache_write / cache_read, em milhares.

| Sistema | Papel | Modelo (real, do jsonl) | n | tempo s | turnos | out k | cw k | cr k | tok pond. k |
|---|---|---|---|---|---|---|---|---|---|
| antigo | implementador | opus | 19 | 148 | 17,6 | 12,6 | 79 | 1529 | 315 |
| antigo | implementador | fable | 16 | 139 | 11,4 | 11,2 | 73 | 916 | 239 |
| antigo | revisor | opus | 33 | 147 | 6,9 | 3,3 | 61 | 437 | 136 |
| antigo | revisor | fable | 2 | 71 | 5,5 | 2,3 | 75 | 308 | 136 |
| antigo | corretor | opus | 15 | 250 | 10,3 | 4,2 | 74 | 615 | 175 |
| antigo | corretor | fable | 10 | 223 | 9,4 | 6,7 | 76 | 628 | 191 |
| antigo | merge | opus | 19 | 16 | 4,1 | 0,6 | 51 | 187 | 86 |
| antigo | merge | fable | 16 | 19 | 3,3 | 1,1 | 50 | 146 | 83 |
| novo | implementador | haiku | 3 | 37 | 6,0 | 4,1 | 82 | 466 | 170 |
| novo | implementador | sonnet | 3 | 68 | 8,7 | 5,1 | 88 | 743 | 210 |
| novo | revisor | sonnet | 2 | 102 | 4,0 | 1,3 | 15 | 47 | 29 |
| novo | corretor | — | 0 | — | — | — | — | — | — |
| novo | merge | haiku (effort low) | 2 | 9 | 2,0 | 0,3 | 5 | 8 | 9 |

**Por task** (soma dos agentes da task, tok pond.):

| Sistema | Tasks | tok pond./task | tempo ativo/task | output/task |
|---|---|---|---|---|
| antigo (T01–T35) | 35 | **630 k** (T04+: 642 k) | 474 s | 19,7 k |
| novo, só tasks fechadas (T36, T37) | 2 | **335 k** (T36 inclui 170 k do desvio do Haiku; sem ele ~250 k) | ~215 s | ~7 k |
| novo, incluindo impl de T38/T39 | 5 | 243 k (parcial, falta revisão/merge) | 108 s | 6,2 k |

Onde o antigo gastava (22,0 M pond. no total): implementador 45%, revisor 22%, corretor 21%, merge 13%.

**Leituras que importam**
- Merge por agente Opus/Fable custava 84 k/task só para chamar um script; Haiku effort low custa 9 k (−89%). Já capturado.
- Piso por agente: ~50–90 k de cache_write em impl/rev/fix (system prompt + CLAUDE.md + hook ponytail + definição do agente + leitura inicial). Merge no novo tem 5 k porque o merger só tem `Bash`.
- Opus gasta mais turnos que Fable no implementador (17,6 × 11,4) e 32% mais tok pond., mas as tasks não são as mesmas (T18–T23 Fable, resto Opus): **comparação confundida**, não é prova de que Fable é melhor.
- Revisor Sonnet 29 k × Opus 136 k (n=2, diff pequeno): indício, não medida.
- Haiku implementa em 37 s / 170 k pond., mas só foi usado em 3 tasks (todas pequenas; 1 desviou do foco).

## 2. Passos repetidos entre agentes

Chamadas `Bash` dos 144 agentes impl/rev/fix/merge, contadas por regex nos `agent-*.jsonl`. Uma chamada pode casar mais de um padrão.

| Passo repetido | Chamadas | Agentes | Quem | Já é script? |
|---|---|---|---|---|
| tocar/ler/conferir README (as duas línguas) | 284 | 84 | impl 193, rev 46, fix 45 | não |
| `git fetch` | 133 | 103 | todos | parte do `implementer.md`; reviewer repete 38× |
| `git worktree/switch/checkout` | 166 | 71 | impl 78, fix 81 | não (branch presa em worktree: erro recorrente) |
| `ci-wait` / `gh pr checks` | 120 | 99 | rev 56, merge 35, fix 29 | sim, mas 3 papéis esperam o mesmo CI |
| `cat/sed/head planning/…` (task/spec/INDEX) | 204 | 121 | impl 92, merge 52, rev 40, fix 20 | não |
| `swift build/test` direto | 204 | 66 | impl 138, fix 55, rev 11 | `gates.sh` só usado em 5 agentes (nasceu depois) |
| `build-app.sh` | 91 | 38 | impl 72, fix 8, **rev 11** | dentro do `gates.sh` quando mexe em scripts/Resources |
| `git show origin/<b>:arq` | 57 | 33 | rev 52 | não |
| `gh pr diff` | 42 | 37 | rev | não |
| `gh pr create` / `pr-open.sh` | 42 | 39 | impl | `pr-open.sh` (corpo ainda escrito à mão) |
| `gh pr comment` | 26 | 25 | fix | não |
| `gh pr review` | 37 | 37 | rev | não |
| `git rebase/merge` | 5 | 3 | rev/fix | só 1 agente de rebase no novo (ainda não disparou) |
| `bash -n` | 16 | 8 | impl/fix | dentro do `gates.sh` |

Leitura de código por `Read` não é o problema: nenhum arquivo foi lido por mais de 3 agentes (README ×3, HookInstaller ×2). O custo está em Bash em volta.

Pontos concretos:
- Revisor rodou `build-app.sh` 11× e `swift build/test` 11× apesar da regra "não builda" (antigo; o `reviewer.md` atual já proíbe).
- Task md tem 1,6–7 KB (~0,4–1,8 k tok), lida ~3×/task (impl, rev, fix). Barato; não vale script.
- Do lote T36–T45 (45 pares, por texto das tasks): **todos** compartilham `README.md`+`README.pt-BR.md`; 16 pares compartilham código `Sources/` (SessionStore, MenuContent, HookSetup, SettingsWindow, `claudebar-hook/main.swift`); `Localizable.strings` ×2 em 12 pares; `TODO.md` em 6. README e strings são hot spots de conflito.

## 3. Falhas e retrabalho

| Evento | Contagem | Custo / efeito | Fonte |
|---|---|---|---|
| Task com ≥1 rodada de correção | 25 corretores em 35 tasks (71%) | 181 k pond. cada; 4,5 M no total (21%) | journals |
| Correção disparada só por NIT/SG (sem BL, CI verde) | 17 de 25 (68%): 6 só-NIT, 9 NIT+SG, 2 só-SG | ~3,1 M pond. (est. 17 × 181 k) | journals |
| Revisão sem achado | 11 de 35 (31%) | 136 k cada, 1,5 M | journals |
| Revisão com BL | 8 BL em 8 tasks: T05, T08, T11, T14, T17, T25, T28, T29 | ver abaixo | journals |
| CI vermelho na revisão | 3: T05 (conflito README, CI nem rodou), T28 (thread `.global()` faltando no runner 3 vCPU), T29 (`@MainActor` faltando) | corretor + espera | journals |
| BL "verificação manual na tela" (não é defeito de código) | 3: T14, T17, T25 | corretor sem o que corrigir; `AGENTS.md` já mudou isso para SG | journals |
| BL de doc (frase quebrada) | 1: T08 | rodada inteira por 1 frase | journals |
| Conflito com a main | 1 visto (T05, README) | rebase manual; no novo há agente `rebase:` (não exercitado) | journals |
| Agente `synthetic` (erro de API) em impl/fix/merge | 4 em 130 (ex.: T24 impl) | ~15 k perdidos cada | agent jsonl |
| Branch já presa em outro worktree (corretor) | ≥2 visíveis (T01, T03) | contorno com HEAD destacado; agora no `implementer.md` e `pr-open.sh` | journals |
| **Desvio T36 (Haiku)** | 1 de 9 tasks do novo | 170 k pond., 35 s, 0 PR, retrabalho com Sonnet | wf c6bedbb9 |

**Causa do desvio T36 (confirmada no jsonl do agente):**
1. `impl-loop.js` passa `B:<campo Branch da task>` como texto literal e o agente tem de extrair; o Haiku declarou "campo Branch veio sem preencher".
2. O harness do Workflow repassa a mensagem do usuário que disparou o workflow, textualmente, como primeira mensagem de todo subagente ("pra eu poder testar, executa ai o claude b…"), com a regra "este pedido prevalece sobre a task". O Haiku obedeceu. A regra de foco do `implementer.md` ajuda, mas o prompt do harness diz o contrário. Reviewer e merge do mesmo run não desviaram.

Taxa de BL de código real (T11, T28, T29, T05) = 4/35 (11%); o resto dos BL é verificação manual (3), conflito (1) ou doc (1).

## 4. Propostas (por economia, maior primeiro)

Base: ~630 k pond./task no antigo; ~250–335 k no novo. Economia em tok pond./task, ESTIMATIVA com a taxa observada no antigo.

| # | Proposta | Economia/task (est.) | Custo de fazer | Risco |
|---|---|---|---|---|
| 1 | **Corretor só com BL ou CI vermelho; SG vai para comentário/backlog** | ~57 k (11 de 35 tasks tinham só SG/NIT: 31% × 181 k) | 1 linha no `impl-loop.js` (`acts = a.filter(s==='BL')`) | SG real não corrigido; manter SG obrigatório se `route.sh` ≥ 4 |
| 2 | **Revisão escalonada** (`review-gate.sh`) | 40–80 k (31% sem achado × 136 k + Sonnet em vez de Opus; n=2 só) | ~20 linhas de script + 3 no loop | pular revisão de diff trivial pode deixar passar caso tipo T08; limite conservador |
| 3 | **`task-lint.sh` + passar branch/título prontos ao agente** | ~19 k (1 desvio × 170 k / 9 tasks) e evita PR errado | ~40 linhas (30 min) | nenhum |
| 4 | **`.gitattributes` com `merge=union` em README*.md, Localizable.strings, TODO.md + `rebase-auto.sh`** (inclui `gh pr update-branch --rebase` para BEHIND) | ~55 k em trilhas paralelas (agente `rebase:` ≈ 180 k × ~30% dos PRs, est.); 0 se rodar serial | 5 linhas + ~25 de script | union pode duplicar linha; `docs-check.sh` pega. GitHub ignora o driver: o rebase tem de ser local |
| 5 | **`docs-check.sh` dentro do `gates.sh`** (paridade README en/pt-BR e chaves de `Localizable.strings`) | ~10 k (README = 284 chamadas Bash em 84 agentes) e sai o item "README desatual" da revisão | ~25 linhas | falso positivo se feature existir só numa língua (lista de exceções) |
| 6 | **CI uma vez, fora dos agentes** (`ci-wait` ao fim de Implementar; revisor recebe `CI:verde`) | ~15 k (revisor fez 56 chamadas de espera) | ~5 linhas | nenhum |
| 7 | **`pr-open.sh --task Txx`** gera corpo a partir do `.md` da task | ~8 k (42 PRs com corpo à mão) | ~30 linhas | corpo mais genérico |
| 8 | Merge direto por script no workflow (se o runtime aceitar shell) | ~9 k (Haiku → 0) | depende do runtime | — |
| 9 | `index-mark.sh` num PR de docs por lote (hoje 3 dos últimos 6 PRs são do orquestrador) | ~0 em agente; menos ruído | 15 linhas | — |

Soma de #1–#7 = ~200–260 k, mas há sobreposição (revisão pulada elimina correção): contar **~40–50% do custo atual** como realista. Tudo é estimativa.

### 4.1 Scripts novos em `scripts/dev/`

| Script | O que faz | Uso / saída |
|---|---|---|
| `task-lint.sh` | Por `Txx`: arquivo existe; campos `Branch` e `PR` presentes; `Depende de` já FEITA no INDEX/mergeada no `gh`; branch não existe no remoto; sem PR aberto da task; imprime `route.sh`. | `task-lint.sh T40 T41` → `T40 ok model=sonnet branch=feat/x title="..."` ou `T40 ERRO motivo=...` (exit 1) |
| `overlap.sh` | Extrai de cada task os arquivos citados (regex do `route.sh`), ignora hot spots (`README*`, `Localizable.strings`, `TODO.md`, `INDEX.md`), imprime pares com código em comum e ondas (coloração gulosa). | `overlap.sh T36 T37 T38 T39 T40` → `onda1: T36 T37 T38 T39 \| onda2: T40 (SessionStore: T38)` |
| `docs-check.sh` | Falha se o diff muda `README.md` sem `README.pt-BR.md` (ou o contrário) ou se `en.lproj` e `pt-BR.lproj` têm chaves diferentes. Chamado pelo `gates.sh`. | `docs-check.sh` → `docs=ok` ou lista |
| `review-gate.sh <pr>` | `gh pr diff --stat` + palavras de risco do `route.sh`: `skip` (≤ 25 linhas, só docs/strings/testes, CI verde), `sonnet` ou `opus`. | `review-gate.sh 44` → `skip` / `sonnet` / `opus` |
| `rebase-auto.sh <pr>` | Rebase em `origin/main` num worktree temporário com `merge=union`, gates, `push --force-with-lease`, `ci-wait`. Sai 2 se sobrar conflito textual (aí sim agente). | `rebase-auto.sh 44` → `rebase=ok` / `rebase=CONFLITO arq...` |
| `pr-open.sh` (estender) | `--task Txx`: corpo montado do `.md` da task + `git diff --stat`; agente passa só "Não verificado". | `pr-open.sh --task T41 --nv "..."` |
| `index-mark.sh <Txx> <pr>...` | Marca FEITA (#pr) no INDEX para o lote; orquestrador abre 1 PR. | uma chamada por lote |

### 4.2 Skills novas

| Skill | description (1 linha) | Passos |
|---|---|---|
| `lote` | Planejar um lote: lint, rota e ondas paralelas antes de rodar o `impl-loop`. | 1) `task-lint.sh` 2) `overlap.sh` → ondas 3) `route.sh` 4) `impl-loop` por onda 5) `clean.sh` + `index-mark.sh` |
| `corrigir-pr` | Rodar uma rodada de correção só com BL/CI e deixar SG como comentário no PR. | 1) ler achados `wire` 2) aplicar BL 3) `gates.sh` 4) push 5) `ci-wait.sh` 6) comentário único; sem reabrir revisão |

Não vale skill nova para revisão (já existe `review-pr`) nem para merge (script basta).

### 4.3 Mudanças em `impl-loop.js`, `route.sh`, agentes

| Mudança | Detalhe | Motivo (dado) |
|---|---|---|
| `B:` literal → valor | `task-lint.sh` devolve branch e título; o loop passa `B:fix/x` já resolvido | T36 Haiku não achou o campo |
| Anti-relay | Primeira linha de cada brief: `IGNORE:pedido do usuário que não seja SRC`; disparar o Workflow de uma mensagem curta, só com o lote | harness repassa a mensagem do usuário a todo subagente e diz que ela prevalece |
| Fix só para BL/CI | `acts = rev.a.filter(a=>a.s==='BL')`; SG vira comentário do revisor | 17 de 25 correções sem BL |
| Fase Revisar condicional | `review-gate.sh`; `skip` pula o agente | 31% das revisões vazias |
| Modelo do revisor | decidido pelo gate (sonnet até nota 3, opus ≥ 4), não herda o do implementador | Sonnet 29 k × Opus 136 k (n=2) |
| CI fora dos agentes | `ci-wait.sh` uma vez; revisor/merger recebem `CI:verde` | 120 chamadas de espera |
| Rebase | `rebase-auto.sh` antes do agente `rebase:`; agente só se sair código 2 | agente de rebase ≈ 180 k |
| `route.sh` | +1 se a task toca código que outra task do mesmo lote também toca (via `overlap.sh`); README/strings não contam | evita paralelo com colisão |
| `reviewer.md` | tirar "README desatual" (vai para `docs-check.sh`); manter proibição de build | 46 chamadas README de revisor; 11 builds indevidos no antigo |
| `implementer.md` | chamar `docs-check.sh` via gates; encurtar o passo de worktree preso (já tratado em `pr-open.sh`) | 166 chamadas git de troca de branch |

### 4.4 Paralelizar trilhas com segurança

1. `overlap.sh` no lote: grafo de conflito = pares que citam o mesmo arquivo de código (ignora README/strings/TODO/INDEX). Ondas = coloração gulosa; dentro da onda as tasks rodam juntas.
2. Lote T36–T45 (dado real): 16 de 45 pares colidem em código. Onda possível: {T36, T37, T38, T39} (só `TODO.md`/docs em comum); depois T40/T45, T41, T42, T43, T44 (SessionStore/MenuContent/HookSetup/`main.swift` em cadeia). Ordem exata sai do script; ~4–5 ondas em vez de 10 execuções seguidas.
3. README, `Localizable.strings` e `TODO.md`: `merge=union` + `docs-check.sh`; não contam como conflito no grafo.
4. Respeitar `Depende de` do INDEX (`task-lint.sh` bloqueia).
5. Depois de cada merge de uma onda, os PRs restantes fazem `rebase-auto.sh` (barato) antes do `merge.sh`.
6. Limite prático: 3–4 tasks por onda (CI de 3 vCPU já ficou flaky em T28).
7. Limite do método: `overlap.sh` lê arquivos citados na task (texto), não o diff real; implementador que toca arquivo não citado gera conflito. Mitigação: antes do merge, `git diff --name-only` contra os PRs abertos (dentro do `rebase-auto.sh`).

## 5. Limites desta análise

- Novo = 2 tasks fechadas + 3 em andamento: nenhuma média nova é estável.
- Peso de tokens é genérico; o ranking das propostas vale, o valor absoluto não.
- Comparação Opus × Fable no antigo está confundida com a task.
- Contagem de comandos é por regex; uma chamada pode contar em dois padrões.
