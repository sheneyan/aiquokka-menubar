@testable import AiQokkaMenubar
import XCTest

@MainActor
final class DeepSeekSettingsTests: XCTestCase {
    func testSaveTrimsKeyAndRefreshes() async {
        let store = FakeCredentialStore()
        var refreshes = 0
        let settings = DeepSeekSettings(credentialStore: store, refresh: { refreshes += 1 })
        settings.draftKey = "  test-key  \n"

        await settings.save()

        XCTAssertEqual(store.value, "test-key")
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(settings.draftKey, "")
        XCTAssertEqual(refreshes, 1)
    }

    func testSaveShowsSafeKeychainStatusWithoutTheKey() async {
        let settings = DeepSeekSettings(
            credentialStore: FailingCredentialStore(),
            refresh: {}
        )
        settings.draftKey = "test-key"

        await settings.save()

        XCTAssertEqual(settings.errorMessage, "无法保存 DeepSeek 凭据（Keychain 状态 -25308）。")
        XCTAssertFalse(settings.errorMessage?.contains("test-key") ?? true)
    }
}

private struct FailingCredentialStore: DeepSeekCredentialStore {
    func load() throws -> String? { nil }
    func save(_ key: String) throws { throw DeepSeekCredentialError.keychainStatus(-25308) }
    func delete() throws {}
}

private final class FakeCredentialStore: DeepSeekCredentialStore, @unchecked Sendable {
    var value: String?
    func load() throws -> String? { value }
    func save(_ key: String) throws { value = key }
    func delete() throws { value = nil }
}
