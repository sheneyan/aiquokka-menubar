@testable import AiQokkaMenubar
import Foundation
import XCTest

final class UsageAlertEvaluatorTests: XCTestCase {
    func testUsedAndLimitCanTriggerTheEightyPercentAlert() {
        let window = UsageWindow(label: "API", usedPercent: nil, used: 80, limit: 100, resetDate: nil, resetText: nil)
        let snapshot = UsageSnapshot(providers: [ProviderUsage(id: "deepseek", name: "DeepSeek", plan: nil, error: nil, windows: [window], extras: [])], fetchedAt: .distantPast)

        XCTAssertEqual(UsageAlertEvaluator().evaluate(snapshot: snapshot, now: .distantPast).windows.first?.selectedAlert?.kind, .nearingLimit)
    }
    private let evaluator = UsageAlertEvaluator()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testUsageBelowTwentyPercentDoesNotTriggerPaceAlert() {
        let evaluation = evaluate(usedPercent: 19, label: "Weekly", resetAfter: 6 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testTwentyPercentUsageTriggersTooFastWhenWindowJustStarted() throws {
        let evaluation = evaluate(usedPercent: 20, label: "Weekly", resetAfter: 7 * day)

        let alert = try XCTUnwrap(evaluation.alerts.first)
        XCTAssertEqual(alert.kind, .tooFast)
    }

    func testWeeklyUsageFifteenPointsAheadOfClockTriggersTooFast() throws {
        let evaluation = evaluate(usedPercent: 30, label: "Weekly", resetAfter: 6 * day)

        let alert = try XCTUnwrap(evaluation.alerts.first)
        XCTAssertEqual(alert.kind, .tooFast)
    }

    func testPaceGapBelowFifteenPointsDoesNotTrigger() {
        let evaluation = evaluate(usedPercent: 29, label: "Weekly", resetAfter: 6 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testExactFifteenPointPaceGapTriggersTooFast() throws {
        let timeProgress = (day / (7 * day)) * 100
        let evaluation = evaluate(
            usedPercent: timeProgress + 15,
            label: "Weekly",
            resetAfter: 6 * day
        )

        let alert = try XCTUnwrap(evaluation.alerts.first)
        XCTAssertEqual(alert.kind, .tooFast)
    }

    func testEightyAndNinetyFivePercentSelectDifferentLevels() throws {
        let warning = try XCTUnwrap(evaluate(usedPercent: 80, label: "Weekly").alerts.first)
        let critical = try XCTUnwrap(evaluate(usedPercent: 95, label: "Weekly").alerts.first)

        XCTAssertEqual(warning.kind, .nearingLimit)
        XCTAssertEqual(critical.kind, .critical)
    }

    func testUnknownDurationDoesNotTriggerPaceAlert() {
        let evaluation = evaluate(usedPercent: 30, label: "Custom Window", resetAfter: 1 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testMissingOrExpiredResetDoesNotTriggerPaceAlert() {
        let missingReset = evaluate(usedPercent: 30, label: "Weekly", resetAfter: nil)
        let expiredReset = evaluate(usedPercent: 30, label: "Weekly", resetAfter: -1)

        XCTAssertTrue(missingReset.alerts.isEmpty)
        XCTAssertTrue(expiredReset.alerts.isEmpty)
    }

    func testProviderErrorsDoNotTriggerAlerts() {
        let snapshot = UsageSnapshot(
            providers: [ProviderUsage(
                id: "codex",
                name: "Codex",
                plan: nil,
                error: "network error",
                windows: [UsageWindow(label: "Weekly", usedPercent: 95, resetDate: now.addingTimeInterval(6 * day), resetText: nil)],
                extras: []
            )],
            fetchedAt: now
        )

        XCTAssertTrue(evaluator.evaluate(snapshot: snapshot, now: now).alerts.isEmpty)
    }

    func testAlertSeverityExposesTheMenuBarSymbols() {
        XCTAssertEqual(UsageAlertSeverity.normal.systemImageName, "gauge.with.dots.needle.67percent")
        XCTAssertEqual(UsageAlertSeverity.warning.systemImageName, "gauge.with.dots.needle.67percent")
        XCTAssertEqual(UsageAlertSeverity.critical.systemImageName, "gauge.with.dots.needle.67percent")
    }

    private var day: TimeInterval { 24 * 60 * 60 }

    private func evaluate(usedPercent: Double, label: String, resetAfter: TimeInterval? = 6 * 24 * 60 * 60) -> UsageAlertEvaluation {
        let resetDate = resetAfter.map { now.addingTimeInterval($0) }
        let window = UsageWindow(label: label, usedPercent: usedPercent, resetDate: resetDate, resetText: nil)
        let provider = ProviderUsage(id: "codex", name: "Codex", plan: "plus", error: nil, windows: [window], extras: [])
        let snapshot = UsageSnapshot(providers: [provider], fetchedAt: now)
        return evaluator.evaluate(snapshot: snapshot, now: now)
    }
}
