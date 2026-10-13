// Draws the app icon. Run: swift tools/make_icon.swift   (writes Resources/AppIcon.icns)
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let body = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.025
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.20, green: 0.78, blue: 0.80, alpha: 1), NSColor(red: 0.10, green: 0.18, blue: 0.48, alpha: 1)])!
        .draw(in: body, angle: -90)

    let c = NSPoint(x: s / 2, y: s * 0.45), r = rect.width * 0.29, w = r * 0.20
    func arc(_ from: CGFloat, _ to: CGFloat, _ alpha: CGFloat) {
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: true)
        p.lineWidth = w
        p.lineCapStyle = .round
        NSColor.white.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }
    arc(210, -30, 0.28)      // full gauge track
    arc(210, 100, 0.95)      // low part: the Mac is calm
    let a = 100 * CGFloat.pi / 180
    let needle = NSBezierPath()
    needle.move(to: c)
    needle.line(to: NSPoint(x: c.x + cos(a) * r * 0.78, y: c.y + sin(a) * r * 0.78))
    needle.lineWidth = w * 0.7
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - w * 0.75, y: c.y - w * 0.75, width: w * 1.5, height: w * 1.5)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: set.appendingPathComponent("icon_\(name).png"))
}
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(512).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("icon_preview.png"))
print("wrote", out.path, "exit", p.terminationStatus)
