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
}

private final class FakeCredentialStore: DeepSeekCredentialStore, @unchecked Sendable {
    var value: String?
    func load() throws -> String? { value }
    func save(_ key: String) throws { value = key }
    func delete() throws { value = nil }
}
