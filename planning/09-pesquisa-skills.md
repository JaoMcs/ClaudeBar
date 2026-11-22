# 09 — Pesquisa: material pronto para desenvolver com agentes

Data: 2026-11-22. Estrelas e último push conferidos via `gh api` no mesmo dia. Nada foi instalado nem clonado.

Contexto: ClaudeBar (Swift 6, SwiftPM, macOS 14, testes em **Swift Testing**), loop implementador → revisor → merge com foco em economizar tokens.

Conclusão geral: **a maior parte do que estamos montando à mão já existe nativo no Claude Code** (frontmatter de subagente com `model`/`effort`/`tools`/`isolation`, dynamic workflows, Stop hook, `/usage` com atribuição por subagente). Coleções gigantes de agentes e frameworks de spec (BMAD, Spec Kit) custam mais token do que economizam para um projeto deste tamanho. Vale pegar peças pequenas e copiar ideias.

---

## Top 10 — adotar já

| # | O quê | Por quê para nós | Passo de adoção |
|---|---|---|---|
| 1 | **Frontmatter oficial de subagente** — [docs sub-agents](https://code.claude.com/docs/en/sub-agents) | Campos `model` (haiku/sonnet/opus/inherit), `effort`, `tools`/`disallowedTools`, `isolation: worktree`, `skills`, `memory`. É o roteamento haiku/sonnet/opus nativo, sem ferramenta externa. A restrição de `tools` é imposta pelo Claude Code, não pedida no prompt. | Criar `.claude/agents/implementador.md` (`model: sonnet`, `isolation: worktree`), `revisor.md` (`model: sonnet`, `tools: Read, Grep, Glob, Bash`, sem Edit/Write), `merge.md` (`model: haiku`, `effort: low`). Prompt curto em cada um. |
| 2 | **Revisor “contra a spec, skip style”** — [best practices › Review against your spec](https://code.claude.com/docs/en/best-practices) | O doc oficial avisa: revisor pedido para achar problema sempre acha algo; corrigir tudo gera abstração e teste inútil. Bate com nosso foco em diff mínimo. | Copiar o `reviewer.md` de exemplo do doc (5 linhas) e apontar para `planning/06-tasks/Txx.md` como spec. Pedir “report only correctness gaps, skip style”. |
| 3 | **Stop hook com build/test** — [best practices › Enforce the check with a Stop hook](https://code.claude.com/docs/en/best-practices) | Garante que o implementador não diz “pronto” com `swift build`/`swift test` falhando, sem gastar token de revisor para descobrir isso. | Em `.claude/settings.json`: hook `Stop` com `swift build 2>&1 | tail -40 1>&2 && swift test 2>&1 | tail -40 1>&2 || exit 2`. |
| 4 | **Dynamic workflows** — [docs workflows](https://code.claude.com/docs/en/workflows) | É literalmente o loop que estamos orquestrando: script JS com `agent()`/`pipeline()`/`parallel()`, resultados intermediários ficam em variáveis do script (não no contexto do orquestrador), modelo por estágio, retomável, salvável como comando `/nome`. | Pedir “use a workflow” para uma task (ex.: T05) com estágios implementar → revisar → corrigir; se servir, `/workflows` → `s` para salvar em `.claude/workflows/`. Setar `workflowSizeGuideline: small`. |
| 5 | **swift-lsp** (plugin oficial) — [claude-plugins-official/plugins/swift-lsp](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/swift-lsp) — Apache-2.0, 48k★ no repo | SourceKit-LSP: go-to-definition em vez de grep+ler arquivos, e erros de tipo reportados após cada edit sem rodar compilador. O doc de custos cita isso como redução de leituras. | `/plugin install swift-lsp@claude-plugins-official`. Requer `sourcekit-lsp` (vem com o Xcode/toolchain). |
| 6 | **Disciplina de custo do doc oficial** — [Manage costs](https://code.claude.com/docs/en/costs) | Lista concreta: CLAUDE.md < 200 linhas e procedimentos em skills; `/usage` mostra % por subagente/skill/MCP com recomendações (`f` aplica); `CLAUDE_CODE_SUBAGENT_MODEL`; hook PreToolUse que corta saída de teste; `/clear` entre tasks; cache de subagente é 5 min (`subagentPromptCacheTtl`). | Rodar `/usage` após 2–3 tasks do loop e cortar o subagente que mais gasta. Adicionar seção `# Compact instructions` no CLAUDE.md. Mover o procedimento do loop do AGENTS.md para uma skill. |
| 7 | **pr-review-toolkit** (plugin oficial) — [link](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) — MIT | 6 agentes prontos; os úteis para nós: `code-reviewer` (score 0–100, só reporta ≥ alto), `silent-failure-hunter` (erros engolidos — relevante para hooks/polling), `pr-test-analyzer`. Os outros (comentários, type-design, simplifier) são ruído. | Não instalar o plugin inteiro: ler `agents/code-reviewer.md` e `silent-failure-hunter.md`, copiar o critério de confiança para o nosso `revisor.md`. Alternativa sem custo: skill `/code-review` que já existe aqui. |
| 8 | **SwiftUI Agent Skill** — [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) — MIT, 3.9k★, push 2026-11-06 | Tem referências **macOS** (scenes, views, window styling) carregadas sob demanda; guia de APIs deprecadas → modernas. Alternativa: [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) (6.6k★, 2026-10-26). Escolher **um**. | `/plugin marketplace add AvdLee/SwiftUI-Agent-Skill` → `swiftui-expert@swiftui-expert-skill`. Ler o SKILL.md antes. Pré-carregar só no implementador via `skills:` se for UI. |
| 9 | **Swift Concurrency + Swift Testing skills** — [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) (MIT, 1.7k★, 2026-11-06) e [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill) (MIT, 483★, 2026-09-14) | Swift 6 strict concurrency (Sendable, MainActor) é onde o agente mais erra; e usamos `import Testing`. Mesmo autor da #8, estilo consistente. | Instalar como plugin/skill; não pré-carregar sempre — deixar a description disparar só quando o diff toca concorrência/testes. |
| 10 | **Ideias do Superpowers (não instalar inteiro)** — [obra/superpowers](https://github.com/obra/superpowers) — MIT, 324k★, push 2026-11-03 | Skills boas: `writing-plans` (tasks de 2–5 min com arquivo, código e verificação), `verification-before-completion`, `systematic-debugging`, `finishing-a-development-branch`. Mas o próprio README avisa que `subagent-driven-development` é o modo mais caro e que sessões podem queimar mais token que o esperado. | Ler os SKILL.md de `writing-plans`, `verification-before-completion` e `systematic-debugging`; copiar só os critérios que faltam para os nossos templates em `planning/06-tasks/`. Se quiser testar: `/plugin install superpowers@claude-plugins-official` numa sessão isolada e medir com `/usage`. |

---

## 1. Skills e coleções

| Nome | Link | O que é | Licença / sinais | Utilidade | Instalação |
|---|---|---|---|---|---|
| anthropics/skills | https://github.com/anthropics/skills | Repo oficial de skills (docx/pdf/xlsx, skill-creator, webapp-testing, template) | Apache-2.0 na maioria; 199k★; push 2026-11-16 | **Baixa** — nada de Swift/git; útil só o `template-skill` e `skill-creator` (já disponível aqui) | `/plugin marketplace add anthropics/skills` |
| claude-plugins-official | https://github.com/anthropics/claude-plugins-official | Marketplace oficial (Anthropic) | Apache-2.0; 48k★; ativo | **Alta** — ver itens abaixo | `/plugin install <nome>@claude-plugins-official` |
| ↳ code-review | idem `/plugins/code-review` | Review de PR com vários agentes e score de confiança | | Média — sobrepõe a skill `/code-review` já disponível | plugin |
| ↳ commit-commands | idem `/plugins/commit-commands` | Comandos commit/push/PR | | Média — o agente de merge pode usar; nossos commits são em PT, ajustar | plugin |
| ↳ claude-md-management | idem | Audita CLAUDE.md e captura aprendizados da sessão | | Média — ajuda a manter CLAUDE.md/AGENTS.md curtos | plugin |
| ↳ session-report | idem | Relatório HTML de tokens por subagente/skill, cache, prompts mais caros | | **Alta** para medir o loop | plugin |
| ↳ feature-dev | idem | Fluxo explorar → arquitetar → revisar com agentes | | Baixa — já temos o nosso fluxo | plugin |
| ↳ ralph-loop | idem | Loop while-true com o mesmo prompt até terminar | | Baixa — caro; o doc de best practices desaconselha “loop until done” | plugin |
| ↳ hookify | idem | Gera hooks a partir de padrões da conversa | | Média — atalho para os hooks da #3 | plugin |
| ↳ claude-code-setup | idem | Recomenda hooks/skills/MCP/subagentes para o repo | | Média — rodar uma vez | plugin |
| twostraws/Swift-Agent-Skills | https://github.com/twostraws/Swift-Agent-Skills | Lista curada de skills Swift | MIT; 3k★; 2026-09-04 | Média — índice; não lista nada de AppKit/SwiftPM | só leitura |
| twostraws Swift Concurrency / Testing Pro | https://github.com/twostraws/Swift-Concurrency-Agent-Skill · https://github.com/twostraws/Swift-Testing-Agent-Skill | Skills de Paul Hudson | MIT; ~0.5k★; push 2026-05 | Média — alternativa às AvdLee, menos ativas | plugin/cópia |
| Dimillian/Skills | https://github.com/Dimillian/Skills | Skills Codex (SwiftUI patterns, view refactor, performance audit, concurrency) | MIT; 4k★; push 2026-03-29 | Média-baixa — escritas para Codex, parado há 8 meses | cópia de SKILL.md |
| rshankras/claude-code-apple-skills | https://github.com/rshankras/claude-code-apple-skills | Coleção ampla Apple (inclui macos-development) | MIT; 905★; 2026-11-09 | Média — amplo demais; ler só `macos-development` | plugin com tags estáveis |
| jazzychad/ios-code-audit | https://github.com/jazzychad/ios-code-audit | Skill de auditoria de código iOS | MIT; 41★ | Baixa — iOS, pouco uso | cópia |
| AvdLee/Xcode-Build-Optimization-Agent-Skill | https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill | Otimização de build Xcode | MIT; 1.3k★ | Baixa — não usamos projeto Xcode | — |
| Jeffallan/claude-skills (swift-expert) | https://github.com/Jeffallan/claude-skills | Skills genéricas por linguagem | MIT; 12k★; ativo | Baixa — genérico | — |
| makgunay/claude-swift-skills, hmohamed01/swift-development, tddworks/claude-skills | | Skills Swift avulsas | 1–62★ | **Descartar** — sem tração | — |
| ComposioHQ/awesome-claude-skills | https://github.com/ComposioHQ/awesome-claude-skills | Lista de skills | 80k★; 2026-09 | Baixa — catálogo genérico | só leitura |
| travisvn/awesome-claude-skills | https://github.com/travisvn/awesome-claude-skills | Lista de skills | 16k★; parado desde 2026-04 | Descartar | — |
| hesreallyhim/awesome-claude-code | https://github.com/hesreallyhim/awesome-claude-code | Lista curada de skills, hooks, comandos, ferramentas | 59k★; push hoje | Média — melhor índice para buscar algo pontual | só leitura |
| davepoon/buildwithclaude | https://github.com/davepoon/buildwithclaude | Hub de skills/agents/hooks/plugins | MIT; 3.8k★; ativo | Baixa | só leitura |

## 2. Subagentes prontos e padrões de AGENTS.md/CLAUDE.md

| Nome | Link | O que é | Sinais | Utilidade | Instalação |
|---|---|---|---|---|---|
| Exemplo `reviewer.md` do doc oficial | https://code.claude.com/docs/en/best-practices | Revisor read-only, contra spec, “skip style” | oficial | **Alta** (Top 10 #2) | copiar |
| pr-review-toolkit agents | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit/agents | code-reviewer, silent-failure-hunter, pr-test-analyzer, etc. | oficial, MIT | **Alta** (Top 10 #7) | copiar arquivos |
| code-simplifier (oficial) | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-simplifier | Agente que simplifica preservando comportamento | oficial | Média — já temos ponytail/`/simplify` | plugin |
| VoltAgent/awesome-claude-code-subagents | https://github.com/VoltAgent/awesome-claude-code-subagents | 100+ subagentes por categoria | MIT; 27k★; 2026-11-02 | Baixa — prompts longos e genéricos; ler `swift-expert`/`code-reviewer` como referência | copiar arquivo |
| wshobson/agents | https://github.com/wshobson/agents | 93 plugins, 199 agentes, 185 skills; agentes já com alias de modelo | MIT; 43k★; push hoje | Média-baixa — bom exemplo de tiering por agente (ver `docs/agents.md#model-configuration`), nada de Swift | `/plugin install <x>@claude-code-workflows` granular |
| 0xfurai/claude-code-subagents | https://github.com/0xfurai/claude-code-subagents | 100+ agentes por linguagem | MIT; 1k★ | Baixa | — |
| vijaythecoder/awesome-claude-agents, lst97, iannuttall | | Coleções antigas | parados 2025 / arquivado | **Descartar** | — |
| AGENTS.md (padrão aberto) | https://agents.md · https://github.com/agentsmd/agents.md | Formato comum para Codex/Cursor/Claude etc. | MIT; 26k★ | Média — já temos AGENTS.md; manter CLAUDE.md apontando para ele | — |
| Best practices › Keep CLAUDE.md short / What you can stop doing | https://code.claude.com/docs/en/best-practices | Só o que o repo não mostra (comandos, convenções, gotchas); sem CAPS/IMPORTANT; sem descrever arquitetura | oficial | **Alta** — revisar nosso AGENTS.md (72 linhas) contra isso | — |
| steipete/agent-rules | https://github.com/steipete/agent-rules | Regras de agente do Peter Steinberger (dev macOS) | MIT; arquivado | Baixa — arquivado; sucessor é [steipete/agent-scripts](https://github.com/steipete/agent-scripts) (7.6k★, ativo), vale ler pelo viés macOS/Swift | só leitura |

## 3. Metodologias e guias

| Nome | Link | O que é | Utilidade | Nota |
|---|---|---|---|---|
| Best practices for Claude Code | https://code.claude.com/docs/en/best-practices | Guia oficial atual | **Alta** | Pontos-chave: dar ao agente um check para rodar; regra sem exceção vira hook/deny, não texto; subagente não deixa resposta melhor, só paralelismo/olho novo; tabela “What you can stop doing” |
| Manage costs | https://code.claude.com/docs/en/costs | Guia oficial de tokens | **Alta** | Top 10 #6 |
| Sub-agents | https://code.claude.com/docs/en/sub-agents | Referência do frontmatter | **Alta** | `CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` força um modelo para todos |
| Dynamic workflows | https://code.claude.com/docs/en/workflows | Orquestração por script | **Alta** | Top 10 #4 |
| How and when to use subagents | https://claude.com/blog/how-and-when-to-use-subagents-in-claude-code | Post oficial (abr/2026) | Média | Resume quando delegar |
| Effective context engineering for AI agents | https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents | Engenharia de contexto (Anthropic) | Média | Base teórica de compaction, notas estruturadas, sub-agent isolation |
| Building effective agents / Multi-agent research system | https://www.anthropic.com/engineering/building-effective-agents · https://www.anthropic.com/engineering/multi-agent-research-system | Padrões (orchestrator-workers, evaluator-optimizer) | Média | Leitura única; já aplicamos orchestrator-workers |
| GitHub Spec Kit | https://github.com/github/spec-kit | spec → plan → tasks → implement, comandos para Claude Code | MIT; 151k★; ativo | **Baixa** — nosso `planning/05-specs` + `06-tasks` já é isso; adotar duplicaria. Útil só o template de spec como checklist |
| OpenSpec | https://github.com/Fission-AI/OpenSpec | SDD leve, focado em mudanças (deltas) em projeto existente | MIT; 75k★; ativo | Média — mais próximo do nosso caso (brownfield) que Spec Kit; copiar a ideia de “proposal/delta” se as tasks crescerem |
| BMAD-METHOD | https://github.com/bmad-code-org/BMAD-METHOD | Time simulado de ~21 agentes (PM, arquiteto, SM…) | 56k★; licença não-padrão | **Descartar** — pesado demais para um app de barra de menu, contrário ao foco em token |
| Kiro (AWS) | https://kiro.dev | IDE (fork VS Code) com specs | proprietário | Descartar — troca de ferramenta |
| get-shit-done | https://github.com/gsd-build/get-shit-done | Framework de SDD para Claude Code | MIT; 64k★; **arquivado** | Descartar |
| context-engineering-intro | https://github.com/coleam00/context-engineering-intro | Template PRP (product requirement prompts) | MIT; 14k★; parado desde 2026-03 | Baixa |
| SuperClaude Framework | https://github.com/SuperClaude-Org/SuperClaude_Framework | Comandos/personas sobre Claude Code | MIT; 24k★ | Baixa — infla contexto |
| Comparativo SDD 2026 | https://dev.to/willtorber/spec-kit-vs-bmad-vs-openspec-choosing-an-sdd-framework-in-2026-d3j | Artigo comparativo | Baixa | Confirma: Spec Kit greenfield, OpenSpec brownfield, BMAD enterprise |

## 4. Ferramentas que já fazem o que montamos

| Nome | Link | O que é | Sinais | Utilidade | Nota |
|---|---|---|---|---|---|
| Dynamic workflows (nativo) | https://code.claude.com/docs/en/workflows | Orquestração multiagente por script, modelo por estágio | oficial | **Alta** | Substitui boa parte do maestro manual |
| Agent teams (nativo, experimental) | https://code.claude.com/docs/en/agent-teams | Lead + teammates com lista de tarefas | oficial | Baixa | Doc: ~7x tokens em plan mode; desligado por padrão |
| claude-code-action | https://github.com/anthropics/claude-code-action | GitHub Action: Claude responde `@claude` e revisa PR no CI | MIT; 10k★; ativo | Média | Tira o revisor da máquina local; custa API/assinatura no CI. Avaliar só se o review local virar gargalo |
| claude-code-security-review | https://github.com/anthropics/claude-code-security-review | Action de review de segurança | MIT; 7k★; parado desde 2026-02 | Baixa | Já há `/security-review` local |
| claude-code-router | https://github.com/musistudio/claude-code-router | Proxy que roteia requisições para modelos/provedores diferentes | MIT; 38k★ | **Baixa** | Roteamento haiku/sonnet/opus já é nativo (`model` no subagente, `opusplan`); proxy adiciona risco |
| ccusage | https://github.com/ccusage/ccusage | CLI que lê logs locais e mostra tokens/custo por sessão/dia | MIT; 20k★; ativo | Média | Para medir antes/depois; `/usage` + session-report já cobrem quase tudo |
| rtk | https://github.com/rtk-ai/rtk | Proxy de CLI que comprime saída de comandos (git, test…) para o LLM | Apache-2.0; 87k★; ativo | Média | Promete 60–90% menos token em saída de comando; binário de terceiro no caminho de todo Bash — avaliar com cuidado. Hook de `tail` do doc oficial resolve o grosso sem dependência |
| claude-squad | https://github.com/smtg-ai/claude-squad | TUI que roda várias sessões em worktrees | AGPL-3.0; 9k★ | Baixa | `isolation: worktree` nativo cobre |
| vibe-kanban | https://github.com/BloopAI/vibe-kanban | Kanban que dispara agentes por card, com worktree e review | Apache-2.0; 29k★ | Baixa | Interface a mais; nosso INDEX.md já é o board |
| cmux | https://github.com/manaflow-ai/cmux | Terminal macOS (Ghostty) com abas/notificações para agentes | 29k★ | Baixa | Concorrente indireto do próprio ClaudeBar — vale olhar como referência de produto |
| ruflo (ex claude-flow) | https://github.com/ruvnet/ruflo | “Swarm” de agentes, MCP, memória | MIT; 82k★ | **Descartar** | Complexidade e token altos, muito marketing |
| ccpm | https://github.com/automazeio/ccpm | PM via GitHub Issues + worktrees paralelos | MIT; 8k★ | Baixa | Ideia de issue-por-task; nosso fluxo já tem |
| humanlayer | https://github.com/humanlayer/humanlayer | Aprovação humana/IDE para agentes | Apache-2.0; 13k★ | Baixa | |
| Claude Code Agent Farm | https://github.com/Dicklesworthstone/claude_code_agent_farm | Dezenas de sessões em paralelo | 925★ | Descartar | |
| serena / claude-context | https://github.com/oraios/serena · https://github.com/zilliztech/claude-context | MCP de busca semântica no código | 32k★ / 13k★ | Baixa | Repo pequeno; swift-lsp basta |

---

## O que NÃO fazer (resumo crítico)

- Não instalar coleções inteiras (wshobson, VoltAgent, superpowers completo): cada skill/agente adiciona descrição ao contexto e dispara em hora errada.
- Não adotar BMAD/Spec Kit: duplicam `planning/`.
- Não usar proxy de roteamento de modelo: o nativo resolve.
- Não usar `ralph-loop`/agent teams no loop padrão: caros por desenho.
