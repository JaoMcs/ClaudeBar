# Roteiro de teste manual

Tudo que os agentes não conseguiram verificar sem tela, som, sessão real do Claude Code ou o `settings.json` de verdade.
Rode uma vez, no seu Mac, na ordem. Os mais arriscados vêm primeiro.

Cada passo: **ação** → **esperado** (PR). Anote ✓ ou ✗ ao lado. Se algo der ✗, a seção diz o que fazer, ou veja o `PENDENCIAS.md`.

Rótulos em inglês; entre parênteses, o texto em pt-BR quando o Mac está em português.

## 0. Preparar

1. **Backup antes de tudo:**
   ```bash
   cp ~/.claude/settings.json ~/settings.json.antes-do-teste
   ```
   No fim (seção 14) você compara com ele.
2. `./scripts/install.sh` → recompila, instala em `~/Applications/ClaudeBar.app`, mostra a prévia dos hooks e pergunta `Aplicar? [s/N]`. **Responda N** (a instalação dos hooks é testada pelo app na seção 2).
3. Deixe aberto um terminal com `log stream` filtrado pelo subsistema do app (comando no README, seção "Alerts") para ver o que acontece.

## 1. Abrir no login (#27) — portão bloqueante

Não use `sfltool resetbtm`: ele apaga os itens de início de todos os apps.

