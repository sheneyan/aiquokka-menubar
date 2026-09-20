@testable import AiQokkaMenubar
import XCTest

final class UsageValuePresentationTests: XCTestCase {
    func testProviderBalanceSummaryShowsUSDThenCNYRegardlessOfWindowOrder() {
        let provider = ProviderUsage(
            id: "deepseek", name: "DeepSeek", plan: "API", error: nil,
            windows: [
                UsageWindow(label: "CNY", usedPercent: nil, remaining: 95.02, currency: "CNY", resetDate: nil, resetText: nil),
                UsageWindow(label: "USD", usedPercent: nil, remaining: 0, currency: "USD", resetDate: nil, resetText: nil)
            ], extras: []
        )

        XCTAssertEqual(provider.balanceSummaryText, "$0.00 / ¥95.02")
    }

    func testProviderBalanceSummaryUsesOnlyTheSupportedCurrencyPresent() {
        let provider = ProviderUsage(
            id: "deepseek", name: "DeepSeek", plan: "API", error: nil,
            windows: [
                UsageWindow(label: "CNY", usedPercent: nil, remaining: 95.02, currency: "RMB", resetDate: nil, resetText: nil)
            ], extras: []
        )

        XCTAssertEqual(provider.balanceSummaryText, "¥95.02")
    }

    func testProviderBalanceSummaryIsNilWhenAUsagePercentExists() {
        let provider = ProviderUsage(
            id: "deepseek", name: "DeepSeek", plan: "API", error: nil,
            windows: [
                UsageWindow(label: "Usage", usedPercent: 20, resetDate: nil, resetText: nil),
                UsageWindow(label: "CNY", usedPercent: nil, remaining: 95.02, currency: "CNY", resetDate: nil, resetText: nil)
            ], extras: []
        )

        XCTAssertNil(provider.balanceSummaryText)
    }

    func testFormatsCurrencyBalanceWithoutProgress() {
        let value = UsageValuePresentation(window: UsageWindow(
            label: "Balance", usedPercent: nil, remaining: 110, currency: "CNY", resetDate: nil, resetText: nil
        ))

        XCTAssertEqual(value.valueText, "¥110.00")
        XCTAssertNil(value.progressPercent)
        XCTAssertNil(value.detailText)
    }

    func testFormatsUsedAndLimitAsUsagePercent() {
        let value = UsageValuePresentation(window: UsageWindow(
            label: "Bundle", usedPercent: nil, used: 25.5, limit: 100, currency: "TOKENS", resetDate: nil, resetText: nil
        ))

        XCTAssertEqual(value.valueText, "25.5%")
        XCTAssertEqual(value.progressPercent, 25.5)
        XCTAssertEqual(value.detailText, "25.50 / 100.00")
    }
}
