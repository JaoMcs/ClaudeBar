# Plano mestre — Evolução do ClaudeBar

> Pasta temporária `planning/` (fora do git via `.git/info/exclude`). Apagada no fim, depois da triagem crítica (Passo 9).
> Data: 2026-11-15. Baseline: `main` @ f943cc4, `swift build` ok, 34 testes passando.

## Prompt refinado (o que o usuário pediu + o que eu acrescentei)

**Objetivo:** levar o ClaudeBar a ficar no mesmo nível dos concorrentes (Claude Status Bar, Nudgy, AgentBar, CodexBar…) e criar algo novo, entregando tudo por PRs pequenos revisados e mergeados em `main`.

Pedidos do usuário:
1. Estudo de concorrentes + possibilidades de inovação, com gestão dos pontos levantados.
2. Painel de subagentes "usuários" (sem contexto do projeto) debatendo para achar melhorias.
3. Outros subagentes validando as funcionalidades propostas.
4. Pesquisa detalhada de **como fazer** cada funcionalidade (subagentes).
5. Markdowns com tudo isso.
6. Especialista macOS refinando cada funcionalidade a nível técnico (tasks, código, passo a passo).
7. Gestor quebrando em tasks/subtasks `.md` na pasta do projeto.
8. Loop: por task → branch → PR → revisor independente comenta → corrige o que fizer sentido → merge em `main`. Até acabar.
9. Agente de design em background até entregar o ícone final, integrado ao projeto.
10. Levantar o que falta e o que depende do usuário.
11. Relatório final. Antes de apagar os `.md` temporários, triagem crítica e guardar só o essencial.

**Acréscimos meus (guard rails):**
- **Gates por PR:** `swift build` e `swift test` verdes; nenhum teste removido para passar; build do `.app` (`scripts/build-app.sh`) quando a task mexer em bundle/recursos.
- **Promessas de segurança do README não podem regredir:** sem rede por padrão (qualquer rede é opt-in e explícita), diretório `0700`/arquivos `0600`, nada via shell com interpolação, não ler conversas sem opt-in.
- **Ícone original:** nada de logo da Anthropic/Claude nem cópia de ícone de concorrente (risco de marca e de impersonação). Inspiração sim, cópia não.
- **PRs pequenos e independentes**, um assunto por PR, `squash merge`, branch apagada após merge. Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; PR com rodapé do Claude Code.
- **Revisor sem contexto do implementador** (só o diff + a task). Como o PR é da mesma conta, a revisão sai como `gh pr review --comment` (GitHub não deixa aprovar o próprio PR).
- **O repo é público:** PRs e comentários ficam visíveis. Nada de dado pessoal, caminho de máquina ou e-mail nos textos.
- **O que depende do usuário não é inventado:** Developer ID, notarização, nome definitivo, licença, bundle id, tap do Homebrew, conta paga → vai para `PENDENCIAS` com o passo exato que falta. Código preparado (ex.: script de notarização que lê credenciais de env) pode entrar, desde que funcione sem elas.
- **Verificação honesta:** o que não deu para testar (UI da barra de menu, notificação nativa, outro Mac) aparece como "não verificado" no relatório.
- **Ordem do loop:** bugs e base primeiro → distribuição → UX diferencial → limites → multi-agente → novidades. Tasks que mexem nos mesmos arquivos rodam em sequência.
- **Design isolado:** o agente de design trabalha só em `planning/07-design/`. A integração do ícone no app vira uma task normal do loop (PR revisado), para não brigar com os outros PRs.
- **Ponytail:** cada task na menor forma que resolve; sem abstrações especulativas.

## Step-by-step

