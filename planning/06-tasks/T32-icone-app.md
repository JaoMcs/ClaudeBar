# T32 — Ícone do app (`AppIcon.icns`)

- **Funcionalidade:** F18 — spec [G13](../05-specs/G13-icone.md); asset em `planning/07-design/final/` (conceito "Prompt Pulse", sem marca da Anthropic)
- **Épico:** Distribuição · **Prioridade:** P1 · **Esforço:** 0,5 h
- **Depende de:** T02 (mesmo heredoc do plist) · **Bloqueia:** T33, T34
- **Branch:** `feat/icone-app`
- **PR:** `feat: ícone do app`

## Objetivo

O `ClaudeBar.app` passa a ter ícone próprio no Finder, Spotlight, Monitor de Atividade, banners e Ajustes > Notificações. Barra de menu, menu e HUD **não mudam** (SF Symbols). Nenhuma linha de Swift.

## Subtasks

- [ ] `mkdir -p Resources && cp planning/07-design/final/AppIcon.icns Resources/AppIcon.icns && git add Resources/AppIcon.icns` (`planning/` não é versionado; o script nunca copia de lá).
- [ ] `scripts/build-app.sh`: `cp Resources/AppIcon.icns …/Contents/Resources/` **antes** do `codesign`; `CFBundleIconFile = AppIcon` no plist.
- [ ] `.github/workflows/ci.yml`: step "Conferir o bundle (ícone e assinatura)" depois de "Empacotar o .app".
- [ ] Conferir: sem `Resources/AppIcon.icns`, `build-app.sh` sai ≠ 0. Restaurar.
- [ ] Verificação manual (Finder ícone/lista, Spotlight, Ajustes > Notificações): o implementador registra o que viu ou "não verificado".
- [ ] READMEs (Project structure).
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Resources/AppIcon.icns` | novo (binário ~1 MB) |
| `scripts/build-app.sh` | 1 `cp` + 2 linhas no plist |
| `.github/workflows/ci.yml` | 1 step |
| READMEs | 1 linha |

## Código-chave (da spec)

```bash
cp "$BIN_DIR/ClaudeBar" "$BUNDLE/Contents/MacOS/ClaudeBar"
cp "$BIN_DIR/claudebar-hook" "$BUNDLE/Contents/MacOS/claudebar-hook"
# O sistema lê o ícone daqui (CFBundleIconFile). Copiar antes de assinar:
# arquivo que entra depois do codesign invalida o selo.
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
```

```xml
    <key>CFBundleExecutable</key>
    <string>ClaudeBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
```

```yaml
      - name: Conferir o bundle (ícone e assinatura)
        run: |
          test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' build/ClaudeBar.app/Contents/Info.plist)" = AppIcon
          test -s build/ClaudeBar.app/Contents/Resources/AppIcon.icns
          codesign --verify --deep --strict build/ClaudeBar.app
```

## Testes obrigatórios

Nenhum teste Swift. A verificação automática é o step da CI (falha se a chave sair do plist, se o `cp` sair ou se o recurso entrar depois do `codesign`).

## Critérios de aceite

- `git ls-files Resources/AppIcon.icns` lista o arquivo; `cmp` com o do design sem diferença.
- `build-app.sh` sai 0; `AppIcon.icns` no bundle não vazio; `CFBundleIconFile` = `AppIcon`; `plutil -lint` OK; `codesign --verify --deep --strict` OK.
- Sem o `.icns`, `build-app.sh` sai ≠ 0.
- Diff sem `.swift` e sem `Package.swift`; `swift test` igual.
- Step da CI passa no PR.

## Gates

`swift build`, `swift test`, `bash -n scripts/*.sh`, `./scripts/build-app.sh`, CI.

## README (as duas línguas)

Project structure: `Resources/AppIcon.icns        app icon, copied into the bundle by build-app.sh` / "ícone do app, copiado para o bundle pelo build-app.sh".

## Riscos

| Risco | Mitigação |
|---|---|
| Cache de ícone mantém o genérico | não pôr no script; se acontecer, `touch` no `.app` / `lsregister -f` à mão, registrar no PR |
| Sem variantes Liquid Glass no macOS 26 | aceito; exige Icon Composer + Xcode |
| Marca | conceito sem logo/cor da Anthropic (README do design) |

## Fora do escopo

Ícone da barra (`MenuBarIcon-*.png`), menu, HUD; `resources:` no `Package.swift`/`Bundle.module`; `CFBundleIconName`/`Assets.car`/`actool`; `iconutil` no build; `touch`/`lsregister`/`killall` no `install.sh`.
