# G02 — Spec técnica: versão de fonte única (F04) + DMG universal com SHA-256 (F23)

Insumos: `04-como-fazer/G02-versao-dmg.md`, `03-validacao/BACKLOG.md` (F04: P0, P, bug; F23: P1, P, depende de F04 e F18), `00-PLANO.md` (guard rails).
Código lido em 2026-11-15 (`main` @ f943cc4): `scripts/build-app.sh`, `scripts/install.sh`, `.gitignore`, `README.md`, `Package.swift`, todo `Sources/` e `Tests/`.

**Verificado nesta spec:** os diffs abaixo foram aplicados numa cópia do projeto real, montada como repositório git (2 commits, como o `main` de hoje), com Swift 6.3.3, Xcode completo, macOS 26 em arm64:

| Checagem | Resultado |
|---|---|
| `bash -n scripts/*.sh` | ok |
| `./scripts/build-app.sh` (só o host) | `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=2`, `lipo` = `arm64`, `codesign --verify --strict` ok |
| `VERSION` = `1.0` | o script sai com 1: `VERSION inválida: '1.0' (use X.Y.Z, só dígitos e pontos)` |
| Sem `.git` | `CFBundleVersion=0`, build passa |
| `./scripts/make-dmg.sh` | cerca de 18 s, DMG de 641 KB, `hdiutil verify` VALID, `shasum -c` OK |
| Slice x86_64 do hook via `arch -x86_64` (Rosetta) | roda; grava o arquivo com `0600` |
| SHA de dois builds seguidos | **diferentes** (`d2327e…` e `ce8dde…`): o DMG não é reprodutível |
| **Achado novo:** build universal com a assinatura atual (só o bundle) | `codesign --verify --strict` **falha**: `code object is not signed at all — In subcomponent: …/Contents/MacOS/claudebar-hook`. O `claudebar-hook` sai de `.build/apple/Products/Release` sem assinatura (o build só do host sai com assinatura ad-hoc do linker, `flags=adhoc,linker-signed`, e por isso não falha hoje). Correção: assinar o hook antes do bundle (F23, abaixo). Com ela, o verify passa. |

O achado novo fecha dois itens "não confirmados" da pesquisa: o hook **precisa** da própria assinatura no build universal, e o slice x86_64 roda no Rosetta (só o hook; o app GUI não foi aberto em x86_64).

Nenhum código Swift muda nas duas funcionalidades. Por isso não há impacto de Swift 6, strict concurrency ou MainActor, e nenhum teste Swift novo.

## Arquivos tocados (para ordenar)

| Arquivo | F04 | F23 |
|---|---|---|
| `VERSION` (novo) | cria | lê |
| `scripts/build-app.sh` | versão e build | `UNIVERSAL=1` e assinatura de dentro para fora |
| `scripts/make-dmg.sh` (novo) | — | cria |
| `.gitignore` | — | `dist/` |
| `README.md` e `README.pt-BR.md` | Development e Project structure | Installation (DMG), Development, Project structure |

Não tocam: `Sources/`, `Tests/`, `Package.swift`, `scripts/install.sh`.

Conflitos de arquivo:
- **F18 (ícone)** também altera `build-app.sh` (Resources e `CFBundleIconFile`). Os trechos são diferentes (cópia de recursos e plist), mas a ordem tem de ser sequencial. A ordem sugerida é F04, depois F18, depois F23. F23 não depende tecnicamente de F18: o DMG empacota o que o `build-app.sh` gerar. Gerar um DMG sem ícone é inútil para o usuário, então F18 vem antes.
- **F02 e F03** alteram `install.sh` e o fluxo dos hooks. F23 não toca `install.sh`, mas o texto do README sobre registrar hooks a partir do DMG depende deles (ver os riscos de F23).

---

## F04 — Versão de fonte única

### Objetivo

A versão visível do app sai de um único lugar (`VERSION`, com `0.1.0`) e passa a ter o formato que a Apple exige. O número de build cresce sozinho a cada commit. Hoje `VERSION="1.0"` fica fixo no script e é gravado nas duas chaves.

### Decisão técnica

