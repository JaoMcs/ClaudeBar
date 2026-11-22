# G03 — Integração de hooks: merge aditivo, caminho estável, transparência, status (F02, F03, F16, F17)

Pesquisa de COMO FAZER. Não é o plano final. Revalidado contra hooks.md e settings.md em 2026-11-15 (acréscimos: `onFailure`, `$HOME` em exec form, settings só-leitura, lista atual de `notification_type`, formato do log de debug). Legenda: **[CONFIRMADO]** = doc oficial (Claude Code, Apple) ou changelog oficial; **[LOCAL]** = verificado nesta máquina (macOS 26.5.2, Swift 6.3.3, Claude Code 2.1.325); **[TERCEIRO]** = código open source de outro projeto; **[SUPOSIÇÃO]** = inferência, testar antes de afirmar.

Fontes principais:
- Hooks: <https://code.claude.com/docs/en/hooks>
- Settings: <https://code.claude.com/docs/en/settings> e <https://code.claude.com/docs/en/settings-reference>
- Statusline: <https://code.claude.com/docs/en/statusline>
- Changelog: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Apple "Updating Mac Software": <https://developer.apple.com/documentation/security/updating-mac-software>

## 1. Ponto de partida no código

- `scripts/install.sh` usa `jq` com `.hooks = ((.hooks // {}) + {UserPromptSubmit: ..., Stop: ..., Notification: ..., SessionEnd: ...})`: **substitui o array inteiro** de cada um desses eventos (apaga hooks do usuário nesses eventos), backup com `cp` ao lado do `settings.json`, e `mv` de um `.tmp` (atômico só se o `.tmp` estiver no mesmo volume; ok). Registra o caminho **dentro do bundle** (`~/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook`), em shell form, sem aspas: `"<HOOK> working --pid $PPID"`. **[LOCAL]** o `~/.claude/settings.json` desta máquina tem exatamente essas entradas.
- `Sources/claudebar-hook/main.swift`: `argv[1]` = estado; `fail()` faz `exit(2)`.
- `ClaudeBarCore/StatusDirectory.swift` já tem `createIfNeeded()` (0700), escrita `.atomic` + `0600`. Reusar para `~/.claude/claudebar/bin` e backups.
- App: `MenuBarExtra(.menu)`, `setActivationPolicy(.accessory)`, `NSAlert` + `NSApplication.shared.activate(ignoringOtherApps: true)` + `runModal()` já usado em `SessionStore.swift` (padrão provado no app). `Notifier.showSample()` já é o "testar alerta" visual.
- `build-app.sh`: `codesign --force --sign - "$BUNDLE"`. **[LOCAL]** `claudebar-hook` dentro do bundle sai `flags=0x20002(adhoc,linker-signed)`; uma cópia com `cp` continua passando em `codesign -v` e executa.

## 2. Bug encontrado de passagem (corrigir junto com o F02)

**[CONFIRMADO]** tabela de exit code 2 em hooks.md: `UserPromptSubmit` → "Blocks the prompt, so it never reaches Claude"; `Stop` → "Prevents Claude from stopping, continues the conversation"; `Notification` → "Exit code and stderr are ignored". Qualquer outro código ≠ 0/2 = "Non-blocking error. The action goes ahead."

**[LOCAL]** `echo '{}' | claudebar-hook` (sem estado) imprime erro e sai com **exit 2**. Ou seja: argumento errado (ex.: entrada antiga/ corrompida, ou um Claude Code que ignore `args`, ver §4) **bloqueia o prompt do usuário** ou **impede o Claude de parar**. Correção de uma linha: `fail()` usa `exit(1)`. Um hook do ClaudeBar nunca deve sair com 2.

## 3. Formato oficial dos hooks (o que pode ir no JSON)

