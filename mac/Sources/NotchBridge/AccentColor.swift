import AppKit

/// Picks a vivid "brand" colour from an app icon: the average of its saturated pixels,
/// pushed bright enough to glow on black. Returns nil for grey/monochrome icons.
enum AccentColor {
    static func from(_ image: NSImage) -> NSColor? {
        let side = 24
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in 0..<(side * side) {
            let a = Double(px[i * 4 + 3]) / 255
            guard a > 0.6 else { continue }
            let pr = Double(px[i * 4]) / 255 / a, pg = Double(px[i * 4 + 1]) / 255 / a, pb = Double(px[i * 4 + 2]) / 255 / a
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            let sat = mx == 0 ? 0 : (mx - mn) / mx
            guard sat > 0.3, mx > 0.25 else { continue }
            // weight vivid pixels more
            let w = sat * mx
            r += pr * w; g += pg * w; b += pb * w; n += w
        }
        guard n > 3 else { return nil }
        let avg = NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
        avg.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
        return NSColor(hue: h, saturation: min(max(s, 0.55), 0.9), brightness: max(v, 0.9), alpha: 1)
    }

    static let fallback = NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 1)
}
