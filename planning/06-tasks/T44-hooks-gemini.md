# T44 — Multiagente, parte 2: hooks do Gemini CLI

- **Funcionalidade:** F53 (2/2) — "Support other coding agents" do `TODO.md`
- **Esforço:** 2,5 h
- **Depende de:** T43 · **Bloqueia:** —
- **Branch:** `feat/hooks-gemini`
- **PR:** `feat: registrar hooks do Gemini CLI (opt-in, só se o CLI existir)`
- **Estado da pesquisa:** doc confirma os 4 eventos (abaixo). Não está BLOQUEADA. Dois pontos ficam em "Não verificado".

## Pesquisa (feita em 2026-11-22; reconferir antes de implementar)

Fontes oficiais:

- Visão geral dos hooks: https://geminicli.com/docs/hooks/
- Referência (campos, payloads, códigos de saída): https://geminicli.com/docs/hooks/reference/
- Escrever hooks: https://geminicli.com/docs/hooks/writing-hooks/
- Configuração (`hooks`, `hooksConfig.enabled`): https://geminicli.com/docs/reference/configuration/

O que a doc confirma:

| Evento do Gemini | Quando dispara (doc) | Estado no app |
|---|---|---|
| `BeforeAgent` | depois do prompt enviado, antes de planejar | `working` |
| `AfterAgent` | uma vez por turno, depois da resposta final | `idle` |
| `Notification` | alerta do sistema; `notification_type` hoje só `ToolPermission` | `waiting` (`--kind permission`) |
| `SessionEnd` | CLI sai ou sessão é limpa (`reason`: `exit`, `clear`, `logout`, `prompt_input_exit`, `other`); best effort, o CLI não espera | `end` |

