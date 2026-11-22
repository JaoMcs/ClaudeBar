# G13 — Ícone do app (F18)

Pesquisa de "como fazer". Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial ou testado nesta máquina; **[SUPOSIÇÃO]** = fonte não oficial, relato de terceiros ou inferência minha.

## Ponto de partida (código atual)

- `scripts/build-app.sh` já cria `Contents/Resources` (vazio), escreve o `Info.plist` via heredoc (com `LSUIElement` = true) e assina ad-hoc no fim (`codesign --force --sign - --timestamp=none`). Não há `CFBundleIconFile`. Resultado: Finder, notificações e o painel "Sobre" mostram o ícone genérico.
- `scripts/install.sh` faz `rm -rf` + `cp -R` do bundle para `~/Applications/ClaudeBar.app`.
- Barra: `ClaudeBarApp.swift` usa `Image(systemName: store.barState.symbolName)` + `Text(contagem)`. `BarState.symbolName` fica em `SessionStore.swift`. **Decisão do F18: não mexer.**
- `Package.swift` não declara recursos, e o F18 continua sem declarar.
- Assets prontos em `planning/07-design/final/` (conceito "Prompt Pulse": chevron `›` + ponto verde, sem marca da Anthropic, ou seja, dentro do guard rail). `AppIcon.icns` tem cerca de 1 MB e 10 tamanhos (16 a 512, em @1x e @2x). **[CONFIRMADO]** com `iconutil -c iconset` local.
- `planning/` está em `.git/info/exclude`, então nada dali é versionado. Por isso o `.icns` precisa sair de lá.

## Escopo (o que muda e o que não muda)

| Muda | Não muda |
|---|---|
| Novo `Resources/AppIcon.icns` na raiz (versionado) | Swift (nenhum arquivo `.swift`) |
| `build-app.sh`: 1 `cp` + 2 linhas no plist | `Package.swift` |
| | Ícone da barra, menu e HUD (SF Symbols) |

Sem código Swift não há impacto de Swift 6 strict concurrency nem de MainActor. O que este item não toca não tem como quebrar.

## Regras oficiais (Apple)

- `CFBundleIconFile`: **[CONFIRMADO]** "The filename you specify does not need to include the extension, although it may. The system looks for the icon file in the main resources directory of the bundle." E também: "If your Mac app uses a custom icon and the asset name for the icon isn't set in `CFBundleIconName`, you must specify the `CFBundleIconFile` property." Fonte: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html (página atual, com resumo curto: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleiconfile).
- `CFBundleIconName`: **[CONFIRMADO]** é o nome do asset num **Asset Catalog** (`Assets.car`). Sem `actool`/Xcode não temos catálogo, então essa chave **não se aplica**. Fonte: a mesma página arquivada e https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleiconname.
- `.icns` como formato do ícone de app no macOS e `iconutil` para gerá-lo: padrão de fato, usado também pelo CodexBar (abaixo). O README do design já documenta como regerar.

## Teste local (feito nesta máquina, macOS 26, sem tocar no repo)

Copiei `~/Applications/ClaudeBar.app` para o scratchpad, coloquei `AppIcon.icns` em `Contents/Resources`, adicionei `CFBundleIconFile=AppIcon` com `PlistBuddy`, reassinei ad-hoc e verifiquei:

```
codesign --verify --deep --strict --verbose=2 T.app
→ valid on disk / satisfies its Designated Requirement
```

- **[CONFIRMADO]** Recurso em `Contents/Resources` + assinatura ad-hoc **depois** da cópia = assinatura válida. A ordem importa: o `.icns` entra em `_CodeSignature/CodeResources`. Se ele for copiado depois do `codesign`, `--verify` falha. O `build-app.sh` já assina por último, então basta pôr o `cp` antes.
- **[CONFIRMADO]** `NSWorkspace.shared.icon(forFile:)` devolveu representações de até 1024 px para o bundle de teste.
- **[SUPOSIÇÃO]** Não abri o Finder para conferir o ícone na tela. Falta conferir visualmente após o `install.sh`.

## Recomendação (diff mínimo)

1. Mover só o necessário: `git mv` não serve (a origem não é versionada), então `mkdir Resources && cp planning/07-design/final/AppIcon.icns Resources/AppIcon.icns` e `git add`. Os PNGs da barra, o iconset e o master 1024 **ficam fora** (YAGNI, porque a barra continua com SF Symbol). Vale trazê-los quando o glifo próprio for adotado ou quando o README/F49 precisar do PNG.
2. `scripts/build-app.sh`, logo depois do `cp` do `claudebar-hook`:
   ```bash
   cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
   ```
   E no heredoc do `Info.plist`, perto de `CFBundleIdentifier`:
   ```xml
       <key>CFBundleIconFile</key>
       <string>AppIcon</string>
   ```
   Com `set -euo pipefail` já ativo, um `.icns` ausente derruba o build. É o comportamento que queremos, sem precisar de `if`.
3. Nada no `install.sh`: ele já copia o bundle inteiro.

**Pasta `Resources/` na raiz e SwiftPM**: o SwiftPM só procura fontes em `Sources/<target>` e `Tests/<target>` (layout padrão, sem `path:` customizado no `Package.swift`), então uma pasta `Resources/` na raiz é ignorada pelo build. **[SUPOSIÇÃO forte]**, baseada na convenção documentada do SwiftPM. Falta rodar `swift build` depois de criar a pasta. Se der conflito, o nome alternativo é `assets/`.

