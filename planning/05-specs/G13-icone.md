# G13 — Spec técnica: ícone do app (F18)

Insumos: `04-como-fazer/G13-icone.md`, `03-validacao/BACKLOG.md` (F18: P1, P, depende da entrega do design, já feita), `00-PLANO.md` (guard rails: ícone original sem marca da Anthropic, sem rede, menor diff).
Código lido em 2026-11-15 (branch `chore/ci-github-actions` @ 3561ab8, que inclui `.github/workflows/ci.yml`).

**Verificado nesta spec**: apliquei o diff abaixo numa cópia dos arquivos versionados (scratchpad), com Swift 6.3.3 e tools 6.0, no macOS 26:
- `swift build`: compila. A pasta `Resources/` na raiz é ignorada pelo SwiftPM. Isso fecha o item "não confirmado" da pesquisa.
- `swift test`: os 34 testes passam.
- `./scripts/build-app.sh`: `PlistBuddy` lê `CFBundleIconFile = AppIcon`, `plutil -lint` dá OK e `codesign --verify --deep --strict` diz "valid on disk / satisfies its Designated Requirement".
- Sem `Resources/AppIcon.icns`, o `build-app.sh` sai com código 1 por causa do `set -euo pipefail`. O build falha alto, que é o que queremos.
- `git check-ignore Resources/AppIcon.icns` não devolve nada: o arquivo é versionável (`.gitignore` só tem `.DS_Store`, `.build/` e `build/`).

Continua **não verificado**, porque é visual e não dá para um agente conferir: o ícone na tela do Finder, num banner de notificação e em Ajustes > Notificações.

## Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `Resources/AppIcon.icns` | **novo**, binário de 1,0 MB copiado de `planning/07-design/final/AppIcon.icns` |
| `scripts/build-app.sh` | 1 `cp` e 2 linhas no heredoc do `Info.plist` |
| `.github/workflows/ci.yml` | 1 step que confere o plist, o `.icns` e a assinatura do bundle |
| `README.md` e `README.pt-BR.md` | 1 linha em "Project structure" |

**Não toca**: nenhum `.swift`, `Package.swift`, `scripts/install.sh`, `Tests/`.
**Conflito provável**: F21 (também copia recursos no `build-app.sh`, para `Contents/Resources`) e F23 (o `make-dmg.sh` depende do `.app` com ícone). Os dois mexem em trechos vizinhos do mesmo script. Ordem natural: F18 → F21/F23. Ambos só acrescentam linhas, então o rebase é trivial. O F04 (versão) mexe no mesmo heredoc do plist, a uma linha de distância: conflito textual pequeno.

---

## F18 — Ícone do app

### Objetivo

O `ClaudeBar.app` passa a ter o ícone "Prompt Pulse" no Finder, no Spotlight/Launchpad, no Monitor de Atividade, nos banners de notificação e em Ajustes > Notificações. Hoje aparece o ícone genérico, o que passa a impressão de "app abandonado" (personas b e c). O ícone da barra de menu, o menu e o HUD **não mudam**: continuam com SF Symbols.

### Decisão técnica

Versionar o `.icns` pronto em `Resources/AppIcon.icns`. O `build-app.sh` copia para `Contents/Resources/` **antes** do `codesign` e declara `CFBundleIconFile = AppIcon` (sem extensão, que é opcional segundo a Apple). O sistema lê o ícone do bundle sozinho, então nenhuma linha de Swift muda e Swift 6 e `MainActor` ficam fora do caso.

Alternativas descartadas:
- Gerar o `.icns` no build com `iconutil` a partir do iconset: mais arquivos e passos sem ganho, porque o ícone quase não muda.
- Asset Catalog + `actool` + `CFBundleIconName`: exige Xcode e quebra a premissa "SwiftPM sem projeto Xcode".
- `resources:` no `Package.swift` + `Bundle.module`: gera `ClaudeBar_ClaudeBar.bundle`, que precisa ser copiado e assinado à parte. O ícone do app não é lido pelo código.
- Copiar direto de `planning/07-design/final/`: `planning/` está em `.git/info/exclude`, então build limpo e CI quebrariam.
- Glifo próprio na barra (`MenuBarIcon-*.png` + `isTemplate`): muda Swift e comportamento. Fica como opção futura (código no README do design) e fora do F18.
- Pasta `assets/` em vez de `Resources/`: só valeria se `Resources/` atrapalhasse o SwiftPM, e foi verificado que não atrapalha.

