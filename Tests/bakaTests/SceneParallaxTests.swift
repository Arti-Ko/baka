import XCTest
import CoreGraphics
@testable import baka

/// Scene phase 3 — parallax math: pointer → look vector, depth → offset, and
/// frame-to-frame smoothing.
final class SceneParallaxTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)

    func testLookIsZeroAtScreenCenter() {
        let look = SceneParallax.look(mouse: CGPoint(x: 500, y: 250), in: screen)
        XCTAssertEqual(look.x, 0, accuracy: 0.0001)
        XCTAssertEqual(look.y, 0, accuracy: 0.0001)
    }

    func testLookReachesUnitAtEdges() {
        let topRight = SceneParallax.look(mouse: CGPoint(x: 1000, y: 500), in: screen)
        XCTAssertEqual(topRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(topRight.y, 1, accuracy: 0.0001)
        let bottomLeft = SceneParallax.look(mouse: CGPoint(x: 0, y: 0), in: screen)
        XCTAssertEqual(bottomLeft.x, -1, accuracy: 0.0001)
        XCTAssertEqual(bottomLeft.y, -1, accuracy: 0.0001)
    }

    func testLookClampsBeyondScreen() {
        let look = SceneParallax.look(mouse: CGPoint(x: 5000, y: -5000), in: screen)
        XCTAssertEqual(look.x, 1, accuracy: 0.0001)
        XCTAssertEqual(look.y, -1, accuracy: 0.0001)
    }

    func testOffsetMovesOppositeToLookAndScalesWithDepth() {
        let look = CGPoint(x: 1, y: 0)
        let shallow = SceneParallax.offset(parallaxDepth: CGPoint(x: 0.2, y: 0.2),
                                           look: look, strength: 100)
        let deep = SceneParallax.offset(parallaxDepth: CGPoint(x: 1, y: 1),
                                        look: look, strength: 100)
        // Opposite direction…
        XCTAssertLessThan(shallow.x, 0)
        // …and a deeper layer travels further.
        XCTAssertLessThan(deep.x, shallow.x)
        XCTAssertEqual(deep.x, -100, accuracy: 0.0001)
    }

    func testZeroDepthLayerNeverMoves() {
        let shift = SceneParallax.offset(parallaxDepth: .zero,
                                         look: CGPoint(x: 1, y: -1), strength: 100)
        XCTAssertEqual(shift, .zero)
    }

    func testSmoothingApproachesTargetAndSettles() {
        var current = CGPoint.zero
        let target = CGPoint(x: 1, y: 1)
        for _ in 0..<200 {
            current = SceneParallax.smoothed(current, toward: target, factor: 0.2)
        }
        XCTAssertTrue(SceneParallax.settled(current, target))
    }

    func testSettledRespectsEpsilon() {
        XCTAssertTrue(SceneParallax.settled(CGPoint(x: 0, y: 0), CGPoint(x: 0.0001, y: 0)))
        XCTAssertFalse(SceneParallax.settled(CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0)))
    }

    // MARK: - parallaxDepth parsing

    func testParallaxDepthParsedFromSceneJSON() throws {
        let json = #"{"objects":[{"image":"a.png","origin":"0 0 0","parallaxDepth":"0.5 0.25"}]}"#
            .data(using: .utf8)!
        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertEqual(doc.layers[0].parallaxX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(doc.layers[0].parallaxY, 0.25, accuracy: 0.0001)
    }

    func testParallaxDepthDefaultsToZero() throws {
        let json = #"{"objects":[{"image":"a.png","origin":"0 0 0"}]}"#.data(using: .utf8)!
        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertEqual(doc.layers[0].parallaxX, 0)
        XCTAssertEqual(doc.layers[0].parallaxY, 0)
    }
}
