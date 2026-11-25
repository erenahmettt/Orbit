import AppKit

// Orbit uygulama ikonunu çizer ve .iconset klasörüne yazar
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func hex(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [hex(0x6558F5), hex(0x9B78E8), hex(0xE86BA8)])!.draw(in: bg, angle: -45)

    let c = NSPoint(x: s / 2, y: s / 2)
    let planetR = rect.width * 0.17
    // yörünge
    let t = NSAffineTransform()
    t.translateX(by: c.x, yBy: c.y)
    t.rotate(byDegrees: 25)
    let orbit = NSBezierPath(ovalIn: NSRect(x: -rect.width * 0.36, y: -rect.width * 0.13, width: rect.width * 0.72, height: rect.width * 0.26))
    orbit.transform(using: t as AffineTransform)
    orbit.lineWidth = s * 0.022
    NSColor.white.withAlphaComponent(0.85).setStroke()
    orbit.stroke()
    // gezegen
    let planet = NSBezierPath(ovalIn: NSRect(x: c.x - planetR, y: c.y - planetR, width: planetR * 2, height: planetR * 2))
    NSGradient(colors: [.white, hex(0xFFE3DF)])!.draw(in: planet, angle: -60)
    // uydu
    let moonR = rect.width * 0.055
    let moon = NSPoint(x: c.x + rect.width * 0.31, y: c.y + rect.width * 0.16)
    hex(0xFF786B).setFill()
    NSBezierPath(ovalIn: NSRect(x: moon.x - moonR, y: moon.y - moonR, width: moonR * 2, height: moonR * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
