# Pendências que só o dono resolve

Tudo aqui precisa de decisão, conta, dinheiro ou tela. O código não espera nada disso para rodar.
Roteiro de teste na tela: [`docs/TESTE-MANUAL.md`](docs/TESTE-MANUAL.md). Ideias futuras: [`ROADMAP.md`](ROADMAP.md).

## 1. Portões manuais em aberto (código já na `main`)

Rode antes de qualquer release. Faça backup do `~/.claude/settings.json` antes.

| PR | O que falta | Próximo passo |
|---|---|---|
| #27 Abrir no login | O revisor pediu o gate antes do merge; o merge saiu sem ele. Não se sabe se `SMAppService.mainApp.register()` funciona com assinatura ad-hoc nem se sobrevive a um rebuild. | Seção 1 do `docs/TESTE-MANUAL.md`. **Falhou ligar ou abrir após logout/login** → plano B: trocar o toggle por um botão "Abrir Itens de Início…" e anotar aqui que depende do Developer ID. **Só perdeu no rebuild** → manter o toggle e a frase do README. **Passou tudo** → tirar a frase "After rebuilding the app, turn it on again" dos dois READMEs. |
| #19 Popup de espera | Resultado marcado pelo dono no painel: o popup some ao trocar de Space. Falta confirmar 1 ou 2 cliques. | Correção do Space na T36 (tirar `.transient`). Depois, seção 6 do roteiro para os cliques; **2 cliques** → `FirstClickHostingView`. |
| #21 Ir para a sessão | A tabela de terminais do README está toda "not verified". | Seção 5. Atualizar a tabela nos dois READMEs com o resultado. Se o iTerm2 falhar, ver "plano B do iTerm2" no `ROADMAP.md`. |

## 2. Distribuição

| Item | Bloqueia | Próximo passo |
|---|---|---|
| Nome definitivo: **Awaitbar** (decidido) | — | Troca de nome e bundle id na T37. O diretório de estado `~/.claude/claudebar` e o `claudebar-hook` ficam para o PR do multiagente, para não quebrar hooks instalados. |
| Apple Developer ID + notarização | Gatekeeper sem "Abrir Mesmo Assim", notificação nativa, abrir no login estável, Homebrew, Automação estável | **Decidido: assinar.** Assinar o Apple Developer Program (US$ 99/ano), criar o certificado "Developer ID Application" e uma credencial do `notarytool` (app-specific password ou API key). Depois: script de assinatura e notarização lendo as credenciais de variáveis de ambiente. Assim que o certificado existir, avisar o Claude para fazer o script. |
| Publicar release | download pronto | Depois de nome + licença (de preferência depois da notarização): `./scripts/make-dmg.sh` gera `dist/ClaudeBar-<versão>.dmg` e o `.sha256`. Criar a tag `v<VERSION>` e anexar os dois arquivos ao release no GitHub. |
| Tap do Homebrew | instalar com `brew` | Depois do nome e da notarização: criar o repo `homebrew-tap` e um cask apontando para o DMG do release, com o SHA-256. O cask `claudebar` já existe no Homebrew (outro app). |
| GIF do README | adoção | Gravar uns 10 s do app em uso: barra mudando de estado, menu aberto, popup, clique levando à sessão. Pôr no topo dos dois READMEs. |

## 3. Dados reais que só uma conta de verdade dá

| Item | Para quê | Próximo passo |
|---|---|---|
| Automação por terminal | ir para a aba exata (Terminal, iTerm2, Ghostty), F30 no `ROADMAP.md` | Só quando o F30 for feito: aprovar o prompt de Automação em cada terminal com o build assinado. Com ad-hoc o macOS pede de novo a cada build. Hoje o app não usa Automação. |
| Payload real de pausa por limite | mostrar o motivo da pausa (F33) | Com o statusline do ClaudeBar instalado, bater o limite de uso e guardar o JSON que chega no `Notification` ou no `StopFailure` (tirar dados pessoais antes de colar numa issue). |

## 4. Já resolvido pelo dono (22 nov 2026)

- `/compact` não dispara "Claude terminou" (#17): marcado pelo dono no painel, nada a mudar.
- Licença: MIT (`LICENSE`).
- Sobras do incidente da T12 em `~/.claude/claudebar` (`bin/` e `backups/`): movidas para o Lixo.

## 5. Dívida técnica conhecida

- `NSApplication.activate(ignoringOtherApps:)` ainda aparece 2 vezes em `SessionStore.swift`. Está no `TODO.md`. Código novo não usa.
