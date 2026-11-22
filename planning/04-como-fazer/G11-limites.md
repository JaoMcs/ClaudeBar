# G11 — Limites 5 h / semanal sem rede (F22)

Pesquisa de "como fazer", não é o plano final. Legenda: **[CONFIRMADO]** = fonte oficial citada; **[SUPOSIÇÃO]** = inferência minha, precisa de teste ou payload real.

Fontes oficiais lidas em 2026-11-15:
- Doc do statusline: https://code.claude.com/docs/en/statusline
- CHANGELOG oficial: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- Índice de settings: https://code.claude.com/docs/en/settings-reference
- Versão local do CLI nesta máquina: `2.1.325`. `statusLine` em `~/.claude/settings.json`: ausente (`null`).

## 1. O payload tem `rate_limits`? Tem.

- **[CONFIRMADO]** Tabela "Available data" da doc do statusline:
  - `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`: "Percentage of the 5-hour or 7-day rate limit consumed, from 0 to 100".
  - `rate_limits.five_hour.resets_at`, `rate_limits.seven_day.resets_at`: "Unix epoch seconds when the 5-hour or 7-day rate limit window resets".
  - Também existe `rate_limits.spend_limit.*`, mas só atrás de um Claude apps gateway. Fora do escopo do F22.
- **[CONFIRMADO]** Exemplo oficial do JSON no stdin (trecho):
  ```json
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
  ```
  `used_percentage` é decimal (`Double`), não inteiro.
- **[CONFIRMADO]** Quando o campo falta, na seção "Fields that may be absent": `rate_limits` "appears only for claude.ai Pro, Max, and Ultra subscribers, or behind a Claude apps gateway [...]. Even then, it appears only after the first API response in the session. Each window [...] may be independently absent, and Claude Code drops a window once its `resets_at` time passes."
  - Consequências: quem usa chave de API nunca recebe o campo, e o app deve mostrar "indisponível". Logo depois de abrir uma sessão o campo também não vem. Uma janela pode aparecer sem a outra.
- **[CONFIRMADO]** Introdução no CHANGELOG, seção `## 2.1.80`: "Added `rate_limits` field to statusline scripts for displaying Claude.ai rate limit usage (5-hour and 7-day windows with `used_percentage` and `resets_at`)".
- **[CONFIRMADO]** Correções relevantes no CHANGELOG:
  - 2.1.243: "Fixed the status line `rate_limits` fields and `/usage` still showing a rate-limit window's pre-reset usage percentage after the window reset while the session was idle". Em versões anteriores, o número podia ficar velho.
  - Uma entrada posterior: "Fixed `/usage`, the approaching-limit warning [...] and the status line sometimes showing more than 100% used". Mesmo assim, faça clamp de 0 a 100 na exibição.
