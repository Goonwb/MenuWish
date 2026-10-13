import Foundation

@main
struct FeatureChecks {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw NSError(domain: "FeatureChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let templates = root.appendingPathComponent("RightMenuMini/Resources/Templates")
        let temporary = fm.temporaryDirectory.appendingPathComponent("MenuWish-check-\(UUID())")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let folder = temporary.appendingPathComponent("中文 folder & \"quoted\"")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for kind in NewFileKind.allCases {
            let first = try NewFileCreator.create(kind, in: folder, templates: templates)
            try require(first.lastPathComponent == "Untitled.\(kind.fileExtension)", "Wrong filename")
            let expected = kind.usesTemplate ? try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.fileExtension)")) : Data()
            try require(Data(contentsOf: first) == expected, "Invalid file contents")
            let sentinel = Data("Do not overwrite".utf8)
            try sentinel.write(to: first)
            let second = try NewFileCreator.create(kind, in: folder, templates: templates)
            try require(second.lastPathComponent == "Untitled 2.\(kind.fileExtension)", "Duplicate name was not numbered")
            try require(Data(contentsOf: first) == sentinel, "Existing file overwritten")
            try require(Data(contentsOf: second) == expected, "Duplicate contents incorrect")
        }
        let missing = temporary.appendingPathComponent("missing")
        do {
            _ = try NewFileCreator.create(.markdown, in: missing, templates: nil)
            throw NSError(domain: "Unexpected creation in a missing directory", code: 1)
        } catch is CocoaError {}
        do {
            _ = try NewFileCreator.create(.pages, in: folder, templates: missing)
            throw NSError(domain: "Missing template silently accepted", code: 1)
        } catch is CocoaError {}
        // Exclusive creation must skip broken symbolic links as well as regular files.
        try fm.createSymbolicLink(atPath: folder.appendingPathComponent("Untitled 3.md").path, withDestinationPath: missing.path)
        let afterLink = try NewFileCreator.create(.markdown, in: folder, templates: nil)
        try require(afterLink.lastPathComponent == "Untitled 4.md", "Broken symlink was replaced")

