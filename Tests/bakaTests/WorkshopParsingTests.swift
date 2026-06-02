import XCTest
@testable import baka

/// Tests the pure parsing logic of the Steam Workshop client — the highest-risk
/// piece since it consumes reverse-engineered, externally-controlled responses.
final class WorkshopParsingTests: XCTestCase {

    // MARK: - ID extraction from browse HTML

    func testExtractsPublishedFileIDsInOrderWithoutDuplicates() {
        let html = """
        <div class="item">
          <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=111">A</a>
          <img src="https://.../filedetails/?id=111">
        </div>
        <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=222">B</a>
        <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=111">dup</a>
        """

        let ids = SteamWorkshopClient.extractPublishedFileIDs(from: html)

        XCTAssertEqual(ids, ["111", "222"])
    }

    func testInterleaveMergesAndDedupes() {
        let a = [item("1"), item("2"), item("3")]
        let b = [item("4"), item("2"), item("5")] // "2" duplicates a
        let merged = SteamWorkshopClient.interleave([a, b]).map(\.id)
        // Round-robin order, duplicate "2" kept only once (first occurrence).
        XCTAssertEqual(merged, ["1", "4", "2", "3", "5"])
    }

    private func item(_ id: String) -> WorkshopItem {
        WorkshopItem(id: id, title: id, previewURL: nil, author: nil,
                     fileURL: nil, kind: .video, tags: [])
    }

    func testReturnsEmptyWhenNoIDsPresent() {
        let ids = SteamWorkshopClient.extractPublishedFileIDs(from: "<html>nothing</html>")
        XCTAssertTrue(ids.isEmpty)
    }

    // MARK: - Details JSON parsing

    func testParsesVideoAndWebDetailsAndSkipsUnsupported() throws {
        let json = """
        {
          "response": {
            "publishedfiledetails": [
              {
                "publishedfileid": "222", "result": 1, "title": "Web One",
                "preview_url": "https://img/2.jpg", "file_url": "",
                "tags": [{"tag": "Web"}]
              },
              {
                "publishedfileid": "111", "result": 1, "title": "Video One",
                "preview_url": "https://img/1.jpg",
                "file_url": "https://cdn/clip.mp4",
                "tags": [{"tag": "Video"}, {"tag": "Nature"}]
              },
              {
                "publishedfileid": "333", "result": 1, "title": "Scene One",
                "tags": [{"tag": "Scene"}]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let items = SteamWorkshopClient.parseDetails(json, order: ["111", "222", "333"])

        // Order is preserved per the requested id order.
        XCTAssertEqual(items.map(\.id), ["111", "222", "333"])

        let video = items[0]
        XCTAssertEqual(video.kind, .video)
        XCTAssertEqual(video.fileURL?.absoluteString, "https://cdn/clip.mp4")
        XCTAssertTrue(video.isDirectlyDownloadable)

        let web = items[1]
        XCTAssertEqual(web.kind, .web)
        // Empty file_url must become nil, not an empty URL.
        XCTAssertNil(web.fileURL)
        XCTAssertFalse(web.isDirectlyDownloadable)

        // Scene now maps to the .scene kind (rendered as a poster), so it is no
        // longer dropped from results.
        XCTAssertEqual(items[2].kind, .scene)
    }

    func testParsesSceneAndApplicationKinds() {
        let json = """
        {"response": {"publishedfiledetails": [
          {"publishedfileid": "1", "result": 1, "title": "Scene", "tags": [{"tag": "Scene"}]},
          {"publishedfileid": "2", "result": 1, "title": "App", "tags": [{"tag": "Application"}]},
          {"publishedfileid": "3", "result": 1, "title": "Untyped", "tags": [{"tag": "Anime"}]}
        ]}}
        """.data(using: .utf8)!

        let items = SteamWorkshopClient.parseDetails(json, order: ["1", "2", "3"])
        XCTAssertEqual(items[0].kind, .scene)
        XCTAssertEqual(items[1].kind, .application)
        XCTAssertNil(items[2].kind) // genuinely untyped → no kind
    }

    func testSkipsEntriesWithNonSuccessResult() {
        let json = """
        {"response": {"publishedfiledetails": [
          {"publishedfileid": "1", "result": 9, "title": "Gone", "tags": [{"tag":"Video"}]}
        ]}}
        """.data(using: .utf8)!

        let items = SteamWorkshopClient.parseDetails(json, order: ["1"])
        XCTAssertTrue(items.isEmpty)
    }

    func testParsesDespiteRawControlCharactersInDescription() {
        // Steam returns unescaped \r\n inside descriptions — invalid JSON that
        // would otherwise make the whole page fail to parse.
        let json = """
        {"response": {"publishedfiledetails": [
          {"publishedfileid": "1", "result": 1, "title": "Has Newline",
           "description": "line one\r\nline two\u{01}", "preview_url": "https://i/1.jpg",
           "file_url": "", "tags": [{"tag": "Video"}]}
        ]}}
        """.data(using: .utf8)!

        let items = SteamWorkshopClient.parseDetails(json, order: ["1"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .video)
        XCTAssertEqual(items.first?.title, "Has Newline")
    }

    func testBrowseURLFiltersByTypeTag() {
        var query = WorkshopQuery()
        query.type = .web
        query.sort = .topRated
        query.categories = ["Anime"]
        query.resolution = "3840 x 2160"
        let url = SteamWorkshopClient.browseURL(for: query, kind: .web)?.absoluteString ?? ""

        XCTAssertTrue(url.contains("appid=431960"))
        XCTAssertTrue(url.contains("requiredtags%5B%5D=Web"))
        XCTAssertTrue(url.contains("requiredtags%5B%5D=Anime"))
        XCTAssertTrue(url.contains("browsesort=toprated"))
        XCTAssertTrue(url.contains("3840"))
    }

    func testReturnsEmptyOnMalformedJSON() {
        let items = SteamWorkshopClient.parseDetails(Data("not json".utf8), order: ["1"])
        XCTAssertTrue(items.isEmpty)
    }
}
