# T36 — Popup de espera continua visível ao trocar de Space

- **Funcionalidade:** F12 (ajuste da T17) — decisão do dono no painel: o popup some ao trocar de Space
- **Esforço:** 0,5 h
- **Depende de:** T17 · **Bloqueia:** —
- **Branch:** `fix/popup-entre-spaces`
- **PR:** `fix: popup de espera não some ao trocar de Space`

## Objetivo

O popup de espera (permissão, pergunta, aguardando) precisa continuar visível quando o usuário troca de Space, até o clique ou a transição de estado. Hoje `makePanel()` em `Sources/ClaudeBar/StatusHUD.swift` usa `collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]`; o `.transient` deixa o sistema esconder o painel na troca de Space.

## Subtasks

- [ ] Tirar `.transient` do `collectionBehavior` (manter `.canJoinAllSpaces` e `.ignoresCycle`). Avaliar `.stationary` só se for necessário para não animar junto com o Space.
- [ ] Conferir que o estado interno do HUD (`shownAlert` ou equivalente) não fica marcado como "na tela" quando o painel foi escondido por fora.
- [ ] READMEs: uma linha onde o popup persistente é descrito.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBar/StatusHUD.swift` | `collectionBehavior` |
| `README.md`, `README.pt-BR.md` | uma linha |

## Critérios de aceite

- `.transient` não está mais no painel do HUD.
- `swift build` e `swift test` verdes.
- No PR, "Não verificado: trocar de Space com o popup aberto (depende de tela)".

## Fora do escopo

O caso de 1 ou 2 cliques (`FirstClickHostingView`): continua pendente de teste do dono.
