@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageAlertCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testFirstSuccessfulEvaluationRequestsAuthorizationAndSendsNearLimit() async throws {
        let client = RecordingUsageNotificationClient()
        let coordinator = makeCoordinator(client: client)

        await coordinator.process(snapshot: snapshot(usedPercent: 80), now: now)

        XCTAssertEqual(client.authorizationRequestCount, 1)
        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit])
        XCTAssertEqual(coordinator.highestSeverity, .warning)
    }

    func testRepeatedRefreshDoesNotSendDuplicateAlert() async throws {
        let client = RecordingUsageNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let current = snapshot(usedPercent: 80)

        await coordinator.process(snapshot: current, now: now)
        await coordinator.process(snapshot: current, now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.count, 1)
        XCTAssertEqual(client.authorizationRequestCount, 1)
    }

    func testCriticalEscalationSendsASecondAlert() async throws {
        let client = RecordingUsageNotificationClient()
        let coordinator = makeCoordinator(client: client)

        await coordinator.process(snapshot: snapshot(usedPercent: 80), now: now)
        await coordinator.process(snapshot: snapshot(usedPercent: 95), now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit, .critical])
        XCTAssertEqual(coordinator.highestSeverity, .critical)
    }

    func testFailedDeliveryIsRetriedOnTheNextRefresh() async throws {
        let client = RecordingUsageNotificationClient(sendResults: [false, true])
        let coordinator = makeCoordinator(client: client)
        let current = snapshot(usedPercent: 80)

        await coordinator.process(snapshot: current, now: now)
        await coordinator.process(snapshot: current, now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.count, 2)
        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit, .nearingLimit])
    }

    func testMissingPercentDoesNotClearPreviouslySentAlert() async {
        let client = RecordingUsageNotificationClient()
        let coordinator = makeCoordinator(client: client)

        await coordinator.process(snapshot: snapshot(usedPercent: 80), now: now)
        await coordinator.process(snapshot: snapshot(usedPercent: nil), now: now.addingTimeInterval(60))
        await coordinator.process(snapshot: snapshot(usedPercent: 80), now: now.addingTimeInterval(120))

        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit])
    }

    func testAuthorizationIsRequestedOnlyOnceAcrossRefreshes() async {
        let client = RecordingUsageNotificationClient()
        let coordinator = makeCoordinator(client: client)

        await coordinator.process(snapshot: snapshot(usedPercent: 10), now: now)
        await coordinator.process(snapshot: snapshot(usedPercent: 10), now: now.addingTimeInterval(60))

        XCTAssertEqual(client.authorizationRequestCount, 1)
    }

    private func makeCoordinator(client: RecordingUsageNotificationClient) -> UsageAlertCoordinator {
        let name = "AiQokkaUsageAlertCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }

        return UsageAlertCoordinator(
            stateStore: UsageAlertStateStore(userDefaults: defaults),
            notificationClient: client
        )
    }

    private func snapshot(usedPercent: Double?) -> UsageSnapshot {
        let window = UsageWindow(
            label: "Weekly",
            usedPercent: usedPercent,
            resetDate: now.addingTimeInterval(6 * day),
            resetText: nil
        )
        let provider = ProviderUsage(
            id: "codex",
            name: "Codex",
            plan: "plus",
            error: nil,
            windows: [window],
            extras: []
        )
        return UsageSnapshot(providers: [provider], fetchedAt: now)
    }

    private var day: TimeInterval { 24 * 60 * 60 }
}

@MainActor
private final class RecordingUsageNotificationClient: UsageNotificationClient {
    private(set) var authorizationRequestCount = 0
    private(set) var sentAlerts: [UsageAlert] = []
    private var sendResults: [Bool]

    init(sendResults: [Bool] = []) {
        self.sendResults = sendResults
    }

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func send(_ alert: UsageAlert) async -> Bool {
        sentAlerts.append(alert)
        if sendResults.isEmpty {
            return true
        }
        return sendResults.removeFirst()
    }
}
