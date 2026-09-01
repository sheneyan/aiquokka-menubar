@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class DisplayModeTests: XCTestCase {
    private var suiteName = ""
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AiQokkaMenubar.DisplayModeTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testMissingValueDefaultsToMenuBar() {
        let settings = DisplayModeSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }

    func testReadsStandaloneWindowAndPersistsChangedMode() {
        userDefaults.set(DisplayMode.standaloneWindow.rawValue, forKey: DisplayModeSettings.userDefaultsKey)

        let settings = DisplayModeSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.mode, .standaloneWindow)

        settings.mode = .menuBar

        XCTAssertEqual(
            userDefaults.string(forKey: DisplayModeSettings.userDefaultsKey),
            DisplayMode.menuBar.rawValue
        )
    }

    func testUnknownRawValueDefaultsToMenuBar() {
        userDefaults.set("futureMode", forKey: DisplayModeSettings.userDefaultsKey)

        let settings = DisplayModeSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }
}
