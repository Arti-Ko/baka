import XCTest
@testable import baka

final class AppVersionTests: XCTestCase {
    func testNewerDetection() {
        XCTAssertTrue(AppVersion.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppVersion.isNewer("v1.0.0", than: "0.9.9"))
        XCTAssertTrue(AppVersion.isNewer("0.1.1", than: "0.1.0"))
        XCTAssertTrue(AppVersion.isNewer("1.0.0", than: "0.99.99"))
    }

    func testNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertFalse(AppVersion.isNewer("v0.1.0", than: "v0.1.0"))
    }

    func testComponentParsing() {
        XCTAssertEqual(AppVersion.components("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(AppVersion.components("0.1"), [0, 1, 0])
        XCTAssertEqual(AppVersion.components("2"), [2, 0, 0])
    }
}
