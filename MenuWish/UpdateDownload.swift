import Foundation
import CryptoKit

/// Only a complete, checksummed DMG from this repository can be downloaded in-app.
struct ReleaseInstaller: Equatable, Sendable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
        let state: String
    }

    let url: URL
    let name: String
    let size: Int64
    let sha256: String

    init?(asset: Asset, tag: String) {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let name = "MenuWish-\(version).dmg"
        let url = asset.browser_download_url
        guard asset.state == "uploaded", asset.name == name,
              url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              url.path == "/Goonwb/MenuWish/releases/download/\(tag)/\(name)",
              asset.size > 0, asset.size <= 200_000_000,
              let digest = asset.digest, digest.hasPrefix("sha256:") else { return nil }
        let hash = String(digest.dropFirst(7))
        guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        self.url = url
        self.name = name
        self.size = asset.size
        self.sha256 = hash
    }
}

enum UpdateDownloadError: Error {
    case invalidResponse, invalidSize, invalidChecksum, cannotMount
}

enum UpdateDownload {
    static func download(_ installer: ReleaseInstaller,
                         progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let delegate = DownloadProgress(expectedSize: installer.size, progress: progress)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: installer.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("MenuWish", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              DownloadProgress.allowedURL(http.url) else { throw UpdateDownloadError.invalidResponse }
        try validate(temporary, installer: installer)
        try Task.checkCancellation()
        let folder = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent("MenuWish/Updates/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(installer.name)
        do { try FileManager.default.moveItem(at: temporary, to: destination) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return destination
    }

    static func validate(_ file: URL, installer: ReleaseInstaller) throws {
        let values = try FileManager.default.attributesOfItem(atPath: file.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              (values[.size] as? NSNumber)?.int64Value == installer.size else {
            throw UpdateDownloadError.invalidSize
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == installer.sha256 else {
            throw UpdateDownloadError.invalidChecksum
        }
    }

    /// Mount without opening anything from the image. The caller opens its folder in Finder.
    static func mount(_ file: URL, installer: ReleaseInstaller) async throws -> URL {
        // Re-check immediately before mounting, including after a long pause on the ready screen.
        try validate(file, installer: installer)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateDownloadError.cannotMount
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func discard(_ file: URL) {
        // Only called with the unique cache URL returned by download().
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expectedSize: Int64
    let progress: @Sendable (Int64, Int64) -> Void

    init(expectedSize: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.expectedSize = expectedSize
        self.progress = progress
    }

    static func allowedURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil else { return false }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.allowedURL(request.url) ? request : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= expectedSize,
              totalBytesExpectedToWrite <= expectedSize else { downloadTask.cancel(); return }
        progress(totalBytesWritten, expectedSize)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
