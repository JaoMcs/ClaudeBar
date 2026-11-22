# T13 — Aviso com som próprio quando a resposta falha

- **Funcionalidade:** F07, parte 2 de 2 (F07.2) — spec [G06, F07.2](../05-specs/G06-erro.md)
- **Épico:** Notificações · **Prioridade:** P1 (recomendada pela spec) · **Esforço:** 1 h
- **Depende de:** T12, T01 · **Bloqueia:** T16, T24
- **Branch:** `feat/aviso-falha`
- **PR:** `feat: aviso com som próprio quando a resposta falha`

## Objetivo

Quem espera o sino do "Claude terminou" hoje não recebe nada quando a resposta falha. Novo aviso `.failed`: título "A resposta do Claude falhou", som `Basso` (volume 1), popup com `exclamationmark.triangle.fill` vermelho. Só na transição `working → error`.

## Subtasks

- [ ] `Notifier.swift` (`Alert`): `case failed` nos três `switch` (`title`, `soundName`, `volume`).
- [ ] `StatusHUD.swift` (`HUDView`): símbolo e `tint` `.red`.
- [ ] `SessionStore.notifyTransitions`: no `case .error`, `post(.failed, …)` se `previous == .working`.
- [ ] `AlertTests`: lista de sons existentes com os 3; `osTresAvisosTocamSonsDiferentes`; título contém "falhou".
- [ ] Verificação manual da spec (popup vermelho + `Basso`; `error` sem `working` antes não avisa; toggle desligado = nada, graças ao T01).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`Notifier.swift`, `StatusHUD.swift`, `SessionStore.swift`, `AlertTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    /// A resposta falhou por erro de API (limite, sobrecarga…): o turno acabou
    /// sem o "terminou" que você esperava.
    case failed
    // title:     case .failed: "A resposta do Claude falhou"
    // soundName: case .failed: "Basso"
    // volume:    case .failed: 1
```

```swift
            case .error:
                acknowledged.remove(row.sessionId)
                if previous == .working {
                    // O código do erro diz se vale reenviar ou esperar o limite.
                    notifier.post(.failed, body: row.message.map { "\(row.name): \($0)" } ?? row.name)
                }
```

HUD: `case .failed: "exclamationmark.triangle.fill"` / `case .failed: .red`.

## Testes obrigatórios

```swift
    @Test func osTresAvisosTocamSonsDiferentes() {
        let sons = [Alert.finished, .waiting, .failed].map(\.soundName)
        #expect(Set(sons).count == 3)
    }
```

`osDoisSonsExistemNoSistema` passa a iterar `[Alert.finished, .waiting, .failed]`; `cadaAvisoTemSeuTitulo` ganha `#expect(Alert.failed.title.contains("falhou"))`.

## Critérios de aceite

- `working → error` mostra o popup vermelho e toca `Basso`.
- `error` sem `working` antes não avisa; subagente não avisa; não repete enquanto continuar em `error`.
- Toggle "Notificações" desligado → nada (teste do T01 verde).
- `swift test` = anterior + 1.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

Tabela de alertas: linha `working → failed` | "A resposta do Claude falhou" + projeto e código do erro | `Basso` | 100%. "There are two alerts" → "three alerts".

## Riscos

Rate limit em várias sessões ao mesmo tempo → vários sons: o `play` rebobina o mesmo `NSSound` e o HUD reaproveita o painel. Aceito.

## Fora do escopo

Toggle só para este aviso (T24 cobre por tipo), retry/ação no popup.
