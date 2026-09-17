@testable import AiQokkaMenubar
import Foundation
import XCTest

final class UsageMilestoneEvaluatorTests: XCTestCase {
    private let evaluator = UsageMilestoneEvaluator()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testReturnsTheLatestTenPercentMilestone() throws {
        let milestones = evaluator.evaluate(snapshot: snapshot(usedPercent: 40.1))

        XCTAssertEqual(milestones.map(\.milestonePercent), [40])
        let milestone = try XCTUnwrap(milestones.first)
        XCTAssertEqual(milestone.providerID, "codex")
        XCTAssertEqual(milestone.windowLabel, "Weekly")
        XCTAssertEqual(milestone.plan, "plus")
    }

    func testUsageBelowTenPercentHasNoMilestone() {
        XCTAssertTrue(evaluator.evaluate(snapshot: snapshot(usedPercent: 9.99)).isEmpty)
    }

    func testExactBoundaryUsesThatMilestone() {
        XCTAssertEqual(
            evaluator.evaluate(snapshot: snapshot(usedPercent: 30)).map(\.milestonePercent),
            [30]
        )
    }

    func testUsesConfiguredMilestoneStep() {
        let fivePercentEvaluator = UsageMilestoneEvaluator(stepPercent: 5)

        XCTAssertEqual(
            fivePercentEvaluator.evaluate(snapshot: snapshot(usedPercent: 84.99)).map(\.milestonePercent),
            [80]
        )
        XCTAssertEqual(
            fivePercentEvaluator.evaluate(snapshot: snapshot(usedPercent: 85)).map(\.milestonePercent),
            [85]
        )
    }

    func testInvalidUsageAndProviderErrorsAreIgnored() {
        let invalid = snapshot(usedPercent: 101)
        let failedProvider = UsageSnapshot(
            providers: [ProviderUsage(
                id: "grok",
                name: "Grok",
                plan: "GrokPro",
                error: "network error",
                windows: [UsageWindow(
                    label: "Weekly",
                    usedPercent: 90,
                    resetDate: now.addingTimeInterval(6 * day),
                    resetText: nil
                )],
                extras: []
            )],
            fetchedAt: now
        )

        XCTAssertTrue(evaluator.evaluate(snapshot: invalid).isEmpty)
        XCTAssertTrue(evaluator.evaluate(snapshot: failedProvider).isEmpty)
    }

    private func snapshot(usedPercent: Double) -> UsageSnapshot {
        let provider = ProviderUsage(
            id: "codex",
            name: "Codex",
            plan: "plus",
            error: nil,
            windows: [UsageWindow(
                label: "Weekly",
                usedPercent: usedPercent,
                resetDate: now.addingTimeInterval(6 * day),
                resetText: nil
            )],
            extras: []
        )
        return UsageSnapshot(providers: [provider], fetchedAt: now)
    }

    private var day: TimeInterval { 24 * 60 * 60 }
}

@MainActor
final class UsageMilestoneCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testCrossingMilestonesSendsOncePerWindowAndPersistsAcrossInstances() async {
        let defaults = makeDefaults()
        let firstClient = RecordingUsageMilestoneNotificationClient()
        let first = makeCoordinator(client: firstClient, defaults: defaults)

        await first.process(snapshot: snapshot(usedPercent: 20))
        await first.process(snapshot: snapshot(usedPercent: 29))
        await first.process(snapshot: snapshot(usedPercent: 30))

        XCTAssertEqual(firstClient.sentMilestones.map(\.milestonePercent), [20, 30])

        let secondClient = RecordingUsageMilestoneNotificationClient()
        let second = makeCoordinator(client: secondClient, defaults: defaults)
        await second.process(snapshot: snapshot(usedPercent: 35))

