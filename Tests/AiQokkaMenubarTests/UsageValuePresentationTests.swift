@testable import AiQokkaMenubar
import XCTest

final class UsageValuePresentationTests: XCTestCase {
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