- Arquivo: `~/.gemini/settings.json` (usuário); também `.gemini/settings.json` (projeto) e `/etc/gemini-cli/settings.json` (sistema). Só mexemos no do usuário.
- Formato: `hooks.<Evento>` é array de `{ "matcher"?, "sequential"?, "hooks": [ { "type": "command", "command": "...", "name"?, "timeout"? (ms, padrão 60000) } ] }`.
- Payload no stdin: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`; no `Notification` também `notification_type`, `message`, `details`. Os campos `session_id` e `cwd` são os que o `HookPayload` de `Sources/claudebar-hook/main.swift` já lê. `transcript_path` não é lido (o app não lê conversa).
- Saída: stdout só pode ter o JSON final (o hook nosso não imprime nada nesses estados); código `0` ok, **`2` bloqueia** (o hook nunca sai com 2: `fail` usa 1), outro = aviso sem bloquear.
- Chave `hooksConfig.enabled` desliga o sistema de hooks inteiro: tratar como `hooksDisabled`, sem mexer.

## Objetivo

Registrar no `~/.gemini/settings.json` os 4 hooks acima, chamando o executável estável com `--agent gemini` (campo da T43), para sessões do Gemini CLI aparecerem no menu e na barra. Só se o Gemini CLI existir, só por ação do usuário com prévia + backup (as mesmas garantias dos hooks do Claude).

## Subtasks

- [ ] Detecção do CLI **sem shell de login**: `FileManager.isExecutableFile` em caminhos fixos (`/opt/homebrew/bin/gemini`, `/usr/local/bin/gemini`) ou `~/.gemini` existir. Nada de `zsh -lc`. Função pura recebendo o `FileManager`/lista de caminhos para teste.
- [ ] `Sources/ClaudeBarCore/GeminiHooks.swift` (novo): `entries` (evento + args) e `install(_:binary:)`/`strip(_:binary:)` puras, reaproveitando `HookInstaller.parse`, `serialize`, `lineDiff`, `isWritable` e `apply` (internos, mesmo módulo). Handler no formato do Gemini: `{"type":"command","command":"<binário entre aspas> <estado> --agent gemini","timeout":5000}` (timeout em **milissegundos**; `SessionEnd` sem `timeout`, como no Claude). O `command` é string de shell (a doc não documenta `args` em array), mas **só texto fixo nosso**: `HookInstaller.shellQuoted(binary)` + argumentos literais, **sem nenhuma variável de shell** (`$PPID`, `$HOME`…). Mesmo precedente do `statusLine` em `plan(_:)`. Decisão da revisão do PR #41.
- [ ] Reconhecimento do que é nosso: `command` que começa com o caminho estável entre aspas e contém `--agent gemini`. Nunca tocar em hook de outra origem.
- [ ] `plan` para o arquivo do Gemini: `HookInstaller.plan` já aceita `settings:`; criar `GeminiHooks.plan(_:settings:binary:)` que devolve o mesmo `HookPlan` (diff só de `hooks`).
- [ ] PID: sem `--pid`. Com `--agent gemini`, o hook grava `pid` 0 (a checagem de pai `claude` do `getppid()` continua só para o Claude). A sessão do Gemini vive pelos hooks: some no `SessionEnd` ou pela regra de sessões fantasmas da T08. Anotar em "Não verificado" se aparecerem fantasmas.
- [ ] Menu: itens "Instalar hooks do Gemini…" / "Remover hooks do Gemini…" no bloco da integração, só aparecem se o CLI foi detectado; reaproveitam o fluxo de prévia de `HookSetup` (nova variante, sem duplicar o alerta).
- [ ] `claudebar-hook install --gemini [--dry-run]` / `uninstall --gemini` no CLI (mesmo padrão do `--statusline`).
- [ ] Binário estável: `binaryInUse` considera também os hooks do Gemini (remover os do Claude não pode apagar o executável se o Gemini ainda o usa).
- [ ] Testes (`Tests/ClaudeBarTests/GeminiHooksTests.swift`, novo), **sempre com caminho injetado ou `mktemp -d`, nunca o `~/.gemini` real**: merge aditivo preserva hook do usuário no mesmo evento; idempotente e reversível; não toca em hook parecido; JSON inválido não vira plano; arquivo ausente vira só os nossos 4; `timeout` em ms e `SessionEnd` sem timeout; nunca `exit 2` (nenhum `command` contém `exit 2`); detecção do CLI (achou/não achou); nenhum `command` gerado contém `$`.
- [ ] READMEs: seção "Gemini CLI" (opt-in, só se instalado, `~/.gemini/settings.json`, links da doc) e a linha do `TODO.md` marcada.
- [ ] `TODO.md`: marcar "Gemini CLI" e a linha de "register only if installed" (a parte do Codex fica).
- [ ] Gates, commit, PR.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/GeminiHooks.swift` | novo: entries, install/strip, plan, detecção |
| `Sources/ClaudeBarCore/HookInstaller.swift` | `binaryInUse` considera o Gemini; `shellQuoted` reutilizado |
| `Sources/claudebar-hook/main.swift` | `install/uninstall --gemini` |
| `Sources/ClaudeBar/HookSetup.swift` | fluxo de prévia do Gemini |
| `Sources/ClaudeBar/MenuContent.swift` | 2 itens condicionais |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | strings |
| `Tests/ClaudeBarTests/GeminiHooksTests.swift` | novo |
| `TODO.md`, `README.md`, `README.pt-BR.md` | status e seção |

## Critérios de aceite

- Nada é gravado sem prévia + backup; arquivo que não é JSON de objeto = nada gravado; `hooksConfig.enabled == false` = não mexe.
- Sem Gemini CLI detectado, nenhum item aparece e nenhum arquivo em `~/.gemini` é criado.
- Hooks do usuário no `~/.gemini/settings.json` ficam intactos; remover tira só os nossos.
- Sessão do Gemini aparece no menu com o rótulo `[gemini]` (T43).
- `swift build` e `swift test` verdes (anterior + novos). Nenhum teste escreve no `~/.gemini` ou `~/.claude` reais (usar pasta temporária).

## Não verificado (declarar no PR)

- Que o Gemini CLI executa `command` por shell e expande `$PPID` para o PID do próprio `gemini` (a doc só diz "shell command"). Se não expandir, o `pid` fica 0 e o "Ir para a sessão" não aparece para essas linhas.
- Que `~/.gemini/settings.json` aceita a chave `hooks` na versão do CLI instalada pelo dono (a doc não marca como experimental, mas também não afirma que vem ligado por padrão).

## Limitação conhecida (decisão do dono)

Só o `Notification` tira a sessão de `working` para `waiting`; não há equivalente ao `PostToolUse --if-waiting`. Um `AfterTool` → `working --if-waiting` resolveria; fica fora desta task, que segue a lista pedida.

## Fora do escopo

Codex CLI (`notify` em `~/.codex/config.toml`), Antigravity, `AfterTool`, hooks de projeto/sistema, `AgentsProbe` e `SessionTerminator` para o Gemini, ícone por agente.
