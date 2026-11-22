# T28 — Limites: `claudebar-hook statusline` (grava `limits.json`, encadeia o original)

- **Funcionalidade:** F22, parte 1 de 3 (F22.1) — spec [G11, F22.1](../05-specs/G11-limites.md)
- **Épico:** Limites · **Prioridade:** P1 (método inédito: sem login, sem rede) · **Esforço:** 2,5 h
- **Depende de:** T08 (`readAll(in:isAlive:)`), T22 (mesmo `main.swift`) · **Bloqueia:** T29, T30
- **Branch:** `feat/limites-statusline`
- **PR:** `feat: ler limites de uso pelo statusline, sem rede`

## Objetivo

Toda vez que o Claude Code atualiza o rodapé, `claudebar-hook statusline` grava `rate_limits.five_hour`/`seven_day` em `~/.claude/claudebar/limits.json` (atômico, `0600`) e devolve exatamente o que o statusline anterior do usuário devolveria. Sem rede, sem OAuth, sem Keychain, sem ler conversa. Ninguém instala ainda (T30); dá para testar editando o settings à mão.

## Ajustes sobre a spec

- `readAll` já é `readAll(in:isAlive:)` (T08): trocar o `.filter { $0.pathExtension == "json" }` dele por `.filter(isSessionFile)`.
- No `main.swift`, `statusline` é tratado **depois** de ler o stdin e **antes** do guard de `session_id` do T08.
- **Novo (custo):** depois do T14 cada escrita no diretório acorda o watcher (→ `merge` + `refreshAgents`). O statusline roda a cada atualização do rodapé. Para não gerar uma consulta ao CLI a cada 2 s só por causa dele, o hook **só regrava** se os números mudaram ou se o dado salvo tem 60 s ou mais:

```swift
    /// Regravar acorda o app (watcher → consulta ao CLI). Só vale a pena se o
    /// número mudou ou se o dado salvo já tem um minuto.
    public func needsWrite(over saved: RateLimits?, now: Date = Date()) -> Bool {
        guard let saved else { return true }
        return saved.fiveHour != fiveHour || saved.sevenDay != sevenDay
            || now.timeIntervalSince(saved.updatedAt ?? .distantPast) >= 60
    }
```

## Subtasks

- [ ] Criar `Sources/ClaudeBarCore/RateLimits.swift` (`RateWindow`, `RateLimits`, `fromStatusLine`, `summary`, `needsWrite`).
- [ ] Criar `Sources/ClaudeBarCore/StatusLineChain.swift` (`reentryVariable`, `originalCommand(at:)`, `run(command:input:timeout:)`, `OutputBox`).
- [ ] `StatusDirectory`: `limitsURL`, `originalStatusLineURL`, `isSessionFile`, `writeLimits`, `readLimits`, `writeAtomically` (extraído de `write`).
- [ ] `main.swift`: `statusLine(_:)` (`-> Never`) e o desvio em `run()`.
- [ ] `RateLimitsTests.swift` novo (suítes "Limites do statusline" e "Encadeamento do statusline") + `soRegravaQuandoMuda`.
- [ ] Verificação manual 2–5 e **7** da spec (descobrir o shell que o Claude Code usa no statusline; se não for `/bin/sh`, trocar o `executableURL` e registrar). O 6 (conta Pro/Max) vai como "não verificado" se a conta da máquina for de API.
- [ ] READMEs.
- [ ] Gates, commit, PR.

## Arquivos

`RateLimits.swift` (novo), `StatusLineChain.swift` (novo), `StatusDirectory.swift`, `main.swift`, `RateLimitsTests.swift` (novo), READMEs.

## Código-chave (da spec)

```swift
    public static func fromStatusLine(_ data: Data, now: Date = Date()) -> RateLimits? {
        struct Input: Decodable {
            let rateLimits: RateLimits?
            enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
        }
        guard var limits = (try? StatusDirectory.decoder.decode(Input.self, from: data))?.rateLimits,
              limits.fiveHour != nil || limits.sevenDay != nil
        else { return nil }
        limits.updatedAt = now
        return limits
    }

    /// Janela ausente ou já renovada vira "–", nunca 0%.
    public func summary(now: Date = Date()) -> String {
        func text(_ window: RateWindow?) -> String {
            guard let window, window.resetsAt > now else { return "–" }
            return "\(window.displayPercent)%"
        }
        return "5h \(text(fiveHour)) · sem \(text(sevenDay))"
    }
```

