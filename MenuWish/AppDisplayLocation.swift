import Foundation

enum AppDisplayLocation: String, CaseIterable {
    case menuBar, dock, both, hidden

    static let preferenceKey = "displayLocation"
    static func resolved(_ storedValue: String?) -> Self { Self(rawValue: storedValue ?? "") ?? .menuBar }
    var showsMenuBar: Bool { self == .menuBar || self == .both }
    var showsDock: Bool { self == .dock || self == .both }
    var quitsWhenLastWindowCloses: Bool { self == .hidden }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .menuBar: return isEnglish ? "Menu Bar Only" : "仅菜单栏"
        case .dock: return isEnglish ? "Dock Only" : "仅 Dock"
        case .both: return isEnglish ? "Menu Bar & Dock" : "菜单栏与 Dock"
        case .hidden: return isEnglish ? "Hidden" : "完全隐藏"
        }
    }
}
