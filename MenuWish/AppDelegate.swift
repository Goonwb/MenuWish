import AppKit
import Carbon

private enum MenuWishPreferences {
    static let suiteName = "com.codex.RightMenuMini.shared"
    static let isMenuEnabled = "isMenuEnabled"
    static let isTerminalEnabled = "isTerminalEnabled"
    static let isCopyPathEnabled = "isCopyPathEnabled"
    static let isGroupedMenuEnabled = "isGroupedMenuEnabled"
    static let languageMode = "languageMode"
    static let appearanceMode = "appearanceMode"
    static let collapsedActionCategories = "collapsedActionCategories"

    static let systemValue = "system"
    static let chineseValue = "zh-Hans"
    static let englishValue = "en"
    static let lightValue = "light"
    static let darkValue = "dark"

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
        appearanceMode: systemValue,
        AppDisplayLocation.preferenceKey: AppDisplayLocation.menuBar.rawValue,
        MenuDisplayMode.preferenceKey: "",
        MenuLayout.preferenceKey: MenuLayout().serialized,
        collapsedActionCategories: ""
    ]
    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        stringDefaultValues.forEach { values[$0.key] = $0.value }
        return values
    }
    static let extensionContainerIdentifier = "com.codex.RightMenuMini.FinderExtension"

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

    static func values(in store: UserDefaults) -> [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        defaultValues.keys.forEach { key in
            if store.object(forKey: key) != nil {
                values[key] = store.bool(forKey: key)
            }
        }
        stringDefaultValues.keys.forEach { key in
            values[key] = string(key, in: store)
        }
        return values
    }

    static func mirrorValues(from store: UserDefaults) {
        let values = values(in: store)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) else {
            return
        }

        for url in preferenceFileURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("MenuWish preferences mirror failed: \(error.localizedDescription)")
            }
        }
    }

    private static func preferenceFileURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileName = "\(suiteName).plist"
        return [
            home
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName),
            home
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(extensionContainerIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
        ]
    }
}

private enum AppText {
    static var languageMode: String {
        MenuWishPreferences.string(MenuWishPreferences.languageMode, in: MenuWishPreferences.store())
    }

