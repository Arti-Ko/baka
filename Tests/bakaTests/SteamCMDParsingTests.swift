import XCTest
@testable import baka

/// Tests the pure output-classification logic of SteamCMD. These guard against
/// the regression where "using cached credentials" (a success message) was
/// misread as a logout, breaking downloads.
final class SteamCMDParsingTests: XCTestCase {

    func testExtractsFinishedItemID() {
        let line = #"Success. Downloaded item 1234567890 to "/path/431960/1234567890" (5 bytes)"#
        XCTAssertEqual(SteamCMD.extractFinishedItemID(line), "1234567890")
    }

    func testFinishedItemIDNilForUnrelatedLine() {
        XCTAssertNil(SteamCMD.extractFinishedItemID("Logging in user 'x' to Steam Public..."))
        XCTAssertNil(SteamCMD.extractFinishedItemID("Downloading item 999")) // not "Downloaded"
    }

    func testCachedCredentialsIsNotALoginFailure() {
        // The exact false positive that broke sessions before.
        let output = "Logging in user 'x'...\nWaiting for user info...OK\nusing cached credentials"
        XCTAssertFalse(SteamCMD.indicatesLoginFailure(output))
    }

    func testDetectsGenuineLoginFailures() {
        XCTAssertTrue(SteamCMD.indicatesLoginFailure("FAILED login with result code Login Failure"))
        XCTAssertTrue(SteamCMD.indicatesLoginFailure("Rate Limit Exceeded"))
        XCTAssertTrue(SteamCMD.indicatesLoginFailure("Invalid Password"))
        XCTAssertTrue(SteamCMD.indicatesLoginFailure("Account Logon Denied"))
    }

    func testClassifyLoginSuccess() {
        XCTAssertEqual(SteamCMD.classifyLogin("Waiting for user info...OK"), .success)
    }

    func testClassifyLoginNeedsGuard() {
        XCTAssertEqual(SteamCMD.classifyLogin("Steam Guard code:"), .needsSteamGuard)
    }
}