1. Menu → **Settings…** (Ajustes…) → toggle **Open at login** → está desligado. (#27)
2. Ligue → sem texto vermelho. Feche e reabra a janela → continua ligado. Ajustes do Sistema → Geral → Itens de Início → ClaudeBar aparece **uma vez**. (#27)
3. Opcional, só leitura: `sfltool dumpbtm | grep -i -A8 claudebar`.
4. Logout e login → o ClaudeBar abre sozinho. (#27)
5. Com a janela de Ajustes aberta, desligue o item em Ajustes do Sistema → volte ao ClaudeBar → o toggle mostra desligado. (#27)
6. Religue. Rode `./scripts/install.sh` de novo (rebuild muda a assinatura) → abra Ajustes e anote o estado. Se desligou, ligue e confira que **não** há dois itens. (#27)
7. Desligue pelo toggle → o item some de Itens de Início, o app continua rodando. (#27)

Decisão: falhou o 2 ou o 4 → plano B (botão em vez de toggle). Só o 6 falhou → mantém o toggle e a frase do README. Tudo passou → tirar a frase "After rebuilding the app, turn it on again" dos READMEs.

## 2. Hooks no settings.json (#5, #7, #8, #9, #12, #13, #14)

1. Abra o app pela primeira vez depois do install → aparece um alerta único com o arquivo, o diff só do bloco `hooks` e a pasta do backup. O alerta fica **na frente** das outras janelas e aparece depois do ícone na barra. (#13)
2. Se você tinha hooks do `install.sh` antigo: o título do submenu diz "Hooks in the old format" (Hooks no formato antigo). (#8, #13)
3. Clique **Skip** (Pular) → nada muda no arquivo (`diff ~/settings.json.antes-do-teste ~/.claude/settings.json` vazio). Reabra o app → o alerta **não** volta. (#13)
4. Ponha um hook seu qualquer em `PostToolUse` no `settings.json`. Menu → submenu da integração → **Install hooks…** (Instalar hooks…) → **Install** → seu hook continua lá, as entradas do ClaudeBar entram depois. Backup novo em `~/.claude/claudebar/backups/`. `ls -l` mostra `0600` nos arquivos e `0700` na pasta. (#5, #7, #13)
5. Repita **Install hooks…** → "Nothing to change" (Nada a mudar). (#7)
6. Em uma sessão nova do Claude Code, `/hooks` lista `PostToolUse`, `PostToolUseFailure`, `StopFailure`, `SessionStart` e o `Notification` com matcher, sem aviso de settings inválido. (#9, #12, #15, #17)
7. Menu → **Test integration** (Testar integração) → 4 linhas com ✓, "Last event received" e em seguida o popup de exemplo. Nenhum `claudebar-selftest.json` sobra em `~/.claude/claudebar/`. A linha `claudebar-selftest` não pisca no menu. (#14)
8. `chmod 444 ~/.claude/settings.json` → o submenu diz que é somente leitura; o teste mostra ✗ em "Hooks registered" (nunca ✓). **Copy hooks JSON** (Copiar JSON dos hooks) copia o bloco. Volte com `chmod 644`. (#13, #14)
9. Ponha `"disableAllHooks": true` → o teste mostra `?` em "Hooks registered" e o aviso de `disableAllHooks`. Tire a linha. (#14)
10. Apague `~/.claude/claudebar/bin/claudebar-hook` → o teste dá ✗ no executável sem travar o app. Reinstale pelo menu. (#14)
11. Edite o `settings.json` com o alerta de instalação aberto e então clique **Install** → "settings.json changed after the preview; nothing was changed". (#13)
12. **Remove hooks…** (Remover hooks…) → só as entradas do ClaudeBar saem; seu hook fica. Reinstale para as próximas seções. (#7, #13)

## 3. Limites e statusLine (#30, #31, #32)

Precisa de conta Pro, Max ou Ultra.

1. Ponha um statusLine seu para testar a devolução: `"statusLine": {"type": "command", "command": "echo meu-rodape"}`.
2. Menu → **Show limits in the Claude Code footer…** (Mostrar limites no rodapé…) → o alerta mostra o diff de `hooks` e `statusLine` e avisa das dicas que somem do rodapé. **Install**. (#32)
3. `~/.claude/claudebar/statusline-original.json` existe, com `0600`, e guarda o seu statusLine. (#32)
4. Numa sessão do Claude Code: o rodapé continua mostrando `meu-rodape`. Depois de uma resposta, o topo do menu mostra **5 h limit** e **Weekly** (Limite 5 h, Semanal) com percentual e hora de renovação. (#30, #31)
5. Feche e abra o menu depois de 1 min → "Updated …" (Atualizado …) mudou. Com o menu aberto o texto não avança (esperado). (#31)
6. **Stop showing limits in the footer…** → o `statusLine` volta exatamente ao seu (`echo meu-rodape`). O `statusline-original.json` some. (#32)
7. Ordem cruzada: instale hooks e statusline, remova os **hooks** → `~/.claude/claudebar/bin/claudebar-hook` continua (o rodapé ainda usa). Remova o statusline → o executável some. (#32)
8. Tire o seu statusLine de teste. Reinstale só os hooks.

## 4. Estados, sessões e polling (#9, #11, #12, #15, #16, #17, #18)

1. Prompt curto, espere terminar e espere mais 90 s → a sessão fica "ready"/ocioso, **não** vira "waiting". (#9)
2. Peça um comando fora da allowlist → a barra mostra o símbolo de permissão. Aprove → em até 1 s volta a "working". (#12, #18)
3. Repita e **negue** → anote o que acontece (fica esperando? vai para ocioso no fim?). (#12)
4. Faça o Claude usar `AskUserQuestion` → símbolo de pergunta na hora e ainda pergunta 10 s depois. Anote o que o `ExitPlanMode` mostra. (#18)
5. Erro de API real (ou rede cortada) → triângulo na barra, linha "failed" (falhou) com o código no submenu. **Mark as seen**, depois outra falha na mesma sessão → acende de novo. (#15)
6. Sessão nova → aparece em menos de 1 s. `kill -9` no `claude` → some em menos de 1 s. Fechar a aba → some. (#17, #11)
7. `/clear` → sem linha duplicada. `/compact` com a sessão trabalhando → **não** toca "Claude finished". Se tocar: tirar o `SessionStart` (ver `PENDENCIAS.md`). (#17)
8. Sessão do app desktop do Claude continua listada. (#11)

## 5. Ir para a sessão (#21, #22, #23, #24)

Para cada host: abra uma sessão nele, troque para outro app, use **Go to session** (Ir para a sessão) no submenu da linha.
Esperado: o app certo vem para a frente (a janela, não a aba) e a sessão fica marcada como vista.

| Host | Menu traz o app? | Clique no popup traz? (#22) | Sem som com o app na frente? (#23) |
|---|---|---|---|
| Terminal.app | | | |
| iTerm2 | | | |
| Ghostty | | | |
| VS Code | | | |
| Cursor | | | |
| Warp | | | |
| tmux (socket padrão, com terminal anexado) → troca para o pane certo | | | |
| App desktop do Claude | | | |

- Falhou → aparece o alerta "Could not go to …" (Não foi possível ir até …); nada mais abre. (#21)
- Depois: preencha a tabela "Going to a session" nos dois READMEs. iTerm2 falhou → plano B no `ROADMAP.md`.
- `claudebar-hook next` com uma sessão esperando → traz o terminal dela; dentro do tmux, troca de pane. `claudebar-hook status` num terminal real lista as sessões. (#24)

## 6. Popup e sons (#16, #19, #22, #28)

1. Menu → **Show sample popup** (Ver exemplo de popup) → não some em 4 s. **Anote: 1 ou 2 cliques para fechar.** 2 cliques → plano B `FirstClickHostingView`. (#19)
2. Pedido de permissão real, sem mexer no mouse → o popup fica mais de 1 min. Aprove no terminal → fecha em até 1 s. (#19)
3. Repita e feche a sessão (`/exit`) → o popup fecha. (#19)
4. Popup de espera da sessão A aberto, sessão B termina → toca o som de "terminou", o popup de A **continua**. (#19)
5. Cursor no canto superior direito, dispare o exemplo → nasce no canto inferior direito. (#19)
6. Popup de espera aberto, troque de Space (Ctrl+→) → **anote** se aparece no outro Space ou some. Se some → tirar `.transient`. (#19)
7. Popup aberto, desligue **Notifications** no menu → fecha. Nada toca enquanto desligado. (#2, #19)
8. Sons: "terminou", permissão, pergunta e falha soam diferentes (Glass, Submarine, Purr, Basso). Falha mostra popup vermelho. (#16, #18)

## 7. Ajustes (#26, #28, #29)

1. **Settings…** com outro app na frente → a janela abre na frente. Layout do formulário legível, sem corte. (#26)
2. Cada Picker de som toca a prévia. Desligar um tipo de aviso → aquele aviso some, os outros continuam. **About ClaudeBar** abre. Reiniciar o app → as escolhas ficam. (#26)
3. Lembrete: ponha 1 min. Permissão sem responder → aviso na hora e um "Still waiting: …" (Ainda esperando: …) ~1 min depois. Mais 2 min → **nenhum** outro. Clique leva à sessão. Desligue o lembrete → só o aviso inicial. Anote se o lembrete sai com o menu aberto. (#28)
4. **Never show the message content** (Nunca mostrar o conteúdo) → popup real e de exemplo dizem só "<projeto> needs you". Desliga sem reiniciar. `log show` não tem o texto da mensagem. (#29)

## 8. Pasta, branch (#20, #25)

1. **Open project folder** → abre a pasta no Finder, que vem para a frente. Pasta apagada → alerta. Pasta em `~/Documents` → anote se aparece prompt de privacidade. (#20)
2. Linha do menu mostra "nome · main", "· feat/x" com outra branch, "· @abc1234" em HEAD solto e nada fora de git. Anote se o macOS pede acesso a "Arquivos e Pastas" para repo em `~/Documents`. (#25)

## 9. VoiceOver (#33)

1. Ligue o VoiceOver (Cmd+F5). Foque o item da barra → lê "ClaudeBar. Sessions: N. <estado>". (#33)
2. Abra o menu → cada linha lê nome e estado. Submenu **What the icons mean** lista os 7 estados com o símbolo igual ao da barra. (#33)
3. Dispare o popup → o VoiceOver anuncia título e corpo. Mudo → trocar o anúncio para o elemento do painel (passo 4 da task). (#33)

## 10. Idiomas (#35, #36)

1. `open ~/Applications/ClaudeBar.app --args -AppleLanguages '(pt-BR)' -NSShowNonLocalizedStrings YES` → nada em MAIÚSCULAS no menu, legenda, barra, popup, alertas de finalizar e de integração, teste da integração, Ajustes, Sobre e limites. (#35, #36)
2. Repita com `'(en)'` e `'(fr)'` → tudo em inglês, inclusive datas relativas. `'(pt-PT)'` → pt-BR. (#35)
3. Dispare os alertas de falha ("Could not go to…", "Could not open the folder") nas duas línguas. (#36)

## 11. Ícone (#10)

Finder (ícone e lista), Spotlight, Monitor de Atividade e Ajustes → Itens de Início mostram o ícone `›●`, não o genérico. Se ficar o genérico: `touch ~/Applications/ClaudeBar.app`. (#10)

## 12. DMG (#34)

1. `./scripts/make-dmg.sh` → `dist/ClaudeBar-<versão>.dmg` e `.sha256`; `shasum -a 256 -c` dá OK. (#34)
2. Em **outro Mac** (de preferência um Intel): baixar, arrastar para Aplicativos, "Abrir Mesmo Assim" (macOS 15 e 26), o app roda. (#34)

## 13. Rede zero (#6)

Com o app aberto por uns minutos: `nettop -p ClaudeBar` (ou Little Snitch) → nenhuma conexão. (#6)

## 14. Fechar

```bash
diff <(python3 -m json.tool ~/settings.json.antes-do-teste) <(python3 -m json.tool ~/.claude/settings.json)
```
Fora de `hooks` (e de `statusLine`, se você deixou instalado), nada pode ter mudado. Se mudou, restaure o backup e abra uma issue.
Atualize `PENDENCIAS.md` e os READMEs com o que você anotou.