| # | Passo | Como | Saída |
|---|---|---|---|
| 0 | Pré-checagem | eu | repo, `gh`, baseline (feito) |
| 1 | Pesquisa de mercado e inovação | Workflow A, fase *Pesquisa* (4 agentes, ângulos diferentes) | `01-pesquisa/*.md` |
| 2 | Painel de usuários | Workflow A, fase *Painel* (6 personas sem contexto, 2 rodadas de debate + moderador) | `02-painel/*.md` |
| 3 | Validação das funcionalidades | Workflow A, fase *Validação* (3 validadores com lentes: valor, viabilidade técnica, risco/segurança) + sintetizador | `03-validacao/*.md` + `03-validacao/BACKLOG.md` |
| — | Checkpoint | eu leio o backlog, corto excessos, confirmo escopo | — |
| 4 | Como fazer | Workflow B, pipeline por funcionalidade: pesquisador (docs oficiais, repos de referência) | `04-como-fazer/<id>.md` |
| 5 | Refino técnico macOS | Workflow B, mesmo pipeline: especialista macOS lê o código real + pesquisa → spec com tasks e código | `05-specs/<id>.md` |
| 6 | Gestão | Workflow B, fase final: gestor → épicos, tasks, subtasks, dependências, ordem | `06-tasks/*.md` + `06-tasks/INDEX.md` |
| 7 | Design (background, desde o passo 1) | Agent em background, loop próprio até ícone final | `07-design/` (icns, pngs, notas) |
| 8 | Loop de implementação | Workflow C, sequencial por task: implementador (worktree) → PR → revisor → corretor → merge | PRs mergeados + `08-reviews/` |
| 9 | Pendências + triagem + relatório | eu + 1 agente crítico | `PENDENCIAS.md` (permanente), relatório, `planning/` apagada |

## Miniprompts

### MP-1 Pesquisa (4 ângulos)
- **1a Concorrentes diretos de status:** "Pesquise a fundo (README, issues, releases) Claude Status Bar, Nudgy, AgentBar, Claude Code Notifier, Claude Status, Pulse, ClaudeDot, Clabar, AgentPulse, vibebar, OpenAgentPeek, Perch. Para cada um: funcionalidades, como detecta estado, como instala, distribuição, preço, pontos fracos citados em issues. Tabela de funcionalidades × apps."
- **1b Limites/uso:** "CodexBar, AgentLimits, Usagebar, TokenBar, CC Usage Tracker, ccusage. Como obtêm limites 5h/semanal (statusline, OAuth/Keychain, JSONL), riscos, o que usuários pedem."
- **1c Gerenciadores e orquestração:** "Conductor, Nimbalyst/Crystal, Claude Squad, Vibe Kanban, ccmanager, Claude desktop. O que deles cabe num app de barra de menu leve."
- **1d Inovação:** "Ideias que nenhum desses tem. Fontes: hooks novos do Claude Code (lista atual de eventos), Gemini/Codex/Copilot CLI hooks, recursos do macOS 14–26 (Live Activities no Mac? widgets interativos, App Intents, Focus filters, Control Center controls), Apple Watch/iPhone. Propor 10+ ideias novas com justificativa."

### MP-2 Painel de usuários (sem contexto)
Personas: (a) dev sênior com 5 sessões Claude Code em terminais/tmux; (b) dev que usa o app desktop do Claude e o VS Code; (c) dev que alterna Claude, Codex e Gemini; (d) tech lead preocupado com custo e limites; (e) dev iniciante que acabou de instalar o Claude Code; (f) dev com foco em privacidade/segurança e acessibilidade.
Rodada 1: cada um recebe só a descrição do produto (README resumido, sem roadmap) + lista de ideias da pesquisa e diz: dores reais, o que usaria, o que ignoraria, o que falta, quanto pagaria.
Rodada 2: cada um lê as respostas dos outros e debate (concorda/discorda, muda prioridade).
Moderador: consolida ranking por votos e pontos de consenso/conflito.

