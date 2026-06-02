import XCTest
@testable import baka

/// Tests the on-disk project parser, especially the salvage path that rescues
/// mistagged items (the cause of "формат не поддерживается" on real downloads).
final class WorkshopProjectTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baka-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ name: String, _ contents: String = "x") throws {
        try contents.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testParsesDeclaredVideo() throws {
        try write("project.json", #"{"type":"video","file":"clip.mp4","title":"Nice"}"#)
        try write("clip.mp4")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .video)
        XCTAssertEqual(project.title, "Nice")
        XCTAssertEqual(project.contentFile.lastPathComponent, "clip.mp4")
    }

    func testSalvagesMistaggedSceneContainingVideo() throws {
        // Declared "scene" but a real mp4 sits in the folder → should play.
        try write("project.json", #"{"type":"scene","file":"scene.pkg"}"#)
        try write("background.mp4")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .video)
        XCTAssertEqual(project.contentFile.lastPathComponent, "background.mp4")
    }

    func testResolvesVideoByScanWhenNamedFileWrong() throws {
        try write("project.json", #"{"type":"video","file":"missing.mp4"}"#)
        try write("actual.webm")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .video)
        XCTAssertEqual(project.contentFile.lastPathComponent, "actual.webm")
    }

    func testReturnsNilForSceneWithNothingDisplayable() throws {
        // Scene with no bundled preview image → nothing to show at all.
        try write("project.json", #"{"type":"scene","file":"scene.pkg"}"#)
        try write("scene.pkg")
        XCTAssertNil(WorkshopProject.load(from: tmp))
    }

    func testSceneWithPreviewBecomesPoster() throws {
        // A genuine Scene that ships a preview → poster, not a failure.
        try write("project.json", #"{"type":"scene","file":"scene.pkg","preview":"preview.gif"}"#)
        try write("scene.pkg")
        try write("preview.gif")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .scene)
        XCTAssertEqual(project.contentFile.lastPathComponent, "preview.gif")
    }

    func testApplicationWithPreviewBecomesPosterApplication() throws {
        try write("project.json", #"{"type":"application","preview":"preview.jpg"}"#)
        try write("app.exe")
        try write("preview.jpg")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .application)
        XCTAssertEqual(project.contentFile.lastPathComponent, "preview.jpg")
    }

    func testSceneFindsAnyImageWhenPreviewFieldMissing() throws {
        // No preview declared, but an image sits in the folder → still a poster.
        try write("project.json", #"{"type":"scene"}"#)
        try write("thumb.png")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .scene)
        XCTAssertEqual(project.contentFile.pathExtension, "png")
    }

    func testInfersWebFromIndexHTMLWithoutProjectJSON() throws {
        try write("index.html", "<html></html>")
        let project = try XCTUnwrap(WorkshopProject.load(from: tmp))
        XCTAssertEqual(project.kind, .web)
        XCTAssertEqual(project.contentFile.lastPathComponent, "index.html")
    }
}
