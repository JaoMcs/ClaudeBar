# Ícone: "Prompt Pulse"

Um chevron de prompt (`›`) seguido de um ponto verde no lugar do cursor: o terminal (de qualquer agente) avisa o estado pela luz. Não usa a marca "Claude" nem a estrela laranja da Anthropic.

Escolhido entre três conceitos. Os outros dois perderam em 16 px: "semáforo de janela" virou ruído e lembra os botões das janelas do macOS; "olho-sentinela" perdia o cursor dentro da pupila e passa ideia de vigilância.

## Paleta

| Uso | Hex |
|---|---|
| Fundo (topo → base) | `#2E3D62` → `#0D1220` |
| Chevron | `#F2F5FA` |
| Sinal (base / brilho) | `#34D399` / `#8BF5C8` |

## Regerar

```bash
swift docs/design/render-icon.swift /tmp/icone
iconutil -c icns /tmp/icone/AppIcon.iconset -o Resources/AppIcon.icns
```

O script gera o `AppIcon-1024.png`, o `.iconset` (16–1024; em 16 e 32 px o traço engrossa e as ondas somem) e os PNGs template da barra (`MenuBarIcon*.png`, 18×18 e 36×36).

## Barra de menu

A barra usa SF Symbols por estado. O glifo próprio existe no script, mas só para 4 estados (ocioso, trabalhando, pronto, esperando); o app hoje tem 7. Ver `ROADMAP.md`.

## Limitações

- O `.icns` é plano (squircle, pré-Tahoe). Aparece certo do macOS 14 ao 26, mas sem as variantes Liquid Glass (Dark, Clear, Tinted). Para isso: Icon Composer com as camadas fundo + chevron + ponto.
- O canto é uma superelipse (n = 5), não um arco circular, como no template da Apple.
