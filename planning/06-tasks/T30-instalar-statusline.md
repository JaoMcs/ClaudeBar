# T30 — Instalar/remover o `statusLine` (opt-in próprio)

- **Funcionalidade:** F22, parte 3 de 3 (F22.3) — spec [G11, F22.3](../05-specs/G11-limites.md)
- **Épico:** Limites · **Prioridade:** P1 · **Esforço:** 2 h
- **Depende de:** T28, T10 (alerta de consentimento), T06 (caminho estável) · **Bloqueia:** —
- **Branch:** `feat/instalar-statusline`
- **PR:** `feat: opção para mostrar limites usando o statusline do Claude Code`

## Objetivo

Opção separada e **desligada por padrão**: "Mostrar limites de uso (usa o statusline do Claude Code)". Ao instalar, o `statusLine` original é guardado em `statusline-original.json` (`0600`) e o `settings.json` passa a apontar para `<caminho estável> statusline`. Ao remover, o original volta inteiro (`padding`, `refreshInterval` incluídos). Mesmo consentimento do T10: prévia, backup, só grava com clique.

## Desenho (a spec deixou como contrato)

- `StatusLineInstall` (Core, funções puras) como na spec.
- `HookAction` ganha `.installStatusLine` e `.uninstallStatusLine`. `HookInstaller.plan` calcula o dicionário novo com `StatusLineInstall` e guarda em `HookPlan.statusLineOriginal: StatusLineInstall.Original?` o que fazer com o arquivo do original. O diff passa a mostrar `hooks` **e** `statusLine` (`hooksOnly` → `relevantKeys`, só essas duas chaves; nada de `env`).
- `apply(_:backups:original:)` (parâmetro `original: URL = StatusDirectory.originalStatusLineURL`, para teste): grava/apaga o arquivo do original **antes** do `settings.json` no install; apaga **depois** no uninstall.
- `hookCommand` = caminho estável entre aspas simples (com `'` escapado como `'\''`) + ` statusline`. É texto que o Claude Code roda em shell; não há dado externo nele.
- App: dois itens no `integrationMenu` do T10 — "Mostrar limites no rodapé do Claude Code…" / "Parar de mostrar limites no rodapé…" — chamando `review(.installStatusLine)` etc., com o aviso abaixo no `informativeText`.
- CLI: `claudebar-hook install --statusline` / `uninstall --statusline`.
- `IntegrationState` **não** ganha caso novo (o statusline é opcional; detecção fica para depois).

## Subtasks

- [ ] Criar `Sources/ClaudeBarCore/StatusLineInstall.swift` (spec).
- [ ] `HookInstaller`: casos novos de `HookAction`, `statusLineOriginal`, diff com `statusLine`, `apply(_:backups:original:)`, `shellQuoted`.
- [ ] `HookSetup`: itens e textos do aviso; `review` com os casos novos.
- [ ] `main.swift`: flag `--statusline` em `install`/`uninstall`.
- [ ] Testes (abaixo).
- [ ] Verificação manual 1–5 da spec (com backup próprio do `settings.json`).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`StatusLineInstall.swift` (novo), `HookInstaller.swift`, `HookSetup.swift`, `MenuContent.swift`, `main.swift`, `RateLimitsTests.swift` (ou `HookInstallerTests.swift`), READMEs.

## Código-chave (da spec)

```swift
public enum StatusLineInstall {
    public enum Original {
        case keep                     // já estava instalado: o arquivo guarda o original de verdade
        case save([String: Any])      // gravar este objeto (0600)
        case remove                   // não havia statusline: apagar arquivo velho
    }

    public static func isOurs(_ statusLine: Any?) -> Bool {
        guard let command = (statusLine as? [String: Any])?["command"] as? String else { return false }
        return command.contains("claudebar-hook")
    }

    public static func install(_ settings: [String: Any], hookCommand: String)
        -> (settings: [String: Any], original: Original) {
        let current = settings["statusLine"] as? [String: Any]
        // Reinstalar não pode salvar o nosso como "original": o hook chamaria a si mesmo.
        if isOurs(current) { return (settings, .keep) }
        var ours = current ?? [:]     // mantém `padding`, `refreshInterval`…
        ours["type"] = "command"
        ours["command"] = hookCommand
        var result = settings
        result["statusLine"] = ours
        return (result, current.map { .save($0) } ?? .remove)
    }

    /// Só desfaz se o `statusLine` ainda é o nosso: se o usuário trocou depois, fica.
    public static func uninstall(_ settings: [String: Any], original: [String: Any]?) -> [String: Any] {
        guard isOurs(settings["statusLine"]) else { return settings }
        var result = settings
        result["statusLine"] = original
        return result
    }
}
```

Texto do aviso no alerta (sem statusline anterior): "O Claude Code esconde algumas dicas do rodapé (como `esc to interrupt`) quando existe um statusline. No lugar delas aparece `5h 23% · sem 41%`. Os limites só aparecem para assinantes Pro, Max e Ultra." Com statusline anterior: "Seu statusline continua aparecendo igual. O ClaudeBar só lê os limites antes de repassar."

## Testes obrigatórios

- `StatusLineInstallTests` da spec: `semStatuslineAnterior`, `guardaOOriginalEMantemPadding`, `reinstalarMantemOOriginal`, `removerRestauraOuRespeitaTroca`.
- Novo, em pasta temporária: `idaEVoltaDoStatusline` — `plan(.installStatusLine)` + `apply(original: tmp)` sobre `{"statusLine":{"type":"command","command":"~/x.sh","padding":2}}`, depois `plan(.uninstallStatusLine)` + `apply` → `statusLine` igual ao original (comparação de dicionário), arquivo do original apagado, original gravado com `0600` no meio do caminho.
- `shellQuoted("/Users/a b/it's")` → `'/Users/a b/it'\''s'`.

## Critérios de aceite

- Ida e volta devolve o `statusLine` original igual.
- Nenhuma escrita sem clique (ou sem `--statusline` explícito no CLI); a opção nasce desligada.
- `statusline-original.json` sempre `0600`.
- Instalar duas vezes não muda o arquivo do original.
- `swift test` = anterior + 6.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Instalação/remoção: o que muda no rodapé, onde fica o backup (`statusline-original.json` + backup com timestamp), remoção manual ("copie o conteúdo de `~/.claude/claudebar/statusline-original.json` de volta para `statusLine`, ou apague a chave se o arquivo não existir").

## Riscos

| Risco | Mitigação |
|---|---|
| Perder o statusline do usuário | original gravado antes, backup com timestamp, `.keep`, remoção condicional |
| Dicas do rodapé somem | aviso no opt-in, resumo no lugar, desligado por padrão |
| `statusLine` de projeto vence o nosso | não mexer; a idade no menu denuncia dado parado |
| App apagado sem remover | rodapé em branco; mitigado pelo caminho estável (T05/T06) |

## Fora do escopo

Settings de projeto e `settings.local.json`; instalar junto com os hooks sem opt-in; montar o comando original dentro do nosso; reparo silencioso; checar o `statusLine` no "Testar integração" (só se couber em uma linha no T11 depois).
