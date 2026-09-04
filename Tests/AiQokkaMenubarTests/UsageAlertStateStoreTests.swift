@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageAlertStateStoreTests: XCTestCase {
    func testSentAlertRemainsSuppressedAfterStoreReload() {
        let defaults = makeDefaults()
        let resetDate = Date(timeIntervalSince1970: 2_000)
        let alert = makeAlert(kind: .nearingLimit, resetDate: resetDate)
        let context = makeContext(resetDate: resetDate, activeKinds: [.nearingLimit])

        let first = UsageAlertStateStore(userDefaults: defaults)
        first.reconcile(context)
        first.markSent(alert)

        let second = UsageAlertStateStore(userDefaults: defaults)
        second.reconcile(context)

        XCTAssertTrue(second.hasSent(alert))
    }

    func testInactiveKindIsRearmedWhenUsageLeavesTheThreshold() {
        let defaults = makeDefaults()
        let resetDate = Date(timeIntervalSince1970: 2_000)
        let alert = makeAlert(kind: .nearingLimit, resetDate: resetDate)
        let store = UsageAlertStateStore(userDefaults: defaults)

        store.reconcile(makeContext(resetDate: resetDate, activeKinds: [.nearingLimit]))
        store.markSent(alert)
        store.reconcile(makeContext(resetDate: resetDate, activeKinds: []))

        XCTAssertFalse(store.hasSent(alert))
    }

    func testChangingResetDateAllowsTheSameKindAgain() {
        let defaults = makeDefaults()
        let oldReset = Date(timeIntervalSince1970: 2_000)
        let newReset = Date(timeIntervalSince1970: 3_000)
        let store = UsageAlertStateStore(userDefaults: defaults)

        let oldAlert = makeAlert(kind: .critical, resetDate: oldReset)
        store.reconcile(makeContext(resetDate: oldReset, activeKinds: [.critical]))
        store.markSent(oldAlert)

        let newAlert = makeAlert(kind: .critical, resetDate: newReset)
        store.reconcile(makeContext(resetDate: newReset, activeKinds: [.critical]))

        XCTAssertFalse(store.hasSent(newAlert))
    }

    func testStateStorageDoesNotContainCredentialsOrRawYAML() throws {
        let defaults = makeDefaults()
        let store = UsageAlertStateStore(userDefaults: defaults)
        let alert = UsageAlert(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", kind: .critical, usedPercent: 95, resetDate: nil)

        store.reconcile(makeContext(resetDate: nil, activeKinds: [.critical]))
        store.markSent(alert)

        let data = try XCTUnwrap(defaults.data(forKey: UsageAlertStateStore.userDefaultsKey))
        let saved = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(saved.contains("DEEPSEEK_API_KEY"))
        XCTAssertFalse(saved.contains("api.deepseek.com"))
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AiQokkaUsageAlertStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeAlert(kind: UsageAlertKind, resetDate: Date?) -> UsageAlert {
        UsageAlert(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", kind: kind, usedPercent: 95, resetDate: resetDate)
    }

    private func makeContext(resetDate: Date?, activeKinds: Set<UsageAlertKind>) -> UsageWindowAlertEvaluation {
        UsageWindowAlertEvaluation(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", resetDate: resetDate, activeKinds: activeKinds, selectedAlert: nil)
    }
}
