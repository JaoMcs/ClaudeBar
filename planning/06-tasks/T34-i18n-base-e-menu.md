# T34 — Inglês + português: base, menu, barra e avisos

- **Funcionalidade:** F21, parte 1 de 2 — spec [G12, F21](../05-specs/G12-a11y-i18n.md)
- **Épico:** i18n/a11y · **Prioridade:** P1 · **Esforço:** 2 h
- **Depende de:** T32 (pasta `Resources/` e o `build-app.sh` com o ícone) e todas as tasks de UI (T01–T31) · **Bloqueia:** T35
- **Branch:** `feat/i18n-menu`
- **PR:** `feat: app em inglês e português (menu, barra e avisos)`

## Objetivo

O app segue o idioma do Mac: português para `pt-BR` (e `pt-PT`), inglês para qualquer outro. A chave é o texto em inglês. Esta parte monta a infraestrutura e converte **menu, barra, legenda, VoiceOver e popups**. Diálogos (`NSAlert`), Ajustes, integração e limites ficam no T35, logo em seguida (os dois PRs são consecutivos; nenhum release sai entre eles).

Default proposto (BACKLOG): segue o sistema, fallback inglês. Se o usuário vetar depois, troca-se só `CFBundleDevelopmentRegion` e o `en.lproj` (descrito na spec). Não bloqueia.

## Subtasks

- [ ] `Resources/en.lproj/Localizable.strings` (só o comentário) e `Resources/pt-BR.lproj/Localizable.strings`.
- [ ] `scripts/build-app.sh`: `plutil -lint` das duas tabelas e `cp -R Resources/en.lproj Resources/pt-BR.lproj "$BUNDLE/Contents/Resources/"` antes do `codesign` (depois do `cp` do ícone); `CFBundleDevelopmentRegion` → `en`.
- [ ] `MenuContent`: remover `formatter.locale = Locale(identifier: "pt_BR")`; literais em inglês; `String(localized:)` em `description(for:)`, `[subagent]`, legenda.
- [ ] `SessionStore` (`BarState.title`, `accessibilityLabel`): `String(localized:)`.
- [ ] `Notifier`/`Alert`: títulos (`finished`, `waiting`, `permission`, `question`, `failed`), `showSample`, corpo do lembrete ("Still waiting: %@") e do modo sem conteúdo ("%@ needs you").
- [ ] Tabela pt-BR com **todas** as chaves usadas por esses arquivos (base da spec + strings de T12, T13, T16, T17, T26, T27, T31).
- [ ] `LocalizationTests.swift` novo (3) e atualizar os testes que comparam texto (`AlertTests`, `AccessibilityTests` se preciso).
- [ ] Verificação 1–5 da spec, limitada ao menu/barra/popups (`-AppleLanguages '(pt-BR)' -NSShowNonLocalizedStrings YES`: nada em MAIÚSCULAS no menu, legenda, rótulo da barra e popup de exemplo; `(en)`/`(fr)` tudo em inglês, inclusive "2 min ago"; `(pt-PT)` em pt-BR).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`Resources/{en,pt-BR}.lproj/Localizable.strings` (novos), `scripts/build-app.sh`, `MenuContent.swift`, `SessionStore.swift` (`BarState`), `Notifier.swift`, `SessionRow.swift` (`waitingBody`), `SessionStore.swift` (corpo do lembrete), `LocalizationTests.swift` (novo), `AlertTests.swift`, READMEs.

## Código-chave (da spec)

```bash
# Traduções (Bundle.main). Valida antes: .strings quebrado não dá erro em
# runtime, só mostra a chave em inglês. Copiar antes de assinar.
plutil -lint Resources/en.lproj/Localizable.strings Resources/pt-BR.lproj/Localizable.strings
cp -R Resources/en.lproj Resources/pt-BR.lproj "$BUNDLE/Contents/Resources/"
```

```swift
    var title: String {
        switch self {
        case .waiting: String(localized: "Claude is waiting for you")
        case .done: String(localized: "Reply ready, not seen yet")
        case .working: String(localized: "Claude is working")
        case .idle: String(localized: "Nothing going on")
        // + permission, question, error
        }
    }

    func accessibilityLabel(openSessions: Int) -> String {
        String(localized: "ClaudeBar. Sessions: \(openSessions). \(title)")
    }
```

Regras: literal em `Text`/`Button`/`Toggle`/`Menu` basta trocar para o inglês (`LocalizedStringKey` acha no `Bundle.main`); `Text(variavel)` **não** traduz, então funções que montam texto devolvem `String(localized:)`. PID entra como `String(pid)` (senão "kill 4.321"). Caminho/id fora da chave. Sem plural, sem `bundle:`/`locale:`.

`en.lproj`:

```
/* Vazio de propósito: a chave já é o texto em inglês. A pasta existe para o
   macOS saber que o app fala inglês e cair nele quando o idioma do Mac não
   for português. */
```

## Testes obrigatórios

`LocalizationTests` da spec: `tabelaEmPortuguesTemOsMesmosMarcadoresDaChave`, `tabelaEmInglesEhValida`, `textosDosEstadosEAvisosTemTraducao` (todos os `BarState.allCases.map(\.title)` + todos os `Alert` títulos). `AlertTests`: `Alert.finished.title == "Claude finished"`, `Alert.waiting.title.contains("waiting")` (no `swift test` não há `.lproj`: volta a chave). Nenhum teste removido; os que comparavam pt passam a comparar o inglês.

## Critérios de aceite

- `build-app.sh` gera `Contents/Resources/en.lproj` e `pt-BR.lproj`, `CFBundleDevelopmentRegion = en`, assinatura válida.
- `grep -rn 'Locale(identifier' Sources` vazio.
- Com `(pt-BR)` + `-NSShowNonLocalizedStrings YES`, nada em MAIÚSCULAS no menu, barra, legenda e popups.
- Com `(en)`/`(fr)`, tudo isso em inglês, inclusive a data relativa.
- `Package.swift` não muda.
- `swift test` = anterior + 3.

## Gates

`swift build`, `swift test`, `bash -n scripts/*.sh`, `./scripts/build-app.sh`, `codesign --verify --deep --strict build/ClaudeBar.app`.

## README (as duas línguas)

"The app's menu and popups are in Portuguese." → "The app follows your Mac's language: Portuguese (Brazil) or English for any other language. After changing the macOS language, quit and reopen ClaudeBar." Exemplo do menu em inglês no README.md e em pt no README.pt-BR. Project structure: `Resources/*.lproj/   translations (key = English text; en.lproj empty on purpose)`. Development: como achar texto sem tradução (`-NSShowNonLocalizedStrings YES`) e a regra "UI nova é escrita em inglês + linha no pt-BR".

## Riscos

| Risco | Mitigação |
|---|---|
| Marcador trocado na tradução | `tabelaEmPortuguesTemOsMesmosMarcadoresDaChave` |
| Chave de várias linhas divergir | aparece em inglês, nunca crasha; `-NSShowNonLocalizedStrings` mostra |
| UI mista entre T34 e T35 | PRs consecutivos, sem release no meio |

## Fora do escopo

Diálogos, `SessionTerminator`, `HookSetup`, `SettingsWindow`, limites (T35); `Bundle.module`, `.xcstrings`, `.stringsdict`; seletor de idioma; traduzir `message` do Claude, logs, stderr do hook.
