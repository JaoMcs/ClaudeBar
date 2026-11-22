# T33 — DMG universal + SHA-256 (só o script)

- **Funcionalidade:** F23 — spec [G02, F23](../05-specs/G02-versao-dmg.md)
- **Épico:** Distribuição · **Prioridade:** P1 · **Esforço:** 1,5 h
- **Depende de:** T02 (`VERSION`), T32 (ícone), T05/T10 (registro dos hooks pelo hook/app) · **Bloqueia:** —
- **Branch:** `chore/dmg-universal`
- **PR:** `chore: script do DMG universal com SHA-256`

## Objetivo

`./scripts/make-dmg.sh` gera `dist/ClaudeBar-<versão>.dmg` (arm64 + x86_64, ad-hoc) e `dist/ClaudeBar-<versão>.dmg.sha256`. Falha se algum binário não for universal ou se `codesign --verify --strict` não passar. Sem rede, sem publicar, sem notarizar.

## Ajustes sobre a spec

- O passo 4 do README do DMG ("registrar hooks com o `jq`") **não vale mais**: depois de T05/T10, ao abrir o app arrastado para Aplicações ele **oferece** registrar os hooks (com o diff). Alternativa por terminal: `/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook install`.
- A verificação 5 da spec ("sai com 2") vira "sai com 1".
- O F03 já tirou a dependência do caminho do bundle, mas o README continua mandando arrastar para Aplicações **antes** de abrir (App Translocation).

## Subtasks

- [ ] `scripts/build-app.sh`: `UNIVERSAL=1` opcional com `ARCH_ARGS` no `swift build` **e** no `--show-bin-path`; assinatura de dentro para fora (hook, depois bundle).
- [ ] `scripts/make-dmg.sh` novo (`chmod +x`).
- [ ] `.gitignore`: `dist/`.
- [ ] Verificação manual 1–5 da spec + revalidar a quarentena: `hdiutil attach` do DMG, copiar o app para uma pasta temporária com `com.apple.quarantine`, rodar `claudebar-hook install --dry-run` a partir dele e conferir que a cópia estável sai sem o xattr (lição do G03).
- [ ] Registrar como "não verificado": DMG baixado em outro Mac, "Abrir Mesmo Assim" no 15 e no 26, app GUI em Intel real.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`scripts/build-app.sh`, `scripts/make-dmg.sh` (novo), `.gitignore`, READMEs.

## Código-chave (da spec)

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
BIN_DIR="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"
```

```bash
echo "==> Assinando (ad-hoc)"
# De dentro para fora: o build universal sai sem assinatura no hook; sem isso
# o `--verify --strict` do bundle falha ("code object is not signed at all").
codesign --force --sign - --timestamp=none "$BUNDLE/Contents/MacOS/claudebar-hook" >/dev/null
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null
```

`scripts/make-dmg.sh` completo na spec (G02): `UNIVERSAL=1 ./scripts/build-app.sh`; `lipo -archs` em cada binário; `codesign --verify --strict`; stage em `mktemp -d` com `ditto` + link `Applications`; `hdiutil create … -format UDZO`; `hdiutil verify`; `(cd dist && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")`.

## Testes obrigatórios

Nenhum teste Swift. As checagens ficam **dentro** do `make-dmg.sh`. Gates do PR:

```bash
bash -n scripts/*.sh
swift build && swift test
./scripts/make-dmg.sh
(cd dist && shasum -c ClaudeBar-*.dmg.sha256)        # OK
./scripts/build-app.sh && codesign --verify --strict build/ClaudeBar.app   # host continua ok
```

## Critérios de aceite

- `make-dmg.sh` sai 0 com `.dmg` e `.dmg.sha256`; `shasum -c` OK.
- `lipo -archs` dos dois binários contém `arm64` e `x86_64`.
- `codesign --verify --strict` passa no universal e no host; `hdiutil verify` VALID; volume com `ClaudeBar.app` + `Applications`.
- `install.sh` continua compilando só o host.
- `dist/` ignorado; `git status` limpo depois.
- Nenhuma chamada de rede (`curl`, `gh`, `notarytool`, `altool`).

## Gates

Acima + CI (que já roda `build-app.sh`).

## README (as duas línguas)

Installation ganha "From a DMG" antes do `install.sh`: (1) `./scripts/make-dmg.sh` (Xcode completo) e `shasum -c`; (2) arrastar para Aplicações **antes** de abrir; (3) ad-hoc, não notarizado: Ajustes do Sistema → Privacidade e Segurança → "Abrir Mesmo Assim" (não desligar o Gatekeeper); (4) ao abrir, o app oferece registrar os hooks mostrando o diff. Development: `UNIVERSAL=1 ./scripts/build-app.sh`; o SHA muda a cada build (DMG não reprodutível). Project structure: `scripts/make-dmg.sh   universal DMG + SHA-256 in dist/ (publishes nothing)`.

## Riscos

| Risco | Mitigação |
|---|---|
| Hook sem assinatura no universal (confirmado) | assinatura de dentro para fora + verify no script |
| `--arch` duplo exigir Xcode completo | `set -e` para o script; README diz "full Xcode" |
| SHA não reprodutível (confirmado) | README diz; não prometer build reprodutível |
| `xattr -dr com.apple.quarantine` | **não** pôr no README nesta task |

## Fora do escopo

Publicar/release (F47/F48), assinar o DMG ou notarizar (F28), `codesign --deep`, desligar Gatekeeper, `create-dmg`/`shellcheck`, commitar `dist/`.
