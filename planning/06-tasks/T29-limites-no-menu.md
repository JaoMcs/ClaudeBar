# T29 — Limites 5 h e semanal no menu

- **Funcionalidade:** F22, parte 2 de 3 (F22.2) — spec [G11, F22.2](../05-specs/G11-limites.md)
- **Épico:** Limites · **Prioridade:** P1 · **Esforço:** 1 h
- **Depende de:** T28 · **Bloqueia:** T31
- **Branch:** `feat/limites-no-menu`
- **PR:** `feat: limites de 5 h e semanal no menu`

## Objetivo

O topo do menu mostra `Limite 5 h: 23% · renova 14:30`, `Semanal: 41% · renova sex., 09:00` e `Atualizado há 3 min`. Sem dado, "indisponível", nunca 0%. Janela já renovada: "renovado, aguardando dado novo".

## Subtasks

- [ ] `SessionStore`: `private(set) var limits: RateLimits?`, lido no fim de `merge()` (mesmo diretório e watcher; nada novo a observar).
- [ ] `MenuContent`: `static func limitLines(_:now:)` e as linhas + `Divider()` no começo do `body`.
- [ ] Testes `menuSemDadoDizIndisponivel` e `menuJanelaRenovada` em `RateLimitsTests.swift`.
- [ ] Verificação manual 1–4 da spec (o 4 confirma ou desmente "conteúdo montado ao abrir"; registrar).
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`SessionStore.swift`, `MenuContent.swift`, `RateLimitsTests.swift`, READMEs.

## Código-chave (da spec)

```swift
    /// Linhas dos limites no topo do menu. Sem dado é "indisponível", nunca 0%.
    static func limitLines(_ limits: RateLimits?, now: Date) -> [String] {
        guard let limits else { return ["Limites de uso: indisponível"] }

        func line(_ title: String, _ window: RateWindow?) -> String {
            guard let window else { return "\(title): indisponível" }
            // Depois do reset o número velho não vale; o novo chega com a próxima resposta.
            guard window.resetsAt > now else { return "\(title): renovado, aguardando dado novo" }
            let reset = Calendar.current.isDate(window.resetsAt, inSameDayAs: now)
                ? window.resetsAt.formatted(date: .omitted, time: .shortened)
                : window.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return "\(title): \(window.displayPercent)% · renova \(reset)"
        }

        var lines = [line("Limite 5 h", limits.fiveHour), line("Semanal", limits.sevenDay)]
        if let updatedAt = limits.updatedAt {
            lines.append("Atualizado \(relativeFormatter.localizedString(for: updatedAt, relativeTo: now))")
        }
        return lines
    }
```

```swift
    var body: some View {
        ForEach(Self.limitLines(store.limits, now: Date()), id: \.self) { line in
            Text(line)
        }
        Divider()
        // … resto igual …
```

## Testes obrigatórios

```swift
    @Test func menuSemDadoDizIndisponivel() {
        #expect(MenuContent.limitLines(nil, now: Date()) == ["Limites de uso: indisponível"])
        let lines = MenuContent.limitLines(RateLimits(updatedAt: Date()), now: Date())
        #expect(lines[0] == "Limite 5 h: indisponível")
        #expect(lines[1] == "Semanal: indisponível")
        #expect(!lines.contains { $0.contains("0%") })
    }

    @Test func menuJanelaRenovada() {
        let now = Date()
        let limits = RateLimits(fiveHour: RateWindow(usedPercentage: 90, resetsAt: now.addingTimeInterval(-60)))
        #expect(MenuContent.limitLines(limits, now: now)[0] == "Limite 5 h: renovado, aguardando dado novo")
    }
```

Não testar o texto exato da hora (depende do locale). Os testes comparam texto pt: o T34 troca para o inglês.

## Critérios de aceite

- Sem dado, nenhuma linha com "%". Com dado, percentual inteiro 0–100.
- Janela vencida nunca mostra o número antigo.
- Nenhum `Timer`/`DirectoryWatcher`/`TimelineView` novo no diff.
- `swift test` = anterior + 2.

## Gates

`swift build`, `swift test`.

## README (as duas línguas)

Na lista do que o menu mostra: limites de 5 h e semanal (%, hora de renovação, idade do dado) ou "indisponível"; como ligar fica para o T30.

## Riscos

- Idade parada com o menu aberto: aceito (fechar e abrir atualiza).
- Quem nunca instalou o statusline vê "Limites de uso: indisponível": decisão de UX mantida da spec (mostra que a função existe).

## Fora do escopo

Percentual no ícone/título da barra (F31/F32), `TimelineView`, timer novo, 0% sem dado.
