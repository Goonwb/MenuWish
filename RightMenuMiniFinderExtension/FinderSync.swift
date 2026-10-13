import AppKit
import FinderSync

private enum RightMenuMiniPreferences {
    static let suiteName = "com.codex.RightMenuMini.shared"
    static let isMenuEnabled = "isMenuEnabled"
    static let isTerminalEnabled = "isTerminalEnabled"
    static let isCopyPathEnabled = "isCopyPathEnabled"
    static let isGroupedMenuEnabled = "isGroupedMenuEnabled"
    static let languageMode = "languageMode"

    static let systemValue = "system"
    static let chineseValue = "zh-Hans"
    static let englishValue = "en"

    static let defaultValues: [String: Bool] = Dictionary(uniqueKeysWithValues:
        NewFileKind.allCases.map { ($0.preferenceKey, true) }
    ).merging([
        isMenuEnabled: true,
        isTerminalEnabled: true,
        isCopyPathEnabled: true,
        isGroupedMenuEnabled: false
    ]) { _, value in value }
    static let stringDefaultValues: [String: String] = [
        languageMode: systemValue,
        MenuDisplayMode.preferenceKey: "",
        MenuLayout.preferenceKey: MenuLayout().serialized
    ]
    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        stringDefaultValues.forEach { values[$0.key] = $0.value }
        return values
    }

    static func store() -> UserDefaults {
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.register(defaults: registeredDefaults)
        return store
    }

    static func bool(_ key: String, in store: UserDefaults) -> Bool {
        if store.object(forKey: key) == nil {
            return defaultValues[key] ?? false
        }
        return store.bool(forKey: key)
    }

    static func string(_ key: String, in store: UserDefaults) -> String {
        let fallback = stringDefaultValues[key] ?? systemValue
        guard let value = store.string(forKey: key), !value.isEmpty else {
            return fallback
        }
        return value
    }

    static func resolvedString(_ key: String) -> String {
        var value = string(key, in: store())

        for url in preferenceFileURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                let dictionary = plist as? [String: Any],
                let mirroredValue = dictionary[key] as? String,
                !mirroredValue.isEmpty
            else {
                continue
            }
            value = mirroredValue
        }

        return value
    }

    static func resolvedValues() -> [String: Bool] {
        var values = defaultValues
        let store = store()

        defaultValues.keys.forEach { key in
            if store.object(forKey: key) != nil {
                values[key] = store.bool(forKey: key)
            }
        }

        for (key, value) in mirroredValues() {
            values[key] = value
        }

        return values
    }


    static func bool(_ key: String, in values: [String: Bool]) -> Bool {
        values[key] ?? defaultValues[key] ?? false
    }

    private static func mirroredValues() -> [String: Bool] {
        var values: [String: Bool] = [:]

        for url in preferenceFileURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                let dictionary = plist as? [String: Any]
            else {
                continue
            }

            defaultValues.keys.forEach { key in
                if let value = dictionary[key] as? Bool {
                    values[key] = value
                } else if let value = dictionary[key] as? NSNumber {
                    values[key] = value.boolValue
                }
            }
        }

        return values
    }

    private static func preferenceFileURLs() -> [URL] {
        let fileManager = FileManager.default
        let fileName = "\(suiteName).plist"
        var urls = [
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
        ]

        if let userHome = realUserHomeDirectory() {
            urls.append(
                userHome
                    .appendingPathComponent("Library/Preferences", isDirectory: true)
                    .appendingPathComponent(fileName)
            )
        }

        return urls
    }

    private static func realUserHomeDirectory() -> URL? {
        let userName = NSUserName()
        guard !userName.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: "/Users").appendingPathComponent(userName, isDirectory: true)
    }
}

private enum MenuText {
    static var languageMode: String {
        RightMenuMiniPreferences.resolvedString(RightMenuMiniPreferences.languageMode)
    }

    static var isEnglish: Bool {
        switch languageMode {
        case RightMenuMiniPreferences.englishValue:
            return true
        case RightMenuMiniPreferences.chineseValue:
            return false
        default:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            return !preferredLanguage.hasPrefix("zh")
        }
    }