### Código

Não há Swift neste item. O enunciado pede exemplo Swift "no estilo do projeto", mas inventar código para um item que não precisa dele iria contra o guard rail "menor código que resolve".

#### `Resources/AppIcon.icns` (novo)

```bash
mkdir -p Resources
cp planning/07-design/final/AppIcon.icns Resources/AppIcon.icns
git add Resources/AppIcon.icns
```

Fica de fora: `AppIcon.iconset/`, `AppIcon-1024.png` e `MenuBarIcon*.png` (YAGNI). Entram quando o glifo da barra for adotado ou quando o F49 (README com GIF) precisar do PNG.

#### `scripts/build-app.sh`

Logo depois da cópia do `claudebar-hook`, e portanto antes do `codesign`:

```bash
cp "$BIN_DIR/ClaudeBar" "$BUNDLE/Contents/MacOS/ClaudeBar"
cp "$BIN_DIR/claudebar-hook" "$BUNDLE/Contents/MacOS/claudebar-hook"
# O sistema lê o ícone daqui (CFBundleIconFile). Copiar antes de assinar:
# arquivo que entra depois do codesign invalida o selo.
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
```

No heredoc do `Info.plist`, antes de `CFBundleIdentifier` (as chaves continuam em ordem alfabética, como hoje):

```xml
    <key>CFBundleExecutable</key>
    <string>ClaudeBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
```

Não precisa de `if [ -f ... ]`: com `set -euo pipefail`, um `.icns` ausente derruba o build com erro claro do `cp`. O que não queremos é um app sem ícone saindo em silêncio.

### Testes

**Nenhum teste Swift.** Swift Testing testaria um arquivo binário e um script de shell, não código Swift. Um `#expect(FileManager.default.fileExists(...))` via `#filePath` só repetiria o que o `cp` com `set -e` já garante.

A verificação automática vai para a CI, que já roda `./scripts/build-app.sh`. Acrescente um step em `.github/workflows/ci.yml` logo depois de "Empacotar o .app":

```yaml
      - name: Conferir o bundle (ícone e assinatura)
        run: |
          test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' build/ClaudeBar.app/Contents/Info.plist)" = AppIcon
          test -s build/ClaudeBar.app/Contents/Resources/AppIcon.icns
          codesign --verify --deep --strict build/ClaudeBar.app
```

Esse step falha nos três casos: chave removida do plist, `cp` removido e recurso adicionado depois do `codesign`. A assinatura também protege F21 e F23, que vão acrescentar arquivos ao bundle.

### Scripts e README

- `scripts/install.sh`: **nada**. Ele já faz `rm -rf` + `cp -R` do bundle inteiro.
- `README.md`, seção "Project structure", nova linha perto de `scripts/`:
  ```
  Resources/AppIcon.icns        app icon, copied into the bundle by build-app.sh
  ```
- `README.pt-BR.md`: a mesma linha, traduzida ("ícone do app, copiado para o bundle pelo build-app.sh").
- Não documentar no README o remédio de cache de ícone (ver Riscos), porque é relato de fórum. Fica só nesta spec e no PR.

### Verificação manual

```bash
./scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" build/ClaudeBar.app/Contents/Info.plist   # AppIcon
test -s build/ClaudeBar.app/Contents/Resources/AppIcon.icns && echo ok
codesign --verify --deep --strict --verbose=2 build/ClaudeBar.app                             # valid on disk
./scripts/install.sh
```

Depois, na tela (o agente não consegue verificar, então deve ir para o relatório como "não verificado"):
1. Finder em `~/Applications`: `ClaudeBar.app` mostra o chevron com o ponto verde, não o ícone genérico. Conferir no modo ícone e no modo lista (16 px).
2. Menu > "testar alerta" (exemplo de popup) com notificações nativas ligadas: o banner mostra o ícone novo.
3. Ajustes do Sistema > Notificações > ClaudeBar: ícone novo na lista.
4. Spotlight (`⌘Espaço` "ClaudeBar"): ícone novo.
5. Barra de menu, menu e HUD: **iguais** a antes (SF Symbols).