### Verificação pós-merge (checklist do PR)
```bash
./scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" build/ClaudeBar.app/Contents/Info.plist   # AppIcon
test -f build/ClaudeBar.app/Contents/Resources/AppIcon.icns
codesign --verify --deep --strict --verbose=2 build/ClaudeBar.app
```
Depois, `install.sh` e conferência visual no Finder (`~/Applications`), numa notificação e em Ajustes > Notificações.

## Onde o ícone aparece num app LSUIElement

- Sem Dock e sem App Switcher, por design (`LSUIElement` e `.accessory`). **[CONFIRMADO]** Doc da chave: "agent app that runs in the background and doesn't appear in the Dock" (https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement).
- Aparece no Finder, no Launchpad/Spotlight, no Monitor de Atividade, nos banners de notificação e na lista de Ajustes > Notificações. **[SUPOSIÇÃO]** Comportamento conhecido, mas não achei página oficial que liste esses lugares. É justamente onde o "sem ícone = abandonado" do backlog aparece.

## Armadilhas

1. **Cache de ícone (Finder/Launch Services/notificações).** Depois de reinstalar, o ícone antigo (genérico) pode continuar aparecendo. Remédios relatados: `touch ~/Applications/ClaudeBar.app`, remover cópias antigas do bundle (Launch Services pode escolher a cópia velha) e, em último caso, `lsregister -f <app>`. **[SUPOSIÇÃO]**, porque são relatos de comunidade: https://developer.apple.com/forums/thread/676723, https://lists.apple.com/archives/cocoa-dev/2013/Jul/msg00267.html. Recomendo **não** pôr isso no script. Se acontecer, um `touch` manual resolve. O `install.sh` já faz `rm -rf` + `cp -R`, o que cria um bundle com mtime novo.
2. **`Assets.car` sobrescrevendo o `.icns`.** Relato de macOS 26: se existir `Assets.car` com ícone, ele vence o `CFBundleIconFile`. **[SUPOSIÇÃO]**, e não se aplica: não geramos `Assets.car`.
3. **Liquid Glass (macOS 26).** O `.icns` é plano e não tem as variantes Dark/Clear/Tinted (README do design). No Tahoe ele aparece como squircle normal, porque já foi desenhado assim. Ficar no Icon Composer + `actool` exigiria Xcode e asset catalog, o que contraria "SwiftPM sem projeto Xcode". **Fora do escopo.**
4. **Assinatura.** Qualquer arquivo adicionado depois do `codesign` invalida o selo. Testado acima. Hoje o fluxo é seguro.
5. **`Bundle.module` / `resources:` no `Package.swift`.** Não usar para isso. Geraria `ClaudeBar_ClaudeBar.bundle`, que precisa ser copiado e assinado à parte. O ícone do app é lido pelo sistema a partir de `Contents/Resources`, não pelo código. O README do design já registra isso.
6. **Marca/guard rail.** O ícone não usa logo nem cor da Anthropic (conceito "Prompt Pulse"). **[CONFIRMADO]** pelo README do design. Nada a fazer.

## Repositório open source de referência

- **steipete/CodexBar** (app SwiftPM de barra de menu), `Scripts/package_app.sh`: https://github.com/steipete/CodexBar/blob/main/Scripts/package_app.sh. Trechos relevantes (lidos via `gh api`):
  ```bash
  # Convert new .icon bundle to .icns if present (macOS 14+/IconStudio export)
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_SOURCE"
  ...
      <key>LSUIElement</key><true/>
      <key>CFBundleIconFile</key><string>Icon</string>
  ...
  cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"
  ```
  Mesmo padrão recomendado aqui: `.icns` na raiz do repo, `cp` para `Contents/Resources`, `CFBundleIconFile` sem extensão, assinatura no fim. Ele **converte no build**. Para nós, versionar o `.icns` pronto é mais simples: 1 MB, raramente muda e dispensa `iconutil` no build.
- Guia comunitário com o mesmo fluxo (SwiftPM + `.app` montado à mão + `CFBundleIconFile`): https://samasaur1.github.io/blog/graphical-macos-apps-with-spm **[SUPOSIÇÃO]**, porque não é fonte oficial.

## Alternativas consideradas

| Opção | Prós | Contras | Veredito |
|---|---|---|---|
| **A. `.icns` versionado + `CFBundleIconFile`** | 3 linhas, sem Xcode, funciona do macOS 14 ao 26 | Sem variantes Liquid Glass | **Recomendado** |
| B. Versionar o iconset/PNG master e gerar o `.icns` no build (`iconutil`) | Fonte editável no repo | Mais passos no build e mais arquivos, sem ganho hoje | Só se o ícone começar a mudar com frequência |
| C. Asset catalog + `actool` + `CFBundleIconName` | Variantes Tahoe | `actool` vem com o Xcode, o que quebra a premissa "SwiftPM sem Xcode" | Não |
| D. Glifo próprio na barra (`Bundle.main.image(forResource:)` + `isTemplate`) | Identidade na barra | Muda comportamento e Swift (fica no `MainActor` da view); "esperando" fica menos explícito | **Opção futura**. O código está pronto no README do design |

## Claude Code (hooks/statusline/settings)

O F18 não toca hooks, statusline nem `settings.json`. Nenhuma doc do Claude Code se aplica.
