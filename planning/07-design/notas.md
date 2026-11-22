# Notas de pesquisa: ícones

## Ícone de app no macOS (HIG)
- O ícone de app no macOS é um retângulo arredondado ("squircle"), em vista frontal e nivelado, com a mesma sombra projetada de todos os outros. O template da Apple já traz essa sombra. O HIG também sugere sombras e brilhos internos para dar definição. [HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- O conteúdo principal deve ficar dentro do retângulo do grid. O que passa dele "parece fora do lugar" (mesma página do HIG).
- Canvas de 1024 px. Pelo template Big Sur–Sequoia, o corpo tem 824×824 centrado, com 100 px de margem, e a sombra fica na margem de baixo. No WWDC25 a Apple simplificou o grid, mas manteve o canvas de 1024. [WWDC25: Say hello to the new look of app icons](https://developer.apple.com/videos/play/wwdc2025/220)
- O canto não é um arco circular: é uma curva contínua (superelipse). Os ~22% de raio citados por terceiros são só uma aproximação. Aqui usei uma superelipse n=5. [dev.to: 15 macOS icon HIG rules](https://dev.to/roboticela/15-macos-icon-design-hig-rules-rounded-corners-retina-quality-532n)
- Tamanhos do `.iconset`: 16, 32, 128, 256 e 512, cada um em @1x e @2x (1024 = 512@2x). Nos tamanhos 16 e 32 vale simplificar o desenho, tirando detalhes finos e engrossando o traço. Fiz isso no script com `small = px <= 32`.

## macOS 26 (Tahoe): Liquid Glass
- Os ícones passam a ser feitos de camadas de "Liquid Glass" montadas no Icon Composer, com variantes Default, Dark, Clear e Tinted. [Apple Newsroom, jun/2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- No Tahoe, todo ícone vira squircle. Ícones fora do formato ganham uma moldura. [mjtsai: macOS Tahoe's new theming system](https://mjtsai.com/blog/2025/06/19/macos-tahoes-new-theming-system/)
- O que isso muda aqui: o app é LSUIElement, sem Dock, e o pacote é montado por script, sem Xcode nem asset catalog. Por isso um `.icns` plano em squircle basta e aparece certo do macOS 14 ao 26. O desenho já separa fundo de primeiro plano (chevron + ponto), o que facilita portar para o Icon Composer depois, se valer a pena.

## Ícone de barra de menu (menu bar extra)
- A barra tem 24 pt (37 pt nos MacBooks com notch), e o item tem no máximo 22 pt de altura útil. Um ícone circular de ~16 pt fica com o peso dos ícones do sistema. Evite padding, a não ser para centralizar na vertical. [Bjango: Designing macOS menu bar extras](https://bjango.com/articles/designingmenubarextras/)
- Template image: o macOS ignora a cor e usa só o alfa, pintando o ícone conforme o modo claro/escuro e o estado selecionado. Entregue em PNG 1x e 2x, ou em PDF/SVG. Opacidade de ~35% indica estado desabilitado (mesma fonte).
- 18×18 pt é o tamanho de trabalho mais comum. É convenção, não regra da Apple. [techconcepts: macOS menu bar guide](https://techconcepts.org/blog/macos-menu-bar-guide)
- Referências de apps com bons ícones de barra: Bartender, iStat Menus, Raycast e Things. Todos usam glifo monocromático, traço de ~1.5–2 pt e uma forma simples que se reconhece pela silhueta. Os que leem melhor têm uma silhueta só e evitam detalhe interno.

## Manter os SF Symbols por estado ou trocar?
**Recomendação: usar o glifo próprio (`›●` e variantes) no label da barra e manter os SF Symbols no menu e no HUD.**
- Hoje o label mostra só um símbolo genérico de círculo mais o número. Ao lado de outros apps de barra (muitos usam círculos), não dá para saber de qual app é o ícone. O `›` resolve isso: ele dá identidade ao item, e o ponto continua carregando o estado.
- As 4 variantes têm o mesmo traço e mudam só o ponto: vazio (ocioso), anel com miolo (trabalhando), cheio (pronto) e cheio com onda (esperando você). Em 1x dá para diferenciá-las. Ver `it3/preview.png`.
- Custos de trocar:
  1. O "esperando você" fica menos explícito que um `exclamationmark`. Isso é compensado pelo som e pelo popup, que já existem.
  2. Um PNG não acompanha o Dynamic Type nem o peso do SF Symbol. Na barra isso não importa, porque o tamanho é fixo.
- Se preferirem não mexer no comportamento agora, uma alternativa sem perda: manter os SF Symbols e usar o ícone próprio só no app (Finder, About, notificações).