### Riscos e mitigação

| Risco | Status | Mitigação |
|---|---|---|
| Cache de ícone: depois de reinstalar, Finder ou notificações continuam com o genérico | **não confirmado**, só relatos de fórum | Não pôr no script. O `install.sh` já recria o bundle (mtime novo). Se acontecer na verificação manual: `touch ~/Applications/ClaudeBar.app`, apagar cópias antigas do `.app` (por exemplo `build/` antigo indexado) e, em último caso, `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/ClaudeBar.app`. Registrar no PR se foi preciso. |
| Lista exata de onde aparece o ícone de app `LSUIElement` | **não confirmado** (sem lista oficial) | Os critérios de aceite exigem só Finder e plist/bundle, que são verificáveis. Notificações e Ajustes ficam na verificação manual como "esperado". |
| `Assets.car` passando por cima do `CFBundleIconFile` no macOS 26 | **não confirmado** e não se aplica | Não gerar `Assets.car`. Se um dia houver catálogo, rever. |
| Sem variantes Liquid Glass (Dark/Clear/Tinted) no Tahoe | conhecido | Aceito. O `.icns` já é squircle e aparece normal. Variantes exigem Icon Composer + `actool` (Xcode), fora do escopo. |
| Assinatura inválida se um recurso entrar depois do `codesign` | **confirmado** na pesquisa | `cp` antes do `codesign` e step de `codesign --verify --strict` na CI. |
| Repo cresce 1 MB com um binário | aceito | O arquivo é único e raramente muda. Não usar Git LFS (YAGNI). |
| Marca | **confirmado** OK | O conceito "Prompt Pulse" não usa logo nem cor da Anthropic (README do design). |

Guard rails: nenhum é afetado. Não há rede, não há leitura de conversa, não há permissão de arquivo nova, não há shell com interpolação de dado externo (o `cp` usa caminhos fixos e `$BUNDLE`, que é constante do script) e o hook não muda.

### Critérios de aceite

1. `git ls-files Resources/AppIcon.icns` lista o arquivo, e `cmp Resources/AppIcon.icns planning/07-design/final/AppIcon.icns` não acusa diferença.
2. `./scripts/build-app.sh` termina com código 0, e `build/ClaudeBar.app/Contents/Resources/AppIcon.icns` existe e não está vazio.
3. `PlistBuddy -c "Print :CFBundleIconFile"` no `Info.plist` gerado devolve exatamente `AppIcon`, e `plutil -lint` dá OK.
4. `codesign --verify --deep --strict build/ClaudeBar.app` sai com código 0.
5. Sem `Resources/AppIcon.icns`, `./scripts/build-app.sh` sai com código diferente de 0.
6. `swift build` e `swift test` passam como antes (34 testes), e o diff não tem nenhum arquivo `.swift` nem o `Package.swift`.
7. A CI tem o step "Conferir o bundle" e ele passa no PR.
8. Verificação manual 1 (Finder) feita, ou registrada no relatório como "não verificado" se for o agente.

### O que NÃO fazer

- Não mexer no ícone da barra, no menu nem no HUD (`ClaudeBarApp.swift`, `SessionStore.swift`/`BarState.symbolName`, `StatusHUD.swift`, `MenuContent.swift`).
- Não declarar `resources:` no `Package.swift` e não usar `Bundle.module`.
- Não usar `CFBundleIconName` nem gerar `Assets.car`/`actool`.
- Não copiar de `planning/` no script (não é versionado).
- Não trazer iconset, master 1024 nem `MenuBarIcon*.png` agora.
- Não pôr `touch`, `lsregister` nem `killall Finder`/`Dock` no `install.sh`.
- Não adicionar `iconutil` ao build.
- Não colocar o `cp` depois do `codesign`.

### Esforço

~0,5 h: 15 min de diff (cp, plist, CI e README) e 15 min de verificação manual na tela.
