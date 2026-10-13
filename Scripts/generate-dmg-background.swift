import AppKit

// Deterministic native artwork; the two large icons are real Finder items.
let width = 660
let height = 340
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2,
    pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.985, green: 0.979, blue: 0.974, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 24, y: y, width: 612, height: size * 1.6),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color, .paragraphStyle: style])
}
let accent = NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.28, alpha: 1)
text("MenuWish", y: 245, size: 32, weight: .bold, color: accent)
text("拖入应用程序，即可安装", y: 208, size: 17, weight: .medium, color: .darkGray)
text("Drag MenuWish to Applications to install", y: 184, size: 13, weight: .regular, color: .gray)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 306, y: 120))
arrow.line(to: NSPoint(x: 354, y: 120))
arrow.move(to: NSPoint(x: 341, y: 133))
arrow.line(to: NSPoint(x: 354, y: 120))
arrow.line(to: NSPoint(x: 341, y: 107))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
accent.withAlphaComponent(0.6).setStroke()
arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
