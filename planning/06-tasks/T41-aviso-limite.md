# T41 — Aviso único quando a janela de 5 h passa de um limiar

- **Funcionalidade:** F51 (extensão da F20, limites) — aviso opt-in
- **Esforço:** 2 h
- **Depende de:** T28, T29 · **Bloqueia:** —
- **Branch:** `feat/aviso-limite`
- **PR:** `feat: aviso quando o limite de 5 h passa de um percentual`

## Objetivo

Avisar uma vez por janela de 5 h quando o uso cruza um limiar (padrão 80%). Usa o `RateLimits` que o app já lê (`StatusDirectory.readLimits()` em `SessionStore.merge()`, campo `limits.fiveHour`: `RateWindow.usedPercentage` e `resetsAt`). Configurável nos Ajustes, **padrão desligado**. Sem dado novo, sem rede.

## Subtasks

- [ ] Função pura em `Sources/ClaudeBarCore/RateLimits.swift`: `RateWindow.crossedThreshold(_ percent: Double, alertedWindow: Date?, now: Date) -> Bool`. Verdadeiro só quando `usedPercentage >= percent`, `resetsAt > now` (janela renovada não vale) e `alertedWindow != resetsAt` (um aviso por janela).
- [ ] `SessionStore`: guardar `limitAlertedWindow: Date?` (o `resetsAt` já avisado). Em `merge()`, depois de ler `limits`, chamar a função e postar o aviso; ao postar, gravar `resetsAt`. Reset da janela (novo `resetsAt`) zera sozinho, pois a comparação é por `resetsAt`.
- [ ] Aviso: reaproveitar o popup/notificação do `Notifier.post` com tipo novo `Alert.limit` (título, som, `enabledKey` próprio, `staysUntilAnswered = false`); respeita o toggle geral do menu e "Nunca mostrar o conteúdo" (texto genérico, sem número, nesse modo).
- [ ] `SettingsWindow.swift`: `Toggle` "Avisar quando o limite de 5 h passar de" (padrão `false`) + `Stepper` de 50 a 95% (padrão 80), desabilitado com o toggle desligado. Chaves novas em `Notifier` ao lado de `reminderEnabledKey`. Strings em `en.lproj` e `pt-BR.lproj`.
- [ ] Persistir `limitAlertedWindow` em `UserDefaults` para não repetir o aviso ao reabrir o app na mesma janela.
- [ ] Testes (`RateLimitsTests.swift`): abaixo do limiar = não; cruzou = sim; já avisado na mesma `resetsAt` = não; nova `resetsAt` = sim de novo; janela já vencida (`resetsAt <= now`) = não; exatamente no limiar = sim.
- [ ] `AlertTests.swift`: o tipo novo respeita o toggle geral e o seu próprio.
- [ ] READMEs: uma linha em limites e em Ajustes.
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/RateLimits.swift` | `crossedThreshold` pura |
| `Sources/ClaudeBar/SessionStore.swift` | checagem em `merge()`, `limitAlertedWindow` |
| `Sources/ClaudeBar/Notifier.swift` | `Alert.limit`, chaves de `UserDefaults` |
| `Sources/ClaudeBar/SettingsWindow.swift` | toggle + `Stepper` |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | strings novas |
| `Tests/ClaudeBarTests/RateLimitsTests.swift`, `Tests/ClaudeBarTests/AlertTests.swift` | testes |
| `README.md`, `README.pt-BR.md` | duas linhas |

## Critérios de aceite

- Desligado por padrão; ligado, no máximo um aviso por janela de 5 h.
- Janela vencida ou sem dado (`limits == nil`, `fiveHour == nil`) nunca avisa.
- Nenhuma rede nova; só o que o `statusline` já grava.
- `swift build` e `swift test` verdes (anterior + novos).

## Fora do escopo

Janela semanal, vários limiares, aviso do tempo restante, ação automática ao cruzar.
