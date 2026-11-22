# T37 — Nome do app: Awaitbar

- **Funcionalidade:** F47 (nome sem "Claude") — decisão do dono no painel: **Awaitbar**
- **Esforço:** 2 h
- **Depende de:** — · **Bloqueia:** release, Homebrew
- **Branch:** `chore/nome-awaitbar`
- **PR:** `chore: o app passa a se chamar Awaitbar`

## Objetivo

O nome que o usuário vê passa a ser **Awaitbar**: nome do `.app`, nome no menu, nos alertas, nos Ajustes, nos READMEs, no DMG e o bundle id. "Claude" só aparece para descrever com o que o app funciona ("for Claude Code"). Motivo: a marca "Claude" não pode estar no nome do produto e `ClaudeBar` já é outro app (inclusive cask no Homebrew).

## Subtasks

- [ ] `scripts/build-app.sh`: `build/Awaitbar.app`, `CFBundleName` e `CFBundleDisplayName` = `Awaitbar`, executável dentro do bundle = `Awaitbar` (copiar o produto SwiftPM `ClaudeBar` com esse nome), `BUNDLE_ID` = `io.github.jaomcs.awaitbar`.
- [ ] `scripts/make-dmg.sh`: `dist/Awaitbar-<versão>.dmg`, `Awaitbar.app` dentro; o laço de binários usa o nome novo do executável.
- [ ] `scripts/install.sh`: instala `~/Applications/Awaitbar.app`; se existir `~/Applications/ClaudeBar.app`, roda o `install` novo primeiro (migra os hooks antigos que apontam para dentro do app velho) e só depois remove o app velho, com `pkill -x ClaudeBar` antes.
- [ ] `scripts/uninstall.sh`: remove `Awaitbar.app` e também `ClaudeBar.app` se sobrar; `pkill` dos dois nomes.
- [ ] Textos que o usuário vê: trocar "ClaudeBar" por "Awaitbar" nos `String(localized:)`/`Text` do app e nas duas tabelas `Localizable.strings` (chave inglesa e valor), mantendo os testes de localização verdes.
- [ ] READMEs: título "Awaitbar", subtítulo "menu bar status for Claude Code sessions", seção curta "Formerly ClaudeBar / Antes ClaudeBar" explicando: bundle id novo, os Ajustes começam do padrão, "Abrir no login" precisa ser ligado de novo.
- [ ] `docs/TESTE-MANUAL.md` e `PENDENCIAS.md`: trocar o nome onde for o app (não onde for histórico de PR).
- [ ] Gates com `./scripts/build-app.sh`: conferir `build/Awaitbar.app/Contents/Info.plist` com `plutil -p`.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `scripts/build-app.sh`, `scripts/make-dmg.sh`, `scripts/install.sh`, `scripts/uninstall.sh` | nome, bundle id, migração |
| `Sources/ClaudeBar/*.swift` | só textos visíveis |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | textos |
| `.github/workflows/ci.yml` | caminho do `.app` no passo de conferência do bundle |
| `README.md`, `README.pt-BR.md`, `docs/TESTE-MANUAL.md`, `PENDENCIAS.md` | nome |

## Critérios de aceite

- `build/Awaitbar.app` com `CFBundleIdentifier` `io.github.jaomcs.awaitbar` e executável `Awaitbar`; assinatura ad-hoc verifica.
- Nenhum texto visível ao usuário diz "ClaudeBar" (grep em `Resources/` e nos `String(localized:)`), exceto a seção "Formerly ClaudeBar".
- `swift test` verde; CI verde (o passo do bundle usa o caminho novo).

## Fora do escopo (não mudar)

- Nomes de target/módulo SwiftPM (`ClaudeBar`, `ClaudeBarCore`, `ClaudeBarTests`), nome do repositório.
- `claudebar-hook` e o diretório `~/.claude/claudebar`: os hooks instalados apontam para lá; mudam junto com o multiagente (ver `TODO.md`).
- Migrar UserDefaults do bundle id antigo.