- O arquivo `VERSION` na raiz traz uma linha `0.1.0`. O `build-app.sh` lê o arquivo, valida com a regex `^[0-9]+\.[0-9]+\.[0-9]+$` (regra da Apple para `CFBundleShortVersionString`) e falha alto se o formato estiver errado.
- `CFBundleVersion` = `git rev-list --count HEAD`, com `0` como fallback fora do git. O squash merge em `main` mantém a contagem sempre crescente.
- Ninguém lê a versão em Swift agora. Quando o F15 fizer o "Sobre" com `orderFrontStandardAboutPanel`, o painel padrão já lê as duas chaves do `Info.plist` e mostra "0.1.0 (N)", sem nenhum código a mais.

Descartadas:
- `git describe --tags`: não há tag, e a saída (`v0.1.0-3-gabc`) quebra o formato da Apple.
- `version.env` com `MARKETING_VERSION` e `BUILD_NUMBER` manuais, como no CodexBar: é mais um número para lembrar de subir.
- Constante Swift com a versão: seria uma segunda fonte, e o oposto do objetivo.
- Plugin SwiftPM para gerar a versão: é abstração para três linhas de shell.

### Código

`VERSION` (novo, uma linha):

```
0.1.0
```

`scripts/build-app.sh`: troca o `VERSION="1.0"` e as duas linhas de build por isto (a parte do `ARCH_ARGS` é do F23; no PR do F04, `swift build -c release` e `--show-bin-path` ficam como estão):

```bash
BUNDLE="build/ClaudeBar.app"
BUNDLE_ID="com.joaomarcos.claudebar"

# Versão visível vem do arquivo VERSION (X.Y.Z, regra da Apple para
# CFBundleShortVersionString). O build é a contagem de commits: sobe a cada
# commit em main; fora de um repositório git cai para 0.
VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION inválida: '$VERSION' (use X.Y.Z, só dígitos e pontos)" >&2
    exit 1
fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

echo "==> Compilando em release ($VERSION, build $BUILD)"
```

No heredoc do plist, só a chave do build muda:

```xml
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
```

Sem o arquivo `VERSION`, o `tr` falha (`No such file or directory`) e o `set -e` encerra o script. A mensagem é clara o bastante e não precisa de checagem extra.

### Testes

Nenhum teste Swift: nenhum código Swift lê a versão, e um teste que lesse o `VERSION` por `#filePath` só repetiria a validação que o script já faz em todo build. Os gates ficam no shell, e o próprio script é o teste:

```bash
bash -n scripts/build-app.sh
./scripts/build-app.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' build/ClaudeBar.app/Contents/Info.plist
# esperado: 0.1.0 e a saída de `git rev-list --count HEAD`
```

Mais os gates normais do PR: `swift build` e `swift test` (34 testes, nada muda).

### README (`README.md` e `README.pt-BR.md`)

- **Development**: uma linha, "The version lives in `VERSION` (X.Y.Z). The build number is the commit count (`git rev-list --count HEAD`)."
- **Project structure**: `VERSION   app version (X.Y.Z), read by build-app.sh`.

### Verificação manual

1. `./scripts/build-app.sh` mostra `==> Compilando em release (0.1.0, build N)`.
2. `PlistBuddy` como acima.
3. Mudar `VERSION` para `1.0` faz o script sair com 1 e mostrar a mensagem. Depois, voltar para `0.1.0`.
4. `./scripts/install.sh` continua funcionando, porque chama o `build-app.sh` sem mudança de interface.

### Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Clone raso (`--depth 1`) reinicia a contagem | Não há CI nem updater hoje. Quando houver CI, usar `fetch-depth: 0`. Uma linha no README de Development. |
| Tarball sem `.git` | Fallback `0`, testado. |
| Branches diferentes geram o mesmo número | Só importa com auto-update (Sparkle), que fica fora desta rodada. |
| `VERSION` com CRLF ou espaço no fim | `tr -d '[:space:]'` limpa. |

### Critérios de aceite

- [ ] `VERSION` existe com `0.1.0` e não sobra `VERSION="1.0"` no script.
- [ ] `CFBundleShortVersionString` == conteúdo de `VERSION`, e `CFBundleVersion` == `git rev-list --count HEAD`.
- [ ] Uma `VERSION` fora do formato X.Y.Z faz o `build-app.sh` sair com código ≠ 0 antes de compilar.
- [ ] `swift build`, `swift test` e `bash -n scripts/*.sh` verdes.

