# G02 — Versão de fonte única (F04) + DMG universal com SHA-256 (F23)

Pesquisa de "como fazer". Não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial ou testado nesta máquina (Swift 6.3.3, macOS 26, arm64); **[SUPOSIÇÃO]** = fonte não oficial, relato de terceiros ou inferência minha.

## Ponto de partida (código atual)

- `scripts/build-app.sh`: `VERSION="1.0"` fixo e usado para **as duas** chaves (`CFBundleShortVersionString` e `CFBundleVersion`). `swift build -c release` só da arquitetura do host. Copia `ClaudeBar` e `claudebar-hook` para `Contents/MacOS`, escreve o `Info.plist` via heredoc, assina ad-hoc (`codesign --force --sign - --timestamp=none`).
- `scripts/install.sh` chama `build-app.sh` e registra o hook com o caminho absoluto `~/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook`.
- Não existe arquivo `VERSION`, nem tag git (`git describe` falha: "No names found"). `git rev-list --count HEAD` = 2.
- Nenhum código Swift lê a versão hoje (só `Bundle.main.bundleIdentifier` em `Notifier.swift`). F04 não mexe em Swift → **sem impacto de Swift 6 strict concurrency / MainActor**. Quem for ler a versão depois (Sobre, F15/A13) usa `Bundle.main.infoDictionary` ou o painel padrão.
- `.gitignore` já ignora `build/` e `.build/`. Sugiro `dist/` para o DMG (também ignorado).

## F04 — versão de fonte única

### Regras de formato (Apple)

- `CFBundleShortVersionString`: **[CONFIRMADO]** "The required format is three period-separated integers, such as 10.14.1. The string can only contain numeric characters (0-9) and periods." — https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
- `CFBundleVersion`: **[CONFIRMADO]** "one to three period-separated integers … can only contain numeric characters (0-9) and periods … For macOS apps, increment the build version before you distribute a build." Um inteiro só é válido (`10` = `10.0.0`). — https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion

### Consequência prática

- `git describe` devolve coisas como `v0.1.0-3-gabc123` ou `abc123-dirty` → **inválido** para `CFBundleShortVersionString` sem pós-processamento, e hoje nem existe tag. **[CONFIRMADO]** (formato da Apple + teste local).
- Por isso: **arquivo `VERSION`** com `0.1.0` (default do backlog) é a fonte única da versão visível; `git rev-list --count HEAD` é o `CFBundleVersion` (inteiro, monotônico enquanto o histórico de `main` não for reescrito).

### Recomendação (diff mínimo no `build-app.sh`)

```bash
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION inválida: '$VERSION' (use X.Y.Z)" >&2; exit 1; }
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
# ... no plist: CFBundleShortVersionString=$VERSION, CFBundleVersion=$BUILD
```

Gate de verificação: `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ClaudeBar.app/Contents/Info.plist` e o mesmo para `:CFBundleVersion`. (PlistBuddy existe nesta máquina **[CONFIRMADO]**.)

### Armadilhas

- **Clone raso** (`git clone --depth 1`, CI com `fetch-depth: 1`): `rev-list --count` vira 1 → build number regride. **[SUPOSIÇÃO]** sobre CI futuro; o comportamento do git é conhecido. Mitigação: CI com `fetch-depth: 0`, ou aceitar porque não há updater ainda.
- **Fora de um repo git** (tarball do GitHub): `git` falha → o fallback `0` evita quebrar o build. **[CONFIRMADO]** pela lógica do script; não testado com tarball.
- Contagem de commits só é monotônica numa branch; builds de branches diferentes podem ter o mesmo número. Irrelevante sem auto-update (Sparkle compara `CFBundleVersion`; isso é F-futura). **[SUPOSIÇÃO]** sobre Sparkle, não verificado nesta pesquisa.

### Alternativas consideradas

| Opção | Prós | Contras | Veredito |
|---|---|---|---|
| `VERSION` + `rev-list --count` | 1 arquivo, valida formato, funciona sem tag | clone raso | **recomendada** |
| `version.env` com `MARKETING_VERSION` + `BUILD_NUMBER` manuais (CodexBar faz assim) | determinístico, sem git | dá para esquecer de incrementar o build | boa, mas um campo a mais para manter |
| `git describe --tags` | sem arquivo | precisa de tag, saída fora do formato Apple | não |

Referência open source: CodexBar (`steipete/CodexBar`) — `version.env` contém `MARKETING_VERSION=0.84.1` e `BUILD_NUMBER=178`; `Scripts/package_app.sh` faz `source "$ROOT/version.env"` e grava `<key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>` / `<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>`. https://github.com/steipete/CodexBar/blob/main/Scripts/package_app.sh , https://github.com/steipete/CodexBar/blob/main/version.env

## F23 — `scripts/make-dmg.sh` (universal + DMG + SHA-256, sem publicar)

### Build universal com SwiftPM

