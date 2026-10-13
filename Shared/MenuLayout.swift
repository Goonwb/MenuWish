import Foundation

enum MenuDisplayMode: String, CaseIterable {
    case flat, grouped, categorized
    static let preferenceKey = "menuDisplayMode"

    static func resolved(_ value: String?, legacyGrouped: Bool) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? (legacyGrouped ? .grouped : .flat)
    }
    var segmentIndex: Int { Self.allCases.firstIndex(of: self)! }
    func title(isEnglish: Bool) -> String {
        switch self {
        case .flat: return isEnglish ? "Flat" : "平铺"
        case .grouped: return isEnglish ? "Combined" : "合并"
        case .categorized: return isEnglish ? "Categories" : "分类"
        }
    }
}

struct MenuActionGroup: Equatable {
    let category: MenuCategory?
    let actions: [MenuAction]
    func title(isEnglish: Bool) -> String {
        category?.title(isEnglish: isEnglish) ?? "MenuWish"
    }
}

enum MenuAction: String, CaseIterable {
    case text = "new-text", markdown = "new-markdown", numbers = "new-numbers"
    case pages = "new-pages", keynote = "new-keynote", terminal, copyPath = "copy-path"

    var fileKind: NewFileKind? { NewFileKind.allCases.first { $0.action == rawValue } }
    var category: MenuCategory { fileKind == nil ? .tools : .files }
    var preferenceKey: String { fileKind?.preferenceKey ?? (self == .terminal ? "isTerminalEnabled" : "isCopyPathEnabled") }
    var symbolName: String { fileKind?.symbolName ?? (self == .terminal ? "square-terminal" : "link") }
    func title(isEnglish: Bool) -> String {
        fileKind?.title(isEnglish: isEnglish) ?? (self == .terminal
            ? (isEnglish ? "Open Terminal" : "进入终端")
            : (isEnglish ? "Copy Path" : "拷贝路径"))
    }
    func detail(isEnglish: Bool) -> String {
        fileKind?.detail(isEnglish: isEnglish) ?? (self == .terminal
            ? (isEnglish ? "Open Terminal at this location" : "从当前位置打开 Terminal")
            : (isEnglish ? "Copy selected paths or current folder" : "复制所选项目或当前文件夹路径"))
    }
}

enum MenuCategory: String, CaseIterable {
    case files, tools
    var actions: [MenuAction] { MenuAction.allCases.filter { $0.category == self } }
    func title(isEnglish: Bool) -> String {
        self == .files ? (isEnglish ? "New Files" : "新建文件") : (isEnglish ? "Tools" : "常用工具")
    }
}

/// Stable IDs preserve the user's order when new actions arrive in a future version.
struct MenuLayout: Equatable {
    static let preferenceKey = "actionLayout"
    private struct Saved: Codable {
        var categories: [String]?
        var actions: [String: [String]]?
        var unified: [String]?
    }
    private(set) var categories: [MenuCategory]
    private(set) var unifiedActions: [MenuAction]

    init(serialized: String = "") {
        let saved = try? JSONDecoder().decode(Saved.self, from: Data(serialized.utf8))
        let parsedCategories = Self.normalized(saved?.categories, defaults: MenuCategory.allCases)
        let parsedActions = Dictionary(uniqueKeysWithValues: MenuCategory.allCases.map { category in
            (category, Self.normalized(saved?.actions?[category.rawValue], defaults: category.actions))
        })
        let defaultUnified = parsedCategories.flatMap { parsedActions[$0] ?? $0.actions }
        categories = parsedCategories
        unifiedActions = Self.normalized(saved?.unified, defaults: defaultUnified)
    }

    var serialized: String {
        let saved = Saved(
            categories: categories.map(\.rawValue),
            actions: Dictionary(uniqueKeysWithValues: categories.map { ($0.rawValue, orderedActions(in: $0).map(\.rawValue)) }),
            unified: unifiedActions.map(\.rawValue)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(saved), as: UTF8.self)
    }

    func orderedActions(in category: MenuCategory) -> [MenuAction] {
        unifiedActions.filter { $0.category == category }
    }

    func enabledActions(values: [String: Bool]) -> [MenuAction] {
        unifiedActions.filter { values[$0.preferenceKey] ?? true }
    }

    func enabledGroups(values: [String: Bool]) -> [[MenuAction]] {
        categories.map { category in
            orderedActions(in: category).filter { values[$0.preferenceKey] ?? true }
        }.filter { !$0.isEmpty }
    }

    func menuGroups(mode: MenuDisplayMode, values: [String: Bool]) -> [MenuActionGroup] {
        if mode == .categorized {
            return categories.compactMap { category in
                let enabled = orderedActions(in: category).filter { values[$0.preferenceKey] ?? true }
                return enabled.isEmpty ? nil : MenuActionGroup(category: category, actions: enabled)
            }
        }
        let enabled = enabledActions(values: values)
        return enabled.isEmpty ? [] : [MenuActionGroup(category: nil, actions: enabled)]
    }

    /// Swap only positions belonging to this category, preserving the user's
    /// interleaved global order for flat and combined modes.
    @discardableResult mutating func moveWithinCategory(_ action: MenuAction, by offset: Int) -> Bool {
        let peers = orderedActions(in: action.category)
        guard [-1, 1].contains(offset), let index = peers.firstIndex(of: action),
              peers.indices.contains(index + offset),
              let source = unifiedActions.firstIndex(of: action),
              let target = unifiedActions.firstIndex(of: peers[index + offset]) else { return false }
        unifiedActions.swapAt(source, target)
        return true
    }

    @discardableResult mutating func moveCategory(_ category: MenuCategory, to index: Int) -> Bool {
        guard categories.indices.contains(index), let source = categories.firstIndex(of: category), source != index else { return false }
        categories.remove(at: source)
        categories.insert(category, at: index)
        return true
    }

    @discardableResult mutating func moveCategory(_ category: MenuCategory, by offset: Int) -> Bool {
        Self.move(category, in: &categories, by: offset)
    }

    @discardableResult mutating func move(_ category: MenuCategory, by offset: Int) -> Bool {
        guard Self.move(category, in: &categories, by: offset) else { return false }
        var updated: [MenuAction] = []
        for cat in categories {
            updated.append(contentsOf: unifiedActions.filter { $0.category == cat })
        }
        unifiedActions = updated
        return true
    }

    @discardableResult mutating func move(_ action: MenuAction, by offset: Int) -> Bool {
        var list = orderedActions(in: action.category)
        guard Self.move(action, in: &list, by: offset) else { return false }
        var updated: [MenuAction] = []
        for cat in categories {
            updated.append(contentsOf: cat == action.category ? list : orderedActions(in: cat))
        }
        unifiedActions = updated
        return true
    }

    @discardableResult mutating func moveUnified(_ action: MenuAction, by offset: Int) -> Bool {
        guard Self.move(action, in: &unifiedActions, by: offset) else { return false }
        return true
    }

    private static func move<T: Equatable>(_ item: T, in list: inout [T], by offset: Int) -> Bool {
        guard [-1, 1].contains(offset), let index = list.firstIndex(of: item),
              list.indices.contains(index + offset) else { return false }
        list.swapAt(index, index + offset)
        return true
    }

    private static func normalized<T: RawRepresentable & Hashable>(_ ids: [String]?, defaults: [T]) -> [T] where T.RawValue == String {
        var seen = Set<T>()
        return ((ids ?? []).compactMap(T.init(rawValue:)) + defaults)
            .filter { defaults.contains($0) && seen.insert($0).inserted }
    }
}