`StatusLineChain.run`: `/bin/sh -c <comando do usuário>` com o comando como **um** argumento; `CLAUDEBAR_STATUSLINE=1` no ambiente do filho; `signal(SIGPIPE, SIG_IGN)`; stdin e stdout em paralelo com `DispatchGroup.wait(timeout:)`; timeout → `terminate()` e `nil`. `originalCommand` ignora comando vazio, `type` ≠ `command` e qualquer comando com `claudebar-hook`. Código completo na spec (G11 linhas 125–223).

```swift
private func statusLine(_ stdinData: Data) -> Never {
    // Grava antes de rodar o original: se o Claude Code cancelar no meio, já está salvo.
    let limits = RateLimits.fromStatusLine(stdinData)
    if let limits, limits.needsWrite(over: StatusDirectory.readLimits()) {
        do { try StatusDirectory.writeLimits(limits) } catch {
            FileHandle.standardError.write(Data("claudebar-hook: \(error.localizedDescription)\n".utf8))
        }
    }
    let isReentry = ProcessInfo.processInfo.environment[StatusLineChain.reentryVariable] != nil
    if !isReentry, let command = StatusLineChain.originalCommand(),
       let result = StatusLineChain.run(command: command, input: stdinData, timeout: 5) {
        FileHandle.standardOutput.write(result.output)
        exit(result.status)
    }
    print((limits ?? StatusDirectory.readLimits() ?? RateLimits()).summary())
    exit(0)
}
```

## Testes obrigatórios

Da spec: `decodificaOExemploOficial`, `semCampoNaoGrava` (4 argumentos), `umaJanelaSo`, `percentualPresoEntre0e100`, `resumoDoRodape`, `readAllNaoApagaOsArquivosDoStatusline`; `repassaStdinEDevolveStdout` (200 KB), `repassaCodigoDeSaida`, `filhoQueIgnoraStdin`, `estouraOTimeout`, `originalComONossoComandoNaoEncadeia`. Novo: `soRegravaQuandoMuda` (sem salvo → true; mesmos números há 10 s → false; mesmos números há 61 s → true; número diferente → true). Nada de ponta a ponta com `HOME` falso (`NSHomeDirectory()` ignora `$HOME`).

## Critérios de aceite

- Payload sem `rate_limits` (ou sem janela) não cria nem altera `limits.json`.
- `limits.json` `0600`, só `five_hour`, `seven_day`, `updated_at`.
- Original `cat` → stdout byte a byte o stdin; `exit 3` → hook sai 3; `sleep 10` → hook sai 0 em ≤ 6 s.
- O hook nunca sai ≠ 0 por erro próprio.
- `readAll` não apaga `limits.json` nem `statusline-original.json`.
- `grep -rn "transcript_path\|URLSession" Sources/` vazio (o T15 também pega `URLSession`).

## Gates

`swift build`, `swift test`, `./scripts/build-app.sh`.

## README (as duas línguas)

Hook CLI: `claudebar-hook statusline` (o que lê, onde grava, encadeamento com `/bin/sh -c`, timeout 5 s, resumo `5h 23% · sem 41%`). Privacidade: só `rate_limits` é lido; `transcript_path` e o resto são ignorados; sem rede nem token. Limitações: só Pro/Max/Ultra, só depois da 1ª resposta; com duas contas, vale a última sessão que atualizou.

## Riscos

| Risco | Mitigação |
|---|---|
| Laço infinito (original = o próprio hook) | filtro em `originalCommand` + `CLAUDEBAR_STATUSLINE` (+ `.keep` no T30) |
| Script do usuário travado | timeout 5 s; neto que segura o stdout pode sobrar (`ponytail:` no código) |
| `/bin/sh` ≠ shell do Claude Code | verificação 7 |
| Acordar o app a cada atualização do rodapé | `needsWrite` |

## Fora do escopo

`transcript_path`, `.credentials.json`, Keychain, cookie, `api/oauth/usage`; ANSI/cores; `refreshInterval`; subdiretório ou watcher novo; menu (T29); instalação (T30); alerta perto do limite (F31).
