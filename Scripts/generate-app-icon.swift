import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let sourcePNG = root.appendingPathComponent("MenuWish/Resources/MenuWish-source.png")
private let assetDirectory = root.appendingPathComponent("MenuWish/Assets.xcassets/AppIcon.appiconset")
private let resourceIconsetDirectory = root.appendingPathComponent("MenuWish/Resources/MenuWish.iconset")

private struct IconImage {
    let filename: String
    let pixelSize: Int
}

private let iconImages: [IconImage] = [
    .init(filename: "icon_16x16.png", pixelSize: 16),
    .init(filename: "icon_16x16@2x.png", pixelSize: 32),
    .init(filename: "icon_32x32.png", pixelSize: 32),
    .init(filename: "icon_32x32@2x.png", pixelSize: 64),
    .init(filename: "icon_128x128.png", pixelSize: 128),
    .init(filename: "icon_128x128@2x.png", pixelSize: 256),
    .init(filename: "icon_256x256.png", pixelSize: 256),
    .init(filename: "icon_256x256@2x.png", pixelSize: 512),
    .init(filename: "icon_512x512.png", pixelSize: 512),
    .init(filename: "icon_512x512@2x.png", pixelSize: 1024)
]

private func loadSourceImage() throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(sourcePNG as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to load \(sourcePNG.path)"]
        )
    }
    return image
}

private func pngData(from image: CGImage, size: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create \(size)x\(size) bitmap context"]
        )
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let resized = context.makeImage() else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create resized image"]
        )
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create PNG destination"]
        )
    }

    CGImageDestinationAddImage(destination, resized, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Unable to write PNG data"]
        )
    }
    return data as Data
}

private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

let sourceImage = try loadSourceImage()
try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourceIconsetDirectory, withIntermediateDirectories: true)

for icon in iconImages {
    let data = try pngData(from: sourceImage, size: icon.pixelSize)
    try write(data, to: assetDirectory.appendingPathComponent(icon.filename))
    try write(data, to: resourceIconsetDirectory.appendingPathComponent(icon.filename))
}

print("Generated app icons from MenuWish-source.png.")
