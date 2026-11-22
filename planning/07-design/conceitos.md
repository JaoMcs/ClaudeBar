# Conceitos

Restrições: original, sem a estrela/sunburst laranja da Anthropic e sem depender da marca "Claude" (o app vai suportar outros agentes). Precisa se ler em 16 px e na barra ao lado de um número.

## A. Prompt Pulse (`›●`) — ESCOLHIDO
- **Ideia:** o chevron de prompt de terminal seguido de um ponto no lugar do cursor. O cursor vira uma luz de estado, com ondas de pulso em volta.
- **Metáfora:** "o terminal te avisa". O chevron representa o agente de código (qualquer um: Claude, Codex, Gemini). O ponto representa o sinal de estado.
- **Paleta:** fundo azul-noite em gradiente `#2E3D62 → #0D1220`, chevron `#F2F5FA`, sinal verde-menta `#34D399` com brilho `#8BF5C8`.
- **16 px:** são duas formas grossas e separadas (um `>` e um `●`), e as ondas somem. O verde é o único ponto de cor e aparece mesmo em 16 px.
- **Barra:** o mesmo `›●` em template. O ponto muda por estado (vazio, anel com miolo, cheio, onda).

## B. Semáforo de janela
- **Ideia:** uma janela de terminal estilizada cuja barra de título tem 3 luzes empilhadas, e só uma acesa (ocioso, trabalhando, pronto).
- **Paleta:** grafite `#1C1F26` com luzes âmbar/verde/azul.
- **16 px:** fraco. Três luzes pequenas viram ruído, e lembra demais os "traffic lights" das janelas do macOS e o clichê do semáforo.

## C. Olho-sentinela
- **Ideia:** uma pálpebra/olho cuja pupila é um cursor de bloco `▍`: alguém de olho nas suas sessões.
- **Paleta:** índigo `#3B3F9E` com íris ciano `#22D3EE`.
- **16 px:** médio. O olho se lê bem, mas o cursor dentro da pupila some. "Olho" também carrega uma ideia de vigilância/privacidade que não combina com o produto.

## Escolha: A
É o único que une as duas metades do produto, agente/terminal (`›`) e estado (`●`), numa forma que sobrevive a 16 px e funciona como template monocromático na barra. O estado mora em um elemento só (o ponto), então as variantes por estado saem naturalmente, sem inventar símbolos novos. Não usa robô, estrela nem laranja.
