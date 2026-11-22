# T03 — Merge aditivo dos hooks: funções puras no Core

- **Funcionalidade:** F02, parte 1 de 3 — spec [G03, F02](../05-specs/G03-hooks-integracao.md)
- **Épico:** Hooks · **Prioridade:** P0 · **Esforço:** 1,5 h
- **Depende de:** — · **Bloqueia:** T04
- **Branch:** `feat/hooks-merge-aditivo`
- **PR:** `feat: merge aditivo dos hooks no Core (funções puras)`

## Objetivo

Criar em `ClaudeBarCore` a lógica que acrescenta e remove **só** os handlers do ClaudeBar no `settings.json`, sem tocar em hook do usuário (nem no mesmo grupo). Esta task entrega só as funções puras sobre o dicionário + testes. Nada ainda chama esse código (o `install.sh` continua com `jq` até T05).

Por que dividir o F02: o PR inteiro da spec passa de 700 linhas. Aqui ficam as regras de posse e merge, que são o coração do risco.

## Subtasks

- [ ] Criar `Sources/ClaudeBarCore/HookInstaller.swift` com: `HookAction`, `HookInstallError`, `enum HookInstaller` com `settingsURL`, `stableBinary`, `backupsURL`, `legacySuffix`, `struct Entry`, `entries`, e as funções `isOurs`, `strip`, `install`, `parse`, `serialize`, `lineDiff`, `hooksOnly`, `handlers`.
- [ ] **Não** incluir ainda `HookPlan`, `plan`, `apply`, `snippet`, `installBinary`, `isWritable`, `timestamp` (T04) nem `IntegrationState`/`state` (T06).
- [ ] Criar `Tests/ClaudeBarTests/HookInstallerTests.swift` com os helpers e a suíte `HookMergeTests` completa da spec.
- [ ] Conferir a mutação do "bug do Peep": fazer `strip` apagar o grupo inteiro → `grupoMistoPerdeSoONosso` falha. Desfazer.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/HookInstaller.swift` | novo (parte pura) |
| `Tests/ClaudeBarTests/HookInstallerTests.swift` | novo (`HookMergeTests`) |

## Código-chave (copiar da spec, G03 linhas 59–421, só os trechos listados)

Regras que não podem mudar:

```swift
    /// O que o `install.sh` antigo gravava: o hook dentro do bundle.
    static let legacySuffix = "/ClaudeBar.app/Contents/MacOS/claudebar-hook"

    struct Entry {
        let event: String
        let args: [String]
    }

    /// Tudo o que o ClaudeBar registra. F05, H0, F07, F08, F24 acrescentam linhas aqui.
    static let entries = [
        Entry(event: "UserPromptSubmit", args: ["working"]),
        Entry(event: "Stop", args: ["idle"]),
        Entry(event: "Notification", args: ["waiting"]),
        Entry(event: "SessionEnd", args: ["end"]),
    ]

    /// Um handler é do ClaudeBar se o **executável** for exatamente o nosso
    /// (ou o do bundle, legado). Nada de `contains("claudebar")`.
    static func isOurs(_ handler: [String: Any], binary: String) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        let executable: String =
            if handler["args"] != nil { command } // exec form: `command` é só o executável
            else if command.hasPrefix("\"") { String(command.dropFirst().prefix { $0 != "\"" }) }
            else { String(command.prefix { $0 != " " }) }
        return executable == binary || executable.hasSuffix(legacySuffix)
    }

    /// `strip` + os nossos grupos no fim de cada evento. Idempotente; migra legado.
    static func install(_ root: [String: Any], binary: String) -> [String: Any] {
        var root = strip(root, binary: binary)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var handler: [String: Any] = ["type": "command", "command": binary, "args": entry.args]
            // SessionEnd sem `timeout` (subiria o orçamento de saída de toda
            // sessão). Nunca `onFailure`: o indicador não pode bloquear o prompt.
            if entry.event != "SessionEnd" { handler["timeout"] = 5 }
            let groups = hooks[entry.event] as? [[String: Any]] ?? []
            hooks[entry.event] = groups + [["hooks": [handler]]]
        }
        root["hooks"] = hooks
        return root
    }
```

`strip` remove **o handler**, nunca o grupo; grupo vazio sai, evento vazio sai. `parse` devolve `[:]` para arquivo vazio e lança `invalidSettings` para não-objeto ou `hooks` malformado. `serialize` usa `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` + `\n` no fim. `lineDiff` usa `CollectionDifference` da stdlib (código completo na spec).

`settingsURL`, `stableBinary` (`StatusDirectory.url/bin/claudebar-hook`) e `backupsURL` (`StatusDirectory.url/backups`) entram já aqui porque `entries`/testes referenciam o caminho estável.

## Testes obrigatórios

Suíte `HookMergeTests` da spec, inteira: `arquivoAusenteGanhaSoOsNossos`, `formatoDoHandler`, `preservaHookDoUsuarioNoMesmoEvento`, `grupoMistoPerdeSoONosso`, `migraEntradaLegadaDoInstallSh`, `naoTocaEmHookParecido`, `idempotenteEReversivel`, `jsonInvalidoNaoViraPlano`. Helpers `json`, `same`, `handlers` no topo do arquivo (`tempFolder` entra em T04).

## Critérios de aceite

- `install` em settings com hook do usuário no mesmo grupo preserva o hook do usuário.
- `install(install(x)) == install(x)` e `strip(install(x)) == strip(x)`.
- Handlers gravados têm `args`, nenhum tem `onFailure`, `SessionEnd` sem `timeout`.
- `contains("claudebar")` não aparece no arquivo.
- Mutação do grupo inteiro derruba `grupoMistoPerdeSoONosso`.
- `swift build` sem aviso de concorrência (`[String: Any]` só dentro de funções síncronas do Core).

## Gates

`swift build`, `swift test` (34 + 8). Não mexe em scripts.

## README

Nada ainda (o comportamento visível muda em T05).

## Riscos

| Risco | Mitigação |
|---|---|
| Apagar hook do usuário | posse por executável exato + remoção por handler + mutação conferida |
| `JSONSerialization` reordena chaves | avisado em T04/T05 (`reformats`) |

## Fora do escopo

Leitura/escrita de arquivo, backup, cópia do binário (T04); CLI e scripts (T05); detecção de estado (T06); campo `matcher` (T07).
