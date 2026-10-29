import AppKit
import Foundation

// A native vector icon: Lewtech's angular L motif and a recording dot.
// Colors come from lewtech.no's public brand stylesheet.
let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/LewtechRecord.iconset"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
func color(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: alpha)
}
func polygon(_ points: [NSPoint], color fill: NSColor) {
    let path = NSBezierPath(); path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close(); fill.setFill(); path.fill()
}
func icon(size: Int) -> Data {
    let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    let faceRect = NSRect(x: 58, y: 58, width: 908, height: 908)
    let face = NSBezierPath(roundedRect: faceRect, xRadius: 205, yRadius: 205)
    let shadow = NSShadow(); shadow.shadowColor = color(0x122019, alpha: 0.26)
    shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); color(0x25372C).setFill(); face.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x304737), ending: color(0x25372C))!.draw(in: face, angle: -90)
    let rim = NSBezierPath(roundedRect: faceRect.insetBy(dx: 2, dy: 2), xRadius: 203, yRadius: 203)
    rim.lineWidth = 3; color(0xEEEADE, alpha: 0.12).setStroke(); rim.stroke()

    // Folded L/window mark, recalling the Lewtech logo without tiny wordmark text.
    let cream = color(0xF1EDE3)
    polygon([NSPoint(x: 262, y: 757), NSPoint(x: 374, y: 757), NSPoint(x: 374, y: 397),
             NSPoint(x: 517, y: 309), NSPoint(x: 517, y: 187), NSPoint(x: 262, y: 343)], color: cream)
    polygon([NSPoint(x: 421, y: 757), NSPoint(x: 755, y: 757), NSPoint(x: 755, y: 649), NSPoint(x: 421, y: 649)], color: cream)
    polygon([NSPoint(x: 421, y: 603), NSPoint(x: 527, y: 603), NSPoint(x: 527, y: 401),
             NSPoint(x: 421, y: 465)], color: cream)
    polygon([NSPoint(x: 574, y: 603), NSPoint(x: 680, y: 603), NSPoint(x: 680, y: 468),
             NSPoint(x: 574, y: 403)], color: cream)

    // Solid terracotta status badge, separated by a dark cutout ring.
    let badge = NSBezierPath(ovalIn: NSRect(x: 664, y: 211, width: 178, height: 178))
    badge.lineWidth = 24; color(0x25372C).setStroke(); badge.stroke()
    color(0xB96E44).setFill(); badge.fill()
    let inset = NSBezierPath(ovalIn: NSRect(x: 711, y: 258, width: 84, height: 84))
    cream.setFill(); inset.fill()
    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])!
}
for base in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let path = URL(fileURLWithPath: outputDirectory).appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        try icon(size: base * density).write(to: path)
    }
}
print(outputDirectory)