    static func localized(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}


@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let containingAppBundleIdentifier = "com.codex.RightMenuMini"

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = monitoredDirectories()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let preferences = RightMenuMiniPreferences.resolvedValues()
        guard RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isMenuEnabled, in: preferences) else {
            return nil
        }

        let mode = MenuDisplayMode.resolved(
            RightMenuMiniPreferences.resolvedString(MenuDisplayMode.preferenceKey),
            legacyGrouped: RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isGroupedMenuEnabled, in: preferences))
        let layout = MenuLayout(serialized: RightMenuMiniPreferences.resolvedString(MenuLayout.preferenceKey))
        let groups = layout.menuGroups(mode: mode, values: preferences)
        guard !groups.isEmpty else { return nil }
        let menu = NSMenu(title: "MenuWish")
        for group in groups {
            let actionItems = group.actions.map(makeActionItem)
            if mode == .flat {
                actionItems.forEach { menu.addItem($0) }
            } else {
                let title = group.title(isEnglish: MenuText.isEnglish)
                let groupItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                groupItem.image = MenuWishAssets.finderMenuImage(named: "sparkles", size: NSSize(width: 18, height: 18),
                                                                appearance: finderMenuAppearance)
                let submenu = NSMenu(title: title)
                actionItems.forEach { submenu.addItem($0) }
                groupItem.submenu = submenu
                menu.addItem(groupItem)
            }
        }
        return menu
    }

    private func makeActionItem(_ action: MenuAction) -> NSMenuItem {
        let selector: Selector = action.fileKind != nil ? #selector(createFile(_:))
            : (action == .terminal ? #selector(openTerminal(_:)) : #selector(copyPath(_:)))
        let item = menuItem(title: action.title(isEnglish: MenuText.isEnglish), symbolName: action.symbolName, action: selector)
        if let kind = action.fileKind, let index = NewFileKind.allCases.firstIndex(of: kind) {
            // Finder copies menu items; tag survives, representedObject does not.
            item.tag = index
        }
        return item
    }

    private var finderMenuAppearance: NSAppearance {
        // Read the system style at menu creation, independently of MenuWish's
        // own appearance override. FinderSync callbacks need not be main-actor isolated.
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return NSAppearance(named: isDark ? .darkAqua : .aqua)!
    }

    private func menuItem(title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let icon = MenuWishAssets.finderMenuImage(named: symbolName, appearance: finderMenuAppearance) {
            item.image = icon
        } else {
            item.image = symbol(symbolName)
        }
        return item
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        guard NewFileKind.allCases.indices.contains(sender.tag),
              let folderURL = bestFolderURL() else { return }
        let kind = NewFileKind.allCases[sender.tag]
        performInContainingApp(action: kind.action, folderURL: folderURL)
    }

    @objc private func openTerminal(_ sender: Any?) {
        guard let folderURL = bestFolderURL() else {
            return
        }

        performInContainingApp(action: "terminal", folderURL: folderURL)
    }

    @objc private func copyPath(_ sender: Any?) {
        let paths = selectedURLsForAction().map(\.path)
        let fallbackPath = bestFolderURL()?.path
        let value = paths.isEmpty ? fallbackPath : paths.joined(separator: "\n")

        guard let value, !value.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func monitoredDirectories() -> Set<URL> {
        let fileManager = FileManager.default
        var urls: Set<URL> = [
            fileManager.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]

        let home = fileManager.homeDirectoryForCurrentUser
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].forEach { name in
            urls.insert(home.appendingPathComponent(name))
        }

        return urls
    }

    private func selectedURLsForAction() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func bestFolderURL() -> URL? {
        if let firstSelectedURL = selectedURLsForAction().first {
            return folderURL(for: firstSelectedURL)
        }

        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return folderURL(for: targetedURL)
        }

        return nil
    }

    private func folderURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue,
           (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true {
            return url
        }

        return url.deletingLastPathComponent()
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func performInContainingApp(action: String, folderURL: URL) {
        guard
            let appURL = containingApplicationURL(),
            let actionURL = actionURL(action: action, folderURL: folderURL, quitAfterHandling: shouldQuitAppAfterHandlingAction())
        else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false

        NSWorkspace.shared.open([actionURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("RightMenuMini action failed: \(action), \(error.localizedDescription)")
            }
        }
    }

    private func containingApplicationURL() -> URL? {
        let extensionURL = Bundle.main.bundleURL
        let contentsURL = extensionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = contentsURL.deletingLastPathComponent()

        return appURL.pathExtension == "app" ? appURL : nil
    }

    private func shouldQuitAppAfterHandlingAction() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: containingAppBundleIdentifier).isEmpty
    }

    private func actionURL(action: String, folderURL: URL, quitAfterHandling: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = "rightmenumini"
        components.host = action
        components.queryItems = [
            URLQueryItem(name: "path", value: folderURL.path),
            URLQueryItem(name: "quit", value: quitAfterHandling ? "1" : "0")
        ]

        return components.url
    }
}
