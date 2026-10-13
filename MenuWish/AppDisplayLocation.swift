import Foundation

enum AppDisplayLocation: String, CaseIterable {
    case menuBar, dock, both

    static let preferenceKey = "displayLocation"
    static func resolved(_ storedValue: String?) -> Self { Self(rawValue: storedValue ?? "") ?? .menuBar }
    var showsMenuBar: Bool { self != .dock }
    var showsDock: Bool { self != .menuBar }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .menuBar: return isEnglish ? "Menu Bar Only" : "仅菜单栏"
        case .dock: return isEnglish ? "Dock Only" : "仅 Dock"
        case .both: return isEnglish ? "Menu Bar & Dock" : "菜单栏与 Dock"
        }
    }
}
