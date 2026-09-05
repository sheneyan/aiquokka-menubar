@testable import AiQokkaMenubar
import Foundation
import XCTest

final class MenuBarStatusPresentationTests: XCTestCase {
    func testProviderReadFailureUsesRedGaugeEvenWhenUsageSeverityIsNormal() {
        let snapshot = UsageSnapshot(
            providers: [ProviderUsage(
                id: "grok",
                name: "grok",
                plan: nil,
                error: "connection refused",
                windows: [],
                extras: []
            )],
            fetchedAt: Date()
        )

        let presentation = MenuBarStatusPresentation(
            snapshot: snapshot,
            lastError: nil,
            severity: .normal
        )

        XCTAssertEqual(presentation.color, .red)
        XCTAssertEqual(presentation.symbolName, "gauge.with.dots.needle.67percent")
    }

    func testRefreshFailureWithNoSnapshotUsesRedGauge() {
        let presentation = MenuBarStatusPresentation(
            snapshot: nil,
            lastError: "network unavailable",
            severity: .normal
        )

        XCTAssertEqual(presentation.color, .red)
        XCTAssertEqual(presentation.symbolName, "gauge.with.dots.needle.67percent")
    }

    func testSuccessfulSnapshotKeepsUsageSeverityColor() {
        let snapshot = UsageSnapshot(
            providers: [ProviderUsage(
                id: "codex",
                name: "Codex",
                plan: "plus",
                error: nil,
                windows: [UsageWindow(label: "Weekly", usedPercent: 80, resetDate: nil, resetText: nil)],
                extras: []
            )],
            fetchedAt: Date()
        )

        let presentation = MenuBarStatusPresentation(
            snapshot: snapshot,
            lastError: nil,
            severity: .warning
        )

        XCTAssertEqual(presentation.color, .yellow)
        XCTAssertEqual(presentation.symbolName, "gauge.with.dots.needle.67percent")
    }
}
