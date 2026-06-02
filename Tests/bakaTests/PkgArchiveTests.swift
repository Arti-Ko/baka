import XCTest
@testable import baka

/// Sprint 2 — Wallpaper Engine `.pkg` container parsing. Builds synthetic
/// packages in-memory and verifies entry extraction, bounds safety on malformed
/// input, and path-traversal protection.
final class PkgArchiveTests: XCTestCase {

    /// Builds a minimal valid `.pkg` blob from (path, bytes) pairs.
    private func makePackage(version: String = "PKGV0001",
                             entries: [(String, [UInt8])]) -> Data {
        func int32(_ value: Int) -> [UInt8] {
            let v = UInt32(bitPattern: Int32(value))
            return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                    UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        func string(_ s: String) -> [UInt8] {
            let bytes = Array(s.utf8)
            return int32(bytes.count) + bytes
        }

        var header: [UInt8] = []
        header += string(version)
        header += int32(entries.count)

        // Lay payloads out back-to-back; offsets are relative to header end.
        var payload: [UInt8] = []
        var offset = 0
        for (path, bytes) in entries {
            header += string(path)
            header += int32(offset)
            header += int32(bytes.count)
            payload += bytes
            offset += bytes.count
        }
        return Data(header + payload)
    }

    func testExtractsEntriesWithCorrectBytes() throws {
        let pkg = makePackage(entries: [
            ("materials/bg.mp4", Array("VIDEOBYTES".utf8)),
            ("scene.json", Array("{}".utf8)),
        ])
        let entries = try PkgArchive.extract(from: pkg)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "materials/bg.mp4")
        XCTAssertEqual(String(decoding: entries[0].data, as: UTF8.self), "VIDEOBYTES")
        XCTAssertEqual(entries[1].path, "scene.json")
        XCTAssertEqual(String(decoding: entries[1].data, as: UTF8.self), "{}")
    }

    func testParsesNewerVersionStrings() throws {
        let pkg = makePackage(version: "PKGV0018", entries: [("a.png", [1, 2, 3])])
        let entries = try PkgArchive.extract(from: pkg)
        XCTAssertEqual(entries.first?.data, Data([1, 2, 3]))
    }

    func testRejectsNonPackageMagic() {
        let notPkg = Data([4, 0, 0, 0] + Array("ZZZZ".utf8))
        XCTAssertThrowsError(try PkgArchive.extract(from: notPkg)) { error in
            XCTAssertEqual(error as? PkgArchive.PkgError, .notAPackage)
        }
    }

    func testThrowsOnTruncatedData() {
        // Valid header claims an entry whose payload runs past the buffer.
        var bytes = makePackage(entries: [("clip.mp4", Array("12345".utf8))])
        bytes.removeLast(3) // chop the payload
        XCTAssertThrowsError(try PkgArchive.extract(from: bytes))
    }

    func testDoesNotTrapOnGarbage() {
        // Random bytes must throw, never crash.
        let garbage = Data((0..<64).map { UInt8(($0 * 37) & 0xFF) })
        XCTAssertThrowsError(try PkgArchive.extract(from: garbage))
    }

    // MARK: - Renderable-asset filtering

    func testOnlyRenderableAssetsAreSelected() {
        XCTAssertTrue(PkgArchive.isRenderableAsset("bg.mp4"))
        XCTAssertTrue(PkgArchive.isRenderableAsset("art/poster.gif"))
        XCTAssertTrue(PkgArchive.isRenderableAsset("index.html"))
        XCTAssertFalse(PkgArchive.isRenderableAsset("textures/t.tex"))
        XCTAssertFalse(PkgArchive.isRenderableAsset("scene.json"))
        XCTAssertFalse(PkgArchive.isRenderableAsset("model.mdl"))
    }

    // MARK: - Path-traversal safety

    func testSafeDestinationResolvesNormalPath() {
        let root = URL(fileURLWithPath: "/content/ws-1")
        let dest = PkgArchive.safeDestination(for: "materials/bg.mp4", under: root)
        XCTAssertEqual(dest?.path, "/content/ws-1/materials/bg.mp4")
    }

    func testSafeDestinationRejectsTraversal() {
        let root = URL(fileURLWithPath: "/content/ws-1")
        XCTAssertNil(PkgArchive.safeDestination(for: "../../etc/passwd", under: root))
        XCTAssertNil(PkgArchive.safeDestination(for: "/etc/passwd", under: root))
        XCTAssertNil(PkgArchive.safeDestination(for: "a/../../b", under: root))
    }

    // MARK: - End-to-end unpack onto disk

    func testUnpackWritesRenderableAssetsAndSkipsTextures() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baka-pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let pkg = makePackage(entries: [
            ("bg.mp4", Array("MOVIE".utf8)),
            ("tex/atlas.tex", Array("RAWTEX".utf8)),
        ])
        let pkgURL = dir.appendingPathComponent("scene.pkg")
        try pkg.write(to: pkgURL)

        PkgArchive.unpack(pkgURL, into: dir)

        let video = dir.appendingPathComponent("bg.mp4")
        let tex = dir.appendingPathComponent("tex/atlas.tex")
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tex.path)) // textures skipped
        XCTAssertEqual(try String(contentsOf: video, encoding: .utf8), "MOVIE")
    }
}