- **[CONFIRMADO, por ausência]** Não há janela por modelo (Sonnet ou Opus semanal) no payload. Várias issues abertas pedem isso (ex.: https://claudeissues.com/issue/69791-statusline-stdin-missing-seven-day-sonnet-and-seven-day-opus-rate-limit-fields). O F22 mostra só 5 h e semanal.
- **[SUPOSIÇÃO]** Houve um relato de regressão em que o campo faltava para um usuário Max na v2.1.96 (https://claudeissues.com/issue/40094-bug-rate-limits-field-missing-from-statusline-json-for-claude-max-20x-plan-oauth). Não sei se foi corrigido. O backlog já registra que o comportamento com conta Pro/Max real não dá para verificar daqui.

**Conclusão:** dá para fazer sem rede, sem OAuth e sem Keychain. Não precisa adiar.

## 2. Como e quando o statusline roda (afeta o design)

Tudo **[CONFIRMADO]** na doc do statusline:
- Configuração: `"statusLine": { "type": "command", "command": "...", "padding": 2, "refreshInterval": N }` em `~/.claude/settings.json` ou nos settings do projeto. "The `command` field runs in a shell".
- Quando roda: no início ou no resume da sessão, depois de cada mensagem do assistente, no `/compact`, quando o modo de permissão muda, no toggle do vim, quando o `command` muda, a cada `refreshInterval` e "A rate-limit window in the data your script last received reaches its `resets_at` time". Há "debounces updates at 300ms".
- **Cancelamento:** "If a new update triggers while your script is still running, Claude Code cancels the in-flight script." A doc não diz qual sinal é usado.
- **Saída:** "Claude Code displays your script's output only after the script exits with code 0". "Scripts that exit with non-zero codes or produce no output cause the status line to go blank". A saída é capturada, e `COLUMNS`/`LINES` vêm no ambiente.
- **Sem timeout documentado.** "Slow scripts block the status line from updating until they complete." O `claudebar-hook` precisa ter **timeout próprio**.
- **Quando não roda:** antes de aceitar o workspace trust ("Status line command skipped: workspace trust not accepted"), com `disableAllHooks: true` e com `allowManagedHooksOnly` (só roda o statusLine dos managed settings). Nesses casos, o dado fica velho, e por isso o menu precisa mostrar a idade.
- **Efeito colateral de instalar:** "With a custom status line configured, Claude Code stops showing most of the footer's keyboard hints, including `esc to interrupt`, the `? for shortcuts` fallback, and the `hold space to speak` [...] hint." Quem **não** tinha statusline perde essas dicas ao instalar o F22. Isso precisa aparecer no opt-in (F16), e o hook deve imprimir algo útil quando não houver comando anterior (ver §4.4).
- `transcript_path` está no payload. O backlog pede para ignorar, e o hook não decodifica esse campo.

## 3. Ponto de partida no código

- `Sources/claudebar-hook/main.swift`: o primeiro argumento é o estado (`working|idle|waiting|end`), o hook lê todo o stdin com `readDataToEndOfFile()` e decodifica `HookPayload` com `try?`. O subcomando `statusline` entra como um `if command == "statusline"` **antes** do `SessionState(rawValue:)`.
- `Sources/ClaudeBarCore/StatusDirectory.swift`:
  - `createIfNeeded()` (0700), `write` com `.atomic` e depois `0600`. É o padrão a reutilizar para `limits.json`.
  - **Armadilha:** `readAll()` lista **todo `*.json`** do diretório e **apaga** o que não decodifica como `SessionStatus`. Um `limits.json` em `~/.claude/claudebar/` seria apagado pelo app a cada refresh. Há três saídas, e a primeira é a recomendada (é uma linha):
    1. Filtrar `file.lastPathComponent != "limits.json"` em `readAll`.
    2. Usar outra extensão (`limits.data`).
    3. Usar um subdiretório.
  - O backlog fixa o caminho `~/.claude/claudebar/limits.json`, por isso a opção 1.
- `Sources/ClaudeBar/SessionStore.swift`: o `DirectoryWatcher` já observa esse diretório, e há um `Timer` de 5 s. O `limits.json` muda no mesmo diretório e dispara o mesmo watcher, então não precisa de observador novo.
- `Sources/ClaudeBar/MenuContent.swift`: já tem um `RelativeDateTimeFormatter` (pt_BR, `.short`). Reutilizar para a idade do dado.
- `scripts/install.sh`: hoje não mexe em `statusLine`. A instalação e a remoção ficam no F16 (dependência do F22).

## 4. Como fazer (recomendado, menor diff)

### 4.1 Formato do `limits.json`
```json
{ "updated_at": 1763200000,
  "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
  "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 } }
```
- Os nomes dos campos são os mesmos do payload oficial. Só `updated_at` é nosso: a hora em que o hook gravou.
- `Codable` no Core: `struct RateWindow: Codable { let usedPercentage: Double; let resetsAt: Date }` e `struct RateLimits: Codable { var updatedAt: Date; var fiveHour: RateWindow?; var sevenDay: RateWindow? }`, com `CodingKeys` snake_case como o `HookPayload`. O `StatusDirectory.decoder` já usa `.secondsSince1970`, que bate com "Unix epoch seconds".
- **Se o payload vier sem `rate_limits`, não grave nada.** Assim, uma sessão com chave de API ou recém-aberta não apaga o dado bom de outra sessão. Se vier com uma janela só, grave só ela (a outra fica `nil`, porque o Claude Code a descartou depois do reset).
- Várias sessões gravam o mesmo arquivo e vence a última. **[SUPOSIÇÃO]** Todas as sessões são da mesma conta, então o número é o mesmo. Com duas contas logadas em terminais diferentes, o arquivo alterna entre as duas. Caso raro, aceito.

### 4.2 Subcomando `claudebar-hook statusline`
Fluxo:
1. Ler stdin inteiro. O código já faz isso.
2. Decodificar só `rate_limits` (struct mínima) com `try?`. Se houver dado, `StatusDirectory.writeLimits(...)` (atômico + 0600, igual ao `write`). Erro → stderr e segue em frente (fail-open).
3. Encadear o comando anterior (§4.3) e devolver o stdout e o exit code dele.

### 4.3 Encadear o `statusLine.command` anterior
- **Onde guardar o comando anterior:** na instalação (F16), copiar o objeto `statusLine` original para `~/.claude/claudebar/statusline-original.json` (0600) e trocar `statusLine.command` pelo caminho do hook + ` statusline`. O hook lê esse arquivo.
  - Não passe o comando anterior como argumento no `command` novo. Isso exige quoting de shell, o que vai contra o guard rail "nada via shell com interpolação".
  - Na remoção, restaurar o objeto inteiro, inclusive `padding`/`refreshInterval`.
- **Como executar:** `Process` com `executableURL = /bin/sh` e `arguments = ["-c", comandoOriginal]`.
  - O comando é texto que o próprio usuário escreveu nos settings dele e vai como **um argumento**, sem interpolação nossa. É o mesmo que o Claude Code faria ("runs in a shell").
  - **[SUPOSIÇÃO]** Não confirmei se o Claude Code usa `/bin/sh` ou o shell do usuário (`$SHELL`). Um comando com sintaxe de zsh ou bash pode se comportar diferente. Se der problema, usar `$SHELL -c`.
  - O ambiente é herdado por padrão no `Process`, então `COLUMNS`/`LINES` chegam ao filho.
- **stdin e stdout sem deadlock:**
  - Escrever o stdin num `Pipe` e fechar o write end.
  - Ler o stdout com `readDataToEndOfFile()` numa thread ou fila separada, porque o pipe do macOS tem buffer finito e o payload pode passar de alguns KB.
  - stderr do filho: repassar para o nosso stderr (o `claude --debug` mostra).
- **Timeout:** `DispatchSemaphore` / `DispatchGroup.wait(timeout:)`. Valor sugerido **[SUPOSIÇÃO]**: 5 s, porque a doc não fixa limite e o Claude Code cancela o script na próxima atualização. Se estourar, `process.terminate()`, devolver o que já saiu (ou nada) e `exit(0)`.
  - **[SUPOSIÇÃO]** `terminate()` manda SIGTERM só para o filho direto. Netos (ex.: `jq` dentro do script) podem sobrar por pouco tempo. Aceitável.
- **Cancelamento pelo Claude Code:** **[SUPOSIÇÃO]** o sinal não está documentado. Se for SIGTERM ou SIGKILL no nosso processo, o filho pode virar órfão até terminar sozinho. Mitigação barata: gravar o `limits.json` **antes** de rodar o filho (o dado não se perde) e manter o timeout curto.
- **Fail-open:** se o arquivo do original não existir, se ele for inválido ou se o filho falhar, o hook nunca sai com código diferente de zero por culpa própria. A sessão do Claude não é afetada (o pior caso é a linha em branco). Se o filho sair com código diferente de zero, repassar esse código, para manter o comportamento original do usuário.

### 4.4 Quando não havia statusline antes
Como o Claude Code esconde as dicas do rodapé (§2), o hook não deve imprimir string vazia, porque o resultado seria uma linha em branco e as dicas sumiriam. Recomendo imprimir uma linha curta, só texto e sem ANSI, por exemplo `5h 23% · sem 41%`, e mostrar o aviso no opt-in. Alternativa: o F16 só oferece o F22 a quem já tem statusline. Isso é pior, porque exclui justamente o usuário comum.

### 4.5 Exibição no menu
- Uma seção no topo do `MenuContent`: `Limite 5 h: 23% · renova 14:30` e `Semanal: 41% · renova sex 09:00`, mais `atualizado há 3 min` com o `relativeFormatter` que já existe.
- Regras:
  - Sem arquivo ou sem janela: mostrar "indisponível". **Nunca** 0%. O backlog pede isso.
  - `resets_at < agora`: a janela renovou e o número antigo não vale mais. Mostrar "renovado, aguardando dado novo", o mesmo que o Claude Code faz ao descartar a janela.
  - Clamp de 0 a 100 e arredondar para inteiro na exibição.
  - Idade grande (ex.: > 1 h, **[SUPOSIÇÃO de UX]**): mostrar a idade em destaque. Não esconder.
- `.menuBarExtraStyle(.menu)`: **[SUPOSIÇÃO]** o conteúdo do menu é avaliado quando ele abre e não anima enquanto fica aberto. Por isso a idade calculada na abertura basta, sem `TimelineView`.
- Hora de renovação: `Date.formatted(date:time:)` (Foundation, macOS 12+, documentada em https://developer.apple.com/documentation/foundation/date/formatted(date:time:)).
- Leitura: no mesmo `refresh` do `SessionStore` (watcher + timer de 5 s), um `try? decoder.decode(RateLimits.self, from: Data(contentsOf:))`. Sem tarefa nova.

### 4.6 Testes (gate)
- Core:
  - Decodificar o JSON de exemplo oficial (§1) → valores corretos.
  - Payload sem `rate_limits` → não grava nada.
  - Uma janela só → a outra fica `nil`.
  - `readAll` com `limits.json` presente → o arquivo não é apagado e não vira sessão.
- Hook: rodar o binário com um script `cat` como original e conferir que o stdout é igual ao stdin. Com um script `sleep 10`, o hook sai em cerca de 5 s com código 0.

## 5. Armadilhas

- **`readAll` apaga `limits.json`** (§3). É o bug mais provável se ninguém lembrar.
- **Swift 6 strict concurrency no CLI:** o `main.swift` usa top-level code. **[SUPOSIÇÃO, verificar com `swift build`]** Pelo SE-0343 (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0343-top-level-concurrency.md), variáveis globais de top-level podem ficar isoladas no MainActor e gerar erro de `Sendable` quando capturadas em closures de `Dispatch`/`readabilityHandler`. Mitigação: manter tudo dentro de funções (como o `run()` atual) e usar estado local. Para o `Data` lido em outra thread, usar uma caixa `final class ... : @unchecked Sendable` com lock, ou ler o stdout de forma síncrona na thread principal depois de escrever o stdin em background.
- **Escrita atômica:** `Data.write(options: .atomic)` cria o arquivo pelo umask, por isso o código atual reforça `0600` depois. Copiar exatamente esse padrão. **[SUPOSIÇÃO]** Há uma janela curta com 0644 dentro de um diretório 0700. O risco é baixo, porque o diretório já bloqueia o acesso.
- **Assinatura ad-hoc / LSUIElement:** não afetam o F22. O hook é um binário de linha de comando chamado pelo Claude Code, e o app só lê um arquivo local. Sem entitlement e sem rede.
- **Atualizar o app muda o caminho do hook?** O `command` aponta para `.../ClaudeBar.app/Contents/MacOS/claudebar-hook`. Se o usuário mover o app, a statusline quebra e fica em branco. O F16 precisa detectar isso e reinstalar. **[SUPOSIÇÃO]**: não testei.
- **statusLine no settings do projeto:** **[SUPOSIÇÃO]** pela precedência geral dos settings (projeto acima de usuário), um `statusLine` de projeto substitui o nosso naquele repo, e o dado fica velho enquanto o usuário trabalha ali. A idade no menu mostra isso. Não tentar mexer em settings de projeto.
- **`refreshInterval`:** não é necessário, porque o Claude Code já re-roda o script no `resets_at`. Não adicionar.
- **Desinstalar o app sem rodar o uninstall:** o statusline fica apontando para um binário inexistente e a linha fica em branco. É a mesma situação dos hooks atuais, e cabe ao F16 documentar.

## 6. Open source (referência, nada copiado)

- **ohugonnot/claude-code-statusline** (https://github.com/ohugonnot/claude-code-statusline): usa `rate_limits.five_hour`/`.seven_day` do stdin "for Pro/Max subscribers". Quando o campo falta, **cai para** `https://api.anthropic.com/api/oauth/usage` com o token de `~/.claude/.credentials.json`. **Esse fallback é proibido aqui** (OAuth, rede). Serve só para confirmar que o campo do stdin funciona na prática.
- Doc oficial, exemplo "Rate limit usage": scripts em bash, Python e Node com `jq -r '.rate_limits.five_hour.used_percentage // empty'`. É o modelo de tratamento de ausência.
- Clabar, Perch e claudewatch (citados no backlog) usam OAuth/Keychain. Não encontrei projeto open source que **encadeie** o statusline anterior e grave arquivo para outro app. Instaladores como os da busca fazem backup (`settings.json.bak`) e **substituem** o statusline. O encadeamento é método nosso.

## 7. Alternativas

| Alternativa | Veredito |
|---|---|
| **Statusline + encadeamento (este doc)** | **Recomendada.** Oficial, sem rede, sem login. |
| Substituir o statusline sem encadear | Mais simples, mas apaga a statusline do usuário. Não. |
| Endpoint `api/oauth/usage` / Keychain / cookie | Proibido pelo backlog e pelo README. Não. |
| Ler `/usage` ou o transcript | Não há API para isso, e o transcript tem conteúdo da conversa (guard rail). Não. |
| Hook `StopFailure` com `error: rate_limit` (G06) | Só diz que o limite **foi batido**, sem % nem hora. Complemento do F33, não substituto. |
| Adiar | Não precisa: o campo está documentado desde a 2.1.80. |
