import XCTest
@testable import baka

/// Scene phase 2 — DXT/BCn block decompression. Hand-builds blocks with known
/// endpoints/indices and verifies exact decoded pixels.
final class BlockTextureCodecTests: XCTestCase {

    // RGB565 endpoints for pure primaries.
    private let red565: UInt16 = 0xF800   // → (255, 0, 0)
    private let blue565: UInt16 = 0x001F  // → (0, 0, 255)

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }

    /// 8-byte color block: two endpoints + 4 index bytes (one per row).
    private func colorBlock(_ c0: UInt16, _ c1: UInt16, indexRows: [UInt8]) -> [UInt8] {
        precondition(indexRows.count == 4)
        return le16(c0) + le16(c1) + indexRows
    }

    private func pixel(_ buf: [UInt8], _ x: Int, _ y: Int, width: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(buf[i..<i + 4])
    }

    // MARK: - DXT1

    func testDXT1SolidColorFromIndexZero() throws {
        // c0 = red, indices all 0 → every pixel red, opaque.
        let block = colorBlock(red565, blue565, indexRows: [0, 0, 0, 0])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(block), width: 4, height: 4, format: .dxt1))
        XCTAssertEqual(pixel(out, 0, 0, width: 4), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 3, 3, width: 4), [255, 0, 0, 255])
    }

    func testDXT1IndexOneSelectsSecondEndpoint() throws {
        // All indices = 1 → every pixel = c1 (blue). Each 2-bit slot = 01 → byte 0x55.
        let block = colorBlock(red565, blue565, indexRows: [0x55, 0x55, 0x55, 0x55])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(block), width: 4, height: 4, format: .dxt1))
        XCTAssertEqual(pixel(out, 0, 0, width: 4), [0, 0, 255, 255])
    }

    func testDXT1PunchThroughAlpha() throws {
        // c0 <= c1 → 3-color mode; index 3 is transparent black.
        // Put index 3 (0b11) in pixel (0,0): row0 byte low bits = 0b11 = 0x03.
        let block = colorBlock(blue565, red565, indexRows: [0x03, 0, 0, 0])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(block), width: 4, height: 4, format: .dxt1))
        XCTAssertEqual(pixel(out, 0, 0, width: 4), [0, 0, 0, 0]) // transparent
        XCTAssertEqual(pixel(out, 1, 0, width: 4), [0, 0, 255, 255]) // index 0 = c0 = blue
    }

    // MARK: - DXT3 (explicit alpha)

    func testDXT3ExplicitAlpha() throws {
        // Alpha block: pixel0 nibble 0x8 (→136), pixel1 nibble 0xF (→255).
        var bytes: [UInt8] = [0xF8] + [UInt8](repeating: 0xFF, count: 7) // first byte: low=8, high=F
        // Color block (opaque red, all index 0).
        bytes += colorBlock(red565, blue565, indexRows: [0, 0, 0, 0])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(bytes), width: 4, height: 4, format: .dxt3))
        XCTAssertEqual(pixel(out, 0, 0, width: 4), [255, 0, 0, 136])
        XCTAssertEqual(pixel(out, 1, 0, width: 4), [255, 0, 0, 255])
    }

    // MARK: - DXT5 (interpolated alpha)

    func testDXT5InterpolatedAlphaEndpoints() throws {
        // a0=255, a1=0; indices all 0 → alpha 255 everywhere.
        var bytes: [UInt8] = [255, 0] + [UInt8](repeating: 0, count: 6)
        bytes += colorBlock(red565, blue565, indexRows: [0, 0, 0, 0])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(bytes), width: 4, height: 4, format: .dxt5))
        XCTAssertEqual(pixel(out, 0, 0, width: 4), [255, 0, 0, 255])
    }

    func testDXT5AlphaIndexSelectsSecondEndpoint() throws {
        // pixel0 alpha index = 1 → alpha = a1 = 0. 3-bit index 1 in first index byte.
        var bytes: [UInt8] = [255, 0, 0x01, 0, 0, 0, 0, 0]
        bytes += colorBlock(red565, blue565, indexRows: [0, 0, 0, 0])
        let out = try XCTUnwrap(BlockTextureCodec.decode(Data(bytes), width: 4, height: 4, format: .dxt5))
        XCTAssertEqual(pixel(out, 0, 0, width: 4)[3], 0)        // transparent
        XCTAssertEqual(pixel(out, 1, 0, width: 4)[3], 255)      // index 0 → a0
    }

    // MARK: - Geometry / safety

    func testNonMultipleOfFourDimensionsClipCleanly() throws {
        // 5×5 needs a 2×2 block grid; 4 identical red blocks.
        let oneBlock = colorBlock(red565, blue565, indexRows: [0, 0, 0, 0])
        let data = Data(oneBlock + oneBlock + oneBlock + oneBlock)
        let out = try XCTUnwrap(BlockTextureCodec.decode(data, width: 5, height: 5, format: .dxt1))
        XCTAssertEqual(out.count, 5 * 5 * 4)
        XCTAssertEqual(pixel(out, 4, 4, width: 5), [255, 0, 0, 255])
    }

    func testReturnsNilWhenDataTooSmall() {
        XCTAssertNil(BlockTextureCodec.decode(Data([0, 0, 0]), width: 4, height: 4, format: .dxt5))
    }
}
