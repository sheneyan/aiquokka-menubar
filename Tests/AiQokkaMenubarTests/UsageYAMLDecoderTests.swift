@testable import AiQokkaMenubar
import XCTest

final class UsageYAMLDecoderTests: XCTestCase {
    private let decoder = UsageYAMLDecoder()

    func testDecodesAggregateProvidersAndWindowValues() throws {
        let snapshot = try decoder.decode(yaml: fixture(named: "aggregate"), fetchedAt: .distantPast)

        XCTAssertEqual(snapshot.fetchedAt, .distantPast)
        XCTAssertEqual(snapshot.providers.map(\.id), ["codex", "grok"])
        XCTAssertEqual(snapshot.providers.map(\.name), ["Codex", "Grok"])

        let codex = try XCTUnwrap(snapshot.providers.first { $0.id == "codex" })
        XCTAssertEqual(codex.plan, "plus")
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].label, "Weekly")
        XCTAssertEqual(codex.windows[0].usedPercent, 4)
        XCTAssertNotNil(codex.windows[0].resetDate)
        XCTAssertEqual(codex.extras.map(\.value), ["1 (0 usable now)", "110.4952793750"])
    }

    func testAcceptsMissingOptionalFieldsUnknownKeysAndInvalidDates() throws {
        let snapshot = try decoder.decode(yaml: fixture(named: "partial"))

        XCTAssertEqual(snapshot.providers.map(\.id), ["alpha", "zeta"])

        let alpha = try XCTUnwrap(snapshot.providers.first { $0.id == "alpha" })
        XCTAssertNil(alpha.plan)
        XCTAssertTrue(alpha.windows.isEmpty)
        XCTAssertTrue(alpha.extras.isEmpty)

        let zeta = try XCTUnwrap(snapshot.providers.first { $0.id == "zeta" })
        XCTAssertEqual(zeta.windows[0].usedPercent, 12.5)
        XCTAssertNil(zeta.windows[0].resetDate)
        XCTAssertEqual(zeta.windows[0].resetText, "soon")
    }

    func testMalformedYAMLThrowsTypedError() {
        XCTAssertThrowsError(try decoder.decode(yaml: fixture(named: "invalid"))) { error in
            guard case UsageDecodeError.invalidDocument = error else {
                return XCTFail("Expected invalidDocument, got \(error)")
            }
        }
    }

    private func fixture(named name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "yml", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
