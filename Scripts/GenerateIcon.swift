import AppKit
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.055, green: 0.14, blue: 0.16, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let colors: [NSColor] = [.init(calibratedRed: 0.22, green: 0.47, blue: 0.46, alpha: 1), .init(calibratedRed: 0.30, green: 0.67, blue: 0.60, alpha: 1), .init(calibratedRed: 0.55, green: 0.88, blue: 0.73, alpha: 1)]
for i in 0..<3 {
    colors[i].setStroke()
    let p = NSBezierPath()
    p.lineWidth = 62; p.lineCapStyle = .round
    p.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: CGFloat(320 - i * 92), startAngle: 220, endAngle: CGFloat(500 - i * 25))
    p.stroke()
}
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
for catalog in ["Phone", "Watch"] {
    try data.write(to: URL(fileURLWithPath: "Resources/\(catalog).xcassets/AppIcon.appiconset/Icon.png"))
}
