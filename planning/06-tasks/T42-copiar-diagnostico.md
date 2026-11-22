# T42 — "Copiar diagnóstico"

- **Funcionalidade:** F52 (suporte) — texto para colar em issue sem vazar dado pessoal
- **Esforço:** 2 h
- **Depende de:** T30 · **Bloqueia:** —
- **Branch:** `feat/copiar-diagnostico`
- **PR:** `feat: item de menu Copiar diagnóstico`

## Objetivo

Item de menu que monta um texto curto para colar numa issue: versão do app, versão do macOS, `IntegrationState`, quantas sessões em cada estado e os caminhos usados, **anonimizados** (`~` no lugar do home; nenhum nome de projeto, nenhum `cwd`). Antes de copiar, mostra a prévia num alerta (Copiar / Cancelar), como já se faz com a prévia dos hooks. Nada sai do computador sozinho.

## Subtasks

- [ ] `Sources/ClaudeBarCore/Diagnostics.swift` (novo), função **pura**: `Diagnostics.text(appVersion:osVersion:integration:counts:paths:home:) -> String`. `counts` é `[SessionState: Int]` (ordem fixa de `SessionState.allCases`); `integration` é o `IntegrationState` em texto estável (`String(describing:)`, em inglês, sem `String(localized:)` para ficar legível em issue).
- [ ] `Diagnostics.anonymize(_ path: String, home: String) -> String`: troca o prefixo `home` por `~` só em fronteira de pasta (`/Users/ana` não casa com `/Users/ana2`), e o nome de usuário solto em qualquer outro caminho não é mantido.
- [ ] Caminhos incluídos: `HookInstaller.settingsURL`, `HookInstaller.stableBinary`, `StatusDirectory.url`. Nenhum `cwd` de sessão, nenhum nome de projeto, nenhuma mensagem.
- [ ] Versão do app: `Bundle.main` `CFBundleShortVersionString` (`"dev"` sem bundle, como no "Sobre" de `SettingsView`); macOS: `ProcessInfo.processInfo.operatingSystemVersionString`.
- [ ] `MenuContent.swift`: botão "Copiar diagnóstico…" no bloco da integração (perto de "Test integration"). Ação em `SessionStore` ou `HookSetup`: monta o texto com `hookSetup.state` e contagem de `rows` (só `!isSubagent`? contar tudo e separar subagentes em linha própria), mostra `NSAlert` com a prévia (fonte monoespaçada em `accessoryView` rolável, `window.level = .floating` + `NSApplication.shared.activate()` como `HookSetup.runInFront`), e só em "Copiar" escreve em `NSPasteboard.general`.
- [ ] Strings do menu e do alerta em `en.lproj` e `pt-BR.lproj`.
- [ ] Testes (`Tests/ClaudeBarTests/DiagnosticsTests.swift`, novo): home vira `~`; `/Users/ana2` não casa com home `/Users/ana`; caminho fora do home fica inalterado; texto final não contém o home, nem `cwd` passado de propósito; contagens na ordem de `SessionState.allCases`; zero sessões imprime zeros.
- [ ] READMEs: uma linha em "Troubleshooting"/integração dizendo o que entra e o que não entra no texto.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/Diagnostics.swift` | novo, funções puras |
| `Sources/ClaudeBar/MenuContent.swift` | botão |
| `Sources/ClaudeBar/SessionStore.swift` ou `Sources/ClaudeBar/HookSetup.swift` | monta, mostra a prévia, copia |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | strings |
| `Tests/ClaudeBarTests/DiagnosticsTests.swift` | novo |
| `README.md`, `README.pt-BR.md` | uma linha |

## Critérios de aceite

- O texto copiado é exatamente o da prévia; cancelar não toca na área de transferência.
- Nenhum nome de usuário, projeto, `cwd`, branch, mensagem ou conteúdo de conversa no texto.
- Nenhuma rede, nenhuma escrita em disco.
- `swift build` e `swift test` verdes (anterior + novos).

## Fora do escopo

Enviar o diagnóstico, anexar log do `OSLog`, incluir o JSON do `settings.json` (pode ter `env` com token).
