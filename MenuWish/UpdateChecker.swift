import Foundation

struct ReleaseDetails: Equatable, Sendable {
    let version: String
    let page: URL
    // nil means the fallback could only retrieve the version; empty means no notes were published.
    let notes: String?
    var installer: ReleaseInstaller? = nil
}

enum UpdateCheckResult: Equatable {
    case available(ReleaseDetails)
    case upToDate(ReleaseDetails)
    case noRelease
}

enum UpdateCheckError: Error {
    case httpStatus(Int)
    case invalidRelease
}

enum UpdateChecker {
    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [ReleaseInstaller.Asset]?
    }

    static func result(data: Data, statusCode: Int, currentVersion: String) throws -> UpdateCheckResult {
        if statusCode == 404 { return .noRelease }
        guard statusCode == 200 else { throw UpdateCheckError.httpStatus(statusCode) }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              release.html_url.scheme == "https",
              release.html_url.host == "github.com",
              release.html_url.path.hasPrefix("/Goonwb/MenuWish/releases/tag/"),
              versionParts(release.tag_name) != nil else {
            throw UpdateCheckError.invalidRelease
        }
        let details = ReleaseDetails(version: release.tag_name, page: release.html_url,
            notes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            installer: release.assets?.compactMap { ReleaseInstaller(asset: $0, tag: release.tag_name) }.first)
        return try compare(details, currentVersion: currentVersion)
    }

    /// Public release redirects remain available when the unauthenticated API is rate limited.
    static func resultFromRedirect(url: URL?, statusCode: Int, currentVersion: String) throws -> UpdateCheckResult {
        if statusCode == 404 { return .noRelease }
        guard statusCode == 200 else { throw UpdateCheckError.httpStatus(statusCode) }
        guard let url, url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Goonwb/MenuWish/releases/tag/") else {
            throw UpdateCheckError.invalidRelease
        }
        return try compare(ReleaseDetails(version: url.lastPathComponent, page: url, notes: nil), currentVersion: currentVersion)
    }

    /// The public Atom feed is a best-effort notes fallback. The latest stable
    /// release was already determined by GitHub's redirect, not by feed order.
    static func notesFromFeed(data: Data, releasePage: URL) -> String? {
        guard data.count <= 2_000_000,
              let feed = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
              let entries = feed.rootElement()?.elements(forName: "entry"),
              let entry = entries.first(where: { entry in
                  entry.elements(forName: "link").contains {
                      $0.attribute(forName: "href")?.stringValue == releasePage.absoluteString
                  }
              }), let content = entry.elements(forName: "content").first else { return nil }
        let body = content.stringValue ?? ""
        guard content.attribute(forName: "type")?.stringValue == "html" else {
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let html = try? XMLDocument(xmlString: "<html><body>\(body)</body></html>",
            options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = html.rootElement() else { return nil }
        return feedText(root)
            .replacingOccurrences(of: #"\n[\t ]*\n(?:[\t ]*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func feedText(_ node: XMLNode) -> String {
        if node.kind == .text { return node.stringValue ?? "" }
        let name = node.name?.lowercased() ?? ""
        if ["script", "style", "img", "svg"].contains(name) { return "" }
        let text = (node.children ?? []).map(feedText).joined()
        switch name {
        case "br": return "\n"
        case "hr": return "\n\n---\n\n"
        case "h1", "h2", "h3", "h4", "h5", "h6": return "\n## \(text)\n"
        case "li": return "\n- " + text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "p", "div", "ul", "ol": return "\n" + text + "\n"
        case "strong", "b": return "**\(text)**"
        default: return text
        }
    }

    private static func compare(_ release: ReleaseDetails, currentVersion: String) throws -> UpdateCheckResult {
        guard let latest = versionParts(release.version), let current = versionParts(currentVersion) else {
            throw UpdateCheckError.invalidRelease
        }

        for index in 0..<max(latest.count, current.count) {
            let lhs = index < latest.count ? latest[index] : 0
            let rhs = index < current.count ? current[index] : 0
            if lhs > rhs { return .available(release) }
            if lhs < rhs { return .upToDate(release) }
        }
        return .upToDate(release)
    }

    private static func versionParts(_ value: String) -> [Int]? {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") { version.removeFirst() }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : nil
    }
}
