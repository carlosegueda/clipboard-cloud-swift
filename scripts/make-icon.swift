import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Coordenadas de arriba hacia abajo.
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
            blue: CGFloat(h & 0xff) / 255, alpha: a)
}

/// Superelipse (forma "squircle" de los iconos de Apple).
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

// Sombra de la plantilla de macOS.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x6E7883)); ctx.fillPath()
ctx.restoreGState()

// Fondo: degradado gris pizarra vertical, con un brillo suave arriba.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x9AA4AE), rgb(0x7A8590), rgb(0x5C6670)] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 60), endRadius: 620, options: [])
ctx.restoreGState()

// Borde interior sutil.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(4); ctx.strokePath()
ctx.restoreGState()

// Glifo: dos cuadrados superpuestos.
let side: CGFloat = 300, off: CGFloat = 120, radius: CGFloat = 64, line: CGFloat = 46
let back = CGRect(x: 302, y: 302, width: side, height: side)
let front = back.offsetBy(dx: off, dy: off)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0x2A3138, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(line); ctx.setLineCap(.round); ctx.setLineJoin(.round)
// Cuadrado de atrás: solo el borde izquierdo y el superior.
let l = CGMutablePath()
l.move(to: CGPoint(x: back.minX, y: back.maxY - radius))
l.addLine(to: CGPoint(x: back.minX, y: back.minY + radius))
l.addArc(tangent1End: CGPoint(x: back.minX, y: back.minY), tangent2End: CGPoint(x: back.minX + radius, y: back.minY), radius: radius)
l.addLine(to: CGPoint(x: back.maxX - radius, y: back.minY))
ctx.addPath(l); ctx.strokePath()
ctx.addPath(CGPath(roundedRect: front, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.strokePath()
ctx.endTransparencyLayer()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
