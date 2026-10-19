import Foundation

@main
struct UpdateDownloadChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() async throws {
        let digest = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let url = "https://github.com/Goonwb/MenuWish/releases/download/v0.1.5/MenuWish-0.1.5.dmg"
        func asset(_ overrides: [String: Any] = [:]) throws -> ReleaseInstaller.Asset {
            var object: [String: Any] = ["name": "MenuWish-0.1.5.dmg", "browser_download_url": url,
                "size": 3, "digest": digest, "state": "uploaded"]
            object.merge(overrides) { _, new in new }
            return try JSONDecoder().decode(ReleaseInstaller.Asset.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        let installer = ReleaseInstaller(asset: try asset(), tag: "v0.1.5")!
        for invalid in [
            ["name": "other.dmg"], ["state": "new"], ["size": 0], ["size": 200_000_001],
            ["digest": NSNull()], ["digest": "sha256:abc"], ["digest": "md5:" + String(repeating: "a", count: 64)],
            ["browser_download_url": url.replacingOccurrences(of: "https:", with: "http:")],
            ["browser_download_url": url.replacingOccurrences(of: "github.com", with: "example.com")],
            ["browser_download_url": url.replacingOccurrences(of: "/v0.1.5/", with: "/v0.1.4/")],
            ["browser_download_url": url + "?redirect=other"],
            ["browser_download_url": url.replacingOccurrences(of: "github.com", with: "user@github.com")]
        ] as [[String: Any]] {
            let candidate = try asset(invalid)
            require(ReleaseInstaller(asset: candidate, tag: "v0.1.5") == nil, "Unsafe/incomplete installer accepted")
        }
        let releaseObject: [String: Any] = ["tag_name": "v0.1.5", "html_url": "https://github.com/Goonwb/MenuWish/releases/tag/v0.1.5",
            "draft": false, "prerelease": false, "body": "Update", "assets": [["name": "MenuWish-0.1.5.dmg",
                "browser_download_url": url, "size": 3, "digest": digest, "state": "uploaded"]]]
        let data = try JSONSerialization.data(withJSONObject: releaseObject)
        guard case .available(let release) = try UpdateChecker.result(data: data, statusCode: 200, currentVersion: "0.1.4") else {
            fatalError("Update unavailable")
        }
        require(release.installer == installer, "Release parser lost installer metadata")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("test.dmg")
        try Data("abc".utf8).write(to: file)
        try UpdateDownload.validate(file, installer: installer)
        try Data("abd".utf8).write(to: file)
        do { try UpdateDownload.validate(file, installer: installer); fatalError("Corrupt data accepted") }
        catch UpdateDownloadError.invalidChecksum {}
        try Data("ab".utf8).write(to: file)
        do { try UpdateDownload.validate(file, installer: installer); fatalError("Truncated data accepted") }
        catch UpdateDownloadError.invalidSize {}
        try Data("abc".utf8).write(to: file)
        do { _ = try await UpdateDownload.mount(file, installer: installer); fatalError("Invalid disk image mounted") }
        catch UpdateDownloadError.cannotMount {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await UpdateDownload.download(installer) { _, _ in }
                fatalError("Cancelled download continued")
            } catch is CancellationError {}
        }
        try await cancelled.value
        print("PASS: trusted release assets, missing/invalid digests, wrong version/host, size limits, corrupt/truncated downloads, invalid DMG, cancellation")
    }
}