**[CONFIRMADO]** (hooks.md):
- Estrutura: `hooks` → `<Evento>` → array de grupos `{ "matcher"?: string, "hooks": [ handler ] }`.
- Handler `command`: `type` (obrigatório), `command` (obrigatório), `args` (opcional), `timeout` (segundos), `async`, `asyncRewake`, `shell`, `onFailure`, `if`, `statusMessage`, `once` (só em skill). Default de `timeout`: 600 s para `command`; reduzido para 30 s em `UserPromptSubmit`.
- **Exec form × shell form**: "A command hook runs as exec form when `args` is set, and shell form when `args` is omitted." Exec form: "resolves `command` as an executable on `PATH` and spawns it directly with `args` as the argument vector. There is no shell". Shell form: "`sh -c` on macOS and Linux".
- `args` entrou na **v2.1.139** ("Added hook `args: string[]` field (exec form) that spawns the command directly without a shell") — changelog oficial.
- Matcher: `"*"`, `""` ou omitido = todos; só letras/dígitos/`_`/`-`/espaço/`,`/`|` = string exata ou lista; qualquer outro caractere = regex JS não ancorada. "If you add a `matcher` field to an event without matcher support, it is silently ignored." `Stop` e `UserPromptSubmit` **não** têm matcher. `SessionEnd` filtra por `reason` (`clear`, `resume`, `logout`, `prompt_input_exit`, `other`). `Notification` filtra por `notification_type` (lista completa e decisão de matchers em `G04-notification-kind.md`).
- `SessionEnd`: timeout default **1,5 s**; "The overall budget rises automatically to match the highest per-hook `timeout` in your settings files, up to 60 seconds." → **não pôr `timeout` no SessionEnd** (um `timeout: 5` ali aumentaria a espera de saída de toda sessão).
- Payload comum no stdin: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name` (+ outros). Processo do hook: "Handlers run in the current directory with Claude Code's environment"; "command hooks run in their own session without a controlling terminal".
- Dedupe: "If you define the same handler in more than one settings file, it runs once."
- `disableAllHooks: true` desliga hooks **e** statusline; `allowManagedHooksOnly` (escopo Managed) roda só hooks da organização (settings-reference).
- **Workspace trust**: "Claude Code holds back hooks from every settings file, including your own `~/.claude/settings.json`, until you accept the workspace trust dialog for the folder". Importa para o F17: pasta não confiada = nenhum evento, sem erro.
- Recarga: "Claude Code watches your settings files and reloads them when they change, so it applies most edits to the running session without a restart, including edits to `permissions`, `hooks`" (settings.md). **O `install.sh` diz "passam a valer nas novas sessões" — está desatualizado.**
- Debug: `claude --debug-file <path>` ou `~/.claude/debug/<session-id>.txt`; linhas `Hooks: <Evento>... [comando] finished with status N (Xms)` (formato garantido a partir da **v2.1.296** **[CONFIRMADO]**).
- **`onFailure`** (v2.1.295+) **[CONFIRMADO]**: `"continue"` | `"block"`; sem o campo, falha/timeout deixa a ação seguir. Com `"block"`, falha "does what exit code 2 does on that event". **Nunca** pôr `onFailure` nos hooks do ClaudeBar (o indicador nunca pode travar o prompt). Também **[CONFIRMADO]**: "Exit code 1 without valid JSON output is a non-blocking error" → reforça a correção do §2.
- **Settings Warning** **[CONFIRMADO]** (settings.md): "an unknown hook event name" faz o Claude Code pular só aquela entrada e manter o resto do arquivo. Logo, registrar `StopFailure` (F07) num Claude Code antigo não quebra o arquivo.
- **`settings.json` gerado/só-leitura** **[CONFIRMADO]** (settings.md): "because another tool generates it or links it to a read-only copy". Caso dotfiles/Nix: se o destino real (após resolver symlink) não for gravável, estado `settingsSomenteLeitura` → mostrar o JSON para o usuário colar na ferramenta dele; não tentar contornar.
- Lista de `notification_type` na doc hoje (2026-11-15) **[CONFIRMADO]**: `permission_prompt`, `idle_prompt`, `auth_success`, `auth_storage_failure`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`, `plugin_notification`. Payload inclui `notification_type`, `message`, `title` opcional. (Decisão de quais registrar: G04.)
- Boas práticas da doc: "Use absolute paths", "Always quote shell variables".