### MP-3 Validação (3 lentes + síntese)
- **Valor/produto:** a funcionalidade resolve dor citada no painel? diferencia de concorrente?
- **Viabilidade técnica macOS:** dá para fazer com APIs públicas, sem App Store, sandbox off, assinatura ad-hoc hoje? custo real?
- **Risco:** segurança, privacidade, marca, dependência de interface não documentada do Claude Code.
Síntese → `BACKLOG.md` com cada funcionalidade: id, nome, veredito (fazer/depois/descartar), prioridade, motivo, dependências, "precisa do usuário?".

### MP-4 Como fazer (por funcionalidade)
"Pesquise como implementar <F> num app macOS SwiftUI MenuBarExtra (SwiftPM, macOS 14, sem Xcode project). Docs oficiais da Apple e do Claude Code, repos open source que já fazem isso (link e trecho relevante), armadilhas conhecidas, alternativas. Não escreva o plano final; traga evidência."

### MP-5 Especialista macOS (por funcionalidade)
"Você é especialista em desenvolvimento macOS (AppKit/SwiftUI, Swift 6 concurrency, SwiftPM, codesign/notarização). Leia o código real em Sources/ e Tests/ e a pesquisa em 04-como-fazer/<id>.md. Escreva 05-specs/<id>.md: arquivos a criar/alterar, código de exemplo compilável no estilo do projeto, testes a adicionar, como verificar manualmente, riscos, critérios de aceite. Mínimo que resolve."

### MP-6 Gestor
"Leia BACKLOG.md e todas as specs. Gere 06-tasks/INDEX.md (ordem de execução, dependências, épico) e um arquivo por task `T<nn>-<slug>.md` com: objetivo, subtasks em checklist, arquivos, critérios de aceite, gates, nome da branch, título do PR. Cada task = 1 PR pequeno. Tasks que dependem do usuário marcadas BLOQUEADA com o motivo."

### MP-8 Loop por task
- **Implementador (worktree):** "Implemente 06-tasks/T<nn>. `git fetch && git switch -c <branch> origin/main`. Código mínimo, testes, README se mudar comportamento. `swift build && swift test`. Commit, push, `gh pr create`. Devolva URL do PR."
- **Revisor (sem contexto):** "Revise o PR <url> contra a task. Leia o diff inteiro e o código em volta. Procure bugs, regressões das garantias de segurança, concorrência (MainActor), testes faltando, excesso de código. Poste a revisão com `gh pr review --comment` com comentários concretos. Devolva lista estruturada."
- **Corretor:** "Para cada comentário: aplique se fizer sentido, ou responda no PR por que não. Rode os gates. Push."
- **Merge:** checks verdes → `gh pr merge --squash --delete-branch`. Atualiza INDEX.

### MP-7 Design (background)
"Agente de design. Pesquise ícones de apps de barra de menu e de ferramentas de agentes para inspiração (sem copiar; sem logo da Anthropic/Claude). Proponha 3 conceitos, escolha um com justificativa, desenhe-o de forma programática (Swift + CoreGraphics ou SVG → PNG via `sips`/`qlmanage`), gere todos os tamanhos do `.iconset` e o `AppIcon.icns` com `iconutil`, e um template image monocromático para a barra de menu. Revise o próprio resultado olhando os PNGs, itere até ficar bom em 16px e 1024px. Trabalhe só em planning/07-design/. Entregue README curto com o conceito e os arquivos."

### MP-9 Triagem crítica
"Leia tudo em planning/. Separe: (1) decisões e motivos que precisam sobreviver (vão para docs permanentes), (2) pendências que dependem do usuário (PENDENCIAS.md), (3) ideias futuras ainda válidas (ROADMAP.md curto), (4) lixo. Seja crítico: só o que alguém precisaria daqui a 6 meses."

## Nota do usuário (2026-11-15)
- `activate(ignoringOtherApps:)` vai ser descontinuada (API_TO_BE_DEPRECATED). Pesquisar a substituta (`NSApp.activate()`, macOS 14+) e NÃO usar em código novo. Tasks/specs que citam essa API precisam ser ajustadas antes do loop. Registrado também em TODO.md.
