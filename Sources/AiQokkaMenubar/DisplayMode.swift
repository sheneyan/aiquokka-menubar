import Combine
import Foundation

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case menuBar = "menuBar"
    case standaloneWindow = "standaloneWindow"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar:
            return "菜单栏"
        case .standaloneWindow:
            return "独立窗口"
        }
    }

    var systemImageName: String {
        switch self {
        case .menuBar:
            return "menubar.rectangle"
        case .standaloneWindow:
            return "macwindow"
        }
    }
}

@MainActor
final class DisplayModeSettings: ObservableObject {
    static let userDefaultsKey = "aiquokka.displayMode"

    @Published var mode: DisplayMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.mode = DisplayMode(
            rawValue: userDefaults.string(forKey: Self.userDefaultsKey) ?? ""
        ) ?? .menuBar
    }
}
