// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

/// Strokes an arc of a circle; angles are in degrees, counterclockwise from the right.
func strokeArc(in ctx: CGContext, center: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat, width: CGFloat) {
    ctx.setLineWidth(width)
    ctx.addArc(center: center, radius: radius, startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
    ctx.strokePath()
}

/// Fills a four-pointed sparkle with softened tips.
func fillSparkle(in ctx: CGContext, center c: CGPoint, radius r: CGFloat) {
    let pinch = r * 0.16
    ctx.move(to: CGPoint(x: c.x, y: c.y + r))
    ctx.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
    ctx.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
    ctx.closePath()
    ctx.setLineWidth(pinch)
    ctx.drawPath(using: .fillStroke)
}

/// The icon is a sleepy face: closed eyes, pink cheeks and a small smile on a mint body.
/// `pixels` is the size being rendered.
func drawIcon(in ctx: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / canvas

    // Body: Apple's macOS icon grid puts an 824 pt rounded square on a 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Shadows ignore the context's scale, so this one is sized by hand.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: color(0x000000, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x48BFBD))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0xB4F3DF), color(0x48BFBD)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Soft light from the upper left.
    let lamp = CGPoint(x: 330, y: 830)
    let light = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.38), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: lamp, startRadius: 0, endCenter: lamp, endRadius: 560, options: [])

    // Cheeks: pink ovals with a soft edge.
    let pink: UInt32 = 0xFF9DB6
    let cheek = CGGradient(
        colorsSpace: space,
        colors: [color(pink, alpha: 0.95), color(pink, alpha: 0.95), color(pink, alpha: 0)] as CFArray,
        locations: [0, 0.72, 1])!
    for x: CGFloat in [232, 792] {
        ctx.saveGState()
        ctx.translateBy(x: x, y: 414)
        ctx.scaleBy(x: 1, y: 54.0 / 84.0)
        ctx.drawRadialGradient(cheek, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 84, options: [])
        ctx.restoreGState()
    }

    // Closed eyes and a small smile. Below 128 px the lines get heavier, so the face still reads at 16 and 32 px.
    let weight = pow(max(1, 128 / CGFloat(pixels)), 0.4)
    ctx.setStrokeColor(color(0x15505C))
    ctx.setLineCap(.round)
    for x: CGFloat in [334, 690] {
        strokeArc(in: ctx, center: CGPoint(x: x, y: 572), radius: 96, from: 206, to: 334, width: 36 * weight)
    }
    strokeArc(in: ctx, center: CGPoint(x: 512, y: 452), radius: 36, from: 212, to: 328, width: 26 * weight)

    // Sparkles: eyes that have had their rest.
    ctx.setFillColor(color(0xFFFFFF))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineJoin(.round)
    fillSparkle(in: ctx, center: CGPoint(x: 724, y: 786), radius: 58)
    fillSparkle(in: ctx, center: CGPoint(x: 818, y: 704), radius: 28)

    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx, pixels: size)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
print("Wrote Resources/AppIcon.icns")
