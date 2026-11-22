# T26 — Lembrete único de espera

- **Funcionalidade:** F13 — spec [G09, F13](../05-specs/G09-popup-lembrete.md) (com a regra de [G10](../05-specs/G10-ajustes-privacidade.md): o controle vai para os Ajustes)
- **Épico:** Notificações · **Prioridade:** P1 · **Esforço:** 1,5 h
- **Depende de:** T24 (janela de Ajustes), T17 (popup persistente), T20, T21 (assinatura de `post`) · **Bloqueia:** T27
- **Branch:** `feat/lembrete-espera`
- **PR:** `feat: lembrete único para sessão esperando você`

## Objetivo

Sessão sua parada em espera há N minutos (padrão 5) recebe **um** lembrete: o mesmo aviso de espera do tipo dela, com "Ainda esperando: …". Sair da espera cancela; um novo episódio ganha lembrete novo. Desligável e com minutos ajustáveis nos **Ajustes** (não no menu).

## Ajustes sobre a spec G09

- Toggle e minutos na `SettingsView` (seção "Avisos"), não o `Toggle` provisório do menu: `Toggle("Lembrar uma vez se continuar esperando", …)` + `Stepper("Depois de \(minutes) min", value: $minutes, in: 1...60)`.
- `previousStates` não existe mais (T16 trocou por `previousRows`): passar `previousRows.mapValues(\.state)` para `dueReminders`.
- O lembrete usa `Alert(waiting: row.kind)`, `sessionId`, `playSound: !isLookingAt(row)` e `onOpen` (vai à sessão), como os avisos de transição.
- Cadência: depois do T14 o `merge()` roda a cada evento e a cada 60 s. O lembrete pode atrasar até ~1 min além de N. Aceito; README diz "about 5 minutes".

## Subtasks

- [ ] `SessionMerge.dueReminders(rows:previous:reminded:now:delay:)` e `reminderKey(_:)` (puras).
- [ ] `Notifier`: chaves `waitingReminderEnabled` (padrão `true`) e `waitingReminderMinutes` (padrão `5`) no `register`; `isReminderEnabled` e `reminderMinutes` **lidos na hora** de `defaults` (`max(…, 1)`), sem cópia — mesmo modelo do T24.
- [ ] `SessionStore`: `reminded: Set<String>`; `remindWaiting(in:)` chamado logo depois de `notifyTransitions` e **antes** de `previousRows` ser reescrito.
- [ ] `SettingsWindow`: toggle + stepper (`@AppStorage`).
- [ ] `WaitingReminderTests` (6) em `SessionMergeTests.swift`.
- [ ] Mutação: tirar `previous[...] == .waiting` → `naoDisparaNaRodadaDaTransicao` falha.
- [ ] Verificação manual 1–8 da spec (com 1 min; espere até ~2 min por causa do timer de 60 s).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionMerge.swift`, `SessionStore.swift`, `Notifier.swift`, `SettingsWindow.swift`, `SessionMergeTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    static func dueReminders(rows: [SessionRow], previous: [String: SessionState],
                             reminded: Set<String>, now: Date, delay: TimeInterval) -> [SessionRow] {
        rows.filter { row in
            guard !row.isSubagent,
                  row.state == .waiting,
                  previous[row.sessionId] == .waiting,
                  let since = row.updatedAt,
                  let key = reminderKey(row)
            else { return false }
            return now.timeIntervalSince(since) >= delay && !reminded.contains(key)
        }
    }

    /// Um episódio de espera: a sessão + quando ela entrou em `waiting`.
    static func reminderKey(_ row: SessionRow) -> String? {
        row.updatedAt.map { "\(row.sessionId)|\($0.timeIntervalSince1970)" }
    }
```

```swift
    private func remindWaiting(in merged: [SessionRow]) {
        // Esquece episódios encerrados: a sessão saiu de `waiting` ou sumiu.
        reminded.formIntersection(merged.filter { $0.state == .waiting }.compactMap(SessionMerge.reminderKey))
        guard notifier.isReminderEnabled else { return }
        let due = SessionMerge.dueReminders(
            rows: merged, previous: previousRows.mapValues(\.state), reminded: reminded,
            now: Date(), delay: TimeInterval(notifier.reminderMinutes * 60))
        reminded.formUnion(due.compactMap(SessionMerge.reminderKey))
        for row in due {
            notifier.post(Alert(waiting: row.kind), body: "Ainda esperando: \(row.message ?? row.name)",
                          sessionId: row.sessionId, playSound: !isLookingAt(row),
                          onOpen: { [weak self] in self?.goToSession(row) })
        }
    }
```

O `guard isEnabled` do `post` (T01/T24) já cala o lembrete com Notificações desligado.

## Testes obrigatórios

`WaitingReminderTests` da spec: `disparaAosCincoMinutosNaoAntes`, `lembraUmaVezSo`, `novoEpisodioGanhaNovoLembrete`, `transicaoCancela`, `naoDisparaNaRodadaDaTransicao`, `subagenteNaoLembra`. Em `AlertTests`: `minutosInvalidosViramUm` (suíte descartável, `waitingReminderMinutes = 0` → `reminderMinutes == 1`).

## Critérios de aceite

- `dueReminders`/`reminderKey` puras (sem `Date()`, disco ou `UserDefaults`).
- No máximo 1 lembrete por `sessionId|updatedAt`; nenhum para subagente; nenhum na rodada da transição.
- Lembrete desligado ou Notificações desligado → nenhum lembrete, nenhum som.
- Nenhum `Timer`, `Task` ou `DispatchSource` novo.
- `swift test` = anterior + 7.

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Alerts: "**Reminder.** A session still waiting for you after about 5 minutes gets one more alert ("Ainda esperando: …", same sound). Answering cancels it; a new wait gets a new reminder. Turn it off or change the delay in **Ajustes…**."

## Riscos

| Risco | Mitigação |
|---|---|
| Lembrete chato | um por episódio, desligável, ajustável |
| Lembrete sobre `waiting` falso | T07/T09 eliminam os casos conhecidos; pior caso é 1 lembrete |
| `reminded` crescer | podado a cada `merge()` |
| Sessão só do CLI em `waiting` (`updatedAt` = início) | lembrete único no 2º merge; raro com hooks; `ponytail:` no código |

## Fora do escopo

Timer por sessão, repetir o lembrete (F36/F50), persistir `reminded`, `Alert.reminder`/som novo, ler transcript.