- **[CONFIRMADO, testado aqui]** `swift build -c release --arch arm64 --arch x86_64` compila este pacote sem erro (~11 s com `--scratch-path` limpo). O bin path muda: `swift build -c release --arch arm64 --arch x86_64 --show-bin-path` → `<.build>/apple/Products/Release`. **Precisa passar os mesmos `--arch` no `--show-bin-path`**, senão ele aponta para `arm64-apple-macosx/release` (o binário fino).
- **[CONFIRMADO, testado aqui]** `lipo -archs` em `ClaudeBar` e `claudebar-hook` → `x86_64 arm64`. Obs.: `lipo -archs` aceita **um arquivo por vez** (com dois dá erro).
- **[CONFIRMADO]** Apple: verificar com `lipo -archs <executável>` apontando para o binário dentro de `Contents/MacOS`, não para o bundle. Alternativa oficial para build systems próprios: compilar cada arquitetura e juntar com `lipo -create -output`. — https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary
- **[SUPOSIÇÃO]** relatos de que com dois `--arch` os `-Xswiftc/-Xcc/-Xlinker` são ignorados e que pode falhar link de lib de sistema em x86_64. Não afeta o ClaudeBar hoje (sem flags extras, sem dependências). — https://forums.swift.org/t/swiftpm-universal-binary/59856 , https://liamnichols.github.io/2020/08/01/building-swift-packages-as-a-universal-binary.html
- O caminho `--arch` duplo passa pelo build system do Xcode (`.build/apple/...`) e exige Xcode instalado, não só Command Line Tools. **[SUPOSIÇÃO]** — não testei só com CLT.
- Fallback se o `--arch` duplo quebrar: dois builds `--arch arm64` e `--arch x86_64` + `lipo -create` (padrão do CodexBar: `lipo -create "${binaries[@]}" -output "$dest"`).

### Assinatura ad-hoc de binário universal

- **[CONFIRMADO, testado aqui]** `codesign --force --sign - --timestamp=none` num `.app` universal → `Format=bundle with Mach-O universal (x86_64 arm64)`, `Signature=adhoc`, `codesign --verify --strict` OK.
- **[CONFIRMADO]** Apple Silicon exige assinatura em todo executável; ad-hoc basta para rodar, mas "binaries signed this way cannot pass through Gatekeeper". O linker já assina ad-hoc; quem modifica o binário depois do link (`strip`, `install_name_tool`) precisa re-assinar. — https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes
- `claudebar-hook` é um segundo executável em `Contents/MacOS`. Sugestão: assinar de dentro para fora (`codesign … claudebar-hook` antes do bundle). **[SUPOSIÇÃO]** que é necessário com ad-hoc; para Developer ID (F28) a Apple manda assinar cada item de código separadamente ("Creating distribution-signed code for macOS", não lido nesta pesquisa). Evitar `--deep`.

### DMG + checksum

- **[CONFIRMADO]** Apple, "Packaging Mac software for distribution": criar pasta raiz, popular com `ditto` (preserva symlinks), `hdiutil create -srcFolder <dir> -o <arquivo>`; DMG para distribuição deve ser "UDIF-format read-only zip-compressed disk image (type UDZO)". Assinar o DMG e notarizar fica para F28. — https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- **[CONFIRMADO, testado aqui]** `hdiutil create -volname "… 0.1.0" -srcfolder stage -ov -format UDZO out.dmg` + `hdiutil verify out.dmg` ("checksum … is VALID") + `shasum -a 256 out.dmg`. Symlink `Applications -> /Applications` dentro do stage funciona.
- `man hdiutil` **[CONFIRMADO]**: formatos `UDZO` (zlib), `ULFO` (lzfse, 10.11+), `ULMO` (lzma, 10.15+). UDZO é o que a Apple cita; ULFO/ULMO comprimem mais. Recomendo UDZO (o app é pequeno).
- Exemplo em fórum Swift (Makefile): `swift build -c release --product ${PRODUCT} --arch arm64 --arch x86_64` e `hdiutil create -volname "${PRODUCT}" -srcfolder "${PKG_DMG_ROOT}" -ov -format UDZO "${PKG_DMG}"`. — https://forums.swift.org/t/how-to-distribute-a-swiftpm-executable-on-macos/47127/5
- Formato do `.sha256`: gerar de dentro de `dist/` (`cd dist && shasum -a 256 X.dmg > X.dmg.sha256`) para `shasum -c X.dmg.sha256` funcionar sem caminho absoluto. Mesmo padrão em https://github.com/LMLiam/clamshellctl/pull/18 (DMG + `.sha256` + `hdiutil verify` + `shasum -c`). **[CONFIRMADO]** comportamento do shasum; o PR só lido via resumo de busca.
- **O SHA muda a cada build** (timestamps no DMG/APFS) — não esperar build reprodutível. **[SUPOSIÇÃO]** forte; não rodei duas vezes para comparar.

### Esqueleto recomendado (só referência, não aplicado)

