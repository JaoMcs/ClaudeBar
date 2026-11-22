# Iterações

Cada pasta `itN/` tem os PNGs e um `preview.png` gerado por `preview.swift`: ícone em 128/32/16 (os dois últimos também ampliados ×4, sem suavizar) sobre fundo claro e escuro, e as 5 variantes da barra ao lado do número "2".

## it1: primeira versão
- Squircle 824/1024 com sombra, chevron branco, ponto verde com 3 ondas e o ponto abaixo da linha média, como um cursor.
- **Crítica:**
  - A onda externa (r=300) é cortada pela borda direita do squircle e fica com cara de erro.
  - A composição está apertada à direita.
  - O fundo `#26324F` some no modo escuro.
  - Na barra, o "trabalhando" (ponto meio cheio) se confunde com o ocioso em 1x.

## it2: limpeza
- Duas ondas (r=148/204) contidas no corpo.
- Fundo mais claro no topo (`#2E3D62`) para destacar no modo escuro.
- Ponto subiu (y=476) para equilibrar com o chevron.
- "Trabalhando" na barra virou anel com miolo (◎), que se distingue do anel vazio em 1x.
- **Crítica:**
  - A onda externa encosta na ponta do chevron e as duas formas parecem coladas.
  - O grupo inteiro está ~35 px à direita do centro óptico.

## it3: final
- Chevron deslocado para x 236–392, ponto para x=652 e ondas reduzidas (140/190). Agora há ~20 px de ar entre a ponta e a onda, e o grupo fica centrado (≈515).
- **Revisão:**
  - **1024:** equilibrado, as ondas ficam dentro do grid.
  - **128:** lê como `›●` com halo.
  - **32 e 16:** versão simplificada (sem ondas, traço mais grosso); o `>` e o ponto verde continuam separados.
  - **Claro/escuro:** a borda interna branca a 10% e a sombra dão contorno no modo escuro.
  - **Barra:** as 5 variantes leem em 1x ao lado do número, nos dois modos.
- **Parece com algo existente?** Lembra de leve ícones de terminal (`>_` do Terminal/iTerm), mas o ponto verde com ondas no lugar do `_` é o elemento próprio. Não tem estrela, laranja nem robô, e não se parece com Claude Status Bar, CodexBar ou Nudgy.
- Parei aqui: uma 4ª rodada só mexeria em gosto, sem ganho de legibilidade.
