@testable import AiQokkaMenubar
import XCTest

final class UsageQuotaLevelTests: XCTestCase {
    func testRemainingQuotaUsesGreenYellowRedBands() {
        XCTAssertEqual(UsageQuotaLevel(usedPercent: 59.9), .healthy)
        XCTAssertEqual(UsageQuotaLevel(usedPercent: 60), .warning)
        XCTAssertEqual(UsageQuotaLevel(usedPercent: 79.9), .warning)
        XCTAssertEqual(UsageQuotaLevel(usedPercent: 80), .critical)
    }
}