### O que NÃO fazer

- Não criar tag git nem release (publicar fica com o usuário, F47 e F48).
- Não ler a versão em Swift nem criar `AppVersion.swift`: o "Sobre" é do F15 e usa o painel padrão.
- Não usar `agvtool` nem `PlistBuddy` para gravar: o heredoc já é a fonte do plist.

---

## F23 — DMG universal + SHA-256 (só o script)

### Objetivo

`./scripts/make-dmg.sh` gera `dist/ClaudeBar-<versão>.dmg` (arm64 + x86_64, assinatura ad-hoc) e o `dist/ClaudeBar-<versão>.dmg.sha256` correspondente. O script falha se algum binário não for universal ou se a assinatura não passar no `--verify --strict`. Não usa rede, não publica e não notariza.

### Decisão técnica

- **`UNIVERSAL=1` opcional no `build-app.sh`**, com um array `ARCH_ARGS` usado no `swift build` **e** no `--show-bin-path` (com outros flags, o caminho aponta para o binário de uma arquitetura só). O `install.sh` continua compilando só o host, que é mais rápido.
- **Assinatura de dentro para fora**: `codesign` primeiro no `claudebar-hook`, depois no bundle. A ordem é **obrigatória** no build universal (testado: sem ela o verify falha) e inofensiva no build do host. Sem `--deep`.
- **`make-dmg.sh` separado**: chama o `build-app.sh`, confere `lipo -archs` em cada binário (um por vez) e o `codesign --verify --strict`, monta o stage com `ditto` e o atalho `Applications`, gera o DMG em UDZO (o formato que a Apple cita), roda `hdiutil verify` e grava o `shasum -a 256` de dentro de `dist/`.

Descartadas:
- Universal sempre: dobra o tempo do `install.sh` sem ganho local.
- Dois builds com `--arch` + `lipo -create` (caminho do CodexBar): mais código. Fica de reserva se o `--arch` duplo quebrar, por exemplo ao entrar uma dependência com `-Xswiftc`.
- `ULFO`/`ULMO`: comprimem mais, mas o app tem 641 KB, e UDZO é o formato que a Apple cita.
- `create-dmg` ou `appdmg` (fundo, posição dos ícones): dependência externa só para cosmética.
- Assinar o DMG ou notarizar: exige Developer ID (F28, depende do usuário).
- `codesign --deep`: a Apple desaconselha, e são só dois binários.

### Código

`scripts/build-app.sh`: junta-se ao F04. Logo depois do `BUILD=…`:

```bash
# UNIVERSAL=1 compila arm64 + x86_64 (usado pelo make-dmg.sh). Sem ele, só a
# arquitetura desta máquina, que é mais rápido para o install.sh.
ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compilando em release ($VERSION, build $BUILD)"
# "${ARCH_ARGS[@]+...}": com set -u, array vazio quebra no bash 3.2 do macOS.
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
# Os mesmos --arch aqui, senão o caminho aponta para o binário de uma arquitetura só.
BIN_DIR="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"
```

O bloco de assinatura no fim troca a linha única por:

```bash
echo "==> Assinando (ad-hoc)"
# De dentro para fora: o hook é um segundo executável em Contents/MacOS e o
# build universal sai sem assinatura nenhuma; sem isso o `--verify --strict`
# do bundle falha ("code object is not signed at all").
codesign --force --sign - --timestamp=none "$BUNDLE/Contents/MacOS/claudebar-hook" >/dev/null
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null
```

`scripts/make-dmg.sh` (novo, `chmod +x`):

