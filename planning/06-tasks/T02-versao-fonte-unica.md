# T02 — Versão de fonte única (`VERSION`)

- **Funcionalidade:** F04 — spec [G02, seção F04](../05-specs/G02-versao-dmg.md)
- **Épico:** Base/Bugs · **Prioridade:** P0 · **Esforço:** 0,5 h
- **Depende de:** — · **Bloqueia:** T32, T33 (mesmo `build-app.sh`)
- **Branch:** `chore/versao-fonte-unica`
- **PR:** `chore: versão de fonte única no arquivo VERSION`

## Objetivo

A versão visível sai de um arquivo `VERSION` (`0.1.0`, formato X.Y.Z exigido pela Apple). `CFBundleVersion` = número de commits. Hoje `VERSION="1.0"` fica fixo no script e vai para as duas chaves.

## Subtasks

- [ ] Criar `VERSION` na raiz com uma linha `0.1.0` (default proposto no BACKLOG; o número da 1ª release pública é decisão do usuário e não bloqueia).
- [ ] `scripts/build-app.sh`: ler e validar `VERSION`, calcular `BUILD`, gravar `CFBundleVersion=$BUILD`.
- [ ] `.github/workflows/ci.yml`: `actions/checkout@v4` com `fetch-depth: 0` (clone raso faria `BUILD=1` sempre).
- [ ] Conferir: `VERSION` com `1.0` faz o script sair com 1 antes de compilar. Voltar para `0.1.0`.
- [ ] README e README.pt-BR (Development e Project structure).
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `VERSION` (novo) | `0.1.0` |
| `scripts/build-app.sh` | leitura, validação, `BUILD` |
| `.github/workflows/ci.yml` | `fetch-depth: 0` |
| `README.md`, `README.pt-BR.md` | 2 linhas |

## Código-chave (da spec)

`scripts/build-app.sh` (troca `VERSION="1.0"` e o echo de compilação; `swift build` e `--show-bin-path` ficam como estão):

```bash
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

Heredoc do plist:

```xml
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
```

`ci.yml`:

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # CFBundleVersion = git rev-list --count HEAD
```

## Testes obrigatórios

Nenhum teste Swift (nenhum código Swift lê a versão). O script é o teste:

```bash
bash -n scripts/build-app.sh
./scripts/build-app.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' build/ClaudeBar.app/Contents/Info.plist
# esperado: 0.1.0 e a saída de `git rev-list --count HEAD`
```

## Critérios de aceite

- `VERSION` existe com `0.1.0`; não sobra `VERSION="1.0"` no script.
- `CFBundleShortVersionString` == `VERSION`; `CFBundleVersion` == `git rev-list --count HEAD`.
- `VERSION` fora de X.Y.Z → `build-app.sh` sai ≠ 0 antes de compilar.
- `./scripts/install.sh` continua funcionando.
- CI verde, com o número de build igual à contagem completa.

## Gates

`swift build`, `swift test` (34, nada muda), `bash -n scripts/*.sh`, `./scripts/build-app.sh`.

## README

- Development: "The version lives in `VERSION` (X.Y.Z). The build number is the commit count (`git rev-list --count HEAD`); shallow clones restart the count."
- Project structure: `VERSION   app version (X.Y.Z), read by build-app.sh`.

## Riscos

- Clone raso reinicia a contagem: `fetch-depth: 0` na CI + linha no README.
- Sem `.git`: fallback `0`.
- `VERSION` com CRLF: `tr -d '[:space:]'`.

## Fora do escopo

Tag/release, ler a versão em Swift (o "Sobre" do T24 usa o painel padrão), `agvtool`, universal/DMG (T33), ícone (T32).
