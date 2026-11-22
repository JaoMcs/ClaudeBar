# T47 — Fechamento dos documentos das rodadas T36–T46

- **Funcionalidade:** processo (item 11 do plano mestre: relatório final)
- **Esforço:** 1 h
- **Depende de:** — · **Bloqueia:** —
- **Branch:** `docs/fechamento-t36-t46`
- **PR:** `docs: fechamento das rodadas T36–T46`

## Objetivo

Deixar os documentos permanentes iguais ao estado da `main`: as tasks T38–T46 marcadas como feitas, o relatório final cobrindo T36–T46 e as pendências sem item já resolvido. Só documentação: nada em `Sources/`, `scripts/` ou `.claude/`.

## Subtasks

- [ ] `scripts/dev/index-mark.sh T38=43 T39=44 T40=49 T41=45 T42=47 T43=48 T44=52 T45=50 T46=53` (confira cada número com `gh pr list --state merged --limit 30` antes; corrija se algum não bater).
- [ ] `planning/RELATORIO-FINAL.md`: nova seção "Rodadas T36–T46 (22 nov 2026)" com a tabela task → PR → modelo → o que ficou "não verificado" (copie o "Não verificado" do corpo de cada PR com `gh pr view <n> --json body`). Some os números de custo de `planning/11-analise-rodadas.md` (não recalcule).
- [ ] `PENDENCIAS.md`: confira cada linha contra a `main`; o que já foi feito sai da lista e vai para "Já resolvido". Não invente item novo. Itens que esperam o dono (teste de tela, certificado Apple) **continuam pendentes**.
- [ ] `ROADMAP.md`: tire das listas o que entrou nas T38–T46 (atalho global, aviso perto do limite, copiar diagnóstico, rótulo desktop × terminal, `elicitation_url_dialog`, Gemini).
- [ ] `TODO.md`: confira que "Deprecated APIs" e "Gemini CLI" estão marcados `[x]`.
- [ ] `scripts/dev/docs-check.sh` e `scripts/dev/pii-check.sh` → `ok`.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `planning/06-tasks/INDEX.md` | status T38–T46 |
| `planning/RELATORIO-FINAL.md` | seção nova |
| `PENDENCIAS.md`, `ROADMAP.md`, `TODO.md` | conferência |

## Critérios de aceite

- `grep -c "FEITA (#" planning/06-tasks/INDEX.md` aumenta em 9.
- Nenhum item que depende do dono foi removido das pendências.
- `scripts/dev/pii-check.sh` → `pii=ok`.

## Fora do escopo

Código, scripts, agentes. O painel (artifact) é atualizado pelo Claude.