```bash
#!/bin/bash
# Gera dist/ClaudeBar-<versão>.dmg (arm64 + x86_64) e o .sha256 ao lado.
# Assinatura ad-hoc: o DMG não passa no Gatekeeper sem o "Abrir Mesmo Assim".
# Não assina o DMG, não notariza, não publica nada — sem rede.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/ClaudeBar.app"

UNIVERSAL=1 ./scripts/build-app.sh

echo "==> Conferindo arquiteturas e assinatura"
for binary in ClaudeBar claudebar-hook; do
    archs="$(lipo -archs "$APP/Contents/MacOS/$binary")"
    if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
        echo "$binary não é universal: $archs" >&2
        exit 1
    fi
done
codesign --verify --strict "$APP"

# build-app.sh já validou o formato.
VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="ClaudeBar-$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ClaudeBar.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Gerando dist/$NAME.dmg"
mkdir -p dist
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg" >/dev/null
hdiutil verify "dist/$NAME.dmg" >/dev/null

# De dentro de dist/, para `shasum -c` funcionar sem caminho absoluto.
(cd dist && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")

echo "==> Pronto:"
cat "dist/$NAME.dmg.sha256"
```

`.gitignore`: acrescentar `dist/`.

Nenhum argumento externo chega a um shell: as variáveis são locais e citadas, e não há `eval` nem `sh -c`. O guard rail "sem shell com interpolação" vale para o app, e o script o respeita do mesmo jeito.

### Testes

Nenhum teste Swift: o diff não toca `Sources/`. As checagens de universal e de assinatura ficam **dentro** do `make-dmg.sh` (ele falha se alguma quebrar), então rodar o script é o teste. Gates do PR:

```bash
bash -n scripts/*.sh
swift build && swift test
./scripts/make-dmg.sh
(cd dist && shasum -c ClaudeBar-*.dmg.sha256)       # ClaudeBar-0.1.0.dmg: OK
./scripts/build-app.sh && codesign --verify --strict build/ClaudeBar.app   # o caminho do host continua ok
```

`shellcheck` não está instalado nesta máquina. Não adicionar como dependência.

### README (`README.md` e `README.pt-BR.md`)

**Installation** ganha uma subseção "From a DMG" antes do `install.sh`:

1. Build it with `./scripts/make-dmg.sh` (full Xcode, not just the Command Line Tools). Check it with `shasum -c ClaudeBar-<v>.dmg.sha256`.
2. Open the DMG and **drag ClaudeBar into Applications before opening it**. Opened straight from the DMG, macOS runs the app from a random path (App Translocation), and the hook path would be wrong.
3. The app is ad-hoc signed, not notarized. On the first launch macOS blocks it. Go to System Settings → Privacy & Security → "Open Anyway". Do not turn Gatekeeper off.
4. Register the hooks. Until F16/F03 land, use the `jq` command from `install.sh` with `HOOK="/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook"`. The README shows this command in full, copied from `install.sh` with only the path changed.

**Development**: `UNIVERSAL=1 ./scripts/build-app.sh` builds arm64 + x86_64. `./scripts/make-dmg.sh` produces `dist/`. The SHA changes on every build, because the DMG is not reproducible.

**Project structure**: `scripts/make-dmg.sh   universal DMG + SHA-256 in dist/ (publishes nothing)`.

### Verificação manual

1. `./scripts/make-dmg.sh` termina com `==> Pronto:` e a linha `<sha>  ClaudeBar-0.1.0.dmg`.
2. `lipo -archs build/ClaudeBar.app/Contents/MacOS/{ClaudeBar,claudebar-hook}` (um de cada vez) mostra `x86_64 arm64`.
3. `codesign -dv build/ClaudeBar.app/Contents/MacOS/claudebar-hook` mostra `Signature=adhoc`.
4. `hdiutil attach dist/ClaudeBar-0.1.0.dmg`: o volume `ClaudeBar-0.1.0` mostra `ClaudeBar.app` e o atalho `Applications`. Depois, `hdiutil detach`.
5. `arch -x86_64 build/ClaudeBar.app/Contents/MacOS/claudebar-hook` sai com 2 e a mensagem de uso, o que mostra que o slice roda no Rosetta. Não passar `working`: o hook grava em `~/.claude/claudebar` de verdade, porque `NSHomeDirectory()` ignora `$HOME`.
6. **Não verificável aqui** (registrar no relatório): abrir o DMG baixado, com quarentena, em outro Mac; o fluxo "Abrir Mesmo Assim" no 15 e no 26; o app GUI num Intel real.

