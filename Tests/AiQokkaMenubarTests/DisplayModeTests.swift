@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class DisplayModeSettingsTests: XCTestCase {

    func testMissingValueDefaultsToMenuBar() {
        let defaults = makeDefaults()
        let settings = DisplayModeSettings(userDefaults: defaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }

    func testPersistsStandaloneWindowForTheNextInstance() {
        let defaults = makeDefaults()
        let first = DisplayModeSettings(userDefaults: defaults)

        first.mode = .standaloneWindow

        let second = DisplayModeSettings(userDefaults: defaults)

        XCTAssertEqual(second.mode, .standaloneWindow)

        second.mode = .menuBar

        XCTAssertEqual(
            defaults.string(forKey: DisplayModeSettings.userDefaultsKey),
            DisplayMode.menuBar.rawValue
        )
    }

    func testUnknownStoredValueFallsBackToMenuBar() {
        let defaults = makeDefaults()
        defaults.set("future-mode", forKey: DisplayModeSettings.userDefaultsKey)

        let settings = DisplayModeSettings(userDefaults: defaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AiQokkaDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
