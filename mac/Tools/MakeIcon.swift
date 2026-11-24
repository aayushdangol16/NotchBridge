// Renders the NotchBridge app icon to an .iconset and converts it with iconutil.
// Usage: swift Tools/MakeIcon.swift <output.icns>
//
// Design: a dark squircle (macOS icon grid), a black notch with soft concave ears at the top,
// a glowing island card dropping out of it, and a green "phone connected" dot.

import AppKit

func render(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)   // top-left based design coords
    }

    // Squircle body (824x824 centred, per the macOS icon grid) with a deep gradient.
    let body = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 186 * s, yRadius: 186 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.13, blue: 0.32, alpha: 1),
                        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.11, alpha: 1)])!.draw(in: body, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    body.addClip()

    // Purple/teal glow behind the island.
    let glow = NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.35, blue: 1, alpha: 0.55), .clear])!
    glow.draw(fromCenter: NSPoint(x: 512 * s, y: (1024 - 420) * s), radius: 0,
              toCenter: NSPoint(x: 512 * s, y: (1024 - 420) * s), radius: 420 * s, options: [])

    // Island: notch strip at the top widening into a rounded card.
    let island = NSBezierPath()
    let top: CGFloat = 100, left: CGFloat = 232, right: CGFloat = 792, bottom: CGFloat = 560, ear: CGFloat = 34, rad: CGFloat = 92
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (1024 - y) * s) }
    island.move(to: p(left - ear, top))
    island.curve(to: p(left, top + ear), controlPoint1: p(left - ear / 3, top), controlPoint2: p(left, top + ear / 3))
    island.line(to: p(left, bottom - rad))
    island.curve(to: p(left + rad, bottom), controlPoint1: p(left, bottom - rad * 0.45), controlPoint2: p(left + rad * 0.45, bottom))
    island.line(to: p(right - rad, bottom))
    island.curve(to: p(right, bottom - rad), controlPoint1: p(right - rad * 0.45, bottom), controlPoint2: p(right, bottom - rad * 0.45))
    island.line(to: p(right, top + ear))
    island.curve(to: p(right + ear, top), controlPoint1: p(right, top + ear / 3), controlPoint2: p(right + ear / 3, top))
    island.close()
    NSColor.black.setFill()
    island.fill()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    island.lineWidth = 4 * s
    island.stroke()

    // Card content: avatar circle with gradient ring, two text lines.
    let avatar = NSBezierPath(ovalIn: r(292, 300, 150, 150))
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.55, blue: 0.4, alpha: 1),
                        NSColor(srgbRed: 0.85, green: 0.3, blue: 0.55, alpha: 1)])!.draw(in: avatar, angle: -45)
    let ring = NSBezierPath(ovalIn: r(280, 288, 174, 174))
    ring.lineWidth = 8 * s
    NSColor(srgbRed: 0.62, green: 0.45, blue: 1, alpha: 1).setStroke()
    ring.stroke()
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: r(486, 318, 230, 40), xRadius: 20 * s, yRadius: 20 * s).fill()
    NSColor.white.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: r(486, 388, 180, 32), xRadius: 16 * s, yRadius: 16 * s).fill()

    // Green "phone connected" dot in the notch strip.
    NSGraphicsContext.current?.saveGraphicsState()
    let dotShadow = NSShadow()
    dotShadow.shadowColor = NSColor(srgbRed: 0.2, green: 1, blue: 0.5, alpha: 0.9)
    dotShadow.shadowBlurRadius = 22 * s
    dotShadow.set()
    NSColor(srgbRed: 0.24, green: 0.9, blue: 0.48, alpha: 1).setFill()
    NSBezierPath(ovalIn: r(686, 176, 46, 46)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
try? render(size: 512).write(to: out.deletingPathExtension().appendingPathExtension("png"))
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
