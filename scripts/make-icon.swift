// Draws the app icon: a dark squircle with the notch pill hanging from the
// top and a red record dot. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.20, blue: 0.21, alpha: 1), NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)])!
        .draw(in: squircle, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    squircle.lineWidth = max(1, s * 0.004)
    squircle.stroke()

    // The notch pill hanging from the top edge.
    let pw = body.width * 0.56, ph = body.height * 0.2
    let pill = NSRect(x: body.midX - pw / 2, y: body.maxY - ph, width: pw, height: ph)
    let pillPath = NSBezierPath()
    let r = ph * 0.5
    pillPath.move(to: NSPoint(x: pill.minX, y: pill.maxY))
    pillPath.line(to: NSPoint(x: pill.maxX, y: pill.maxY))
    pillPath.line(to: NSPoint(x: pill.maxX, y: pill.minY + r))
    pillPath.curve(to: NSPoint(x: pill.maxX - r, y: pill.minY), controlPoint1: NSPoint(x: pill.maxX, y: pill.minY + r * 0.45), controlPoint2: NSPoint(x: pill.maxX - r * 0.45, y: pill.minY))
    pillPath.line(to: NSPoint(x: pill.minX + r, y: pill.minY))
    pillPath.curve(to: NSPoint(x: pill.minX, y: pill.minY + r), controlPoint1: NSPoint(x: pill.minX + r * 0.45, y: pill.minY), controlPoint2: NSPoint(x: pill.minX, y: pill.minY + r * 0.45))
    pillPath.close()
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSColor.black.setFill()
    pillPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Red dot inside the pill and transcript lines below.
    let d = ph * 0.34
    NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.minX + ph * 0.42, y: pill.midY - d / 2, width: d, height: d)).fill()
    let lineH = body.height * 0.055
    let widths: [CGFloat] = [0.62, 0.5, 0.56]
    let colors = [NSColor(srgbRed: 0.45, green: 0.66, blue: 1, alpha: 0.95), NSColor(white: 1, alpha: 0.85), NSColor(srgbRed: 0.75, green: 0.6, blue: 1, alpha: 0.95)]
    for (i, w) in widths.enumerated() {
        let y = body.midY - CGFloat(i) * lineH * 2.1 - lineH
        let rect = NSRect(x: body.minX + body.width * 0.19, y: y, width: body.width * w, height: lineH)
        colors[i].setFill()
        NSBezierPath(roundedRect: rect, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
