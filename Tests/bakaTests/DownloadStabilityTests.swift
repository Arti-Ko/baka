import XCTest
@testable import baka

/// Sprint 1 — download/library stability: disk reconciliation, symlink-safe
/// path remapping, and transient-network retry policy.
final class DownloadStabilityTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baka-stab-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Library reconciliation

    func testStaleEntriesAreThoseWithMissingContent() throws {
        let present = tmp.appendingPathComponent("here.mp4")
        try "x".write(to: present, atomically: true, encoding: .utf8)
        let missing = tmp.appendingPathComponent("gone.mp4")

        let alive = Wallpaper(id: "a", title: "a", kind: .video, contentURL: present)
        let dead = Wallpaper(id: "b", title: "b", kind: .video, contentURL: missing)
        let notInstalled = Wallpaper(id: "c", title: "c", kind: .video, contentURL: nil)

        let stale = WallpaperLibrary.staleEntries([alive, dead, notInstalled]).map(\.id)
        XCTAssertEqual(stale, ["b"]) // only the one whose file vanished
    }

    func testOrphanFoldersAreUnknownIDs() throws {
        let fm = FileManager.default
        for id in ["ws-1", "ws-2", "ws-orphan"] {
            try fm.createDirectory(at: tmp.appendingPathComponent(id), withIntermediateDirectories: true)
        }
        let orphans = WallpaperLibrary
            .orphanFolders(in: tmp, knownIDs: ["ws-1", "ws-2"])
            .map(\.lastPathComponent)
        XCTAssertEqual(orphans, ["ws-orphan"])
    }

    // MARK: - Symlink-safe path remap

    func testRemapRebuildsPathUnderNewRoot() {
        let src = URL(fileURLWithPath: "/old/root")
        let dst = URL(fileURLWithPath: "/new/dest")
        let content = src.appendingPathComponent("assets/clip.mp4")
        let mapped = WorkshopInstaller.remap(content, from: src, to: dst)
        XCTAssertEqual(mapped?.path, "/new/dest/assets/clip.mp4")
    }

    func testRemapSurvivesSymlinkedRoot() throws {
        // Simulate the /var → /private/var symlink that broke the old string
        // replacement: source folder reported via /var, content via /private/var.
        let real = tmp.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let content = real.appendingPathComponent("index.html")
        try "x".write(to: content, atomically: true, encoding: .utf8)

        let dest = URL(fileURLWithPath: "/dest")
        // Pass the *symlinked* root as the source — remap must still resolve it.
        let mapped = WorkshopInstaller.remap(content, from: link, to: dest)
        XCTAssertEqual(mapped?.lastPathComponent, "index.html")
        XCTAssertEqual(mapped?.deletingLastPathComponent().lastPathComponent, "dest")
    }

    func testRemapReturnsNilWhenOutsideRoot() {
        let mapped = WorkshopInstaller.remap(
            URL(fileURLWithPath: "/somewhere/else/file.mp4"),
            from: URL(fileURLWithPath: "/old/root"),
            to: URL(fileURLWithPath: "/new/dest")
        )
        XCTAssertNil(mapped)
    }

    // MARK: - Retry policy

    func testTransientErrorsAreRetryable() {
        XCTAssertTrue(SteamWorkshopClient.isTransient(URLError(.timedOut)))
        XCTAssertTrue(SteamWorkshopClient.isTransient(URLError(.networkConnectionLost)))
        XCTAssertFalse(SteamWorkshopClient.isTransient(URLError(.badURL)))
        XCTAssertFalse(SteamWorkshopClient.isTransient(URLError(.userAuthenticationRequired)))
    }

    func testBackoffGrowsExponentiallyAndCaps() {
        XCTAssertEqual(SteamWorkshopClient.backoffNanos(attempt: 1), 400_000_000)
        XCTAssertEqual(SteamWorkshopClient.backoffNanos(attempt: 2), 800_000_000)
        XCTAssertEqual(SteamWorkshopClient.backoffNanos(attempt: 3), 1_600_000_000)
        // Clamped so a runaway attempt count can't overflow the shift.
        XCTAssertEqual(SteamWorkshopClient.backoffNanos(attempt: 99),
                       SteamWorkshopClient.backoffNanos(attempt: 5))
    }
}
