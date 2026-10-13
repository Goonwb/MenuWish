import AppKit

@main
struct FinderIconChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let names = ["file-text", "markdown", "tablecells", "doc.richtext",
                     "rectangle.on.rectangle", "square-terminal", "link", "sparkles"]
        for name in names {
            var images: [NSImage] = []
            for (appearanceName, expected) in [(NSAppearance.Name.aqua, 0.0), (.darkAqua, 1.0)] {
                let appearance = NSAppearance(named: appearanceName)!
                let image = MenuWishAssets.finderMenuImage(named: name, appearance: appearance, bundle: bundle)!
                precondition(!image.isTemplate)
                let decoded = NSBitmapImageRep.imageReps(with: image.tiffRepresentation!)
                    .compactMap { $0 as? NSBitmapImageRep }
                precondition(Set(decoded.map(\.pixelsWide)) == [16, 32])
                for bitmap in decoded {
                    var visible = 0
                    var transparent = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            // colorAt exposes the bitmap components as a calibrated
                            // NSColor; compare raw components without a second conversion.
                            let pixel = bitmap.colorAt(x: x, y: y)!
                            if pixel.alphaComponent < 0.01 { transparent += 1 }
                            if pixel.alphaComponent > 0.95 {
                                precondition(abs(pixel.redComponent - expected) < 0.01)
                                precondition(abs(pixel.greenComponent - expected) < 0.01)
                                precondition(abs(pixel.blueComponent - expected) < 0.01)
                                visible += 1
                            }
                        }
                    }
                    precondition(visible > 0 && transparent > 0)
                }
                images.append(image)
            }
            precondition(images[0] !== images[1], "Appearance variants shared a stale cached image")
            let lightAgain = MenuWishAssets.finderMenuImage(named: name,
                appearance: NSAppearance(named: .aqua)!, bundle: bundle)!
            precondition(lightAgain === images[0])
            let template = MenuWishAssets.image(named: name, bundle: bundle)!
            precondition(template.isTemplate && template !== images[0] && template !== images[1])
            precondition(NSImage(data: template.tiffRepresentation!)?.isTemplate == false,
                         "TIFF behavior changed; revisit native Finder template handling")
        }
        for symbol in ["doc.text", "terminal"] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            image.isTemplate = true
            precondition(NSImage(data: image.tiffRepresentation!)?.isTemplate == false)
        }
        print("PASS: eight Finder icons retain light/dark monochrome pixels and transparency through TIFF at 1x/2x; cache variants and host template masks remain separate")
        print("CONFIRMED: TIFF round-trip drops the template flag for custom artwork and SF Symbols; hover recoloring remains unavailable")
    }
}