        XCTAssertTrue(secondClient.sentMilestones.isEmpty)
    }

    func testAResetWindowCanNotifyAgain() async {
        let defaults = makeDefaults()
        let client = RecordingUsageMilestoneNotificationClient()
        let coordinator = makeCoordinator(client: client, defaults: defaults)

        await coordinator.process(snapshot: snapshot(usedPercent: 20))
        await coordinator.process(snapshot: snapshot(usedPercent: 20, resetAfter: 13 * day))

        XCTAssertEqual(client.sentMilestones.map(\.milestonePercent), [20, 20])
    }

    func testFailedDeliveryIsRetriedWithoutMarkingTheMilestoneSent() async {
        let client = RecordingUsageMilestoneNotificationClient(sendResults: [false, true])
        let coordinator = makeCoordinator(client: client)
        let current = snapshot(usedPercent: 40)

        await coordinator.process(snapshot: current)
        await coordinator.process(snapshot: current)

        XCTAssertEqual(client.sentMilestones.map(\.milestonePercent), [40, 40])
    }

    func testSameLabelWindowsWithDifferentResetsRemainIndependent() async {
        let client = RecordingUsageMilestoneNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let firstReset = now.addingTimeInterval(6 * day)
        let secondReset = now.addingTimeInterval(7 * day)
        let current = UsageSnapshot(providers: [ProviderUsage(
            id: "codex",
            name: "Codex",
            plan: "plus",
            error: nil,
            windows: [
                UsageWindow(label: "Weekly", usedPercent: 20, resetDate: firstReset, resetText: nil),
                UsageWindow(label: "Weekly", usedPercent: 20, resetDate: secondReset, resetText: nil)
            ],
            extras: []
        )], fetchedAt: now)

        await coordinator.process(snapshot: current)
        await coordinator.process(snapshot: current)

        XCTAssertEqual(client.sentMilestones.count, 2)
    }

    func testDisabledConfigurationDoesNotInvokePublisher() async {
        let client = RecordingUsageMilestoneNotificationClient()
        let coordinator = makeCoordinator(
            client: client,
            configuration: UsageNtfyConfiguration(
                isEnabled: false,
                executablePath: "/bin/agent-notify",
                configPath: "/tmp/agent-notify.env"
            )
        )

        await coordinator.process(snapshot: snapshot(usedPercent: 50))

        XCTAssertTrue(client.sentMilestones.isEmpty)
    }

    func testChangingStepDoesNotBackfillAlreadyPassedMilestone() async {
        let defaults = makeDefaults()
        let firstClient = RecordingUsageMilestoneNotificationClient()
        let first = makeCoordinator(client: firstClient, defaults: defaults)

        await first.process(snapshot: snapshot(usedPercent: 79))
        XCTAssertEqual(firstClient.sentMilestones.map(\.milestonePercent), [70])

        let secondClient = RecordingUsageMilestoneNotificationClient()
        let second = makeCoordinator(
            client: secondClient,
            defaults: defaults,
            configuration: UsageNtfyConfiguration(
                isEnabled: true,
                executablePath: "/bin/agent-notify",
                configPath: "/tmp/agent-notify.env",
                milestoneStepPercent: 5
            )
        )

        await second.process(snapshot: snapshot(usedPercent: 81))
        XCTAssertTrue(secondClient.sentMilestones.isEmpty)

        await second.process(snapshot: snapshot(usedPercent: 85))
        XCTAssertEqual(secondClient.sentMilestones.map(\.milestonePercent), [85])
    }

    func testChangingStepWithoutExistingStateStartsAtNextConfiguredMilestone() async {
        let client = RecordingUsageMilestoneNotificationClient()
        let coordinator = makeCoordinator(
            client: client,
            configuration: UsageNtfyConfiguration(
                isEnabled: true,
                executablePath: "/bin/agent-notify",
                configPath: "/tmp/agent-notify.env",
                milestoneStepPercent: 5
            )
        )

        await coordinator.process(snapshot: snapshot(usedPercent: 81))
        XCTAssertTrue(client.sentMilestones.isEmpty)

        await coordinator.process(snapshot: snapshot(usedPercent: 85))
        XCTAssertEqual(client.sentMilestones.map(\.milestonePercent), [85])
    }

    private func makeCoordinator(
        client: RecordingUsageMilestoneNotificationClient,
        defaults: UserDefaults? = nil,
        configuration: UsageNtfyConfiguration? = nil
    ) -> UsageMilestoneCoordinator {
        let resolvedDefaults = defaults ?? makeDefaults()
        return UsageMilestoneCoordinator(
            stateStore: UsageMilestoneStateStore(userDefaults: resolvedDefaults),
            notificationClient: client,
            configurationProvider: { configuration ?? .testEnabled }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AiQokkaUsageMilestoneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func snapshot(usedPercent: Double, resetAfter: TimeInterval = 6 * 24 * 60 * 60) -> UsageSnapshot {
        let provider = ProviderUsage(
            id: "codex",
            name: "Codex",
            plan: "plus",
            error: nil,
            windows: [UsageWindow(
                label: "Weekly",
                usedPercent: usedPercent,
                resetDate: now.addingTimeInterval(resetAfter),
                resetText: nil
            )],
            extras: []
        )
        return UsageSnapshot(providers: [provider], fetchedAt: now)
    }

    private var day: TimeInterval { 24 * 60 * 60 }
}

@MainActor
private final class RecordingUsageMilestoneNotificationClient: UsageMilestoneNotificationClient {
    private(set) var sentMilestones: [UsageQuotaMilestone] = []
    private var sendResults: [Bool]

    init(sendResults: [Bool] = []) {
        self.sendResults = sendResults
    }

    func send(
        _ milestone: UsageQuotaMilestone,
        configuration: UsageNtfyConfiguration
    ) async -> Bool {
        sentMilestones.append(milestone)
        if sendResults.isEmpty {
            return true
        }
        return sendResults.removeFirst()
    }
}

private extension UsageNtfyConfiguration {
    static let testEnabled = UsageNtfyConfiguration(
        isEnabled: true,
        executablePath: "/bin/agent-notify",
        configPath: "/tmp/agent-notify.env"
    )
}
