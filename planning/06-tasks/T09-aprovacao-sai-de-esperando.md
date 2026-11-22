# T09 — Permissão aprovada tira a sessão de "esperando" (`PostToolUse --if-waiting`)

- **Funcionalidade:** H0, pré-requisito de F12 e F13 — spec [G09, H0](../05-specs/G09-popup-lembrete.md)
- **Épico:** Hooks · **Prioridade:** P0 (bug visível com F12/F13) · **Esforço:** 1 h
- **Depende de:** T07 (matchers já feitos), T08 (guard de `session_id`) · **Bloqueia:** T16, T17, T26
- **Branch:** `fix/aprovacao-sai-de-esperando`
- **PR:** `fix: permissão aprovada tira a sessão de esperando`

## Objetivo

Hoje, depois que você aprova uma permissão, nenhum hook dispara e a sessão fica "esperando" até o `Stop`, com o Claude já trabalhando. Registrar `PostToolUse` e `PostToolUseFailure` (sem matcher) → `claudebar-hook working --if-waiting`: só regrava se o arquivo atual estiver em `waiting`. No resto do turno ele lê ~200 bytes e sai sem gravar (o `updatedAt` continua sendo "quando o estado mudou" e o app não acorda a cada ferramenta).

O matcher do `Notification` (metade do H0 na spec) já entrou em T07. Esta task só faz a outra metade. Esse `PostToolUse` genérico também cobre o "respondeu o `AskUserQuestion` → `working`" do F24: T16 **não** registra `PostToolUse:AskUserQuestion`.

## Subtasks

- [ ] `HookInstaller.entries`: duas entradas novas, timeout 5, sem matcher.
- [ ] `main.swift`: tratar `--if-waiting` depois do `guard let state` (fail-open: qualquer falha = `return`, exit 0; nunca `fail()`).
- [ ] Teste em `HookMergeTests`: `PostToolUse` do usuário (ex.: `prettier`) continua, o nosso entra depois; reinstalar não duplica.
- [ ] Simulação isolada com `CFFIXED_USER_HOME` e verificação manual 3–6 da spec (inclui anotar o que acontece ao **negar** uma permissão).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | 2 entradas |
| `Sources/claudebar-hook/main.swift` | `--if-waiting` |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | 1 teste |
| READMEs | tabela de hooks, CLI |

## Código-chave

```swift
        // Permissão aprovada (ou ferramenta que falhou) tira a sessão de
        // "esperando". Sem matcher: qualquer ferramenta pode ter pedido permissão.
        Entry(event: "PostToolUse", args: ["working", "--if-waiting"]),
        Entry(event: "PostToolUseFailure", args: ["working", "--if-waiting"]),
```

Em `run()`, logo depois do `guard let state = SessionState(rawValue: command)`:

```swift
    // `PostToolUse` roda a cada ferramenta. Só interessa quando ela tira a sessão
    // de "esperando" (permissão aprovada); no resto do turno o arquivo já diz
    // `working`, e regravar só mexeria no `updatedAt` e acordaria o app à toa.
    // Arquivo ausente ou ilegível: não grava (o `Stop` acerta o estado depois).
    if arguments.contains("--if-waiting") {
        let current = (try? Data(contentsOf: StatusDirectory.fileURL(sessionId: sessionId)))
            .flatMap { try? StatusDirectory.decoder.decode(SessionStatus.self, from: $0) }
        guard current?.state == .waiting else { return }
    }
```

## Testes obrigatórios

- `HookMergeTests.postToolUseDoUsuarioFica`: settings com `PostToolUse: [{hooks: [{command: "prettier --write"}]}]` → depois do `install`, `handlers(root, "PostToolUse").map(command)` == `["prettier --write", binary]`; `install` de novo não duplica.
- Simulação:

```bash
export CFFIXED_USER_HOME="$(mktemp -d)"; H=.build/debug/claudebar-hook
echo '{"session_id":"t","cwd":"/tmp"}' | $H working --if-waiting --pid 1; ls "$CFFIXED_USER_HOME/.claude/claudebar/"   # nada
echo '{"session_id":"t","cwd":"/tmp"}' | $H waiting --kind permission --pid 1
echo '{"session_id":"t","cwd":"/tmp"}' | $H working --if-waiting --pid 1; grep state "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # working
stat -f %m "$CFFIXED_USER_HOME/.claude/claudebar/t.json"; echo '{"session_id":"t","cwd":"/tmp"}' | $H working --if-waiting --pid 1; stat -f %m "$CFFIXED_USER_HOME/.claude/claudebar/t.json"   # igual
unset CFFIXED_USER_HOME
```

## Critérios de aceite

- `PostToolUse`/`PostToolUseFailure` do usuário preservados; instalação idempotente.
- `working --if-waiting` não grava com arquivo ausente ou fora de `waiting` e sai 0.
- Com `claude` real: aprovar uma permissão volta o arquivo para `working` em ≤ 1 s (ou "não verificado").
- Resultado do teste de **negar** permissão registrado no PR.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Tabela de hooks:

```markdown
| `PostToolUse`, `PostToolUseFailure` | `working`, only if the session was `waiting` (a permission was just approved) |
```

CLI: `[--if-waiting]` com uma linha de explicação.

## Riscos

| Risco | Mitigação |
|---|---|
| Custo de um processo por ferramenta | caminho sem gravação ≈ 25 ms (medido na spec); se pesar, matcher com lista de ferramentas — só depois de medir |
| Ferramenta paralela apaga um `waiting` com o prompt aberto | pior caso: popup fecha cedo e ícone volta a "processando" (o estado de hoje); registrar se observado |
| Versão sem `PostToolUseFailure` | evento desconhecido é ignorado; `/hooks` sem aviso de settings inválido |

## Fora do escopo

`PreToolUse → working`; ler `tool_input`/`tool_response`; `PermissionRequest`/`PermissionDenied`.