        let concurrent = temporary.appendingPathComponent("concurrent")
        try fm.createDirectory(at: concurrent, withIntermediateDirectories: true)
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do { _ = try NewFileCreator.create(.markdown, in: concurrent, templates: nil) }
            catch { fatalError("Concurrent creation failed: \(error)") }
        }
        try require(fm.contentsOfDirectory(atPath: concurrent.path).count == 20, "Concurrent files were lost")

        var layout = MenuLayout()
        try require(layout.categories == [.files, .tools], "Default categories changed")
        try require(layout.move(.tools, by: -1), "Category move failed")
        try require(layout.move(.markdown, by: -1), "Action move failed")
        try require(layout.move(.copyPath, by: -1), "Tool move failed")
        try require(!layout.move(.markdown, by: -1), "Action moved outside its category")
        try require(!layout.move(.tools, by: -1), "Category moved outside the list")
        try require(MenuLayout(serialized: layout.serialized) == layout, "Sort order did not persist")
        try require(MenuLayout(serialized: "bad data") == MenuLayout(), "Corrupt order did not recover")
        let migrated = MenuLayout(serialized: #"{"categories":["tools","tools","future"],"actions":{"files":["new-markdown","new-markdown","terminal","unknown"],"tools":["copy-path"]}}"#)
        try require(migrated.categories == [.tools, .files], "Category migration duplicated or lost a group")
        try require(migrated.orderedActions(in: .files) == [.markdown, .text, .numbers, .pages, .keynote], "New actions were not appended safely")
        try require(migrated.orderedActions(in: .tools) == [.copyPath, .terminal], "Tool migration failed")
        var enabled = Dictionary(uniqueKeysWithValues: MenuAction.allCases.map { ($0.preferenceKey, true) })
        try require(layout.enabledGroups(values: enabled).first == [.copyPath, .terminal], "Menu ignored category order")
        MenuCategory.tools.actions.forEach { enabled[$0.preferenceKey] = false }
        try require(layout.enabledGroups(values: enabled).count == 1, "Empty category was retained")
        MenuAction.allCases.forEach { enabled[$0.preferenceKey] = false }
        try require(layout.enabledGroups(values: enabled).isEmpty, "Disabled actions leaked into the menu")

        try require(MenuDisplayMode.resolved(nil, legacyGrouped: false) == .flat, "Legacy flat mode changed")
        try require(MenuDisplayMode.resolved("", legacyGrouped: true) == .grouped, "Legacy grouped mode changed")
        try require(MenuDisplayMode.resolved("future", legacyGrouped: true) == .grouped, "Invalid mode did not recover")
        for mode in MenuDisplayMode.allCases {
            try require(MenuDisplayMode.resolved(mode.rawValue, legacyGrouped: false) == mode, "Mode did not persist")
        }
        let allEnabled = Dictionary(uniqueKeysWithValues: MenuAction.allCases.map { ($0.preferenceKey, true) })
        var categorized = MenuLayout()
        // Interleave a tool with file actions, then reorder inside a category.
        _ = categorized.moveUnified(.terminal, by: -1)
        let interleaved = categorized.unifiedActions
        try require(categorized.moveWithinCategory(.keynote, by: -1), "Category action move failed")
        try require(categorized.unifiedActions.firstIndex(of: .terminal) == interleaved.firstIndex(of: .terminal), "Category sort moved an unrelated tool")
        let globalOrder = categorized.unifiedActions
        try require(categorized.moveCategory(.tools, by: -1), "Category order move failed")
        try require(categorized.unifiedActions == globalOrder, "Category sorting overwrote flat order")
        let groups = categorized.menuGroups(mode: .categorized, values: allEnabled)
        try require(groups.map(\.category) == [.tools, .files], "Category menu order is wrong")
        try require(groups[0].actions == [.terminal, .copyPath], "Tool submenu contains wrong actions")
        try require(groups[1].actions == [.text, .markdown, .numbers, .keynote, .pages], "File submenu ignored item order")
        try require(groups[0].title(isEnglish: false) == "常用工具", "Category title is ambiguous")
        try require(groups[1].title(isEnglish: true) == "New Files", "English category title is wrong")
        for mode in [MenuDisplayMode.flat, .grouped] {
            let result = categorized.menuGroups(mode: mode, values: allEnabled)
            try require(result.count == 1 && result[0].category == nil && result[0].actions == globalOrder,
                        "Flat or combined mode lost global order")
        }
        var filtered = allEnabled
        MenuCategory.files.actions.forEach { filtered[$0.preferenceKey] = false }
        try require(categorized.menuGroups(mode: .categorized, values: filtered).map(\.category) == [.tools], "Empty submenu remained visible")
        for mode in MenuDisplayMode.allCases {
            try require(categorized.menuGroups(mode: mode, values: enabled).isEmpty, "All-disabled menu is not empty")
        }
        try require(MenuLayout(serialized: categorized.serialized) == categorized, "Categorized sort did not persist")
        try require(!categorized.moveWithinCategory(.text, by: -1), "Item escaped its category")
        let beforeDrag = categorized.unifiedActions
        try require(categorized.moveCategory(.files, to: 0), "Category drop at start failed")
        try require(categorized.moveCategory(.files, to: 1), "Category drop at end failed")
        try require(!categorized.moveCategory(.files, to: 1), "Drop in place changed order")
        try require(!categorized.moveCategory(.files, to: 2) && !categorized.moveCategory(.files, to: -1), "Invalid drop changed order")
        try require(categorized.unifiedActions == beforeDrag, "Dragging a category changed its contents")
        try require(MenuLayout(serialized: categorized.serialized) == categorized, "Dragged category order did not persist")


        try require(AppDisplayLocation.resolved(nil) == .menuBar, "First launch should use the menu bar")
        try require(AppDisplayLocation.resolved("obsolete") == .menuBar, "Invalid display preference hid all entry points")
        for location in AppDisplayLocation.allCases {
            try require(location.showsMenuBar || location.showsDock, "Display mode lost every entry point")
            try require(AppDisplayLocation.resolved(location.rawValue) == location, "Display mode did not round-trip")
        }
        try require(!AppDisplayLocation.dock.showsMenuBar && AppDisplayLocation.dock.showsDock, "Dock-only mode is incorrect")
        try require(AppDisplayLocation.both.showsMenuBar && AppDisplayLocation.both.showsDock, "Both mode is incorrect")

        func release(_ version: String, _ url: String = "https://github.com/Goonwb/MenuWish/releases/tag/v1", prerelease: Bool = false, notes: String? = "## 更新\n- **新功能**\n- 修复菜单") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": version, "html_url": url, "draft": false, "prerelease": prerelease, "body": notes as Any? ?? NSNull()])
        }
        let current = "0.1.3"
        for version in ["v0.1.3", "0.1.3.0", "v0.1.2"] {
            guard case let .upToDate(details) = try UpdateChecker.result(data: release(version), statusCode: 200, currentVersion: current) else { fatalError("Incorrect latest version status") }
            try require(details.notes?.contains("新功能") == true, "Latest release notes were discarded")
        }
        for version in ["v0.1.4", "v0.1.10", "v1.0.0"] {
            guard case .available = try UpdateChecker.result(data: release(version), statusCode: 200, currentVersion: current) else { fatalError("Missed update") }
        }
        try require(UpdateChecker.result(data: Data(), statusCode: 404, currentVersion: current) == .noRelease, "404 handling")
        for status in [403, 429, 500] {
            do {
                _ = try UpdateChecker.result(data: Data(), statusCode: status, currentVersion: current)
                fatalError("HTTP error treated as success")
            } catch UpdateCheckError.httpStatus(let value) { try require(value == status, "Wrong HTTP status") }
        }
        for data in [Data("not json".utf8), try release("unknown"), try release("1..3"), try release("v0.2.0", "https://example.com/file"), try release("v0.2.0", prerelease: true)] {
            do {
                _ = try UpdateChecker.result(data: data, statusCode: 200, currentVersion: current)
                fatalError("Invalid release treated as success")
            } catch UpdateCheckError.invalidRelease {}
        }
        for notes in [nil, "", "  \n  "] as [String?] {
            guard case let .available(details) = try UpdateChecker.result(data: release("v1.0.0", notes: notes), statusCode: 200, currentVersion: current) else { fatalError("Missing notes blocked update") }
            try require(details.notes == "", "Empty notes were not normalized")
        }
        let page = URL(string: "https://github.com/Goonwb/MenuWish/releases/tag/v0.1.10")!
        try require(UpdateChecker.resultFromRedirect(url: page, statusCode: 200, currentVersion: current) == .available(ReleaseDetails(version: "v0.1.10", page: page, notes: nil)), "Rate-limit fallback failed")
        let feed = Data("""
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><link href="https://example.com/wrong"/><content>Wrong release</content></entry><entry><link href="\(page.absoluteString)"/><content type="html">&lt;p&gt;English notes&lt;/p&gt;&lt;hr&gt;&lt;h3&gt;更新&lt;/h3&gt;&lt;ul&gt;&lt;li&gt;&lt;strong&gt;分类&lt;/strong&gt; &amp;amp; 排序&lt;/li&gt;&lt;/ul&gt;&lt;script&gt;ignored()&lt;/script&gt;&lt;img src="https://example.com/image"/&gt;</content></entry></feed>
        """.utf8)
        let notes = UpdateChecker.notesFromFeed(data: feed, releasePage: page)
        try require(notes?.contains("## 更新") == true && notes?.contains("- **分类** & 排序") == true, "Feed notes formatting failed")
        try require(notes?.contains("English notes\n\n---\n\n## 更新") == true, "Feed dropped the bilingual horizontal rule")
        try require(notes?.contains("ignored()") == false && notes?.contains("Wrong release") == false, "Feed included unrelated content")
        try require(UpdateChecker.notesFromFeed(data: feed, releasePage: URL(string: "https://github.com/Goonwb/MenuWish/releases/tag/v99.0")!) == nil, "Feed selected another version")
        try require(UpdateChecker.notesFromFeed(data: Data("<feed/>".utf8), releasePage: page) == nil, "Empty feed was treated as a release")
        for url in [URL(string: "https://github.com/Goonwb/MenuWish/releases/latest")!, URL(string: "https://example.com/releases/tag/v99.0")!] {
            do {
                _ = try UpdateChecker.resultFromRedirect(url: url, statusCode: 200, currentVersion: current)
                fatalError("Invalid redirect treated as a release")
            } catch UpdateCheckError.invalidRelease {}
        }
        print("PASS: file creation, collisions and concurrent writes; category/action ordering, persistence and migration; release notes and update success/error cases")
    }
}