### JSON proposto (exec form, caminho estável)

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Users/<u>/.claude/claudebar/bin/claudebar-hook", "args": ["working"], "timeout": 5 }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/Users/<u>/.claude/claudebar/bin/claudebar-hook", "args": ["idle"], "timeout": 5 }] }],
    "Notification": [
      { "matcher": "permission_prompt",  "hooks": [{ "type": "command", "command": "/Users/<u>/.claude/claudebar/bin/claudebar-hook", "args": ["waiting", "--kind", "permission"], "timeout": 5 }] },
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "/Users/<u>/.claude/claudebar/bin/claudebar-hook", "args": ["waiting", "--kind", "question"], "timeout": 5 }] }
    ],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/Users/<u>/.claude/claudebar/bin/claudebar-hook", "args": ["end"] }] }]
  }
}
```
(`StopFailure` do F07 entra igual, `args: ["error"]`.) Caminho absoluto expandido na instalação: em exec form não há shell. `$HOME` **não** expande **[CONFIRMADO]** ("Special characters such as apostrophes, `$`, and backticks pass through verbatim"; só os placeholders `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` são substituídos). `~` também não **[SUPOSIÇÃO forte: a doc não fala de `~`, só de "No shell tokenization"]**. Gravar o caminho já expandido resolve as duas.

**Sem `--pid $PPID`**: em exec form `$PPID` não expande. O hook passa a usar `getppid()` quando `--pid` não vier. **[SUPOSIÇÃO]** em exec form o pai direto é o processo do Claude Code ("spawns it directly"); verificar logando `getppid()` contra `pgrep -x claude`. Em shell form hoje `$PPID` = pai do `sh` = Claude, então o valor deve ser o mesmo.

Alternativa: manter shell form com o caminho entre aspas (`"\"/Users/.../claudebar-hook\" working --pid $PPID"`). Funciona em qualquer versão do Claude Code, mas reintroduz o shell (guard rail "nada via shell com interpolação"). **Recomendo exec form**; mínimo Claude Code 2.1.139 documentado no README. **[SUPOSIÇÃO]** comportamento de versões < 2.1.139 com `args` desconhecido: provavelmente ignoram o campo e rodam `command` sem argumentos → por isso o §2 (exit 1) é pré-requisito.

## 4. F02 — merge aditivo em Swift (ClaudeBarCore)

### Identidade "é do ClaudeBar"
Lição do iTerm2 **[TERCEIRO]** (`ModernTests/ClaudeCodeHookOwnershipTests.swift`, <https://github.com/gnachman/iTerm2>): decidir posse pela *forma* do comando apagou hooks de outra instância ("stripped all ten entries belonging to the main install"). Regra recomendada: handler é nosso se o **executável** (o `command` em exec form; o 1º token, com ou sem aspas, em shell form legado) for **exatamente**:
1. `~/.claude/claudebar/bin/claudebar-hook` (expandido), ou
2. termina em `/ClaudeBar.app/Contents/MacOS/claudebar-hook` (legado do `install.sh`, para migrar).
Nada de `contains("claudebar")`.

### Merge e remoção (funções puras sobre `[String: Any]`)
- `strip(root)`: em cada evento, em cada grupo, remove **só os handlers nossos**; grupo que ficou com `hooks` vazio sai; evento vazio sai; `hooks` vazio sai. **Armadilha [TERCEIRO]**: o Peep (<https://github.com/jclasley/peep>, `Sources/Peep/Hooks.swift`) remove o **grupo inteiro** se ele contém um handler nosso (`groups.filter { !$0.hooks.contains(isOurs) }`) → apagaria hooks do usuário que dividam o grupo. Não copiar isso.
- `install(root) = strip(root)` + anexar nossos grupos ao fim de cada array. Idempotente; reinstalar migra o legado.
- Propriedade para o self-check: `strip(install(x)) == strip(x)` (comparar com `NSDictionary.isEqual`) e `install(install(x)) == install(x)`. Um teste em `Tests/` cobrindo: arquivo ausente, `{}`, hooks do usuário no mesmo evento, grupo misto, entrada legada, JSON inválido.
- Nunca escrever se o arquivo existe e não é objeto JSON válido (Peep e iTerm2 fazem igual **[TERCEIRO]**). Arquivo vazio = `{}` (iTerm2).

### Serialização — `JSONSerialization` (recomendado) × `Codable`
**[LOCAL]** com `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`:
- ordem de chaves original perdida (`.sortedKeys` pelo menos deixa determinístico) — **[CONFIRMADO]** `sortedKeys` = "sorts keys in lexicographic order";
- `0.1` vira `0.10000000000000001`; `1.0` vira `1` (mesmo valor ao reler, só cosmético);
- chave duplicada: fica a **primeira**;
- formato `"a" : 1` (espaço antes dos dois-pontos) e `[]` vira `[\n\n  ]`; `true`, `null`, unicode, `/` preservados;
- `JSONEncoder` com um enum `JSONValue` imprime `0.1` corretamente, mas custa ~40 linhas e também perde ordem.
Recomendo `JSONSerialization` + aviso "o arquivo será reformatado (ordem das chaves), backup em X". `withoutEscapingSlashes` evita `\/` nos caminhos (macOS 10.15+ **[CONFIRMADO]**).

### Dry-run com diff
Sem dependência: `CollectionDifference` da stdlib (`novo.difference(from: antigo)` sobre linhas, macOS 10.15+ **[CONFIRMADO]**, **[LOCAL]** funcionou). Para o diff não mostrar o arquivo inteiro reformatado, comparar `serialize(parse(original))` × `serialize(install(...))` (diff semântico) e avisar à parte que a formatação muda. Alternativa: `Process` com `/usr/bin/diff -u` e `arguments` (sem shell) — mais bonito, mas um processo a mais; não precisa.

### Escrita segura
- **Symlink**: **[LOCAL]** `Data.write(to: link, options: .atomic)` **substitui o symlink por arquivo comum** (o alvo real fica intacto e para de receber mudanças). iTerm2 resolve com `settingsURL.resolvingSymlinksInPath()` antes de escrever ("People who keep their Claude Code settings in a dotfiles repo (GNU Stow, chezmoi) have a settings.json that is a symlink") **[TERCEIRO]**. Fazer igual (1 linha).
- **Atômico**: `.atomic` = "write data to an auxiliary file first and then replace the original" **[CONFIRMADO]**. **[LOCAL]** sobre arquivo existente `0600` o modo continuou `0600`. Arquivo novo: aplicar `0600` depois (já é o padrão do `StatusDirectory.write`).
- **Corrida com o próprio Claude Code**: ele grava `~/.claude/settings.json` em `/config` e `/model` **[CONFIRMADO]** settings.md. Mitigação: guardar os bytes lidos ao montar a prévia; na hora de gravar, reler; se mudou, refazer a prévia e pedir de novo (nunca gravar algo diferente do que foi mostrado). Janela de corrida residual de milissegundos: aceitar.
- Alternativa `FileManager.replaceItemAt(_:withItemAt:backupItemName:options:)` **[CONFIRMADO]**: "ensures no data loss", preserva "creation date, permissions" por padrão e pode manter backup ao lado. Mais parâmetros, mesmo resultado; `.atomic` basta.

### Backup
- Antes de qualquer escrita: copiar o arquivo real para `~/.claude/claudebar/backups/settings.json.<yyyyMMdd-HHmmss>` com `0600` (o `settings.json` pode ter `env` com tokens). Dir `0700` via `createIfNeeded()`. Ao lado do `settings.json` (como hoje) polui `~/.claude`; dentro do nosso dir fica fácil de listar e de apagar no uninstall (perguntando).
- Precedente de mercado: m1ckc3s/claude-status-bar faz backup antes e uninstall remove só os seus; Clabar grava `settings.json.clabar-backup` (snippets de busca, não li o código) **[TERCEIRO, não verificado]**.
- ponytail: guardar todos; limitar a N só se alguém reclamar.

### CLI e `install.sh`
- `claudebar-hook install [--dry-run] | uninstall [--dry-run] | status`, tratados **antes** de ler o stdin (hoje `run()` lê stdin primeiro e travaria esperando EOF num terminal).
- `install.sh`: build → copia o app → `"$APP/Contents/MacOS/claudebar-hook" install --dry-run` → `read -p "Aplicar? [s/N]"` → `install`. Sem `jq`. `uninstall.sh`: `claudebar-hook uninstall` (pode rodar a partir do binário estável mesmo sem o app).
- Lembrar `CLAUDE_CONFIG_DIR` existe (settings.md) — F44 fica para depois; só não espalhar `~/.claude` hard-coded fora de um único lugar (já é `StatusDirectory.url`).

## 5. F03 — binário em caminho estável

- Destino `~/.claude/claudebar/bin/claudebar-hook`, dir `0700`, arquivo `0700`.
- **Cópia, não `cp` por cima**: **[CONFIRMADO]** Apple: "Modifying the file in place yields a mismatch between the file's contents and the in-kernel cache, which can cause a hard-to-reproduce code-signing crash"; fix: "write the updated code to a temporary file and replace the existing file with that temporary one" (`rename`). Implementação: `copyItem` para `bin/.claudebar-hook.<UUID>` + `rename(2)` (ou `replaceItemAt`). Quinn (DTS) em <https://developer.apple.com/forums/thread/130313> repete: `cp`/`scp` não fazem isso.
- Assinatura: **[LOCAL]** o helper é `adhoc,linker-signed` e a cópia continua válida. Nada a fazer.
- Origem: no app, `Bundle.main.url(forAuxiliaryExecutable: "claudebar-hook")` **[CONFIRMADO]**. **[SUPOSIÇÃO]** dentro do próprio CLI (que mora em `Contents/MacOS`), `Bundle.main` aponta para o `.app` e `executableURL` seria o `ClaudeBar`, não o hook → no CLI usar o mesmo `url(forAuxiliaryExecutable:)` ou o caminho do processo; testar.
- "Desatualizado": comparar bytes `Data(contentsOf: bundle) == Data(contentsOf: estável)` (centenas de KB, stdlib, sem hash). Mais simples e exato que versão embutida.
- Alternativa iTerm2 **[TERCEIRO]**: symlink estável → binário dentro do bundle, re-apontado a cada abertura. Mais leve, mas quebra (link pendurado) se o app for movido/apagado até a próxima abertura — exatamente o bug que o F03 quer matar. Ficar com cópia.
- **[SUPOSIÇÃO]** quarentena: aqui o binário instalado só tem `com.apple.provenance` **[LOCAL]**. Se o app vier de DMG baixado com `com.apple.quarantine`, a cópia herda o atributo e o Gatekeeper pode barrar a execução pelo Claude Code em silêncio. Não remover o xattr por conta própria (contorna Gatekeeper); o teste ponta a ponta do F17 é o que detecta. Testar com o DMG do F23.

### Detecção na abertura (nunca reparo silencioso)
Estados (função pura no Core, lendo settings + arquivo): `naoInstalado`, `ok`, `binarioAusente`, `binarioDesatualizado`, `hooksFaltando` (parte das entradas), `hooksLegado` (apontam para o bundle), `settingsInvalido` (não mexer), `settingsSomenteLeitura` (mostrar JSON para colar), `hooksDesligados` (`disableAllHooks: true` no user settings). Qualquer estado ≠ `ok`/`naoInstalado` → item no menu "⚠︎ Integração precisa de reparo…" que abre a tela do F16 com o diff. Alerta automático só uma vez por estado novo (lembrar o último estado em `UserDefaults`), para não virar alerta a cada abertura.

Ponto de decisão (não inventar): **atualizar só o binário** (sem tocar `settings.json`) a cada update do app exigiria pedir permissão toda vez. O backlog diz "oferece". Proposta: pedir; registrar em PENDENCIAS se o usuário preferir automático para o binário.

## 6. F16 — tela de transparência

Menor caminho que já funciona no app: **`NSAlert` com `accessoryView`** (um `NSScrollView` + `NSTextView` só-leitura, fonte monoespaçada) contendo o diff/JSON exato, `informativeText` com caminho do arquivo e do backup, botões "Instalar" / "Cancelar" (ou "Remover"). **[CONFIRMADO]** "places the accessory view between the informative text or suppression checkbox (if present) and the response buttons"; `showsSuppressionButton` existe para "não perguntar de novo" (não usar no consentimento de instalar).
- Por que não uma `Window` SwiftUI: em app `.accessory`, `openWindow`/`SettingsLink` abrem atrás das outras janelas; relatos em <https://developer.apple.com/forums/thread/836619> e <https://developer.apple.com/forums/thread/731628>, contorno = trocar para `.regular` temporariamente (<https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/>) **[TERCEIRO]**. O padrão `activate(ignoringOtherApps:)` + `runModal()` já funciona em `SessionStore.swift`. Se a tela crescer (status do F17 + botões), aí sim `Window` + troca de activation policy.
- `NSApp.activate()` sem argumento é macOS 14+ **[CONFIRMADO]**, mas o fórum acima diz que não traz app accessory para frente; manter `activate(ignoringOtherApps:)` (deprecated, funciona) **[TERCEIRO]**.
- 1º uso: `NSAlert` "O ClaudeBar precisa registrar hooks no Claude Code" → "Ver o que será alterado…" / "Pular". "Pular" não grava nada e não pergunta de novo (flag em `UserDefaults`); o item de menu continua lá.
- Swift 6: `[String: Any]` não é `Sendable`. Manter merge/IO como funções síncronas do Core chamadas no `@MainActor` (arquivo de poucos KB, ação disparada por clique). Só valores `Sendable` (`Data`, `String`, enum de estado) cruzam fronteira se um dia for para background. **[SUPOSIÇÃO]** nenhum aviso de concorrência com essa forma; o build com Swift 6 confirma.

## 7. F17 — "tudo ok" + testar alerta

Checagens (todas locais, sem rede):
1. Hooks registrados = estado `ok` do §5.
2. Binário: `FileManager.isExecutableFile(atPath:)` **[CONFIRMADO]** (segue symlink; usa uid real) **e** bytes iguais ao do bundle.
3. **Teste ponta a ponta** (o que realmente prova): rodar o binário estável via `Process` com `executableURL` + `arguments` (sem shell), stdin = `{"session_id":"claudebar-selftest","cwd":"/"}`, estado `waiting`; conferir que `~/.claude/claudebar/claudebar-selftest.json` apareceu; disparar `Notifier.showSample()`; depois `end` para apagar. Pega quarentena, assinatura quebrada e permissão. Atenção: o arquivo de teste vai ter `pid` 0/ o do app → garantir que `readAll()` não o mostre como sessão real (usar `end` logo em seguida).
4. Último evento: maior `updatedAt` em `StatusDirectory.readAll()` → "último evento há X". Se nenhum evento e há sessões `claude` vivas (já detectadas pelo `AgentsProbe`), dica: "pasta não confiada? hooks ficam retidos até aceitar o diálogo de confiança" (**[CONFIRMADO]** workspace trust) ou `disableAllHooks`.
5. Não dá para ver do app: `allowManagedHooksOnly` em managed settings e `disableAllHooks` em settings de projeto. Mostrar só o que é verificável; dizer "confira `/hooks` no Claude Code" (menu read-only **[CONFIRMADO]**).

## 8. Alternativas consideradas

| Opção | Prós | Contras | Veredito |
|---|---|---|---|
| Merge em Swift (`JSONSerialization`) no Core + CLI | sem dependência, testável, mesma lógica no app e no script | reformata o arquivo | **recomendado** |
| Manter `jq` com merge aditivo | já existe | dependência externa, não reusável no app | não |
| Plugin do Claude Code (`hooks/hooks.json` de plugin) | não toca `settings.json`; hooks de plugin "stay separate" **[CONFIRMADO]** | exige marketplace/instalação de plugin, fluxo fora do app, `${CLAUDE_PLUGIN_ROOT}` | avaliar depois; muda o produto |
| Shell form com aspas | compatível com qualquer versão | shell e interpolação | só se 2.1.139 for mínimo alto demais |
| Symlink estável → bundle (iTerm2) | sem cópia | pendura se mover o app | não |

## 9. Repositórios citados

- iTerm2 — `sources/ClaudeCode/ClaudeCodeOnboarding.swift` (`writeSettings`: resolve symlink + `.atomic`; merge que nunca escreve JSON inválido; symlink estável do helper) e `ModernTests/ClaudeCodeHookOwnershipTests.swift` (posse por caminho exato): <https://github.com/gnachman/iTerm2>
- Peep — `Sources/Peep/Hooks.swift` (status `none/current/stale`, merge com `async: true, timeout: 5`, recusa JSON inválido; bug do grupo inteiro): <https://github.com/jclasley/peep>
- Outros apps de barra de menu que instalam hooks (só snippets de busca, código não lido): <https://github.com/m1ckc3s/claude-status-bar>, <https://github.com/Magir/clabar>, <https://github.com/Hamma111/nudgy>, <https://github.com/tcballard/Meanwhile>

## 10. Não confirmado (testar antes de afirmar)

1. Em exec form, o pai direto do hook é o processo `claude` (para `getppid()` substituir `--pid $PPID`).
2. `~` não é expandido em exec form (doc só confirma `$`); irrelevante se o caminho for gravado expandido.
3. Comportamento de Claude Code < 2.1.139 diante de `args` (provável: ignora e roda `command` sem argumentos).
4. `Bundle.main` dentro do CLI `claudebar-hook` (em `Contents/MacOS`) aponta para o `.app`.
5. Cópia do binário vinda de DMG com `com.apple.quarantine` ser barrada quando o Claude Code a executa.
6. Nenhum aviso de Swift 6 strict concurrency com `[String: Any]` mantido em funções síncronas chamadas do `@MainActor`.
7. Código de m1ckc3s/claude-status-bar, Clabar, nudgy, Meanwhile (só snippets de busca).
8. Janela SwiftUI/`openWindow` abrindo atrás em app `.accessory` (relatos de fórum, não doc).

