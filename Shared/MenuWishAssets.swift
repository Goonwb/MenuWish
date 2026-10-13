import AppKit

/// One asset source for the host app and its separately bundled Finder extension.
enum MenuWishAssets {
    private final class BundleAnchor: NSObject {}
    static let originalSparklesSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18" fill="black">
      <path d="M 8.70 4.75 L 9.82 7.88 L 12.95 9.00 L 9.82 10.12 L 8.70 13.25 L 7.58 10.12 L 4.45 9.00 L 7.58 7.88 Z" />
      <path d="M 4.15 2.65 L 4.77 4.13 L 6.25 4.75 L 4.77 5.37 L 4.15 6.85 L 3.53 5.37 L 2.05 4.75 L 3.53 4.13 Z" />
      <path d="M 13.65 11.55 L 14.19 12.81 L 15.45 13.35 L 14.19 13.89 L 13.65 15.15 L 13.11 13.89 L 11.85 13.35 L 13.11 12.81 Z" />
    </svg>
    """

    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func actionColor(for name: String) -> NSColor? {
        switch name {
        case "file-text": return .systemGray
        case "markdown": return .systemIndigo
        case "doc.richtext": return .systemOrange
        case "tablecells": return .systemGreen
        case "link": return .systemBlue
        case "rectangle.on.rectangle": return .systemBlue
        case "square-terminal", "terminal": return .systemTeal
        default: return nil
        }
    }

    /// FinderSync drops template metadata when transporting menu images as TIFF.
    /// Resolve a neutral foreground for the extension's system appearance each
    /// time a menu opens. This is an appearance fallback, not hover recoloring.
    static func finderMenuImage(named name: String,
                                size: NSSize = NSSize(width: 16, height: 16),
                                appearance: NSAppearance, bundle: Bundle? = nil) -> NSImage? {
        var result: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let foreground: NSColor = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .white : .black
            result = image(named: name, size: size, bundle: bundle, tint: foreground)
        }
        return result
    }

    static func image(named name: String, size: NSSize = NSSize(width: 16, height: 16),
                      bundle: Bundle? = nil, tint: NSColor? = nil) -> NSImage? {
        let resourceBundle = bundle ?? Bundle(for: BundleAnchor.self)
        let color = tint?.usingColorSpace(.sRGB)
        let colorKey = color.map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent),\($0.alphaComponent)" } ?? "template"
        let key = "\(resourceBundle.bundleURL.path)_\(name)_\(size.width)x\(size.height)_\(colorKey)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let svgString: String?
        if name == "sparkles" || name == "menuwish-stars" {
            svgString = originalSparklesSVG
        } else {
            let filenames = [
                "file-text": "text", "markdown": "markdown", "tablecells": "numbers",
                "doc.richtext": "pages", "rectangle.on.rectangle": "keynote",
                "square-terminal": "terminal", "terminal": "terminal", "link": "copy-path"
            ]
            guard let filename = filenames[name],
                  let url = resourceBundle.url(forResource: filename, withExtension: "svg", subdirectory: "MenuIcons") else { return nil }
            svgString = try? String(contentsOf: url, encoding: .utf8)
        }

        guard let svg = svgString,
              let data = svg.data(using: .utf8),
              let svgImage = NSImage(data: data) else {
            return nil
        }

        let rendered = NSImage(size: size)
        for scale in [1.0, 2.0] {
            let pxW = Int(size.width * scale)
            let pxH = Int(size.height * scale)
            let colorSpace = color == nil ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
            guard let ctx = CGContext(
                data: nil,
                width: pxW,
                height: pxH,
                bitsPerComponent: 8,
                bytesPerRow: pxW * (color == nil ? 2 : 4),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                continue
            }
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)
            ctx.scaleBy(x: scale, y: scale)

            ctx.saveGState()
            let g = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            svgImage.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

            if let color {
                // Bake color into the bitmap: FinderSync transports TIFF pixels,
                // so host-only template tinting does not reach Finder menus.
                ctx.setBlendMode(.sourceIn)
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
            }

            if let cgImage = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if color != nil {
                    rep.setProperty(.colorSyncProfileData, withValue: NSColorSpace.sRGB.iccProfileData)
                }
                rep.size = size
                rendered.addRepresentation(rep)
            }
        }

        // Host controls tint masks; Finder receives fully colored bitmap pixels.
        // Bitmap menu icons retain their resolved color when the item is highlighted.
        rendered.isTemplate = color == nil

        lock.lock()
        cache[key] = rendered
        lock.unlock()

        return rendered
    }
}