    static var isEnglish: Bool {
        switch languageMode {
        case MenuWishPreferences.englishValue:
            return true
        case MenuWishPreferences.chineseValue:
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


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum SidebarTab {
        case general
        case actions

        var identifier: String {
            switch self {
            case .general:
                return "general"
            case .actions:
                return "actions"
            }
        }

        static func from(identifier: String) -> SidebarTab? {
            switch identifier {
            case "general":
                return .general
            case "actions":
                return .actions
            default:
                return nil
            }
        }
    }

    private let extensionBundleIdentifier = "com.codex.RightMenuMini.FinderExtension"
    private let sidebarWidth: CGFloat = 220
    private let contentWidth: CGFloat = 540
    private let repositoryURL = URL(string: "https://github.com/Goonwb/MenuWish")!
    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/Goonwb/MenuWish/releases/latest")!
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenuAuthorizationItem: NSMenuItem?
    private var receivedActionURL = false
    private let preferences = MenuWishPreferences.store()
    private var currentTab: SidebarTab = .general
    private var reorderSheet: NSWindow?
    private var draftLayout = MenuLayout()
    private var previewCategory: MenuCategory = .files
    private var draftEnabledStates: [MenuAction: Bool] = [:]
    private var sheetScrollView: NSScrollView?
    private var sheetStackView: NSStackView?
    private var sheetResetButton: NSButton?
    private var collapsedActionCategories: Set<MenuCategory> {
        get {
            Set((preferences.string(forKey: MenuWishPreferences.collapsedActionCategories) ?? "")
                .split(separator: ",").compactMap { MenuCategory(rawValue: String($0)) })
        }
        set {
            preferences.set(newValue.map(\.rawValue).sorted().joined(separator: ","),
                forKey: MenuWishPreferences.collapsedActionCategories)
            preferences.synchronize()
            MenuWishPreferences.mirrorValues(from: preferences)
        }
    }
    private var contentContainer: NSView?
    private var sidebarButtons: [SidebarTab: NSButton] = [:]
    private var preferenceSwitches: [String: NSSwitch] = [:]
    private var preferenceCheckboxes: [String: NSButton] = [:]
    private var preferenceRows: [String: NSView] = [:]
    private var statusDetailLabels: [String: NSTextField] = [:]
    private var sectionTitleLabels: [String: NSTextField] = [:]
    private var rowTitleLabels: [String: NSTextField] = [:]
    private var rowDetailLabels: [String: NSTextField] = [:]
    private var popupControls: [String: NSPopUpButton] = [:]
    private var localizedButtons: [String: NSButton] = [:]
    private var preferenceIconViews: [String: NSImageView] = [:]
    private var preferenceIconTiles: [String: NSView] = [:]
    private var cardViews: [NSView] = []
    private var dividerLines: [NSView] = []
    private var iconTileViews: [NSView] = []
    private var iconTileColors: [ObjectIdentifier: NSColor] = [:]
    private var finderExtensionEnabled = false
    private var authorizationIconTile: NSView?
    private var authorizationIconView: NSImageView?
    private var authorizationTitleLabel: NSTextField?
    private var authorizationDetailLabel: NSTextField?
    private var authorizationButton: NSButton?
    private var updateStatusLabel: NSTextField?
    private var updateCheckButton: NSButton?
    private var isCheckingForUpdates = false
    private var releaseAlert: NSAlert?
    private var updateDownloadWindow: UpdateDownloadWindow?
    private var appliedDisplayLocation = AppDisplayLocation.menuBar
    private var versionBadge: NSView?
    private var versionBadgeLabel: NSTextField?
    private var layoutSegmentControl: NSSegmentedControl?
    private var reorderActionsButton: NSButton?
    private var sidebarBrandLabel: NSTextField?
    private var previewStageView: NSView?
    private var previewMenuContainer: NSView?
    private var previewModeLabel: NSTextField?
    private var previewModePill: NSView?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.register(defaults: MenuWishPreferences.registeredDefaults)
        MenuWishPreferences.mirrorValues(from: preferences)
        registerFinderExtension()
        applyAppearancePreference()
        if let bundledIcon = bundledApplicationIconImage() {
            NSApp.applicationIconImage = bundledIcon
        }
        applyDisplayLocation()


        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.receivedActionURL else {
                return
            }
            self.showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyAuthorizationStatus(finderExtensionEnabled)
    }

    private func showWindow() {
        if window == nil {
            buildWindow()
        }

        window?.center()
        refreshPreferenceControls()
        refreshAuthorizationStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        applyAppearancePreference()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 821, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MenuWish"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        let visualView = NSVisualEffectView()
        visualView.material = .windowBackground
        visualView.blendingMode = .behindWindow
        visualView.state = .active
        visualView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = visualView

        preferenceSwitches.removeAll()
        preferenceRows.removeAll()
        statusDetailLabels.removeAll()
        sectionTitleLabels.removeAll()
        rowTitleLabels.removeAll()
        rowDetailLabels.removeAll()
        popupControls.removeAll()
        localizedButtons.removeAll()
        preferenceIconViews.removeAll()
        preferenceIconTiles.removeAll()
        cardViews.removeAll()
        dividerLines.removeAll()
        iconTileViews.removeAll()
        iconTileColors.removeAll()
        sidebarButtons.removeAll()
        updateStatusLabel = nil
        updateCheckButton = nil
        versionBadge = nil
        versionBadgeLabel = nil

        let sidebar = sidebarView()
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = separatorLayerColor.cgColor

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        visualView.addSubview(sidebar)
        visualView.addSubview(separator)
        visualView.addSubview(content)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: visualView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: visualView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: visualView.topAnchor),
            separator.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            content.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: visualView.trailingAnchor),
            content.topAnchor.constraint(equalTo: visualView.topAnchor),
            content.bottomAnchor.constraint(equalTo: visualView.bottomAnchor)
        ])

        self.window = window
        self.contentContainer = content
        selectSidebarTab(.general)
        refreshAuthorizationStatus()
    }

    private func configureStatusItem() {
        guard displayLocation.showsMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            statusMenuAuthorizationItem = nil
            return
        }
        let statusItem = self.statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuWishAssets.image(named: "sparkles", size: NSSize(width: 18, height: 18))
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: AppText.localized("打开 MenuWish", "Open MenuWish"),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        ))
        let authorizationItem = NSMenuItem(
            title: AppText.localized("初次授权", "First-Time Permission"),
            action: #selector(openExtensionSettings),
            keyEquivalent: ""
        )
        menu.addItem(authorizationItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: AppText.localized("退出 MenuWish", "Quit MenuWish"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        self.statusMenuAuthorizationItem = authorizationItem
        self.statusItem = statusItem
        refreshAuthorizationStatus()
    }

    private var displayLocation: AppDisplayLocation {
        AppDisplayLocation.resolved(preferences.string(forKey: AppDisplayLocation.preferenceKey))
    }

    private var displayLocationItems: [(value: String, title: String)] {
        AppDisplayLocation.allCases.map { ($0.rawValue, $0.title(isEnglish: AppText.isEnglish)) }
    }

    private func applyDisplayLocation() {
        let location = displayLocation
        let policy: NSApplication.ActivationPolicy = location.showsDock ? .regular : .accessory
        // Create the menu-bar entry before hiding Dock; show Dock before removing
        // the menu-bar entry. There is always a reachable settings entry point.
        if location.showsMenuBar { configureStatusItem() }
        if NSApp.activationPolicy() != policy && !NSApp.setActivationPolicy(policy) {
            preferences.set(appliedDisplayLocation.rawValue, forKey: AppDisplayLocation.preferenceKey)
            preferences.synchronize()
            MenuWishPreferences.mirrorValues(from: preferences)
            configureStatusItem()
            updatePopup(AppDisplayLocation.preferenceKey, items: displayLocationItems)
            showNativeAlert(title: AppText.localized("无法更改应用入口", "Unable to Change App Access"),
                message: AppText.localized("已保留原来的应用入口设置，请稍后再试。", "Your previous app access setting has been kept. Please try again later."), style: .warning)
            return
        }
        appliedDisplayLocation = location
        configureApplicationMenu()
        configureStatusItem()
        if window?.isVisible == true {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MenuWish")
        func add(_ title: String, action: Selector, key: String, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            appMenu.addItem(item)
            return item
        }
        _ = add(AppText.localized("MenuWish 设置…", "MenuWish Settings…"), action: #selector(showMainWindow), key: ",", target: self)
        appMenu.addItem(.separator())
        _ = add(AppText.localized("隐藏 MenuWish", "Hide MenuWish"), action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp)
        let hideOthers = add(AppText.localized("隐藏其他", "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", target: NSApp)
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        _ = add(AppText.localized("全部显示", "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), key: "", target: NSApp)
        appMenu.addItem(.separator())
        _ = add(AppText.localized("退出 MenuWish", "Quit MenuWish"), action: #selector(quitApp), key: "q", target: self)
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: AppText.localized("编辑", "Edit"))
        edit.addItem(withTitle: AppText.localized("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: AppText.localized("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windows = NSMenu(title: AppText.localized("窗口", "Window"))
        windows.addItem(withTitle: AppText.localized("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: AppText.localized("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windows
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windows
    }

    @objc private func showMainWindow() {
        showWindow()
    }

    @objc private func sidebarTabSelected(_ sender: NSButton) {
        guard
            let identifier = sender.identifier?.rawValue,
            let tab = SidebarTab.from(identifier: identifier)
        else {
            return
        }

        selectSidebarTab(tab)
    }

    private func selectSidebarTab(_ tab: SidebarTab) {
        currentTab = tab

        refreshSidebarSelectionAppearance()

        guard let contentContainer else {
            return
        }

        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        preferenceSwitches.removeAll()
        preferenceCheckboxes.removeAll()
        preferenceRows.removeAll()
        statusDetailLabels.removeAll()
        sectionTitleLabels.removeAll()
        rowTitleLabels.removeAll()
        rowDetailLabels.removeAll()
        popupControls.removeAll()
        localizedButtons.removeAll()
        preferenceIconViews.removeAll()
        preferenceIconTiles.removeAll()
        cardViews.removeAll()
        dividerLines.removeAll()
        iconTileViews.removeAll()
        iconTileColors.removeAll()
        authorizationIconTile = nil
        authorizationIconView = nil
        authorizationTitleLabel = nil
        authorizationDetailLabel = nil
        authorizationButton = nil
        updateStatusLabel = nil
        updateCheckButton = nil
        versionBadge = nil
        versionBadgeLabel = nil
        layoutSegmentControl = nil
        reorderActionsButton = nil
        previewStageView = nil
        previewMenuContainer = nil
        previewModeLabel = nil
        previewModePill = nil

        let content: NSView
        switch tab {
        case .general:
            content = generalContentView()
        case .actions:
            content = actionsContentView()
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scrollView.documentView = document
        contentContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 30),
            content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            content.widthAnchor.constraint(equalToConstant: contentWidth),
            document.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 30)
        ])

        applyAuthorizationStatus(finderExtensionEnabled)
        contentContainer.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func refreshSidebarSelectionAppearance() {
        for (buttonTab, button) in sidebarButtons {
            let isSelected = buttonTab == currentTab
            button.layer?.backgroundColor = isSelected
                ? sidebarSelectionColor.cgColor
                : NSColor.clear.cgColor

            for subview in button.subviews {
                if let imageView = subview as? NSImageView {
                    let foreground: NSColor = isSelected ? sidebarSelectedForegroundColor : .secondaryLabelColor
                    if buttonTab == .actions {
                        imageView.effectiveAppearance.performAsCurrentDrawingAppearance {
                            imageView.image = MenuWishAssets.image(named: "sparkles",
                                size: NSSize(width: 20, height: 20), tint: foreground)
                        }
                    }
                    imageView.contentTintColor = foreground
                    imageView.setAccessibilityLabel(sidebarTitle(for: buttonTab))
                } else if let label = subview as? NSTextField {
                    label.textColor = isSelected ? sidebarSelectedForegroundColor : .secondaryLabelColor
                    label.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
                }
            }
        }
    }

    private func bundledApplicationIconImage() -> NSImage? {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon2026Corners", withExtension: "icns"),
            let image = NSImage(contentsOf: iconURL),
            image.isValid
        else {
            return nil
        }
        return image
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = bundledApplicationIconImage() ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        let titleLabel = NSTextField(labelWithString: "MenuWish")
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.sidebarBrandLabel = titleLabel

        let versionLabel = NSTextField(labelWithString: "v\(currentVersionString)")
        versionLabel.font = .systemFont(ofSize: 11.5)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let brandStack = NSStackView(views: [titleLabel, versionLabel])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 4
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        let generalButton = sidebarNavigationButton(symbol: "gearshape", title: sidebarTitle(for: .general), tab: .general)
        let actionsButton = sidebarNavigationButton(symbol: "sparkles", title: sidebarTitle(for: .actions), tab: .actions)

        let navStack = NSStackView(views: [generalButton, actionsButton])
        navStack.orientation = .vertical
        navStack.alignment = .width
        navStack.spacing = 8
        navStack.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(icon)
        sidebar.addSubview(brandStack)
        sidebar.addSubview(navStack)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 60),
            icon.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),

            brandStack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            brandStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            brandStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),

            navStack.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 28),
            navStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            navStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            generalButton.widthAnchor.constraint(equalTo: navStack.widthAnchor),
            actionsButton.widthAnchor.constraint(equalTo: navStack.widthAnchor)
        ])

        return sidebar
    }

    private func sidebarTitle(for tab: SidebarTab) -> String {
        switch tab {
        case .general:
            return AppText.localized("通用", "General")
        case .actions:
            return AppText.localized("菜单功能", "Menu Actions")
        }
    }

    private func sidebarNavigationButton(symbol: String, title: String, tab: SidebarTab) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(sidebarTabSelected(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(tab.identifier)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous

        let icon = NSImageView()
        icon.image = MenuWishAssets.image(named: symbol, size: NSSize(width: 20, height: 20))
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.setAccessibilityLabel(title)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(icon)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 36),

            icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12)
        ])

        sidebarButtons[tab] = button
        return button
    }

    private func generalContentView() -> NSView {
        let statusSection = sectionTitle(AppText.localized("服务与状态", "Service & Status"), key: "section.status")

        let authRow = authorizationRow()
        let menuRow = statusToggleRow()
        let statusPanel = settingsPanel(rows: [authRow, menuRow])

        let preferencesSection = sectionTitle(AppText.localized("偏好", "Preferences"), key: "section.preferences")
        let languageRow = settingsPopUpRow(
            symbol: "character.bubble",
            title: AppText.localized("语言", "Language"),
            detail: AppText.localized("选择 App 和 Finder 菜单显示语言", "Choose the app and Finder menu language"),
            key: MenuWishPreferences.languageMode,
            items: [
                (MenuWishPreferences.systemValue, AppText.localized("跟随系统", "System")),
                (MenuWishPreferences.chineseValue, "简体中文"),
                (MenuWishPreferences.englishValue, "English")
            ],
            action: #selector(languageSelectionChanged(_:))
        )
        let appearanceRow = settingsPopUpRow(
            symbol: "circle.lefthalf.filled",
            title: AppText.localized("外观", "Appearance"),
            detail: AppText.localized("选择浅色、深色或跟随系统", "Choose light, dark, or system appearance"),
            key: MenuWishPreferences.appearanceMode,
            items: [
                (MenuWishPreferences.systemValue, AppText.localized("跟随系统", "System")),
                (MenuWishPreferences.lightValue, AppText.localized("浅色", "Light")),
                (MenuWishPreferences.darkValue, AppText.localized("深色", "Dark"))
            ],
            action: #selector(appearanceSelectionChanged(_:))
        )
        let locationRow = settingsPopUpRow(
            symbol: "dock.rectangle",
            title: AppText.localized("应用入口", "App Access"),
            detail: AppText.localized("选择在菜单栏或 Dock 中显示 MenuWish", "Show MenuWish in the menu bar or Dock"),
            key: AppDisplayLocation.preferenceKey,
            items: displayLocationItems,
            controlWidth: 150,
            action: #selector(displayLocationSelectionChanged(_:))
        )
        let preferencesPanel = settingsPanel(rows: [
            locationRow,
            appearanceRow,
            languageRow
        ])

        let versionRow = settingsVersionRow(
            symbol: "info.circle",
            title: AppText.localized("当前版本", "Current Version"),
            version: currentVersionString,
            detail: AppText.localized("可检查最新版本与发布日志", "Check latest version and release notes"),
            buttonTitle: AppText.localized("检查", "Check"),
            action: #selector(checkForUpdates)
        )
        updateStatusLabel = versionRow.detailLabel
        updateCheckButton = versionRow.button
        refreshUpdateControls()

        let githubRow = settingsButtonRow(
            symbol: "github",
            title: "GitHub",
            detail: "github.com/Goonwb/MenuWish",
            buttonTitle: AppText.localized("前往", "Visit"),
            action: #selector(openGitHubProfile)
        )

        let projectSection = sectionTitle(AppText.localized("关于", "About"), key: "section.about")
        let projectPanel = settingsPanel(rows: [
            versionRow.row,
            githubRow.row
        ])

        let stack = NSStackView(views: [
            statusSection,
            statusPanel,
            preferencesSection,
            preferencesPanel,
            projectSection,
            projectPanel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(10, after: statusSection)
        stack.setCustomSpacing(24, after: statusPanel)
        stack.setCustomSpacing(10, after: preferencesSection)
        stack.setCustomSpacing(24, after: preferencesPanel)
        stack.setCustomSpacing(10, after: projectSection)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        return stack
    }

    private func actionsContentView() -> NSView {
        let layoutCard = menuLayoutAndPreviewCard()
        let stack = NSStackView(views: [layoutCard])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(22, after: layoutCard)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(menuActionsCard())
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return stack
    }

    private func menuActionsCard() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: AppText.localized("菜单功能", "Menu Actions"))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let reorderButton = NSButton(
            title: AppText.localized("调整顺序…", "Reorder Actions…"),
            target: self,
            action: #selector(openReorderSheet(_:))
        )
        reorderButton.bezelStyle = .rounded
        reorderButton.isBordered = false
        reorderButton.contentTintColor = .controlAccentColor
        reorderButton.font = .systemFont(ofSize: 12, weight: .medium)
        reorderButton.controlSize = .regular
        reorderButton.translatesAutoresizingMaskIntoConstraints = false
        reorderButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        reorderButton.imagePosition = .imageLeading
        self.reorderActionsButton = reorderButton

        header.addSubview(title)
        header.addSubview(reorderButton)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 52),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: reorderButton.leadingAnchor, constant: -12),
            reorderButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            reorderButton.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        let list = NSStackView(views: [header])
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        let layout = actionLayout
        for (categoryIndex, category) in layout.categories.enumerated() {
            if categoryIndex > 0 {
                if let previousRow = list.arrangedSubviews.last {
                    list.setCustomSpacing(20, after: previousRow)
                }
            }
            list.addArrangedSubview(categoryHeader(category.title(isEnglish: AppText.isEnglish)))
            for action in layout.orderedActions(in: category) {
                list.addArrangedSubview(preferenceRow(
                    symbol: action.symbolName,
                    title: action.title(isEnglish: AppText.isEnglish),
                    detail: action.detail(isEnglish: AppText.isEnglish),
                    key: action.preferenceKey,
                    isCompact: true
                ))
            }
        }

        let card = plainCard(height: nil, cornerRadius: 16, fixedWidth: contentWidth)
        card.layer?.borderWidth = 0
        card.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            list.topAnchor.constraint(equalTo: card.topAnchor),
            list.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private var menuDisplayMode: MenuDisplayMode {
        MenuDisplayMode.resolved(MenuWishPreferences.string(MenuDisplayMode.preferenceKey, in: preferences),
            legacyGrouped: preferenceValue(for: MenuWishPreferences.isGroupedMenuEnabled))
    }

    private var actionLayout: MenuLayout {
        MenuLayout(serialized: MenuWishPreferences.string(MenuLayout.preferenceKey, in: preferences))
    }

    // MARK: - Reorder Modal Sheet

    @objc private func openReorderSheet(_ sender: Any?) {
        guard let window = self.window else { return }
        draftLayout = actionLayout
        var initialEnabled: [MenuAction: Bool] = [:]
        for action in MenuAction.allCases {
            initialEnabled[action] = preferenceValue(for: action.preferenceKey)
        }
        draftEnabledStates = initialEnabled

        let sheetWidth: CGFloat = 480
        let sheetHeight: CGFloat = 500

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.appearance = window.appearance

        let visualView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        visualView.material = .sheet
        visualView.blendingMode = .behindWindow
        visualView.state = .active
        visualView.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView = visualView

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle.fill", accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 30, weight: .medium)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: AppText.localized("调整菜单功能顺序", "Reorder Menu Actions"))
        titleLabel.font = .systemFont(ofSize: 15.5, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: menuDisplayMode == .categorized
            ? AppText.localized("拖动类目标题排序，使用箭头调整功能顺序", "Drag category headers; use arrows to reorder actions")
            : AppText.localized("上下移动功能项以调整在访达（Finder）右键菜单中的显示顺序", "Adjust order of items in the Finder context menu"))
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 3
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [iconView, headerTextStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 14
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        visualView.addSubview(headerStack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = usesDarkAppearance
            ? NSColor(white: 0.12, alpha: 0.9)
            : NSColor(white: 0.98, alpha: 0.95)
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.12).cgColor
            : NSColor.black.withAlphaComponent(0.1).cgColor
        scroll.automaticallyAdjustsContentInsets = false

        let docView = CategoryReorderDocumentView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.onMove = { [weak self] category, index in
            self?.moveSheetCategory(category, to: index)
        }

        let listStack = NSStackView()
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 0

        docView.addSubview(listStack)
        scroll.documentView = docView
        visualView.addSubview(scroll)

        self.sheetScrollView = scroll
        self.sheetStackView = listStack

        let resetBtn = NSButton(
            title: AppText.localized("恢复默认", "Reset to Default"),
            target: self,
            action: #selector(sheetResetOrderClicked(_:))
        )
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .regular
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        self.sheetResetButton = resetBtn

        let cancelBtn = NSButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(sheetCancelClicked(_:))
        )
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .regular
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let doneBtn = NSButton(
            title: AppText.localized("完成", "Done"),
            target: self,
            action: #selector(sheetDoneClicked(_:))
        )
        doneBtn.bezelStyle = .rounded
        doneBtn.controlSize = .regular
        doneBtn.keyEquivalent = "\r"
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.contentTintColor = .controlAccentColor
        sheet.initialFirstResponder = doneBtn

        let buttonGroup = NSStackView(views: [cancelBtn, doneBtn])
        buttonGroup.orientation = .horizontal
        buttonGroup.spacing = 10
        buttonGroup.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(resetBtn)
        footer.addSubview(buttonGroup)
        visualView.addSubview(footer)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: visualView.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: visualView.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: visualView.trailingAnchor, constant: -24),

            scroll.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: visualView.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: visualView.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),

            listStack.topAnchor.constraint(equalTo: docView.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            docView.bottomAnchor.constraint(equalTo: listStack.bottomAnchor),
            docView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            footer.leadingAnchor.constraint(equalTo: visualView.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: visualView.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: visualView.bottomAnchor, constant: -18),
            footer.heightAnchor.constraint(equalToConstant: 32),

            resetBtn.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            resetBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            buttonGroup.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            buttonGroup.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])

        renderSheetList()

        self.reorderSheet = sheet
        window.beginSheet(sheet) { [weak self] _ in
            (self?.sheetScrollView?.documentView as? CategoryReorderDocumentView)?.cancelDrag()
            self?.reorderSheet = nil
            self?.sheetScrollView = nil
            self?.sheetStackView = nil
            self?.sheetResetButton = nil
            self?.draftEnabledStates.removeAll()
        }
    }

    private func renderSheetList() {
        guard let stack = sheetStackView, let scroll = sheetScrollView else { return }
        let origin = scroll.contentView.bounds.origin
        stack.subviews.forEach { $0.removeFromSuperview() }

        let defaultLayout = MenuLayout()
        let isLayoutDefault = draftLayout == defaultLayout
        let isEnabledDefault = MenuAction.allCases.allSatisfy { action in
            draftEnabledStates[action] == true
        }
        sheetResetButton?.isEnabled = !(isLayoutDefault && isEnabledDefault)

        let groups: [[MenuAction]] = menuDisplayMode == .categorized
            ? draftLayout.categories.map { draftLayout.orderedActions(in: $0) }
            : [draftLayout.unifiedActions]
        let document = scroll.documentView as? CategoryReorderDocumentView
        document?.cancelDrag()
        document?.groups = []
        for actions in groups {
            let content: NSStackView
            if menuDisplayMode == .categorized, let category = actions.first?.category {
                let group = NSStackView()
                group.orientation = .vertical
                group.alignment = .width
                group.spacing = 0
                group.translatesAutoresizingMaskIntoConstraints = false
                let header = sheetCategoryRow(category)
                header.groupView = group
                group.addArrangedSubview(header)
                stack.addArrangedSubview(group)
                group.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                document?.groups.append((category, group))
                content = group
            } else {
                content = stack
            }
            for (index, action) in actions.enumerated() {
                content.addArrangedSubview(sheetActionRow(action: action, index: index, count: actions.count))
                if index < actions.count - 1 { content.addArrangedSubview(sheetDivider()) }
            }
        }

        stack.layoutSubtreeIfNeeded()
        var bounds = scroll.contentView.bounds
        bounds.origin = origin
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func sheetCategoryRow(_ category: MenuCategory) -> CategoryDragHeaderView {
        let row = CategoryDragHeaderView(category: category)
        row.translatesAutoresizingMaskIntoConstraints = false
        let title = category.title(isEnglish: AppText.isEnglish)
        row.setAccessibilityLabel(title)
        row.toolTip = AppText.localized("拖动整个类目排序；聚焦后也可按 Option + ↑ / ↓", "Drag to reorder; when focused, press Option + ↑ / ↓")
        row.onKeyboardMove = { [weak self] offset in
            guard let self, let index = self.draftLayout.categories.firstIndex(of: category) else { return false }
            return self.moveSheetCategory(category, to: index + offset)
        }
        row.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: AppText.localized("上移类目", "Move category up"), handler: { [weak row] in row?.onKeyboardMove?(-1) ?? false }),
            NSAccessibilityCustomAction(name: AppText.localized("下移类目", "Move category down"), handler: { [weak row] in row?.onKeyboardMove?(1) ?? false })
        ])
        let grip = NSImageView()
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        grip.contentTintColor = .tertiaryLabelColor
        grip.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(grip)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 36),
            grip.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            grip.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 12),
            grip.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -16)
        ])
        return row
    }

    @discardableResult private func moveSheetCategory(_ category: MenuCategory, to index: Int) -> Bool {
        guard draftLayout.moveCategory(category, to: index) else { return false }
        let focusStyle = (reorderSheet?.firstResponder as? CategoryDragHeaderView)?.focusRingType ?? .exterior
        renderSheetList()
        if let document = sheetScrollView?.documentView as? CategoryReorderDocumentView,
           let group = document.groups.first(where: { $0.category == category })?.view,
           let header = group.subviews.first as? CategoryDragHeaderView {
            document.scrollToVisible(document.convert(header.bounds, from: header))
            reorderSheet?.makeFirstResponder(header)
            header.focusRingType = focusStyle
        }
        return true
    }

    private func sheetActionRow(action: MenuAction, index: Int, count: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let isActionEnabled = draftEnabledStates[action] ?? true

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(sheetActionCheckboxToggled(_:)))
        checkbox.state = isActionEnabled ? .on : .off
        checkbox.identifier = NSUserInterfaceItemIdentifier("chk:\(action.rawValue)")
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.setAccessibilityLabel(action.title(isEnglish: AppText.isEnglish))

        let color = iconColor(forSymbol: action.symbolName)
        let tile = NSView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        tile.alphaValue = isActionEnabled ? 1.0 : 0.45

        let icon = NSImageView()
        if let iconImage = MenuWishAssets.image(named: action.symbolName, size: NSSize(width: 18, height: 18), tint: color) {
            icon.image = iconImage
        } else {
            icon.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
            icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        }
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: action.title(isEnglish: AppText.isEnglish))
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = isActionEnabled ? .labelColor : .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let upImage = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: AppText.localized("上移", "Move Up"))?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold)) ?? NSImage()
        let downImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: AppText.localized("下移", "Move Down"))?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold)) ?? NSImage()

        let seg = NSSegmentedControl(
            images: [upImage, downImage],
            trackingMode: .momentary,
            target: self,
            action: #selector(sheetActionSegmentClicked(_:))
        )
        seg.controlSize = .regular
        seg.segmentStyle = .separated
        seg.identifier = NSUserInterfaceItemIdentifier("act:\(action.rawValue)")
        seg.setEnabled(index > 0, forSegment: 0)
        seg.setEnabled(index < count - 1, forSegment: 1)
        seg.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(checkbox)
        row.addSubview(tile)
        row.addSubview(titleLabel)
        row.addSubview(seg)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 48),

            checkbox.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            checkbox.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            tile.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 10),
            tile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 32),
            tile.heightAnchor.constraint(equalToConstant: 32),

            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: seg.leadingAnchor, constant: -14),

            seg.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            seg.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return row
    }

    private func sheetDivider() -> NSView {
        let div = NSView()
        div.translatesAutoresizingMaskIntoConstraints = false
        div.wantsLayer = true
        div.layer?.backgroundColor = usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.06).cgColor
            : NSColor.black.withAlphaComponent(0.06).cgColor
        div.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return div
    }

    @objc private func sheetActionCheckboxToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("chk:"),
              let action = MenuAction(rawValue: String(id.dropFirst(4))) else { return }
        draftEnabledStates[action] = (sender.state == .on)
        renderSheetList()
    }

    @objc private func sheetActionSegmentClicked(_ sender: NSSegmentedControl) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("act:"),
              let action = MenuAction(rawValue: String(id.dropFirst(4))) else { return }
        let offset = sender.selectedSegment == 0 ? -1 : 1
        let moved = menuDisplayMode == .categorized
            ? draftLayout.moveWithinCategory(action, by: offset)
            : draftLayout.moveUnified(action, by: offset)
        if moved { renderSheetList() }
    }

    @objc private func sheetResetOrderClicked(_ sender: NSButton) {
        draftLayout = MenuLayout()
        for action in MenuAction.allCases {
            draftEnabledStates[action] = true
        }
        renderSheetList()
    }

    @objc private func sheetCancelClicked(_ sender: NSButton) {
        guard let sheet = reorderSheet, let window = self.window else { return }
        window.endSheet(sheet, returnCode: .cancel)
    }

    @objc private func sheetDoneClicked(_ sender: NSButton) {
        guard let sheet = reorderSheet, let window = self.window else { return }
        saveActionLayout(draftLayout)
        for (action, enabled) in draftEnabledStates {
            preferences.set(enabled, forKey: action.preferenceKey)
        }
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
        reloadActionsPreservingScroll()
        window.endSheet(sheet, returnCode: .OK)
    }

    private func settingsSegmentRow(
        symbol: String,
        title: String,
        detail: String,
        segments: [String],
        selected: Int,
        action: Selector
    ) -> (row: NSView, control: NSSegmentedControl) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let seg = NSSegmentedControl(labels: segments, trackingMode: .selectOne, target: self, action: action)
        seg.controlSize = .regular
        seg.selectedSegment = selected
        seg.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(seg)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: seg.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: seg.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            seg.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            seg.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return (row, seg)
    }

    private func settingsActionRow(
        symbol: String,
        title: String,
        detail: String,
        buttonTitle: String,
        action: Selector
    ) -> (row: NSView, button: NSButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        return (row, button)
    }

    private func saveActionLayout(_ layout: MenuLayout) {
        preferences.set(layout.serialized, forKey: MenuLayout.preferenceKey)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        reloadActionsPreservingScroll()
    }

    private func reloadActionsPreservingScroll() {
        let oldScroll = contentContainer?.subviews.first as? NSScrollView
        let origin = oldScroll?.contentView.bounds.origin ?? .zero
        reloadCurrentTab()
        guard let scroll = contentContainer?.subviews.first as? NSScrollView else { return }
        var bounds = scroll.contentView.bounds
        bounds.origin = origin
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func sectionTitle(_ title: String, key: String? = nil) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14.5, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        if let key {
            sectionTitleLabels[key] = label
        }

        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            container.heightAnchor.constraint(equalToConstant: 26),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func categoryHeader(_ title: String, key: String? = nil) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        if let key {
            sectionTitleLabels[key] = label
        }

        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            container.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func settingsButtonRow(
        symbol: String,
        title: String,
        detail: String,
        buttonTitle: String,
        action: Selector
    ) -> (row: NSView, detailLabel: NSTextField, button: NSButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        if symbol == "github" {
            if let image = NSImage(named: "github") {
                image.isTemplate = true
                icon.image = image
            } else {
                icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: title)
            }
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        localizedButtons["github"] = button

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        return (row, detailLabel, button)
    }

    private func settingsVersionRow(
        symbol: String,
        title: String,
        version: String,
        detail: String,
        buttonTitle: String,
        action: Selector
    ) -> (row: NSView, detailLabel: NSTextField, button: NSButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Version badge
        let badge = NSView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = versionBadgeBackgroundColor.cgColor
        badge.layer?.borderWidth = 0.5
        badge.layer?.borderColor = versionBadgeBorderColor.cgColor

        let badgeLabel = NSTextField(labelWithString: version)
        badgeLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        badgeLabel.textColor = .controlAccentColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)
        versionBadge = badge
        versionBadgeLabel = badgeLabel

        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            badgeLabel.topAnchor.constraint(equalTo: badge.topAnchor, constant: 1.5),
            badgeLabel.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -1.5)
        ])

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        rowTitleLabels["version"] = titleLabel
        rowDetailLabels["version"] = detailLabel
        localizedButtons["version.check"] = button

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(badge)
        row.addSubview(detailLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),

            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            badge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        return (row, detailLabel, button)
    }

    private func settingsLinkRow(
        symbol: String,
        title: String,
        detail: String,
        action: Selector
    ) -> NSView {
        let row = ClickableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.target = self
        row.action = action

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        if symbol == "github" {
            if let image = NSImage(named: "github") {
                image.isTemplate = true
                icon.image = image
            } else {
                icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: title)
            }
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "")
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .bold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),

            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -22),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12)
        ])

        return row
    }

    private func settingsPopUpRow(
        symbol: String,
        title: String,
        detail: String,
        key: String,
        items: [(value: String, title: String)],
        controlWidth: CGFloat = 118,
        action: Selector
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier(key)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.controlSize = .regular
        popup.target = self
        popup.action = action
        rowTitleLabels[key] = titleLabel
        rowDetailLabels[key] = detailLabel
        popupControls[key] = popup

        items.forEach { item in
            popup.addItem(withTitle: item.title)
            popup.lastItem?.representedObject = item.value
        }

        let selectedValue = MenuWishPreferences.string(key, in: preferences)
        if let selectedItem = popup.itemArray.first(where: { $0.representedObject as? String == selectedValue }) {
            popup.select(selectedItem)
        }

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: controlWidth)
        ])

        return row
    }

    private func authorizationRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous

        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let button = primaryButton(
            title: AppText.localized("授权", "Authorize"),
            symbol: "checkmark.shield",
            action: #selector(openExtensionSettings)
        )
        button.isHidden = finderExtensionEnabled
        localizedButtons["authorization"] = button

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        authorizationIconView = icon
        authorizationIconTile = iconTile
        authorizationTitleLabel = titleLabel
        authorizationDetailLabel = detailLabel
        authorizationButton = button

        return row
    }

    private func statusToggleRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let key = MenuWishPreferences.isMenuEnabled
        let color = NSColor.systemBlue

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "power", accessibilityDescription: AppText.localized("右键菜单", "Context Menu"))
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: AppText.localized("右键菜单服务", "Context Menu Service"))
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        toggle.target = self
        toggle.action = #selector(preferenceSwitchChanged(_:))
        toggle.controlSize = .regular
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.state = preferenceValue(for: key) ? .on : .off
        toggle.isEnabled = finderExtensionEnabled

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        preferenceSwitches[key] = toggle
        preferenceRows[key] = row
        statusDetailLabels[key] = detailLabel
        rowTitleLabels[key] = titleLabel
        rowDetailLabels[key] = detailLabel
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        return row
    }

    private func settingsPanel(rows: [NSView], rowHeight: CGFloat = 64, insetLeading: CGFloat = 74) -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.distribution = .fill
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        rows.enumerated().forEach { index, row in
            if index > 0 {
                list.addArrangedSubview(divider(insetLeading: insetLeading))
            }
            list.addArrangedSubview(row)
        }

        let panelHeight = CGFloat(CGFloat(rows.count) * rowHeight + CGFloat(max(rows.count - 1, 0)))
        let panel = plainCard(height: panelHeight, cornerRadius: 16, fixedWidth: contentWidth)
        panel.addSubview(list)

        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            list.topAnchor.constraint(equalTo: panel.topAnchor),
            list.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        return panel
    }

    private var usesDarkAppearance: Bool {
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var cardBackgroundColor: NSColor {
        usesDarkAppearance ? NSColor(white: 0.13, alpha: 1.0) : .white
    }

    private var cardBorderColor: NSColor {
        usesDarkAppearance ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.06)
    }

    private var cardShadowColor: NSColor {
        .black
    }

    private var iconTileBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.16 : 0.08)
    }

    private var sidebarSelectionColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.72 : 0.76)
    }

    private var sidebarSelectedForegroundColor: NSColor {
        .alternateSelectedControlTextColor
    }

    private var versionBadgeBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.18 : 0.09)
    }

    private var versionBadgeBorderColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.32 : 0.18)
    }

    private var separatorLayerColor: NSColor {
        usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.separatorColor.withAlphaComponent(0.12)
    }

    private func tintBackgroundColor(for color: NSColor) -> NSColor {
        color.withAlphaComponent(usesDarkAppearance ? 0.18 : 0.08)
    }

    private func registerIconTile(_ tile: NSView, color: NSColor) {
        iconTileViews.append(tile)
        iconTileColors[ObjectIdentifier(tile)] = color
    }

    private func iconColor(forSymbol symbol: String) -> NSColor {
        if let color = MenuWishAssets.actionColor(for: symbol) { return color }
        switch symbol {
        case "power":
            return .systemBlue
        case "rectangle.stack", "rectangle.on.rectangle":
            return .systemPurple
        case "doc.badge.plus", "doc.text", "square.and.pencil", "plus.square", "file-text":
            return .systemOrange
        case "terminal", "terminal.fill", "square-terminal":
            return .systemTeal
        case "tablecells", "doc.on.doc", "link":
            return .systemGreen
        case "sparkles":
            return .controlAccentColor
        case "markdown", "doc.richtext", "character.bubble":
            return .systemBlue
        case "circle.lefthalf.filled":
            return .systemOrange
        case "info.circle":
            return .controlAccentColor
        case "github":
            return .labelColor
        default:
            return .controlAccentColor
        }
    }

    private func plainCard(height: CGFloat?, cornerRadius: CGFloat, fixedWidth: CGFloat?) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        cardViews.append(view)
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = cardBackgroundColor.cgColor
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = cardBorderColor.cgColor

        view.layer?.shadowColor = cardShadowColor.cgColor
        view.layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        view.layer?.shadowRadius = 8.0
        view.layer?.shadowOpacity = usesDarkAppearance ? 0.12 : 0.04
        view.layer?.masksToBounds = false

        var constraints: [NSLayoutConstraint] = []
        if let height {
            constraints.append(view.heightAnchor.constraint(equalToConstant: height))
        }
        if let fixedWidth {
            constraints.append(view.widthAnchor.constraint(equalToConstant: fixedWidth))
        }
        NSLayoutConstraint.activate(constraints)

        return view
    }

    private func preferenceRow(
        symbol: String,
        title: String,
        detail: String,
        key: String,
        isCompact: Bool = false
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let rowHeight: CGFloat = isCompact ? 48 : 64
        let tileCornerRadius: CGFloat = isCompact ? 8 : 11
        let tileSize: CGFloat = isCompact ? 30 : 38
        let iconSize: CGFloat = isCompact ? 16 : 22
        let iconPointSize: CGFloat = isCompact ? 16 : 20
        let textLeading: CGFloat = isCompact ? 12 : 16
        let titleFontSize: CGFloat = isCompact ? 13 : 13.5
        let detailFontSize: CGFloat = isCompact ? 11 : 11.5
        let textSpacing: CGFloat = isCompact ? 2 : 4
        let sidePadding: CGFloat = isCompact ? 20 : 18
        let toggleTrailing: CGFloat = -20

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = tileCornerRadius
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        registerIconTile(iconTile, color: color)

        let icon = NSImageView()
        if let iconImage = MenuWishAssets.image(named: symbol, size: NSSize(width: iconSize, height: iconSize), tint: color) {
            icon.image = iconImage
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            icon.symbolConfiguration = .init(pointSize: iconPointSize, weight: .semibold)
        }
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: detailFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = textSpacing
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        toggle.target = self
        toggle.action = #selector(preferenceSwitchChanged(_:))
        toggle.controlSize = .regular
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.toolTip = title
        toggle.state = preferenceValue(for: key) ? .on : .off
        toggle.isEnabled = finderExtensionEnabled && preferenceValue(for: MenuWishPreferences.isMenuEnabled)
        preferenceSwitches[key] = toggle
        preferenceRows[key] = row
        statusDetailLabels[key] = detailLabel
        rowTitleLabels[key] = titleLabel
        rowDetailLabels[key] = detailLabel
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        let constraints = [
            row.heightAnchor.constraint(equalToConstant: rowHeight),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: tileSize),
            iconTile.heightAnchor.constraint(equalToConstant: tileSize),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: textLeading),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: toggleTrailing),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: sidePadding)
        ]

        NSLayoutConstraint.activate(constraints)
        return row
    }

    // MARK: - Live Finder Menu Preview & Layout Card

    private func menuLayoutAndPreviewCard() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        cardViews.append(card)
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = cardBackgroundColor.cgColor
        card.layer?.borderWidth = 0
        card.layer?.borderColor = cardBorderColor.cgColor
        card.layer?.shadowColor = cardShadowColor.cgColor
        card.layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        card.layer?.shadowRadius = 8.0
        card.layer?.shadowOpacity = usesDarkAppearance ? 0.12 : 0.04
        card.layer?.masksToBounds = false

        let previewTitle = NSTextField(labelWithString: AppText.localized("菜单预览", "Menu Preview"))
        previewTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        previewTitle.textColor = .labelColor
        previewTitle.translatesAutoresizingMaskIntoConstraints = false

        let seg = NSSegmentedControl(
            labels: MenuDisplayMode.allCases.map { $0.title(isEnglish: AppText.isEnglish) },
            trackingMode: .selectOne,
            target: self,
            action: #selector(layoutSegmentChanged(_:))
        )
        seg.controlSize = .regular
        seg.segmentStyle = .rounded
        seg.setAccessibilityLabel(AppText.localized("显示样式", "Display Style"))
        seg.selectedSegment = menuDisplayMode.segmentIndex
        seg.translatesAutoresizingMaskIntoConstraints = false
        self.layoutSegmentControl = seg

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(previewTitle)
        toolbar.addSubview(seg)

        let menuArea = NSView()
        menuArea.translatesAutoresizingMaskIntoConstraints = false
        menuArea.wantsLayer = true
        menuArea.layer?.cornerRadius = 10
        menuArea.layer?.cornerCurve = .continuous
        menuArea.layer?.backgroundColor = usesDarkAppearance
            ? NSColor(white: 0.12, alpha: 0.7).cgColor
            : NSColor(white: 0.96, alpha: 1.0).cgColor
        menuArea.layer?.borderWidth = 0
        menuArea.layer?.borderColor = usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.08).cgColor
            : NSColor.black.withAlphaComponent(0.06).cgColor
        card.addSubview(toolbar)
        card.addSubview(menuArea)
        self.previewMenuContainer = menuArea

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: contentWidth),

            toolbar.topAnchor.constraint(equalTo: card.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            toolbar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            previewTitle.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            previewTitle.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            previewTitle.trailingAnchor.constraint(lessThanOrEqualTo: seg.leadingAnchor, constant: -16),
            seg.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            seg.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            menuArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            menuArea.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            menuArea.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            menuArea.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        self.previewStageView = card
        renderMenuPreview()
        return card
    }

    private func simulatedMenuBox() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.shadowColor = NSColor.black.cgColor
        wrapper.layer?.shadowOffset = CGSize(width: 0, height: -3)
        wrapper.layer?.shadowRadius = 10
        wrapper.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.18
        wrapper.layer?.masksToBounds = false

        let box = NSVisualEffectView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.material = .popover
        box.blendingMode = .withinWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = usesDarkAppearance
            ? NSColor(white: 1.0, alpha: 0.16).cgColor
            : NSColor(white: 0.0, alpha: 0.12).cgColor
        box.layer?.masksToBounds = true
        wrapper.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: wrapper.topAnchor),
            box.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        return wrapper
    }

    private func previewMenuIcon(named name: String) -> NSImage? {
        MenuWishAssets.finderMenuImage(named: name,
            appearance: window?.effectiveAppearance ?? NSApp.effectiveAppearance)
    }

    private func simulatedMenuItem(
        icon: NSImage?,
        title: String,
        hasChevron: Bool = false,
        isDimmed: Bool = false,
        isHighlighted: Bool = false
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        if isHighlighted {
            row.layer?.cornerRadius = 5
            row.layer?.cornerCurve = .continuous
            row.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }

        let imgView = NSImageView()
        imgView.image = icon
        imgView.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        // Finder's baked monochrome images retain their color on selection.
        // Only the contextual system items use template tinting here.
        imgView.contentTintColor = icon?.isTemplate == true
            ? (isDimmed ? .tertiaryLabelColor : .labelColor) : nil
        imgView.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(imgView)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12.5, weight: isHighlighted ? .semibold : .regular)
        label.textColor = isHighlighted ? .white : (isDimmed ? .tertiaryLabelColor : .labelColor)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 22),
            imgView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 7),
            imgView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            imgView.widthAnchor.constraint(equalToConstant: 16),
            imgView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        if hasChevron {
            let chevron = NSImageView()
            chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            chevron.symbolConfiguration = .init(pointSize: 9, weight: .bold)
            chevron.contentTintColor = isHighlighted ? .white : .tertiaryLabelColor
            chevron.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7),
                chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4)
            ])
        } else {
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8).isActive = true
        }

        return row
    }

    private func simulatedMenuDivider() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.12).cgColor
            : NSColor.black.withAlphaComponent(0.10).cgColor
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 7),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
        return container
    }

    private func categorizedPreviewBox(rows: [NSView], width: CGFloat) -> NSView {
        let box = simulatedMenuBox()
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(list)
        rows.forEach { $0.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        let height = rows.reduce(CGFloat(10 + max(0, rows.count - 1) * 2)) { $0 + $1.fittingSize.height }
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width),
            box.heightAnchor.constraint(equalToConstant: height),
            list.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
            list.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5),
            list.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 5),
            list.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5)
        ])
        return box
    }

    private func renderCategorizedPreview(in container: NSView, layout: MenuLayout, isServiceEnabled: Bool) {
        let values = Dictionary(uniqueKeysWithValues: MenuAction.allCases.map { ($0.preferenceKey, preferenceValue(for: $0.preferenceKey)) })
        let groups = layout.menuGroups(mode: .categorized, values: values)
        let selected = groups.first { $0.category == previewCategory } ?? groups.first
        if let category = selected?.category { previewCategory = category }

        var parentRows: [NSView] = [simulatedMenuItem(
            icon: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil),
            title: AppText.localized("显示简介", "Get Info"), isDimmed: true), simulatedMenuDivider()]
        for group in groups {
            let title = group.title(isEnglish: AppText.isEnglish)
            let row = simulatedMenuItem(icon: previewMenuIcon(named: "sparkles"),
                title: title, hasChevron: true, isHighlighted: group.category == previewCategory)
            let button = NSButton(title: "", target: self, action: #selector(previewCategorySelected(_:)))
            button.isBordered = false
            button.identifier = NSUserInterfaceItemIdentifier(group.category!.rawValue)
            button.setAccessibilityLabel(title)
            button.toolTip = AppText.localized("点击查看此类目的菜单预览", "Click to preview this category")
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(row)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 22),
                row.topAnchor.constraint(equalTo: button.topAnchor),
                row.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: button.trailingAnchor)
            ])
            parentRows.append(button)
        }
        if groups.isEmpty {
            parentRows.append(simulatedMenuItem(icon: nil,
                title: AppText.localized("未启用任何菜单项", "No items enabled"), isDimmed: true))
        }
        parentRows.append(simulatedMenuDivider())
        parentRows.append(simulatedMenuItem(icon: NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil),
            title: AppText.localized("快速操作", "Quick Actions"), hasChevron: true, isDimmed: true))
        let parent = categorizedPreviewBox(rows: parentRows, width: 220)
        var boxes: [NSView] = [parent]
        if let selected {
            let rows = selected.actions.map { action in
                simulatedMenuItem(icon: previewMenuIcon(named: action.symbolName),
                    title: action.title(isEnglish: AppText.isEnglish))
            }
            boxes.append(categorizedPreviewBox(rows: rows, width: 235))
        }
        let menus = NSStackView(views: boxes)
        menus.orientation = .horizontal
        menus.alignment = .top
        menus.spacing = 4
        menus.translatesAutoresizingMaskIntoConstraints = false
        menus.alphaValue = isServiceEnabled ? 1 : 0.42
        container.addSubview(menus)
        NSLayoutConstraint.activate([
            menus.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            menus.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            menus.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
    }

    @objc private func previewCategorySelected(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let category = MenuCategory(rawValue: value) else { return }
        previewCategory = category
        renderMenuPreview()
    }

    private func renderMenuPreview() {
        guard let container = previewMenuContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        container.layer?.backgroundColor = usesDarkAppearance
            ? NSColor(white: 0.12, alpha: 0.7).cgColor
            : NSColor(white: 0.94, alpha: 0.75).cgColor
        container.layer?.borderColor = usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.08).cgColor
            : NSColor.black.withAlphaComponent(0.06).cgColor
        previewModePill?.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.18 : 0.09).cgColor

        let isGrouped = menuDisplayMode != .flat
        let isServiceEnabled = finderExtensionEnabled && preferenceValue(for: MenuWishPreferences.isMenuEnabled)

        previewModeLabel?.stringValue = menuDisplayMode.title(isEnglish: AppText.isEnglish)

        let layout = actionLayout
        let enabledActions = layout.unifiedActions.filter { preferenceValue(for: $0.preferenceKey) }

        if menuDisplayMode == .categorized {
            renderCategorizedPreview(in: container, layout: layout, isServiceEnabled: isServiceEnabled)
        } else if !isGrouped {
            let menuBox = simulatedMenuBox()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .width
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false

            let infoItem = simulatedMenuItem(
                icon: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil),
                title: AppText.localized("显示简介", "Get Info"),
                isDimmed: true
            )
            stack.addArrangedSubview(infoItem)
            stack.addArrangedSubview(simulatedMenuDivider())

            if enabledActions.isEmpty {
                let emptyRow = NSView()
                emptyRow.translatesAutoresizingMaskIntoConstraints = false
                let emptyLabel = NSTextField(labelWithString: AppText.localized("未启用任何菜单项", "No items enabled"))
                emptyLabel.font = .systemFont(ofSize: 11.5)
                emptyLabel.textColor = .tertiaryLabelColor
                emptyLabel.alignment = .center
                emptyLabel.translatesAutoresizingMaskIntoConstraints = false
                emptyRow.addSubview(emptyLabel)
                NSLayoutConstraint.activate([
                    emptyRow.heightAnchor.constraint(equalToConstant: 24),
                    emptyLabel.centerXAnchor.constraint(equalTo: emptyRow.centerXAnchor),
                    emptyLabel.centerYAnchor.constraint(equalTo: emptyRow.centerYAnchor)
                ])
                stack.addArrangedSubview(emptyRow)
            } else {
                for action in enabledActions {
                    let img = previewMenuIcon(named: action.symbolName)
                    let row = simulatedMenuItem(
                        icon: img,
                        title: action.title(isEnglish: AppText.isEnglish)
                    )
                    stack.addArrangedSubview(row)
                }
            }

            stack.addArrangedSubview(simulatedMenuDivider())
            let quickActionsItem = simulatedMenuItem(
                icon: NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil),
                title: AppText.localized("快速操作", "Quick Actions"),
                hasChevron: true,
                isDimmed: true
            )
            stack.addArrangedSubview(quickActionsItem)

            menuBox.addSubview(stack)
            container.addSubview(menuBox)

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: menuBox.topAnchor, constant: 5),
                stack.bottomAnchor.constraint(equalTo: menuBox.bottomAnchor, constant: -5),
                stack.leadingAnchor.constraint(equalTo: menuBox.leadingAnchor, constant: 5),
                stack.trailingAnchor.constraint(equalTo: menuBox.trailingAnchor, constant: -5),

                menuBox.widthAnchor.constraint(equalToConstant: 220),
                menuBox.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                menuBox.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
                menuBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
            ])

            menuBox.alphaValue = isServiceEnabled ? 1.0 : 0.42

        } else {
            let parentBox = simulatedMenuBox()
            let parentStack = NSStackView()
            parentStack.orientation = .vertical
            parentStack.alignment = .width
            parentStack.spacing = 2
            parentStack.translatesAutoresizingMaskIntoConstraints = false

            let infoItem = simulatedMenuItem(
                icon: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil),
                title: AppText.localized("显示简介", "Get Info"),
                isDimmed: true
            )
            parentStack.addArrangedSubview(infoItem)
            parentStack.addArrangedSubview(simulatedMenuDivider())

            let groupItem = simulatedMenuItem(
                icon: previewMenuIcon(named: "sparkles"),
                title: "MenuWish",
                hasChevron: true,
                isHighlighted: true
            )
            parentStack.addArrangedSubview(groupItem)
            parentStack.addArrangedSubview(simulatedMenuDivider())

            let quickActionsItem = simulatedMenuItem(
                icon: NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil),
                title: AppText.localized("快速操作", "Quick Actions"),
                hasChevron: true,
                isDimmed: true
            )
            parentStack.addArrangedSubview(quickActionsItem)

            parentBox.addSubview(parentStack)

            let subBox = simulatedMenuBox()
            let subStack = NSStackView()
            subStack.orientation = .vertical
            subStack.alignment = .width
            subStack.spacing = 2
            subStack.translatesAutoresizingMaskIntoConstraints = false

            if enabledActions.isEmpty {
                let emptyRow = NSView()
                emptyRow.translatesAutoresizingMaskIntoConstraints = false
                let emptyLabel = NSTextField(labelWithString: AppText.localized("未启用任何菜单项", "No items enabled"))
                emptyLabel.font = .systemFont(ofSize: 11.5)
                emptyLabel.textColor = .tertiaryLabelColor
                emptyLabel.alignment = .center
                emptyLabel.translatesAutoresizingMaskIntoConstraints = false
                emptyRow.addSubview(emptyLabel)
                NSLayoutConstraint.activate([
                    emptyRow.heightAnchor.constraint(equalToConstant: 24),
                    emptyLabel.centerXAnchor.constraint(equalTo: emptyRow.centerXAnchor),
                    emptyLabel.centerYAnchor.constraint(equalTo: emptyRow.centerYAnchor)
                ])
                subStack.addArrangedSubview(emptyRow)
            } else {
                for action in enabledActions {
                    let img = previewMenuIcon(named: action.symbolName)
                    let row = simulatedMenuItem(
                        icon: img,
                        title: action.title(isEnglish: AppText.isEnglish)
                    )
                    subStack.addArrangedSubview(row)
                }
            }

            subBox.addSubview(subStack)

            let groupHStack = NSStackView(views: [parentBox, subBox])
            groupHStack.orientation = .horizontal
            groupHStack.alignment = .top
            groupHStack.spacing = 4
            groupHStack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(groupHStack)

            NSLayoutConstraint.activate([
                parentStack.topAnchor.constraint(equalTo: parentBox.topAnchor, constant: 5),
                parentStack.bottomAnchor.constraint(equalTo: parentBox.bottomAnchor, constant: -5),
                parentStack.leadingAnchor.constraint(equalTo: parentBox.leadingAnchor, constant: 5),
                parentStack.trailingAnchor.constraint(equalTo: parentBox.trailingAnchor, constant: -5),
                parentBox.widthAnchor.constraint(equalToConstant: 140),

                subStack.topAnchor.constraint(equalTo: subBox.topAnchor, constant: 5),
                subStack.bottomAnchor.constraint(equalTo: subBox.bottomAnchor, constant: -5),
                subStack.leadingAnchor.constraint(equalTo: subBox.leadingAnchor, constant: 5),
                subStack.trailingAnchor.constraint(equalTo: subBox.trailingAnchor, constant: -5),
                subBox.widthAnchor.constraint(equalToConstant: 190),

                groupHStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                groupHStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
                groupHStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
            ])

            parentBox.alphaValue = isServiceEnabled ? 1.0 : 0.42
            subBox.alphaValue = isServiceEnabled ? 1.0 : 0.42
        }

        if !isServiceEnabled {
            let statusPill = NSView()
            statusPill.translatesAutoresizingMaskIntoConstraints = false
            statusPill.wantsLayer = true
            statusPill.layer?.cornerRadius = 6
            statusPill.layer?.backgroundColor = usesDarkAppearance
                ? NSColor(white: 0.15, alpha: 0.95).cgColor
                : NSColor(white: 0.96, alpha: 0.95).cgColor
            statusPill.layer?.borderWidth = 0.5
            statusPill.layer?.borderColor = usesDarkAppearance
                ? NSColor.white.withAlphaComponent(0.15).cgColor
                : NSColor.black.withAlphaComponent(0.12).cgColor

            let statusLabel = NSTextField(labelWithString: AppText.localized("右键菜单服务已暂停", "Context Menu Service Paused"))
            statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.translatesAutoresizingMaskIntoConstraints = false
            statusPill.addSubview(statusLabel)

            container.addSubview(statusPill)
            NSLayoutConstraint.activate([
                statusLabel.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 8),
                statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -8),
                statusLabel.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 3),
                statusLabel.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -3),

                statusPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                statusPill.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }
    }

    private func divider(insetLeading: CGFloat = 74) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = separatorLayerColor.cgColor
        dividerLines.append(line)
        view.addSubview(line)

        view.wantsLayer = true
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insetLeading),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            line.topAnchor.constraint(equalTo: view.topAnchor),
            line.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }

    private func primaryButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    private func secondaryButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    @objc private func languageSelectionChanged(_ sender: NSPopUpButton) {
        updateStringPreference(from: sender)
        configureApplicationMenu()
        configureStatusItem()
        refreshLocalizedInterface()
    }

    @objc private func displayLocationSelectionChanged(_ sender: NSPopUpButton) {
        updateStringPreference(from: sender)
        applyDisplayLocation()
    }

    @objc private func appearanceSelectionChanged(_ sender: NSPopUpButton) {
        updateStringPreference(from: sender)
        applyAppearancePreference()
        refreshVisibleAppearance()
    }

    private func updateStringPreference(from sender: NSPopUpButton) {
        guard
            let key = sender.identifier?.rawValue,
            let value = sender.selectedItem?.representedObject as? String
        else {
            return
        }

        preferences.set(value, forKey: key)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
    }

    private func applyAppearancePreference() {
        let appearance: NSAppearance?
        switch MenuWishPreferences.string(MenuWishPreferences.appearanceMode, in: preferences) {
        case MenuWishPreferences.lightValue:
            appearance = NSAppearance(named: .aqua)
        case MenuWishPreferences.darkValue:
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }

        NSApp.appearance = appearance
        window?.appearance = appearance
    }

    private func refreshLocalizedInterface() {
        window?.title = "MenuWish"
        sidebarBrandLabel?.stringValue = "MenuWish"

        for (tab, button) in sidebarButtons {
            for subview in button.subviews {
                if let label = subview as? NSTextField {
                    label.stringValue = sidebarTitle(for: tab)
                }
            }
        }

        refreshVisibleLocalizedContent()
    }

    private func reloadCurrentTab() {
        selectSidebarTab(currentTab)
    }

    private func refreshVisibleLocalizedContent() {
        if currentTab == .actions { reloadCurrentTab(); return }
        sectionTitleLabels["section.status"]?.stringValue = AppText.localized("服务与状态", "Service & Status")
        sectionTitleLabels["section.preferences"]?.stringValue = AppText.localized("偏好", "Preferences")
        sectionTitleLabels["section.about"]?.stringValue = AppText.localized("关于", "About")
        sectionTitleLabels["section.menuItems"]?.stringValue = AppText.localized("在访达右键菜单中显示以下项目", "Show Items in Finder Context Menu")

        localizedButtons["authorization"]?.title = AppText.localized("授权", "Authorize")
        refreshUpdateControls()
        localizedButtons["github"]?.title = AppText.localized("前往", "Visit")

        rowTitleLabels[MenuWishPreferences.isMenuEnabled]?.stringValue = AppText.localized("右键菜单服务", "Context Menu Service")
        rowTitleLabels[MenuWishPreferences.languageMode]?.stringValue = AppText.localized("语言", "Language")
        rowDetailLabels[MenuWishPreferences.languageMode]?.stringValue = AppText.localized("选择 App 和 Finder 菜单显示语言", "Choose the app and Finder menu language")
        rowTitleLabels[MenuWishPreferences.appearanceMode]?.stringValue = AppText.localized("外观", "Appearance")
        rowDetailLabels[MenuWishPreferences.appearanceMode]?.stringValue = AppText.localized("选择浅色、深色或跟随系统", "Choose light, dark, or system appearance")
        rowTitleLabels["version"]?.stringValue = AppText.localized("当前版本", "Current Version")
        rowTitleLabels[AppDisplayLocation.preferenceKey]?.stringValue = AppText.localized("应用入口", "App Access")
        rowDetailLabels[AppDisplayLocation.preferenceKey]?.stringValue = AppText.localized("选择在菜单栏或 Dock 中显示 MenuWish", "Show MenuWish in the menu bar or Dock")
        updatePopup(AppDisplayLocation.preferenceKey, items: displayLocationItems)

        updatePopup(
            MenuWishPreferences.languageMode,
            items: [
                (MenuWishPreferences.systemValue, AppText.localized("跟随系统", "System")),
                (MenuWishPreferences.chineseValue, "简体中文"),
                (MenuWishPreferences.englishValue, "English")
            ]
        )
        updatePopup(
            MenuWishPreferences.appearanceMode,
            items: [
                (MenuWishPreferences.systemValue, AppText.localized("跟随系统", "System")),
                (MenuWishPreferences.lightValue, AppText.localized("浅色", "Light")),
                (MenuWishPreferences.darkValue, AppText.localized("深色", "Dark"))
            ]
        )

        for kind in NewFileKind.allCases {
            rowTitleLabels[kind.preferenceKey]?.stringValue = kind.title(isEnglish: AppText.isEnglish)
            rowDetailLabels[kind.preferenceKey]?.stringValue = kind.detail(isEnglish: AppText.isEnglish)
        }
        rowTitleLabels[MenuWishPreferences.isTerminalEnabled]?.stringValue = AppText.localized("进入终端", "Open Terminal")
        rowDetailLabels[MenuWishPreferences.isTerminalEnabled]?.stringValue = AppText.localized("从当前位置打开 Terminal", "Open Terminal at this location")
        rowTitleLabels[MenuWishPreferences.isCopyPathEnabled]?.stringValue = AppText.localized("拷贝路径", "Copy Path")
        rowDetailLabels[MenuWishPreferences.isCopyPathEnabled]?.stringValue = AppText.localized("复制所选项目或当前文件夹路径", "Copy selected paths or current folder")

        applyAuthorizationStatus(finderExtensionEnabled)
    }

    private func updatePopup(_ key: String, items: [(value: String, title: String)]) {
        guard let popup = popupControls[key] else {
            return
        }

        let selectedValue = MenuWishPreferences.string(key, in: preferences)
        popup.removeAllItems()
        items.forEach { item in
            popup.addItem(withTitle: item.title)
            popup.lastItem?.representedObject = item.value
        }

        if let selectedItem = popup.itemArray.first(where: { $0.representedObject as? String == selectedValue }) {
            popup.select(selectedItem)
        }
    }

    private func refreshVisibleAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0

            cardViews.forEach { view in
                view.layer?.backgroundColor = cardBackgroundColor.cgColor
                view.layer?.borderColor = cardBorderColor.cgColor
                view.layer?.shadowOpacity = usesDarkAppearance ? 0.12 : 0.04
            }
            dividerLines.forEach { line in
                line.layer?.backgroundColor = separatorLayerColor.cgColor
            }
            iconTileViews.forEach { tile in
                if let color = iconTileColors[ObjectIdentifier(tile)] {
                    tile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
                }
            }

            refreshSidebarSelectionAppearance()
            versionBadge?.layer?.backgroundColor = versionBadgeBackgroundColor.cgColor
            versionBadge?.layer?.borderColor = versionBadgeBorderColor.cgColor
            versionBadgeLabel?.textColor = .controlAccentColor
            applyAuthorizationStatus(finderExtensionEnabled)
            renderMenuPreview()
        }
    }

    @objc private func preferenceSwitchChanged(_ sender: NSSwitch) {
        guard finderExtensionEnabled else {
            sender.state = .off
            return
        }

        guard let key = sender.identifier?.rawValue else {
            return
        }

        preferences.set(sender.state == .on, forKey: key)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    @objc private func layoutSegmentChanged(_ sender: NSSegmentedControl) {
        guard finderExtensionEnabled && preferenceValue(for: MenuWishPreferences.isMenuEnabled) else {
            sender.selectedSegment = menuDisplayMode.segmentIndex
            return
        }
        guard MenuDisplayMode.allCases.indices.contains(sender.selectedSegment) else { return }
        let mode = MenuDisplayMode.allCases[sender.selectedSegment]
        preferences.set(mode.rawValue, forKey: MenuDisplayMode.preferenceKey)
        preferences.set(mode != .flat, forKey: MenuWishPreferences.isGroupedMenuEnabled)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    @objc private func actionRowClicked(_ sender: Any) {
        guard finderExtensionEnabled && preferenceValue(for: MenuWishPreferences.isMenuEnabled) else {
            return
        }
        let key: String?
        if let row = sender as? NSView, let id = row.identifier?.rawValue {
            key = id
        } else if let btn = sender as? NSButton, let id = btn.identifier?.rawValue {
            key = id
        } else {
            key = nil
        }
        guard let actionKey = key else { return }

        let newEnabled = !preferenceValue(for: actionKey)
        preferences.set(newEnabled, forKey: actionKey)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    @objc private func preferenceCheckboxChanged(_ sender: NSButton) {
        guard finderExtensionEnabled && preferenceValue(for: MenuWishPreferences.isMenuEnabled) else {
            if let key = sender.identifier?.rawValue {
                sender.state = preferenceValue(for: key) ? .on : .off
            }
            return
        }
        guard let key = sender.identifier?.rawValue else { return }

        let isEnabled = sender.state == .on
        preferences.set(isEnabled, forKey: key)
        preferences.synchronize()
        MenuWishPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    private func updateActionRowAppearance(key: String, isEnabled: Bool, isServiceEnabled: Bool) {
        guard let row = preferenceRows[key] else { return }
        if let clickable = row as? ClickableRowView {
            clickable.isEnabled = isServiceEnabled
        }
        if !isServiceEnabled {
            row.alphaValue = 0.46
            return
        }
        row.alphaValue = 1.0
        let tile = preferenceIconTiles[key]
        let titleLabel = rowTitleLabels[key]
        let detailLabel = rowDetailLabels[key]

        tile?.alphaValue = isEnabled ? 1.0 : 0.45
        titleLabel?.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        detailLabel?.textColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    private func refreshPreferenceControls() {
        let menuEnabled = preferenceValue(for: MenuWishPreferences.isMenuEnabled)
        let isGrouped = menuDisplayMode != .flat

        layoutSegmentControl?.selectedSegment = menuDisplayMode.segmentIndex
        layoutSegmentControl?.isEnabled = finderExtensionEnabled && menuEnabled
        reorderActionsButton?.isEnabled = finderExtensionEnabled && menuEnabled

        guard !preferenceSwitches.isEmpty || !preferenceCheckboxes.isEmpty else {
            return
        }

        guard finderExtensionEnabled else {
            reorderActionsButton?.isEnabled = false
            preferenceSwitches.values.forEach { toggle in
                toggle.state = .off
                toggle.isEnabled = false
            }
            preferenceCheckboxes.values.forEach { checkbox in
                checkbox.state = .off
                checkbox.isEnabled = false
            }
            preferenceRows.values.forEach { row in
                row.alphaValue = 0.46
                if let clickable = row as? ClickableRowView {
                    clickable.isEnabled = false
                }
            }
            statusDetailLabels[MenuWishPreferences.isMenuEnabled]?.stringValue = AppText.localized("请先启用上方的 Finder 扩展授权", "Please enable Finder Extension permission above first")
            statusDetailLabels[MenuWishPreferences.isGroupedMenuEnabled]?.stringValue = AppText.localized("授权后可设置", "Available after permission")
            updateMenuPowerAppearance(isEnabled: false)
            return
        }

        for (key, toggle) in preferenceSwitches {
            toggle.state = preferenceValue(for: key) ? .on : .off
            toggle.isEnabled = true
        }

        for (key, checkbox) in preferenceCheckboxes {
            let isItemEnabled = preferenceValue(for: key)
            checkbox.state = isItemEnabled ? .on : .off
            checkbox.isEnabled = menuEnabled
            updateActionRowAppearance(key: key, isEnabled: isItemEnabled, isServiceEnabled: menuEnabled)
        }

        statusDetailLabels[MenuWishPreferences.isMenuEnabled]?.stringValue = menuEnabled
            ? AppText.localized("已激活并显示在右键菜单中", "Activated and shown in context menu")
            : AppText.localized("已暂停（菜单项目已隐藏）", "Paused (menu items hidden)")
        updateMenuPowerAppearance(isEnabled: menuEnabled)

        statusDetailLabels[MenuWishPreferences.isGroupedMenuEnabled]?.stringValue = isGrouped
            ? AppText.localized("折叠为子菜单", "Grouped in submenu")
            : AppText.localized("直接显示已启用功能", "Show actions directly")

        dependentPreferenceKeys.forEach { key in
            preferenceSwitches[key]?.isEnabled = menuEnabled
            if preferenceCheckboxes[key] == nil {
                preferenceRows[key]?.alphaValue = menuEnabled ? 1 : 0.48
            }
        }

        preferenceRows[MenuWishPreferences.isMenuEnabled]?.alphaValue = 1
        renderMenuPreview()
    }

    private func updateMenuPowerAppearance(isEnabled: Bool) {
        let color: NSColor = isEnabled ? .systemGreen : .systemRed
        preferenceIconViews[MenuWishPreferences.isMenuEnabled]?.contentTintColor = color

        let tile = preferenceIconTiles[MenuWishPreferences.isMenuEnabled]
        tile?.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        tile?.layer?.shadowColor = color.cgColor
        tile?.layer?.shadowOffset = .zero
        tile?.layer?.shadowRadius = 5.0
        tile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.16
        tile?.layer?.masksToBounds = false
    }

    private var dependentPreferenceKeys: [String] {
        NewFileKind.allCases.map(\.preferenceKey) + [
            MenuWishPreferences.isTerminalEnabled,
            MenuWishPreferences.isCopyPathEnabled,
            MenuWishPreferences.isGroupedMenuEnabled
        ]
    }

    private func preferenceValue(for key: String) -> Bool {
        MenuWishPreferences.bool(key, in: preferences)
    }

    @objc private func openExtensionSettings() {
        registerFinderExtension()
        if refreshAuthorizationStatus() {
            return
        }
        revealExtensionItemsSettings()
        scheduleAuthorizationRefresh()
    }

    private func registerFinderExtension() {
        guard let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MenuWishFinderExtension.appex") else {
            return
        }

        removeStaleFinderExtensions(keeping: extensionURL)
        runPluginKit(arguments: ["-a", extensionURL.path])
    }

    private func removeStaleFinderExtensions(keeping currentExtensionURL: URL) {
        finderExtensionEntries()
            .filter { entry in
                entry.identifier == extensionBundleIdentifier
                    && !sameFilePath(entry.url, currentExtensionURL)
            }
            .forEach { entry in
                runPluginKit(arguments: ["-r", entry.url.path])
            }
    }

    private func runPluginKit(arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }

    @discardableResult
    private func refreshAuthorizationStatus() -> Bool {
        let isEnabled = finderExtensionIsEnabled()
        applyAuthorizationStatus(isEnabled)
        return isEnabled
    }

    private func applyAuthorizationStatus(_ isEnabled: Bool) {
        finderExtensionEnabled = isEnabled
        statusMenuAuthorizationItem?.isHidden = isEnabled
        authorizationButton?.isHidden = isEnabled

        if isEnabled {
            authorizationIconView?.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: AppText.localized("已授权", "Authorized")
            )
            authorizationIconView?.contentTintColor = .systemGreen
            authorizationIconTile?.layer?.backgroundColor = tintBackgroundColor(for: .systemGreen).cgColor
            authorizationIconTile?.layer?.shadowColor = NSColor.systemGreen.cgColor
            authorizationIconTile?.layer?.shadowOffset = .zero
            authorizationIconTile?.layer?.shadowRadius = 6.0
            authorizationIconTile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.18
            authorizationIconTile?.layer?.masksToBounds = false

            authorizationTitleLabel?.stringValue = AppText.localized("Finder 扩展授权", "Finder Extension Permission")
            authorizationDetailLabel?.stringValue = AppText.localized("已授权 · 服务准备就绪", "Authorized · Service ready")
        } else {
            authorizationIconView?.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: AppText.localized("需要授权", "Permission Required")
            )
            authorizationIconView?.contentTintColor = .systemOrange
            authorizationIconTile?.layer?.backgroundColor = tintBackgroundColor(for: .systemOrange).cgColor
            authorizationIconTile?.layer?.shadowColor = NSColor.systemOrange.cgColor
            authorizationIconTile?.layer?.shadowOffset = .zero
            authorizationIconTile?.layer?.shadowRadius = 6.0
            authorizationIconTile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.18
            authorizationIconTile?.layer?.masksToBounds = false

            authorizationTitleLabel?.stringValue = AppText.localized("Finder 扩展授权", "Finder Extension Permission")
            authorizationDetailLabel?.stringValue = AppText.localized("未授权 · 请在系统设置中开启", "Unauthorized · Please enable in System Settings")
        }

        refreshPreferenceControls()
    }

    private func finderExtensionIsEnabled() -> Bool {
        let entries = finderExtensionEntries()

        if let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MenuWishFinderExtension.appex"),
           let currentEntry = entries.first(where: { entry in
               entry.identifier == extensionBundleIdentifier && sameFilePath(entry.url, extensionURL)
           }) {
            return currentEntry.isEnabled
        }

        return entries.contains { entry in
            entry.identifier == extensionBundleIdentifier && entry.isEnabled
        }
    }

    private struct FinderExtensionEntry {
        let identifier: String
        let isEnabled: Bool
        let url: URL
    }

    private func finderExtensionEntries() -> [FinderExtensionEntry] {
        let output = runPluginKitAndCapture(arguments: [
            "-m",
            "-A",
            "-v",
            "-p",
            "com.apple.FinderSync",
            "-i",
            extensionBundleIdentifier
        ])

        return output
            .components(separatedBy: .newlines)
            .compactMap(parseFinderExtensionEntry)
    }

    private func parseFinderExtensionEntry(_ line: String) -> FinderExtensionEntry? {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 4 else {
            return nil
        }

        let stateAndIdentifier = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let state = stateAndIdentifier.first, state == "+" || state == "-" else {
            return nil
        }

        let rawIdentifier = stateAndIdentifier
            .dropFirst()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = rawIdentifier
            .split(separator: "(", maxSplits: 1)
            .first
            .map(String.init) ?? rawIdentifier
        let path = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !identifier.isEmpty, !path.isEmpty else {
            return nil
        }

        return FinderExtensionEntry(
            identifier: identifier,
            isEnabled: state == "+",
            url: URL(fileURLWithPath: path)
        )
    }

    private func sameFilePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func runPluginKitAndCapture(arguments: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            NSLog("MenuWish pluginkit query failed: \(error.localizedDescription)")
            return ""
        }
    }

    private func scheduleAuthorizationRefresh() {
        [1.0, 2.5, 5.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshAuthorizationStatus()
            }
        }
    }

    private func refreshUpdateControls() {
        updateCheckButton?.isEnabled = !isCheckingForUpdates
        updateCheckButton?.title = isCheckingForUpdates
            ? AppText.localized("检查中…", "Checking…") : AppText.localized("检查", "Check")
        updateStatusLabel?.stringValue = isCheckingForUpdates
            ? AppText.localized("正在检查 GitHub Releases…", "Checking GitHub Releases…")
            : AppText.localized("可检查最新版本与发布日志", "Check latest version and release notes")
    }

    @objc private func checkForUpdates() {
        if let updateDownloadWindow {
            updateDownloadWindow.showWindow(nil)
            updateDownloadWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        if let releaseAlert {
            releaseAlert.window.makeKeyAndOrderFront(nil)
            return
        }
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        refreshUpdateControls()
        performUpdateCheck()
    }

    private func performUpdateCheck(useWebFallback: Bool = false) {
        let url = useWebFallback ? repositoryURL.appendingPathComponent("releases/latest") : latestReleaseAPIURL
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if useWebFallback { request.httpMethod = "HEAD" }
        request.setValue("MenuWish/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        if !useWebFallback { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if !useWebFallback, let response = response as? HTTPURLResponse,
                   [403, 429].contains(response.statusCode) {
                    self.performUpdateCheck(useWebFallback: true)
                    return
                }
                if let error {
                    self.showUpdateFailure(error.localizedDescription)
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    self.showUpdateFailure(AppText.localized("无法连接 GitHub。", "Unable to connect to GitHub."))
                    return
                }
                do {
                    let result = try useWebFallback
                        ? UpdateChecker.resultFromRedirect(url: response.url, statusCode: response.statusCode, currentVersion: self.currentVersionString)
                        : UpdateChecker.result(data: data ?? Data(), statusCode: response.statusCode, currentVersion: self.currentVersionString)
                    if useWebFallback {
                        self.fetchFallbackReleaseNotes(result)
                    } else {
                        self.finishUpdateCheck(result)
                    }
                } catch UpdateCheckError.httpStatus(let code) {
                    let message = [403, 429].contains(code)
                        ? AppText.localized("GitHub 暂时限制了请求，请稍后再试。", "GitHub is limiting requests. Please try again later.")
                        : AppText.localized("GitHub 返回 \(code)，请稍后再试。", "GitHub returned \(code). Please try again later.")
                    self.showUpdateFailure(message)
                } catch {
                    self.showUpdateFailure(AppText.localized("无法读取有效的版本信息，请稍后再试。", "Unable to read valid release information. Please try again later."))
                }
            }
        }.resume()
    }

    private func fetchFallbackReleaseNotes(_ result: UpdateCheckResult) {
        let release: ReleaseDetails
        let updateAvailable: Bool
        switch result {
        case let .available(details): release = details; updateAvailable = true
        case let .upToDate(details): release = details; updateAvailable = false
        case .noRelease: finishUpdateCheck(result); return
        }
        let request = URLRequest(url: repositoryURL.appendingPathComponent("releases.atom"),
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let notes = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
                ? data.flatMap { UpdateChecker.notesFromFeed(data: $0, releasePage: release.page) } : nil
            let details = ReleaseDetails(version: release.version, page: release.page, notes: notes)
            DispatchQueue.main.async {
                self?.finishUpdateCheck(updateAvailable ? .available(details) : .upToDate(details))
            }
        }.resume()
    }

    private func finishUpdateCheck(_ result: UpdateCheckResult) {
        isCheckingForUpdates = false
        refreshUpdateControls()
        switch result {
        case let .available(release): showReleaseAlert(release, updateAvailable: true)
        case let .upToDate(release): showReleaseAlert(release, updateAvailable: false)
        case .noRelease:
            showNativeAlert(title: AppText.localized("暂无可用更新", "No Release Available"),
                message: AppText.localized("GitHub 上尚无可用的正式发布版本，请稍后再试。", "No stable release is available on GitHub yet. Please try again later."))
        }
    }

    private func showUpdateFailure(_ message: String) {
        isCheckingForUpdates = false
        refreshUpdateControls()
        showNativeAlert(title: AppText.localized("检查更新失败", "Unable to Check for Updates"), message: message, style: .warning)
    }

    private func showReleaseAlert(_ release: ReleaseDetails, updateAvailable: Bool) {
        let alert = NSAlert()
        alert.messageText = updateAvailable
            ? AppText.localized("发现新版本", "A New Version Is Available")
            : AppText.localized("已是最新版本", "You're Up to Date")
        alert.informativeText = AppText.localized(
            "当前版本：\(currentVersionString)\n最新正式版本：\(release.version)",
            "Current version: \(currentVersionString)\nLatest stable release: \(release.version)")
        alert.accessoryView = ReleaseNotesView(
            release: release, isEnglish: AppText.isEnglish)
        if updateAvailable {
            alert.addButton(withTitle: release.installer == nil
                ? AppText.localized("前往下载", "Open Download Page")
                : AppText.localized("下载更新", "Download Update"))
            alert.addButton(withTitle: AppText.localized("稍后", "Later"))
        } else {
            alert.addButton(withTitle: AppText.localized("好", "OK"))
            alert.addButton(withTitle: AppText.localized("发布页面", "Release Page"))
        }
        NSApp.activate(ignoringOtherApps: true)
        releaseAlert = alert
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            self?.releaseAlert = nil
            if updateAvailable && result == .alertFirstButtonReturn {
                if let installer = release.installer, let self {
                    let controller = UpdateDownloadWindow(release: release, installer: installer,
                        isEnglish: AppText.isEnglish) { [weak self] in self?.updateDownloadWindow = nil }
                    self.updateDownloadWindow = controller
                    controller.start()
                } else {
                    NSWorkspace.shared.open(release.page)
                }
            } else if !updateAvailable && result == .alertSecondButtonReturn {
                NSWorkspace.shared.open(release.page)
            }
        }
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func showNativeAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: AppText.localized("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        // Modal alerts also work when the settings window is closed during the request.
        alert.runModal()
    }

    @objc private func openGitHubProfile() {
        NSWorkspace.shared.open(repositoryURL)
    }

    private var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func revealExtensionItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fileprovider-nonui",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ]

        for value in candidates {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }

        let script = """
        tell application "System Settings"
            activate
            reveal anchor "ExtensionItems" of pane id "com.apple.LoginItems-Settings.extension"
        end tell
        """

        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        receivedActionURL = true

        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "rightmenumini",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let action = components.host,
            let folderPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
            !folderPath.isEmpty
        else {
            return
        }

        let shouldQuitAfterHandling = components.queryItems?.first(where: { $0.name == "quit" })?.value == "1"
        let folderURL = URL(fileURLWithPath: folderPath)

        if let kind = NewFileKind.allCases.first(where: { $0.action == action }) {
            createFile(kind, in: folderURL)
        } else if action == "terminal" {
            openTerminal(in: folderURL)
        }

        if shouldQuitAfterHandling {
            terminateIfOnlyHandlingAction()
        }
    }

    private func terminateIfOnlyHandlingAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.window?.isVisible != true else {
                return
            }

            NSApp.terminate(nil)
        }
    }

    private func createFile(_ kind: NewFileKind, in folderURL: URL) {
        do {
            _ = try NewFileCreator.create(kind, in: folderURL,
                templates: Bundle.main.resourceURL?.appendingPathComponent("Templates"))
        } catch {
            showNativeAlert(
                title: AppText.localized("无法新建文件", "Unable to Create File"),
                message: AppText.localized("位置：", "Location: ") + folderURL.path + "\n\n" + error.localizedDescription,
                style: .warning
            )
        }
    }

    private func openTerminal(in folderURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", folderURL.path]

        do {
            try task.run()
        } catch {
            NSLog("MenuWish fallback terminal failed: \(error.localizedDescription)")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}

@main
@MainActor
struct MenuWishApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class ClickableRowView: NSView {
    var action: Selector?
    weak var target: AnyObject?
    var isEnabled: Bool = true
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .assumeInside]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true

        guard isEnabled else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            if let checkbox = subviews.first(where: { $0 is NSButton }) as? NSButton,
               checkbox.frame.contains(localPoint) {
                return
            }
            if let target, let action {
                _ = target.perform(action, with: self)
            }
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        guard isEnabled else { return }
        let isDark: Bool
        if let appearance = window?.effectiveAppearance {
            isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        if isPressed {
            let highlightRect = bounds.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8)
            NSColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.12 : 0.06).set()
            path.fill()
        } else if isHovered {
            let highlightRect = bounds.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8)
            NSColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.06 : 0.03).set()
            path.fill()
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}