```bash
#!/bin/bash
# Gera dist/ClaudeBar-<versão>.dmg universal + .sha256. Não publica nada.
set -euo pipefail
cd "$(dirname "$0")/.."
UNIVERSAL=1 ./scripts/build-app.sh          # build-app.sh acrescenta --arch arm64 --arch x86_64 se UNIVERSAL=1
APP=build/ClaudeBar.app
for b in ClaudeBar claudebar-hook; do
  [[ "$(lipo -archs "$APP/Contents/MacOS/$b")" == *arm64* && "$(lipo -archs "$APP/Contents/MacOS/$b")" == *x86_64* ]] \
    || { echo "$b não é universal" >&2; exit 1; }
done
codesign --verify --strict "$APP"
VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="ClaudeBar-$VERSION"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ClaudeBar.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg"
hdiutil verify "dist/$NAME.dmg"
(cd dist && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256" && cat "$NAME.dmg.sha256")
```

No `build-app.sh`, a mudança mínima é um array: `ARCH_ARGS=(); [[ "${UNIVERSAL:-0}" == 1 ]] && ARCH_ARGS=(--arch arm64 --arch x86_64)` usado **tanto** no `swift build` quanto no `--show-bin-path`. Assim `install.sh` continua rápido (só host) e o DMG sai universal. Alternativa mais simples: sempre universal (+~2× tempo de build); aceitável, mas deixa o `install.sh` mais lento.

## Armadilhas de produto (para o README de F23)

1. **Gatekeeper com ad-hoc**: o DMG baixado vem com quarentena; app ad-hoc não passa no Gatekeeper **[CONFIRMADO, Apple]**. No macOS 15 Sequoia a Apple removeu o atalho Control-clique → Abrir; o caminho é tentar abrir, depois Ajustes do Sistema → Privacidade e Segurança → "Abrir Mesmo Assim". **[SUPOSIÇÃO — imprensa, não doc Apple]**: https://appleinsider.com/articles/24/08/06/apple-removes-control-click-option-for-skipping-gatekeeper-in-macos-sequoia , https://mjtsai.com/blog/2024/07/05/sequoia-removes-gatekeeper-contextual-menu-override . Relatos (não verificados) de que o botão some em alguns casos no 15.1 e de que ele só aparece por ~1 h após a tentativa. Alternativa para usuário técnico: `xattr -dr com.apple.quarantine /Applications/ClaudeBar.app` **[SUPOSIÇÃO]** (comando conhecido, não tirado de doc Apple aqui). O README deve dizer isso com honestidade e não instruir a desligar o Gatekeeper.
2. **App Translocation**: aberto direto do DMG (sem mover), o Gatekeeper randomiza o caminho do bundle no primeiro launch **[CONFIRMADO, Apple, mesma página de packaging]**. Impacto no ClaudeBar: o hook registrado em `settings.json` aponta para caminho absoluto; se algum fluxo futuro registrar o hook a partir de `Bundle.main` rodando translocado, o caminho fica errado. Hoje o `install.sh` usa caminho fixo em `~/Applications`, então o README do DMG precisa mandar arrastar para Aplicações **antes** de registrar hooks. **[SUPOSIÇÃO]** sobre o impacto (inferência do código).
3. **Caminho do app**: `install.sh` instala em `~/Applications`; o DMG sugere `/Applications`. O registro de hooks (seja qual for a feature que fizer isso a partir do DMG) precisa usar o caminho real de onde o app está. Decisão para a spec.
4. **Nome/marca**: o DMG pode ser gerado localmente, mas **publicar** está fora (F28/F47, guard rail de marca). O script não faz upload, não cria release, não toca rede.
5. **`LSUIElement`/`LSMinimumSystemVersion 14.0`** já estão no plist e não mudam com universal. `LSRequiresNativeExecution` / `LSArchitecturePriority` existem **[CONFIRMADO, Apple]** mas não são necessários; não adicionar.
6. **Swift 6 / MainActor**: nada nestas features toca código Swift; sem risco de concorrência. **[CONFIRMADO]** pelo escopo do diff.

## Recomendação final

- F04: arquivo `VERSION` (`0.1.0`) validado por regex + `CFBundleVersion = git rev-list --count HEAD` com fallback `0`.
- F23: `UNIVERSAL=1` opcional no `build-app.sh` (mesmos `--arch` no `--show-bin-path`), `make-dmg.sh` com `lipo -archs` + `codesign --verify` + `ditto` + `hdiutil create -format UDZO` + `hdiutil verify` + `shasum -a 256` em `dist/`. Sem assinatura do DMG, sem notarização, sem publicar.
- Gates: `bash -n scripts/*.sh`, `shellcheck` se instalado, rodar `./scripts/make-dmg.sh`, `shasum -c dist/*.sha256`, `PlistBuddy` nas duas chaves.

## Não verificado

- Abrir o DMG baixado (com quarentena) em outro Mac / Intel real; comportamento exato do "Abrir Mesmo Assim" no macOS 15/26.
- Rodar o slice x86_64 (só daria via Rosetta aqui).
- Build universal com só Command Line Tools (sem Xcode).
- Reprodutibilidade do SHA entre dois builds.
- Necessidade de assinar `claudebar-hook` separadamente com ad-hoc.
