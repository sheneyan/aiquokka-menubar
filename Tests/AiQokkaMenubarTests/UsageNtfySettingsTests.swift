@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageNtfySettingsTests: XCTestCase {
    func testNtfyIsDisabledByDefault() {
        let settings = UsageNtfySettings(userDefaults: makeDefaults())

        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.configuration.isEnabled)
    }

    func testSettingsPersistAndReload() {
        let defaults = makeDefaults()
        let first = UsageNtfySettings(userDefaults: defaults)

        first.isEnabled = true
        first.agentNotifyExecutablePath = "/custom/bin/agent-notify"
        first.agentNotifyConfigPath = "/custom/agent-notify.env"
        first.milestoneStepPercent = 5

        let second = UsageNtfySettings(userDefaults: defaults)

        XCTAssertTrue(second.isEnabled)
        XCTAssertEqual(second.agentNotifyExecutablePath, "/custom/bin/agent-notify")
        XCTAssertEqual(second.agentNotifyConfigPath, "/custom/agent-notify.env")
        XCTAssertEqual(second.milestoneStepPercent, 5)
        XCTAssertEqual(second.configuration, UsageNtfyConfiguration(
            isEnabled: true,
            executablePath: "/custom/bin/agent-notify",
            configPath: "/custom/agent-notify.env",
            milestoneStepPercent: 5
        ))
    }

    func testInvalidMilestoneStepFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: UsageNtfySettings.milestoneStepPercentKey)

        let settings = UsageNtfySettings(userDefaults: defaults)

        XCTAssertEqual(settings.milestoneStepPercent, 10)
        XCTAssertEqual(settings.configuration.milestoneStepPercent, 10)
    }

    func testEmptyPathsAreNotReadyToSend() {
        let settings = UsageNtfySettings(userDefaults: makeDefaults())
        settings.isEnabled = true
        settings.agentNotifyExecutablePath = ""
        settings.agentNotifyConfigPath = ""

        XCTAssertFalse(settings.configuration.isConfigured)
    }

    func testConfigFileMustHave0600Permissions() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiquokka-agent-notify-\(UUID().uuidString).env")
        defer { try? FileManager.default.removeItem(at: path) }
        FileManager.default.createFile(atPath: path.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)

        let settings = UsageNtfySettings(userDefaults: makeDefaults())
        settings.isEnabled = true
        settings.agentNotifyExecutablePath = "/bin/echo"
        settings.agentNotifyConfigPath = path.path

        XCTAssertTrue(settings.statusText.contains("0600"))
    }

    func testDefaultExecutablePathFallsBackToUserLocalBin() {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiquokka-home-\(UUID().uuidString)")

        let path = UsageNtfySettings.defaultExecutablePath(
            homeDirectory: homeDirectory,
            isExecutable: { _ in false }
        )

        XCTAssertEqual(
            path,
            homeDirectory.appendingPathComponent(".local/bin/agent-notify").path
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AiQokkaUsageNtfySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