/// The entire header handles dragging, including its label and grip.
@MainActor
private final class CategoryDragHeaderView: NSView {
    let category: MenuCategory
    weak var groupView: NSView?
    var onKeyboardMove: ((Int) -> Bool)?
    private var mouseDownPoint: NSPoint?
    private var dragDocument: CategoryReorderDocumentView? {
        enclosingScrollView?.documentView as? CategoryReorderDocumentView
    }

    init(category: MenuCategory) {
        self.category = category
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        focusRingType = .exterior
        return super.becomeFirstResponder()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 3), xRadius: 5, yRadius: 5).fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        focusRingType = .none
        mouseDownPoint = event.locationInWindow
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let group = groupView, let document = dragDocument else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        document.beginDrag(category: category, group: group, start: start)
        document.updateDrag(at: point)
    }
    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        dragDocument?.finishDrag(at: event.locationInWindow)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, dragDocument?.isDragging == true {
            mouseDownPoint = nil
            dragDocument?.cancelDrag()
        } else if event.modifierFlags.contains(.option), [125, 126].contains(event.keyCode) {
            _ = onKeyboardMove?(event.keyCode == 126 ? -1 : 1)
        } else { super.keyDown(with: event) }
    }
}

/// Keep reordering local to this sheet so dragging never exports data to another app.
@MainActor
private final class CategoryReorderDocumentView: NSView {
    var groups: [(category: MenuCategory, view: NSView)] = []
    var onMove: ((MenuCategory, Int) -> Void)?
    private let indicator = NSView()
    private let floatingGroup = NSImageView()
    private var draggingCategory: MenuCategory?
    private weak var draggingGroup: NSView?
    private var pointerOffset = NSPoint.zero
    private var pointerInWindow = NSPoint.zero
    private var scrollTimer: Timer?
    private var collapsedRows: [(view: NSView, wasHidden: Bool)] = []
    private var dragSpacer: NSView?
    private var originalScrollOrigin: NSPoint?
    var isDragging: Bool { draggingCategory != nil }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.layer?.cornerRadius = 1
        indicator.layer?.zPosition = 20
        indicator.isHidden = true
        addSubview(indicator)
        floatingGroup.wantsLayer = true
        floatingGroup.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        floatingGroup.layer?.cornerRadius = 8
        floatingGroup.layer?.shadowOpacity = 0.18
        floatingGroup.layer?.shadowRadius = 8
        floatingGroup.layer?.zPosition = 10
        floatingGroup.alphaValue = 0.85
        floatingGroup.isHidden = true
        addSubview(floatingGroup)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clearDropIndicator() { indicator.isHidden = true }

