@testable import AiQokkaMenubar
import AppKit
import XCTest

final class MenuBarStatusIconTests: XCTestCase {
    func testStatusIconIsRenderedAsAColoredNonTemplateImage() throws {
        let image = try XCTUnwrap(
            MenuBarStatusIcon.image(
                systemName: "gauge.with.dots.needle.67percent",
                color: .red
            )
        )

        XCTAssertFalse(image.isTemplate)
    }
}
