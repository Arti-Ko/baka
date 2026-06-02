import XCTest
@testable import baka

/// Sprint 3 — locks the `WallpaperKind` metadata that drives renderer selection,
/// workshop filtering, and the preview UI (live controls vs poster note).
final class WallpaperKindTests: XCTestCase {

    func testOnlyVideoAndWebAreLiveRendered() {
        XCTAssertTrue(WallpaperKind.video.isLiveRendered)
        XCTAssertTrue(WallpaperKind.web.isLiveRendered)
        XCTAssertFalse(WallpaperKind.scene.isLiveRendered)
        XCTAssertFalse(WallpaperKind.application.isLiveRendered)
    }

    func testWorkshopTagsMatchSteamValues() {
        XCTAssertEqual(WallpaperKind.video.workshopTag, "Video")
        XCTAssertEqual(WallpaperKind.web.workshopTag, "Web")
        XCTAssertEqual(WallpaperKind.scene.workshopTag, "Scene")
        XCTAssertEqual(WallpaperKind.application.workshopTag, "Application")
    }

    func testEveryKindHasABadgeAndSymbol() {
        for kind in WallpaperKind.allCases {
            XCTAssertFalse(kind.badgeText.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.displayName.isEmpty)
        }
    }

    func testTypeFilterDefaultsToLiveTypes() {
        // The default Workshop filter shows the live types, not Scene/App.
        XCTAssertEqual(WallpaperTypeFilter.both.kinds, [.video, .web])
        XCTAssertEqual(WallpaperTypeFilter.scene.kinds, [.scene])
        XCTAssertEqual(WallpaperTypeFilter.application.kinds, [.application])
    }
}
