# T35 — Inglês + português: diálogos, Ajustes, integração e limites

- **Funcionalidade:** F21, parte 2 de 2 — spec [G12, F21](../05-specs/G12-a11y-i18n.md)
- **Épico:** i18n/a11y · **Prioridade:** P1 · **Esforço:** 1,5 h
- **Depende de:** T34 · **Bloqueia:** — (última task da rodada)
- **Branch:** `feat/i18n-dialogos`
- **PR:** `feat: app em inglês e português (diálogos, Ajustes e integração)`

## Objetivo

Terminar a tradução: tudo o que sobrou em pt-BR literal no app (`NSAlert`s, finalizar sessão, ir para a sessão, abrir pasta, integração com o Claude Code, teste da integração, janela de Ajustes, Sobre, limites no menu) vira chave em inglês + linha no `pt-BR.lproj`. No fim, a varredura não acha mais string de UI em português no código.

## Subtasks

- [ ] `SessionStore`: `confirmTermination` (cwd **fora** da chave, `String(pid)`), `report` de finalizar/ir para a sessão/abrir pasta.
- [ ] `SessionTerminator`: `actionTitle`, `unavailableReason`, mensagens de `.failed` (`String(pid)`, `errno` como `%d`).
- [ ] `HookSetup`: `menuTitle`, `summary`, alertas, botões, linhas ✓/✗ do teste, dica de workspace trust; textos do statusline (T30).
- [ ] `HookInstallError.errorDescription` (Core): `String(localized:)` (no app acha a tradução; no CLI cai na chave em inglês, que é o esperado para stderr).
- [ ] `SettingsWindow`: título, seções, toggles, pickers, stepper do lembrete, modo sem conteúdo, login, Sobre (créditos).
- [ ] `MenuContent.limitLines`: textos dos limites (`%@` para a hora formatada).
- [ ] Atualizar testes que comparam texto: `SessionTerminatorTests` (linhas 51, 59, 72 da spec → "Desktop app", "Claude app", `"Terminate session (kill 4321)"`), `RateLimitsTests` (`limitLines` em inglês).
- [ ] Varredura (abaixo) e passo com `-NSShowNonLocalizedStrings YES` abrindo **todos** os diálogos e a janela de Ajustes.
- [ ] READMEs (exemplos de diálogo, se houver).
- [ ] Gates, commit, PR.

## Arquivos

`SessionStore.swift`, `SessionTerminator.swift`, `HookSetup.swift`, `ClaudeBarCore/HookInstaller.swift` (erros), `SettingsWindow.swift`, `MenuContent.swift` (limites), `Resources/pt-BR.lproj/Localizable.strings`, `SessionTerminatorTests.swift`, `RateLimitsTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    private func confirmTermination(of row: SessionRow) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Terminate \(row.name)?")
        // O caminho fica fora da tradução: chave com caminho nunca seria encontrada.
        let consequence: String? = switch SessionTerminator.target(for: row) {
        case .signal(let pid):
            // `String(pid)`: número em `String(localized:)` sai com separador de milhar.
            String(localized: """
            Process \(String(pid)) gets SIGTERM. The conversation is kept (resume it \
            with `claude --resume`), but whatever is running stops right away and \
            the terminal is left with an empty shell.
            """)
        case .backgroundStop(let id):
            String(localized: """
            `claude stop \(id)` ends the agent and keeps the conversation: you can \
            resume it later with `claude attach \(id)`.
            """)
        case .hostedByApp, .unavailable:
            nil
        }
        alert.informativeText = [row.cwd, consequence].compactMap(\.self).joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Terminate"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        // … activate + runModal como hoje …
    }
```

```swift
        case .signal(let pid): String(localized: "Terminate session (kill \(String(pid)))")
        case .backgroundStop(let id): String(localized: "Terminate subagent (claude stop \(id))")
```

Linhas da tabela pt-BR para os diálogos de finalizar estão prontas na spec (G12, bloco "Finalizar sessão"); as de integração, Ajustes, limites, ir para a sessão e abrir pasta são escritas aqui seguindo o texto pt atual.

## Varredura obrigatória antes do PR

```bash
grep -rnE '"[^"]*[ãáâàçéêíóôõúÃÁÂÇÉÊÍÓÔÕÚ][^"]*"' Sources/ClaudeBar Sources/ClaudeBarCore | grep -v 'log\.'
grep -rnE '"[^"]*[ãáâàçéêíóôõúÃÁÂÇÉÊÍÓÔÕÚ][^"]*"' Tests | grep -v '//\|Issue.record\|@Suite\|"\\('
```

Só pode sobrar comentário, log e stderr do `claudebar-hook` (CLI não é traduzido). Palavras sem acento ("pronto", "Finalizar") não aparecem no grep: a prova final é o `-NSShowNonLocalizedStrings YES` com cada tela aberta.

## Testes obrigatórios

Os 3 de `LocalizationTests` (T34) continuam verdes com a tabela maior (pegam marcador trocado ou valor vazio). Asserts de texto atualizados para o inglês. `sessaoDeTerminalUsaSigtermNoPid` protege contra "kill 4.321".

## Critérios de aceite

- Varredura só devolve comentários, logs e stderr do hook.
- Com `(pt-BR)` + `-NSShowNonLocalizedStrings YES`, nada em MAIÚSCULAS em: diálogo de finalizar (cancelar), "não foi possível ir até…", "não foi possível abrir a pasta", integração (menu e alerta), teste da integração, Ajustes, Sobre, limites.
- Com `(en)`/`(fr)`, tudo em inglês.
- Títulos de finalizar mostram o PID sem separador ("kill 4321").
- `swift test` verde, nenhum teste removido.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`, `codesign --verify --deep --strict build/ClaudeBar.app`.

## README (as duas línguas)

Exemplos de diálogo/menu no README.md em inglês, no README.pt-BR em português. Conferir que nenhuma seção ainda diz "the app is in Portuguese".

## Riscos

| Risco | Mitigação |
|---|---|
| Chave de várias linhas não casar | aparece em inglês, o passo com `-NSShowNonLocalizedStrings` mostra |
| Erro do Core no CLI sair em inglês | esperado: stderr do hook não é UI |
| Teste do usuário com Mac em outro idioma | README manda reabrir o app depois de trocar o idioma |

## Fora do escopo

Traduzir `message` do Claude, logs `OSLog`, stderr do hook, comentários; `.stringsdict`; seletor de idioma; chaves simbólicas (`"menu.refresh"`).
