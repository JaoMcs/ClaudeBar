// Desenha o ícone do ClaudeBar ("Prompt Pulse") e exporta PNGs.
// Uso: swift render-icon.swift <pasta-de-saída>
// Gera: AppIcon-1024.png, AppIcon.iconset/*, MenuBarIcon*.png (+ variantes por estado).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Paleta
let bgTop: UInt32 = 0x2E3D62, bgBottom: UInt32 = 0x0D1220   // tinta/azul-noite
let glyph: UInt32 = 0xF2F5FA                                 // chevron
let signal: UInt32 = 0x34D399, signalHi: UInt32 = 0x8BF5C8   // ponto de sinal (verde-menta)

func png(_ px: Int, _ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: px, height: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

// Squircle (superelipse n=5) ~ o "continuous corner" do macOS.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5, steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let pt = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

// Ícone do app, desenhado em espaço 1024 e escalado. `small` simplifica para 16/32 px.
func appIcon(_ ctx: CGContext, px: Int) {
    let k = CGFloat(px) / 1024, small = px <= 32
    ctx.scaleBy(x: k, y: k)
    // Grid da Apple (macOS 11+): corpo 824x824 centrado, margem 100; sombra embaixo.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(bgBottom)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: nil, colors: [rgb(bgTop), rgb(bgBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Brilho do sinal vazando no fundo (luz ambiente do ponto).
    let dot = CGPoint(x: 652, y: 476)
    let glow = CGGradient(colorsSpace: nil, colors: [rgb(signal, 0.30), rgb(signal, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: dot, startRadius: 0, endCenter: dot, endRadius: 360, options: [])
    // Ondas de "pulso" (somem em tamanhos pequenos).
    if !small {
        ctx.setLineWidth(14)
        for (r, a) in [(140.0, 0.40), (190.0, 0.18)] {
            ctx.setStrokeColor(rgb(signal, a))
            ctx.strokeEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r))
        }
    }
    // Chevron do prompt.
    ctx.setStrokeColor(rgb(glyph))
    ctx.setLineWidth(small ? 118 : 92)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 236, y: 656))
    ctx.addLine(to: CGPoint(x: 392, y: 512))
    ctx.addLine(to: CGPoint(x: 236, y: 368))
    ctx.strokePath()
    // Ponto de sinal (o "cursor" que vira luz de estado).
    let r: CGFloat = small ? 112 : 92
    let dg = CGGradient(colorsSpace: nil, colors: [rgb(signalHi), rgb(signal)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
    ctx.drawRadialGradient(dg, startCenter: CGPoint(x: dot.x - r * 0.35, y: dot.y + r * 0.35), startRadius: 0,
                           endCenter: dot, endRadius: r * 1.1, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    // Borda interna clara (definição em fundo escuro, como pede o HIG).
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()
}

// Ícone de barra (template, preto + alfa) em espaço 18x18 pt.
enum BarState: String, CaseIterable { case base, idle, working, ready, waiting }

func barIcon(_ ctx: CGContext, px: Int, state: BarState) {
    let k = CGFloat(px) / 18
    ctx.scaleBy(x: k, y: k)
    let black = rgb(0x000000)
    ctx.setStrokeColor(black); ctx.setFillColor(black)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    // Chevron
    ctx.setLineWidth(2.0)
    ctx.move(to: CGPoint(x: 2.5, y: 14)); ctx.addLine(to: CGPoint(x: 7.5, y: 9)); ctx.addLine(to: CGPoint(x: 2.5, y: 4))
    ctx.strokePath()
    // Sinal, centro (13, 7) — abaixo da linha média, como o cursor no fim da linha.
    let c = CGPoint(x: 12.75, y: 6.25)
    func circle(_ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
    switch state {
    case .base, .ready:
        ctx.fillEllipse(in: circle(3.25))
    case .idle:
        ctx.setLineWidth(1.5); ctx.strokeEllipse(in: circle(2.5))
    case .working:  // anel com miolo: aceso, mas ainda não pronto
        ctx.setLineWidth(1.25); ctx.strokeEllipse(in: circle(2.85))
        ctx.fillEllipse(in: circle(1.2))
    case .waiting:  // ponto + onda: chamando você
        ctx.fillEllipse(in: circle(2.25))
        ctx.setLineWidth(1.25)
        ctx.addArc(center: c, radius: 4.5, startAngle: -.pi / 2.6, endAngle: .pi / 2.6, clockwise: false)
        ctx.strokePath()
    }
}

png(1024, "AppIcon-1024.png") { appIcon($0, px: 1024) }
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    png(s, "AppIcon.iconset/icon_\(s)x\(s).png") { appIcon($0, px: s) }
    png(s * 2, "AppIcon.iconset/icon_\(s)x\(s)@2x.png") { appIcon($0, px: s * 2) }
}
for st in BarState.allCases {
    let base = st == .base ? "MenuBarIcon" : "MenuBarIcon-\(st.rawValue)"
    png(18, "\(base).png") { barIcon($0, px: 18, state: st) }
    png(36, "\(base)@2x.png") { barIcon($0, px: 36, state: st) }
}
print("ok -> \(out.path)")