    func beginDrag(category: MenuCategory, group: NSView, start: NSPoint) {
        guard !isDragging, let header = group.subviews.first as? CategoryDragHeaderView,
              let bitmap = header.bitmapImageRepForCachingDisplay(in: header.bounds) else { return }
        header.cacheDisplay(in: header.bounds, to: bitmap)
        let image = NSImage(size: header.bounds.size)
        image.addRepresentation(bitmap)
        floatingGroup.image = image
        floatingGroup.frame = convert(header.bounds, from: header)
        let point = convert(start, from: nil)
        pointerOffset = NSPoint(x: point.x - floatingGroup.frame.minX, y: point.y - floatingGroup.frame.minY)
        draggingCategory = category
        draggingGroup = group
        collapseCategoriesForDrag()
        group.alphaValue = 0.25
        floatingGroup.isHidden = false
        NSCursor.closedHand.push()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollDuringDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func collapseCategoriesForDrag() {
        guard let list = groups.first?.view.superview as? NSStackView else { return }
        originalScrollOrigin = enclosingScrollView?.contentView.bounds.origin
        let originalHeight = list.bounds.height
        for (_, view) in groups {
            guard let group = view as? NSStackView else { continue }
            group.detachesHiddenViews = true
            for row in group.arrangedSubviews where !(row is CategoryDragHeaderView) {
                collapsedRows.append((row, row.isHidden))
                row.isHidden = true
            }
        }
        // Keep the document's scroll extent stable while all category bodies fold.
        // The pointer and floating header can then stay anywhere in the list area.
        let headersHeight = groups.reduce(CGFloat.zero) { total, entry in
            total + ((entry.view.subviews.first as? CategoryDragHeaderView)?.bounds.height ?? 0)
        }
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: max(0, originalHeight - headersHeight)).isActive = true
        list.addArrangedSubview(spacer)
        dragSpacer = spacer
        layoutSubtreeIfNeeded()
        if let scroll = enclosingScrollView {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func restoreCategoriesAfterDrag() {
        dragSpacer?.removeFromSuperview()
        dragSpacer = nil
        for (row, wasHidden) in collapsedRows { row.isHidden = wasHidden }
        collapsedRows.removeAll()
        layoutSubtreeIfNeeded()
        if let origin = originalScrollOrigin, let scroll = enclosingScrollView {
            var bounds = scroll.contentView.bounds
            bounds.origin = origin
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        originalScrollOrigin = nil
    }

    private func target(at point: NSPoint) -> (Int, CGFloat)? {
        guard let category = draggingCategory,
              let current = groups.firstIndex(where: { $0.category == category }) else { return nil }
        let others = groups.filter { $0.category != category }
        let index = others.firstIndex { convert($0.view.bounds, from: $0.view).midY > point.y } ?? others.count
        guard index != current else { return nil }
        let edge: CGFloat
        if index < others.count { edge = convert(others[index].view.bounds, from: others[index].view).minY }
        else if let last = others.last { edge = convert(last.view.bounds, from: last.view).maxY }
        else { return nil }
        return (index, edge)
    }

    func updateDrag(at windowPoint: NSPoint) {
        guard isDragging else { return }
        pointerInWindow = windowPoint
        let point = convert(windowPoint, from: nil)
        floatingGroup.setFrameOrigin(NSPoint(x: 4, y: point.y - pointerOffset.y))
        guard visibleRect.contains(point), let (_, edge) = target(at: point) else { clearDropIndicator(); return }
        indicator.frame = NSRect(x: 8, y: min(max(1, edge - 1), bounds.height - 3), width: max(0, bounds.width - 16), height: 2)
        indicator.isHidden = false
    }

    private func scrollDuringDrag() {
        guard isDragging, let scroll = enclosingScrollView else { return }
        let point = convert(pointerInWindow, from: nil)
        let visible = visibleRect
        guard point.x >= visible.minX, point.x <= visible.maxX,
              point.y >= visible.minY - 24, point.y <= visible.maxY + 24 else { return }
        let delta: CGFloat = point.y < visible.minY + 28 ? -10 : (point.y > visible.maxY - 28 ? 10 : 0)
        guard delta != 0 else { return }
        let clip = scroll.contentView
        var targetBounds = clip.bounds
        targetBounds.origin.y += delta
        clip.scroll(to: clip.constrainBoundsRect(targetBounds).origin)
        scroll.reflectScrolledClipView(clip)
        updateDrag(at: pointerInWindow)
    }

    func finishDrag(at windowPoint: NSPoint) {
        guard let category = draggingCategory else { return }
        let point = convert(windowPoint, from: nil)
        let index = visibleRect.contains(point) ? target(at: point)?.0 : nil
        cancelDrag()
        if let index { onMove?(category, index) }
    }

    func cancelDrag() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        if isDragging { NSCursor.pop() }
        draggingCategory = nil
        draggingGroup?.alphaValue = 1
        draggingGroup = nil
        restoreCategoriesAfterDrag()
        floatingGroup.isHidden = true
        floatingGroup.image = nil
        clearDropIndicator()
    }
}
