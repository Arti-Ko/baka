import XCTest
@testable import baka

/// Scene phase 1 — `scene.json` parsing and the model/material → texture
/// resolution chain.
final class SceneDocumentTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baka-scene-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ relative: String, _ contents: String) throws {
        let url = tmp.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - scene.json parsing

    func testParsesProjectionAndImageLayersSkippingParticles() throws {
        let json = """
        {
          "general": { "orthogonalprojection": { "width": 2560, "height": 1440 } },
          "objects": [
            { "image": "models/bg.json", "origin": "1280 720 0", "alpha": 1 },
            { "particle": "particles/snow.json", "origin": "0 0 0" },
            { "image": "models/fg.json", "origin": "1280 200 0", "alpha": "0.5", "visible": false }
          ]
        }
        """.data(using: .utf8)!

        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertEqual(doc.projectionWidth, 2560)
        XCTAssertEqual(doc.projectionHeight, 1440)
        // Particle object is dropped; two image layers remain in order.
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.layers[0].imageRef, "models/bg.json")
        XCTAssertEqual(doc.layers[0].originX, 1280)
        XCTAssertEqual(doc.layers[0].originY, 720)
        XCTAssertTrue(doc.layers[0].visible)
        XCTAssertEqual(doc.layers[1].alpha, 0.5, accuracy: 0.001)
        XCTAssertFalse(doc.layers[1].visible)
    }

    func testReturnsNilWhenNoImageLayers() {
        let json = #"{"objects":[{"particle":"p.json"},{"sound":"s.json"}]}"#.data(using: .utf8)!
        XCTAssertNil(SceneDocument.parse(json))
    }

    func testDefaultsProjectionWhenMissing() throws {
        let json = #"{"objects":[{"image":"a.png","origin":"0 0 0"}]}"#.data(using: .utf8)!
        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertEqual(doc.projectionWidth, 1920)
        XCTAssertEqual(doc.projectionHeight, 1080)
    }

    func testVectorParsing() {
        XCTAssertEqual(SceneDocument.vector("3 4 5", count: 3), [3, 4, 5])
        XCTAssertEqual(SceneDocument.vector("7 8", count: 3), [7, 8, 0]) // padded
        XCTAssertEqual(SceneDocument.vector(nil, count: 2), [0, 0])
    }

    // MARK: - Material/texture resolution

    func testResolvesModelThroughMaterialToTexFile() throws {
        try write("models/bg.json", #"{"material":"materials/bg.json"}"#)
        try write("materials/bg.json", #"{"passes":[{"textures":["materials/bg"]}]}"#)
        try write("materials/bg.tex", "TEXDATA")

        let url = SceneAssetResolver.textureURL(for: "models/bg.json", in: tmp)
        XCTAssertEqual(url?.lastPathComponent, "bg.tex")
    }

    func testResolvesDirectImageReference() throws {
        try write("art/poster.png", "PNG")
        let url = SceneAssetResolver.textureURL(for: "art/poster.png", in: tmp)
        XCTAssertEqual(url?.lastPathComponent, "poster.png")
    }

    func testFirstTextureFromMaterialDictionary() {
        let material: [String: Any] = ["passes": [["textures": ["", "materials/real"]]]]
        XCTAssertEqual(SceneAssetResolver.firstTexture(inMaterial: material), "materials/real")
    }

    func testReturnsNilWhenTextureMissing() {
        XCTAssertNil(SceneAssetResolver.textureURL(for: "models/nope.json", in: tmp))
    }
}
