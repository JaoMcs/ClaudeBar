# T27 — Modo "nunca mostrar conteúdo"

- **Funcionalidade:** F25 — spec [G10, F25](../05-specs/G10-ajustes-privacidade.md)
- **Épico:** UI/Ajustes · **Prioridade:** P2 (inovação) · **Esforço:** 1 h
- **Depende de:** T24, T26 · **Bloqueia:** —
- **Branch:** `feat/modo-sem-conteudo`
- **PR:** `feat: modo para nunca mostrar o conteúdo da mensagem`

## Objetivo

Toggle **Nunca mostrar o conteúdo da mensagem** nos Ajustes, desligado por padrão. Ligado, todo aviso de espera (transição, lembrete, exemplo) mostra `"<projeto> precisa de você"` no lugar da `message` do Claude ("Claude needs your permission to use Bash: …"). Vale para o popup, para o anúncio do VoiceOver (que reusa o `body`) e para a notificação nativa futura. Passa a valer no próximo aviso, sem reiniciar.

## Ajuste sobre a spec

Com T26 em `main`, o lembrete também passa por `waitingBody`. O aviso `.failed` (T13) e o submenu de erro (T12) mostram o **código da API** (`rate_limit — 429`), que não é conteúdo da conversa: ficam como estão, e isso vai escrito no README.

## Subtasks

- [ ] `SessionRow.waitingBody(hidingContent:)`.
- [ ] `Notifier`: `hideContentKey`, `hidesContent` lido na hora; `showSample` respeita o modo.
- [ ] `SessionStore`: `notifyTransitions` (caso de espera) e `remindWaiting` usam `waitingBody(hidingContent: notifier.hidesContent)`.
- [ ] `SettingsWindow`: toggle + legenda na seção "Avisos".
- [ ] Testes (3).
- [ ] Verificação manual 1–4 da spec (inclui `log show` sem o texto da mensagem).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionRow.swift`, `SessionStore.swift`, `Notifier.swift`, `SettingsWindow.swift`, `AlertTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    /// Texto do aviso de espera. Com "nunca mostrar conteúdo" ligado, a mensagem
    /// do Claude (que pode citar comando, arquivo ou pergunta) não é desenhada.
    func waitingBody(hidingContent: Bool) -> String {
        hidingContent ? "\(name) precisa de você" : message ?? name
    }
```

```swift
    static let hideContentKey = "hideContent"
    /// Lido na hora, sem cópia, para valer no próximo aviso sem reiniciar.
    var hidesContent: Bool { defaults.bool(forKey: Self.hideContentKey) }

    func showSample() {
        post(.permission, body: hidesContent
            ? "Exemplo: meu-projeto precisa de você"
            : "Exemplo: Claude needs your permission to use Bash")
    }
```

```swift
                notifier.post(Alert(waiting: row.kind),
                              body: row.waitingBody(hidingContent: notifier.hidesContent), …)
                // lembrete:
                body: "Ainda esperando: \(row.waitingBody(hidingContent: notifier.hidesContent))"
```

```swift
    @AppStorage(Notifier.hideContentKey) private var hideContent = false
                Toggle("Nunca mostrar o conteúdo da mensagem", isOn: $hideContent)
                Text("O aviso diz só \"<projeto> precisa de você\". Útil ao compartilhar a tela.")
                    .font(.caption).foregroundStyle(.secondary)
```

## Testes obrigatórios

`modoSemConteudoEscondeAMensagem`, `semMensagemUsaONome`, `modoSemConteudoLidoNaHora` (da spec, com `scratchDefaults()` do T24).

## Critérios de aceite

- `grep -rn "row\.message" Sources/ClaudeBar` só encontra `SessionRow.waitingBody` e os dois usos do **código de erro** (submenu de `.error` e corpo do `.failed`). Nenhum `post` de espera recebe `row.message` direto.
- Modo desligado = comportamento atual byte a byte (`message ?? name`).
- Ligar/desligar vale no próximo aviso sem reiniciar.
- Nenhum uso de `sharingType`; nenhum `Logger` com `body`.
- `swift test` = anterior + 3.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

Alerts: bullet da spec ("replaces Claude's message with "<project> precisa de você"… macOS no longer honours "hide this window from screen capture"… The message is still stored in the state file (`0600`)… error codes are not conversation content and stay visible"). Security: "**Optional "never show content" mode** — see Alerts."

## Riscos

| Risco | Mitigação |
|---|---|
| Feature futura exibir `row.message` direto | critério do grep; revisor recusa |
| Achar que o modo apaga o dado do disco | README diz que só muda a exibição |
| Nome do projeto também ser sensível | fora do escopo; um `if` se o usuário pedir |

## Fora do escopo

`NSWindow.sharingType`; o hook ler preferências do app ou deixar de gravar `message`; esconder `cwd`/nome; "modo privacidade" com várias chaves.
