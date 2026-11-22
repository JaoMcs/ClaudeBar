# T07 — `Notification` só para permissão e formulário + `kind` no arquivo

- **Funcionalidade:** F05 — spec [G04, F05](../05-specs/G04-notification-kind.md)
- **Épico:** Hooks · **Prioridade:** P0 · **Esforço:** 1,5 h
- **Depende de:** T05, T06 · **Bloqueia:** T09, T12, T16
- **Branch:** `fix/notification-matchers`
- **PR:** `fix: esperando só para permissão e formulário (matchers do Notification)`

## Objetivo

Acabar com o "esperando você" falso: hoje o `Notification` sem matcher grava `waiting` para `idle_prompt` (~60 s depois de cada resposta), `auth_success`, `quota_*`… Passa a haver dois grupos: `permission_prompt` → `waiting --kind permission`, `elicitation_dialog` → `waiting --kind question`. O tipo fica gravado no arquivo como `kind: String?` (pronto para T16). UI não muda.

## Subtasks

- [ ] `HookInstaller`: `Entry(event:matcher:args:)` com `var matcher: String? = nil` (`var`, para entrar no init memberwise); `install` grava `group["matcher"]` quando houver; `handlers(in:)` devolve o matcher do grupo; `state` compara `event + matcher + args`.
- [ ] `entries`: trocar `Notification` por duas entradas com matcher (abaixo).
- [ ] `SessionStatus.swift`: `enum WaitKind` (não `Codable`), `kind: String?`, `waitKind`, parâmetro `kind: WaitKind? = nil` no `init`.
- [ ] `main.swift`: `value(after:in:)`; `parsePID` usa `value(after:)` **mantendo o fallback de `getppid()` de T05**; `kind` só com `waiting`.
- [ ] Testes: `SessionStatusTests.swift` novo (4) + atualizar `formatoDoHandler` e acrescentar `notificationTemDoisMatchers` em `HookMergeTests`; `estados` continua verde.
- [ ] Simulação isolada com `CFFIXED_USER_HOME` (abaixo) e verificação manual 4 da spec (90 s sem virar "esperando").
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | `matcher` |
| `Sources/ClaudeBarCore/SessionStatus.swift` | `WaitKind`, `kind` |
| `Sources/claudebar-hook/main.swift` | `--kind` |
| `Tests/ClaudeBarTests/SessionStatusTests.swift` | novo |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | matchers |
| READMEs | tabela de hooks, exemplo, CLI |

## Código-chave

`HookInstaller.entries` (formato do instalador do F02, não o `jq`):

```swift
    static let entries = [
        Entry(event: "UserPromptSubmit", args: ["working"]),
        Entry(event: "Stop", args: ["idle"]),
        // Só o que de fato espera você. `idle_prompt`, `auth_success`, `quota_*`
        // nem chamam o binário.
        Entry(event: "Notification", matcher: "permission_prompt", args: ["waiting", "--kind", "permission"]),
        Entry(event: "Notification", matcher: "elicitation_dialog", args: ["waiting", "--kind", "question"]),
        Entry(event: "SessionEnd", args: ["end"]),
    ]
```

`SessionStatus.swift`:

```swift
/// Por que a sessão está esperando você. No arquivo o campo é texto
/// (`kind: String?`): valor desconhecido faria o decode falhar, e `readAll`
/// apaga arquivo que não decodifica.
public enum WaitKind: String, Sendable {
    case permission
    case question
}

    public let message: String?
    /// `WaitKind` em texto. `nil` em arquivo antigo e fora de `waiting`.
    public let kind: String?

    public var waitKind: WaitKind? { kind.flatMap(WaitKind.init(rawValue:)) }
    // init: `message: String? = nil, kind: WaitKind? = nil` … `self.kind = kind?.rawValue`
```

`main.swift`:

```swift
// Uso: claudebar-hook <working|idle|waiting|end> [--kind <permission|question>] [--pid <pid do claude>]

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func parsePID(_ arguments: [String]) -> Int32 {
    if let pid = value(after: "--pid", in: arguments).flatMap({ Int32($0) }) { return pid }
    // Exec form não tem `$PPID` (T05): pai direto, só se for mesmo um `claude`.
    let parent = getppid()
    return processExecutablePath(parent)?.lowercased().contains("claude") == true ? parent : 0
}

    // O tipo vem do argumento que o instalador escreveu (um matcher por tipo),
    // não do payload: `notification_type` já faltou em versão antiga.
    let kind = state == .waiting
        ? value(after: "--kind", in: arguments).flatMap(WaitKind.init(rawValue:))
        : nil
    // … SessionStatus(…, message: …, kind: kind)
```

`HookPayload` **não muda**.

## Testes obrigatórios

`SessionStatusTests` (da spec): `arquivoAntigoSemKindDecodifica`, `kindDesconhecidoDecodificaComoGenerico`, `kindSobreviveAoEncodeEDecode`, `semKindNaoGravaAChave`. Em `HookMergeTests`: `Notification` com exatamente dois grupos, cada um com `matcher` e os `args` acima; nenhum grupo `Notification` nosso sem matcher.

Simulação isolada (não toca o estado real):

```bash
swift build
export CFFIXED_USER_HOME="$(mktemp -d)"
echo '{"session_id":"t","cwd":"/tmp"}' | .build/debug/claudebar-hook waiting --kind permission --pid 1
grep kind "$CFFIXED_USER_HOME/.claude/claudebar/t.json"          # "kind" : "permission"
echo '{"session_id":"t","cwd":"/tmp"}' | .build/debug/claudebar-hook working --pid 1
grep -c kind "$CFFIXED_USER_HOME/.claude/claudebar/t.json"       # 0
echo '{"session_id":"t","cwd":"/tmp"}' | .build/debug/claudebar-hook waiting --kind zzz --pid 1
grep -c kind "$CFFIXED_USER_HOME/.claude/claudebar/t.json"       # 0
unset CFFIXED_USER_HOME
```

## Critérios de aceite

- `Notification` registrado com exatamente os dois grupos com matcher.
- `SessionStatus.kind` é `String?`; `WaitKind` não é `Codable`.
- `state` volta `hooksOutdated` para uma instalação de T05 (sem matcher) e `ok` depois de reinstalar.
- Com `claude` real: 90 s depois de "pronto", a sessão **não** vira "esperando" (registrar no PR ou marcar "não verificado").
- `swift test` = anterior + 5; nenhum removido.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh` (o hook muda).

## README (as duas línguas)

- Tabela de hooks: `Notification` (`permission_prompt`, `elicitation_dialog`) → `waiting`; "other notification types (idle reminder, auth, quota…) are not registered".
- Exemplo de arquivo de estado com `"kind" : "permission",`.
- CLI: `[--kind <permission|question>]`; exemplo em Development.
- `permission_prompt` sai "after a few seconds without typing".

## Riscos

| Risco | Mitigação |
|---|---|
| Decode quebrar e `readAll` apagar estados na atualização | `kind: String?` + 2 testes; revisor recusa enum armazenado |
| Nome do matcher mudar no Claude Code | hook não dispara → "esperando" vem só do CLI; fail-safe |
| Depois de aprovar, nada volta a `working` até o `Stop` | T09 (H0) |

## Fora do escopo

Ler `notification_type`/`title`; UI de permissão × pergunta (T16); `PreToolUse`/`PostToolUse` (T09, T16); `elicitation_url_dialog`; `PermissionRequest`.
