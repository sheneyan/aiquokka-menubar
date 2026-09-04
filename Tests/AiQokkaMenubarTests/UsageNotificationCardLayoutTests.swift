@testable import AiQokkaMenubar
import AppKit
import SwiftUI
import XCTest

@MainActor
final class UsageNotificationCardLayoutTests: XCTestCase {
    func testLongMessageWrapsInsideTheFixedCardWidth() {
        let view = UsageNotificationCard(
            systemImage: "bell.badge",
            title: "开启用量提醒",
            message: "点击“开启”后，macOS 会弹出通知授权提示，并在用量过快或接近上限时提醒你。",
            actionTitle: "开启",
            isRequesting: false,
            action: {}
        )
        .frame(width: 380)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)

        XCTAssertGreaterThan(hostingView.fittingSize.height, 65)
    }
}
