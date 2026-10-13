import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    var bytesPerRow: Int {
        width * 4
    }

    func offset(x: Int, y: Int) -> Int {
        (y * width + x) * 4
    }
}

private func usage() -> Never {
    fputs(
        "Usage: swift Scripts/prepare-app-icon-source.swift <input.png> <output.png> [outputSize] [artSize]\n",
        stderr
    )
    exit(2)
}

private func loadImage(at url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to load \(url.path)"]
        )
    }
    return image
}

private func rgbaImage(from image: CGImage) throws -> RGBAImage {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create source bitmap"]
        )
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return RGBAImage(width: width, height: height, pixels: pixels)
}

private func isBackgroundCandidate(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
    let high = max(red, max(green, blue))
    let low = min(red, min(green, blue))
    let saturation = high - low

    // Seed only the border-connected white/neutral matte. This keeps the white
    // document and glossy edge highlights because they are not border-connected.
    return (low >= 242 && saturation <= 22) || (low >= 150 && saturation <= 14)
}

private func removeBorderMatte(from source: RGBAImage) -> RGBAImage {
    let width = source.width
    let height = source.height
    var output = source
    var background = [Bool](repeating: false, count: width * height)
    var queue: [(x: Int, y: Int)] = []
    queue.reserveCapacity(width * 2 + height * 2)

    func enqueueIfNeeded(_ x: Int, _ y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else {
            return
        }

        let index = y * width + x
        guard !background[index] else {
            return
        }

        let offset = source.offset(x: x, y: y)
        guard isBackgroundCandidate(
            red: source.pixels[offset],
            green: source.pixels[offset + 1],
            blue: source.pixels[offset + 2]
        ) else {
            return
        }

        background[index] = true
        queue.append((x, y))
    }

    for x in 0..<width {
        enqueueIfNeeded(x, 0)
        enqueueIfNeeded(x, height - 1)
    }

    for y in 0..<height {
        enqueueIfNeeded(0, y)
        enqueueIfNeeded(width - 1, y)
    }

    var head = 0
    while head < queue.count {
        let item = queue[head]
        head += 1

        enqueueIfNeeded(item.x + 1, item.y)
        enqueueIfNeeded(item.x - 1, item.y)
        enqueueIfNeeded(item.x, item.y + 1)
        enqueueIfNeeded(item.x, item.y - 1)
    }

    for y in 0..<height {
        for x in 0..<width {
            guard background[y * width + x] else {
                continue
            }

            let offset = output.offset(x: x, y: y)
            output.pixels[offset] = 0
            output.pixels[offset + 1] = 0
            output.pixels[offset + 2] = 0
            output.pixels[offset + 3] = 0
        }
    }

    return output
}

private func alphaBounds(of image: RGBAImage) -> CGRect {
    var minX = image.width
    var minY = image.height
    var maxX = -1
    var maxY = -1

    for y in 0..<image.height {
        for x in 0..<image.width {
            let alpha = image.pixels[image.offset(x: x, y: y) + 3]
            guard alpha > 0 else {
                continue
            }

            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
}

private func cgImage(from image: RGBAImage) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let data = Data(image.pixels)

    guard
        let provider = CGDataProvider(data: data as CFData),
        let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create transparent source image"]
        )
    }

    return cgImage
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create PNG destination"]
        )
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "MenuWishIcon",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Unable to write \(url.path)"]
        )
    }
}

private let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    usage()
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let outputSize = arguments.count >= 4 ? (Int(arguments[3]) ?? 1024) : 1024
let artSize = arguments.count >= 5 ? (Int(arguments[4]) ?? 832) : 832

let source = try rgbaImage(from: try loadImage(at: inputURL))
let transparent = removeBorderMatte(from: source)
let transparentImage = try cgImage(from: transparent)
let bounds = alphaBounds(of: transparent).insetBy(dx: -4, dy: -4).intersection(
    CGRect(x: 0, y: 0, width: source.width, height: source.height)
)

guard let cropped = transparentImage.cropping(to: bounds) else {
    throw NSError(
        domain: "MenuWishIcon",
        code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Unable to crop icon art"]
    )
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let outputContext = CGContext(
    data: nil,
    width: outputSize,
    height: outputSize,
    bitsPerComponent: 8,
    bytesPerRow: outputSize * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
) else {
    throw NSError(
        domain: "MenuWishIcon",
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create output bitmap"]
    )
}

let scale = min(CGFloat(artSize) / bounds.width, CGFloat(artSize) / bounds.height)
let targetWidth = bounds.width * scale
let targetHeight = bounds.height * scale
let targetRect = CGRect(
    x: (CGFloat(outputSize) - targetWidth) / 2,
    y: (CGFloat(outputSize) - targetHeight) / 2,
    width: targetWidth,
    height: targetHeight
)

outputContext.interpolationQuality = .high
outputContext.clear(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
outputContext.draw(cropped, in: targetRect)

guard let outputImage = outputContext.makeImage() else {
    throw NSError(
        domain: "MenuWishIcon",
        code: 8,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create output icon source"]
    )
}

try writePNG(outputImage, to: outputURL)
print("Prepared \(outputURL.path) from \(inputURL.path).")
