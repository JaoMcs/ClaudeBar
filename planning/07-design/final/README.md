# Ícone do ClaudeBar: "Prompt Pulse"

**Conceito:** um chevron de prompt (`›`) seguido de um ponto verde que pulsa no lugar do cursor. O terminal (qualquer agente) avisa o estado pela luz. Não depende da marca "Claude".

## Paleta
| Uso | Hex |
|---|---|
| Fundo (topo → base) | `#2E3D62` → `#0D1220` |
| Chevron | `#F2F5FA` |
| Sinal (base / brilho) | `#34D399` / `#8BF5C8` |

## Arquivos
- `AppIcon.icns`: ícone do app (16–1024, gerado com `iconutil`)
- `AppIcon-1024.png`: master em 1024×1024
- `AppIcon.iconset/`: os 10 PNGs-fonte do `.icns`
- `MenuBarIcon.png` / `@2x` (18×18 / 36×36): template preto + alfa, ponto cheio (marca)
- `MenuBarIcon-{idle,working,ready,waiting}.png` / `@2x`: variantes por estado, com o mesmo traço

Para regerar tudo: `swift ../render-icon.swift .` e depois `iconutil -c icns AppIcon.iconset -o AppIcon.icns`.

## Integração

### 1. Ícone do app (`scripts/build-app.sh`)
Depois do `mkdir -p ... Contents/Resources`:
```bash
cp planning/07-design/final/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp planning/07-design/final/MenuBarIcon*.png "$BUNDLE/Contents/Resources/"
```
O ideal é mover os arquivos antes para uma pasta versionada (ex.: `Resources/`), porque `planning/` está no `.git/info/exclude`.

No heredoc do Info.plist:
```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

### 2. Ícone da barra (`Sources/ClaudeBar/ClaudeBarApp.swift`)
O `Package.swift` não declara recursos, e não precisa. `Bundle.module` exigiria `resources: [.process("Resources")]` no `executableTarget` e um `ClaudeBar_ClaudeBar.bundle` copiado para a raiz do `.app`, o que atrapalha o codesign. É mais simples deixar os PNGs em `Contents/Resources` (passo 1) e carregá-los do `Bundle.main`, com fallback para o SF Symbol atual quando rodar via `swift run`, onde não há bundle:

```swift
// SessionStore.swift: junto de `symbolName`
extension BarState {
    var assetName: String {
        switch self {
        case .waiting: "MenuBarIcon-waiting"
        case .done: "MenuBarIcon-ready"
        case .working: "MenuBarIcon-working"
        case .idle: "MenuBarIcon-idle"
        }
    }
}

// ClaudeBarApp.swift: no `label:` do MenuBarExtra
} label: {
    if let icon = Bundle.main.image(forResource: store.barState.assetName) {
        Image(nsImage: { icon.isTemplate = true; return icon }())
    } else {
        Image(systemName: store.barState.symbolName)
    }
    Text("\(store.openSessionCount)")
}
```
`Bundle.main.image(forResource:)` junta `X.png` e `X@2x.png` numa imagem com as duas resoluções. `isTemplate = true` faz o macOS pintar o ícone para claro/escuro e para o estado selecionado.

Mantenha os SF Symbols no menu e no HUD. A justificativa está em `../notas.md`.

## Limitações
- O `.icns` é plano (pré-Tahoe). No macOS 26 aparece certo porque já é squircle, mas não tem as variantes Liquid Glass (Dark/Clear/Tinted). Para ter isso, é preciso montar no Icon Composer a partir das camadas: fundo + chevron + ponto.
- Os PNGs da barra não acompanham o peso do SF Symbol do sistema. Se quiserem nitidez vetorial, dá para exportar PDF no lugar.
