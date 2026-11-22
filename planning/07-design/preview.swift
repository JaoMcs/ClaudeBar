// Folha de revisão: ícone em 128/32/16 (ampliados sem suavizar) sobre fundo claro e escuro,
// e o ícone de barra ao lado de um número, também claro/escuro.
// Uso: swift preview.swift <pasta-com-pngs> <saida.png>
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let W = 1400, H = 900
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func img(_ n: String) -> CGImage { NSImage(contentsOf: dir.appendingPathComponent(n))!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func gray(_ v: CGFloat) -> CGColor { CGColor(gray: v, alpha: 1) }

for (i, bg) in [gray(0.96), gray(0.12)].enumerated() {
    let y0 = CGFloat(H / 2 * (1 - i))
    ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(W), height: CGFloat(H / 2)))
    // App icon: 128 real, 32 e 16 reais e ampliados x4 (nearest).
    ctx.interpolationQuality = .high
    ctx.draw(img("AppIcon.iconset/icon_128x128.png"), in: CGRect(x: 30, y: y0 + 280, width: 128, height: 128))
    ctx.draw(img("AppIcon.iconset/icon_32x32.png"), in: CGRect(x: 180, y: y0 + 340, width: 32, height: 32))
    ctx.draw(img("AppIcon.iconset/icon_16x16.png"), in: CGRect(x: 230, y: y0 + 348, width: 16, height: 16))
    ctx.interpolationQuality = .none
    ctx.draw(img("AppIcon.iconset/icon_32x32.png"), in: CGRect(x: 280, y: y0 + 280, width: 128, height: 128))
    ctx.draw(img("AppIcon.iconset/icon_16x16.png"), in: CGRect(x: 430, y: y0 + 280, width: 128, height: 128))
    // Barra: cada estado ao lado de "2", tamanho real 2x e ampliado x4.
    let fg = i == 0 ? NSColor.black : NSColor.white
    for (j, n) in ["MenuBarIcon", "MenuBarIcon-idle", "MenuBarIcon-working", "MenuBarIcon-ready", "MenuBarIcon-waiting"].enumerated() {
        let tinted = NSImage(size: NSSize(width: 36, height: 36), flipped: false) { r in
            NSImage(contentsOf: dir.appendingPathComponent("\(n)@2x.png"))!.draw(in: r)
            fg.set(); r.fill(using: .sourceAtop); return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let x = CGFloat(30 + j * 270)
        ctx.interpolationQuality = .none
        ctx.draw(tinted, in: CGRect(x: x, y: y0 + 60, width: 144, height: 144))
        ctx.draw(tinted, in: CGRect(x: x + 160, y: y0 + 120, width: 36, height: 36))
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = g
        ("2" as NSString).draw(at: NSPoint(x: x + 200, y: y0 + 122),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 27, weight: .medium), .foregroundColor: fg])
    }
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
