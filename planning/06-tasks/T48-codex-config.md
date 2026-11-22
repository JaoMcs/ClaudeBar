# T48 — Multiagente, parte 3: Codex CLI (configuração para copiar)

- **Funcionalidade:** F53 (3/3) — "Codex CLI" do `TODO.md`
- **Esforço:** 2,5 h
- **Depende de:** T43, T44 · **Bloqueia:** —
- **Branch:** `feat/codex-config`
- **PR:** `feat: sessões do Codex CLI no menu (configuração para copiar)`

## Objetivo

Sessões do Codex CLI aparecerem no menu com `--agent codex`, como o Gemini (T44). Diferença: o Codex usa `~/.codex/config.toml` (TOML) e o projeto não tem parser TOML nem dependência externa. Por isso **o app não grava o arquivo do Codex**: mostra a configuração pronta para o usuário colar e detecta (só leitura) se ela já está lá.

## Pesquisa obrigatória antes de codar

- Ler a documentação oficial atual do Codex CLI (OpenAI) sobre `notify` e sobre hooks, se existirem. Responder na descrição do PR, com links: quais eventos existem (fim de turno, pedido de aprovação, início/fim de sessão), o nome dos campos de sessão e diretório, e confirmar o que o `TODO.md` já registra (o `notify` recebe o JSON como **argumento**, não pelo stdin, e só avisa fim de turno). Fontes: a documentação oficial do Codex CLI no site/repositório da OpenAI e `codex --help` do CLI instalado (só leitura; não rode sessões).
- Se a doc só tiver `notify` de fim de turno: mapear só `idle` e registrar em "Não verificado" que "trabalhando/esperando" não existem para o Codex.
- Sem acesso à documentação (sem web) ou se ela não confirmar nada disso: pare, deixe o PR em rascunho com a pesquisa e escreva **BLOQUEADA** com o motivo.

## Subtasks

- [ ] `Sources/ClaudeBarCore/CodexConfig.swift` (novo): `cliDetected(paths:)` (caminhos fixos: `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`; sem shell de login), `snippet(binary:) -> String` com o TOML a colar (só texto fixo nosso, **sem variável de shell**), `isConfigured(configText:binary:) -> Bool` (busca simples de linha, sem parser).
- [ ] `claudebar-hook`: aceitar o formato de entrada do Codex (argv ou stdin, conforme a pesquisa) com `--agent codex`; falha sempre fail-open (nunca `exit 2`, erro só no stderr).
- [ ] Menu (`HookSetup.swift`/`MenuContent.swift`): se o Codex for detectado, item "Copiar configuração do Codex" (copia o `snippet` e mostra num alerta onde colar) e o estado "Codex: configurado / não configurado" lido do arquivo.
- [ ] Testes (`Tests/ClaudeBarTests/CodexConfigTests.swift`, novo) com caminhos injetados ou `mktemp -d`, **nunca o `~/.codex` real**: snippet sem `$`; `isConfigured` verdadeiro/falso; parse da entrada do Codex com exemplo da doc.
- [ ] READMEs (en e pt-BR): seção "Codex CLI"; `TODO.md`: marcar Codex.

## Arquivos

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeBarCore/CodexConfig.swift` | novo |
| `Sources/claudebar-hook/main.swift` | entrada do Codex |
| `Sources/ClaudeBar/HookSetup.swift`, `Sources/ClaudeBar/MenuContent.swift` | item de menu |
| `Resources/en.lproj/Localizable.strings`, `Resources/pt-BR.lproj/Localizable.strings` | textos |
| `Tests/ClaudeBarTests/CodexConfigTests.swift` | novo |
| `README.md`, `README.pt-BR.md`, `TODO.md` | docs |

## Critérios de aceite

- Nenhuma escrita em `~/.codex`; o app só lê.
- `scripts/dev/gates.sh` → `gates=ok`.
- PR com a pesquisa (links) e "Não verificado": sessão real do Codex aparecendo no menu.

## Fora do escopo

Editar TOML automaticamente; "Ir para a sessão" do Codex (pid 0, como o Gemini).