### Riscos e mitigação

| Risco (estado na pesquisa) | Mitigação |
|---|---|
| Hook sem assinatura no build universal (**confirmado aqui**) | Assinatura de dentro para fora no `build-app.sh` mais o `codesign --verify --strict` no `make-dmg.sh`, que falha alto. |
| `--arch` duplo pode exigir Xcode completo (não testado só com CLT) | O `swift build` falha e o `set -e` para o script. O README diz "full Xcode". Não investir em fallback até alguém bater nisso. |
| `-Xswiftc`/`-Xlinker` ignorados com dois `--arch` (relato) | Hoje o projeto não usa nenhum. Se algum entrar, trocar pelo caminho `lipo -create`. Anotar como `ponytail:` no script só se acontecer. |
| SHA não reprodutível (**confirmado aqui**) | O `.sha256` vale para *aquele* arquivo. O README diz isso. Não prometer build reprodutível. |
| Gatekeeper no Sequoia: Control-clique removido, "Abrir Mesmo Assim" (imprensa, não doc da Apple) | O README descreve o caminho atual sem afirmar detalhes não confirmados (botão que some no 15.1, janela de cerca de 1 h). |
| `xattr -dr com.apple.quarantine` (sem doc da Apple) | **Adiar:** não pôr no README nesta task. Se o "Abrir Mesmo Assim" falhar em teste real, entra como alternativa para usuário técnico. |
| App Translocation e o caminho do hook (inferido do código) | O README manda arrastar para Aplicações antes de abrir. O F03 (hook copiado para `~/.claude/claudebar/bin`) elimina a dependência do caminho do bundle. Nenhum código novo aqui. |
| `/Applications` (DMG) contra `~/Applications` (`install.sh`) | Os hooks precisam apontar para onde o app está. O README do DMG usa `/Applications`, e o `install.sh` não muda. O F03 unifica isso. |
| Marca ou nome no DMG | Gerar localmente é permitido. Publicar fica fora (F47). |

### Critérios de aceite

- [ ] `./scripts/make-dmg.sh` sai com 0 e cria `dist/ClaudeBar-<VERSION>.dmg` e `.dmg.sha256`.
- [ ] `(cd dist && shasum -c ClaudeBar-*.dmg.sha256)` mostra `OK`.
- [ ] `lipo -archs` de `ClaudeBar` e de `claudebar-hook` dentro do `.app` contém `arm64` e `x86_64`.
- [ ] `codesign --verify --strict build/ClaudeBar.app` passa no build universal **e** no do host.
- [ ] `hdiutil verify` dá VALID, e o volume tem `ClaudeBar.app` mais o atalho `Applications`.
- [ ] `./scripts/install.sh` continua compilando só o host, sem `--arch`.
- [ ] `dist/` está no `.gitignore`, e `git status` fica limpo depois de rodar o script.
- [ ] O script não faz chamada de rede: nada de `curl`, `gh`, `notarytool` ou `xcrun altool`.
- [ ] O README, nas duas línguas, cobre o build, o `shasum -c`, o "arrastar antes de abrir", o "Abrir Mesmo Assim" e o registro dos hooks.

### O que NÃO fazer

- Não publicar, criar release nem subir o DMG em lugar nenhum (F47/F48/F28).
- Não assinar o DMG nem notarizar, e não ler credenciais de env nesta task (F28).
- Não usar `codesign --deep`, nem adicionar `LSArchitecturePriority`/`LSRequiresNativeExecution`.
- Não instruir a desligar o Gatekeeper (`spctl --master-disable`).
- Não registrar hooks a partir do app, nem mudar o `install.sh` (F02/F03/F16).
- Não adicionar `create-dmg`, `shellcheck` ou outra dependência.
- Não commitar `dist/` nem `build/`.

---

## Esforço

| Funcionalidade | Arquivos | Horas |
|---|---|---|
| F04 | `VERSION` (novo), `scripts/build-app.sh`, `README.md`, `README.pt-BR.md` | 0,5 |
| F23 | `scripts/build-app.sh`, `scripts/make-dmg.sh` (novo), `.gitignore`, `README.md`, `README.pt-BR.md` | 1,5 |
