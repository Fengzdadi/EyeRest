// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Body: Apple's macOS icon grid puts an 824 pt rounded square on a 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2A9D9F))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x6EDBC1), color(0x1E7F94)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The eye: an almond of two curves.
    let c = CGPoint(x: 512, y: 500)
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: c.x - 300, y: c.y))
    eye.addCurve(to: CGPoint(x: c.x + 300, y: c.y),
                 control1: CGPoint(x: c.x - 150, y: c.y + 215),
                 control2: CGPoint(x: c.x + 150, y: c.y + 215))
    eye.addCurve(to: CGPoint(x: c.x - 300, y: c.y),
                 control1: CGPoint(x: c.x + 150, y: c.y - 215),
                 control2: CGPoint(x: c.x - 150, y: c.y - 215))
    eye.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x0B3B45, alpha: 0.35))
    ctx.addPath(eye)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Iris, clipped to the eye so the lids cover its top and bottom.
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let irisRect = CGRect(x: c.x - 132, y: c.y - 132, width: 264, height: 264)
    ctx.addEllipse(in: irisRect)
    ctx.clip()
    let iris = CGGradient(colorsSpace: space, colors: [color(0x37B3A4), color(0x135E70)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(iris, startCenter: CGPoint(x: c.x - 30, y: c.y + 40), startRadius: 0,
                           endCenter: c, endRadius: 132, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Pupil and a highlight.
    ctx.setFillColor(color(0x0A2A33))
    ctx.fillEllipse(in: CGRect(x: c.x - 58, y: c.y - 58, width: 116, height: 116))
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.92))
    ctx.fillEllipse(in: CGRect(x: c.x + 18, y: c.y + 30, width: 46, height: 46))

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
    drawIcon(in: ctx)
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
