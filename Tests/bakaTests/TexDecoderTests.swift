import XCTest
import AppKit
import Compression
@testable import baka

/// Scene phase 1 — `.tex` texture decoding: FreeImage-wrapped, raw RGBA8888,
/// and LZ4-compressed mips, plus bounds safety on malformed data.
final class TexDecoderTests: XCTestCase {

    // MARK: - Byte builders

    private func i32(_ value: Int) -> [UInt8] {
        let v = UInt32(bitPattern: Int32(value))
        return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    private func str(_ s: String) -> [UInt8] { i32(s.utf8.count) + Array(s.utf8) }

    private func makeTex(format: Int, container: String, freeImageFormat: Int?,
                         mipW: Int, mipH: Int, isLZ4: Bool, decompressedSize: Int,
                         payload: [UInt8]) -> Data {
        let version = Int(container.drop { !$0.isNumber }) ?? 1
        var bytes: [UInt8] = []
        bytes += str("TEXV0005")
        bytes += str("TEXI0001")
        bytes += i32(format)
        bytes += i32(0)            // flags
        bytes += i32(mipW)         // textureWidth
        bytes += i32(mipH)         // textureHeight
        bytes += i32(mipW)         // imageWidth
        bytes += i32(mipH)         // imageHeight
        bytes += i32(0)            // unk0
        bytes += str(container)
        bytes += i32(1)            // imageCount
        if version >= 3 { bytes += i32(freeImageFormat ?? 0) }
        bytes += i32(1)            // mipmapCount
        bytes += i32(mipW)
        bytes += i32(mipH)
        if version >= 2 {
            bytes += i32(isLZ4 ? 1 : 0)
            bytes += i32(decompressedSize)
        }
        bytes += i32(payload.count)
        bytes += payload
        return Data(bytes)
    }

    private func pngBytes(width: Int, height: Int) throws -> [UInt8] {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let data = rep.representation(using: .png, properties: [:])!
        return [UInt8](data)
    }

    private func lz4Compress(_ input: [UInt8]) -> [UInt8] {
        let capacity = input.count + 4096
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let n = input.withUnsafeBufferPointer { src in
            compression_encode_buffer(dst, capacity, src.baseAddress!, input.count, nil, COMPRESSION_LZ4_RAW)
        }
        return Array(UnsafeBufferPointer(start: dst, count: n))
    }

    // MARK: - LZ4

    func testLZ4RoundTrip() {
        let original = [UInt8]("the quick brown fox jumps over the lazy dog ".utf8) +
                       [UInt8](repeating: 0x42, count: 500)
        let compressed = lz4Compress(original)
        XCTAssertFalse(compressed.isEmpty)
        let restored = TexDecoder.lz4Decompress(Data(compressed), decompressedSize: original.count)
        XCTAssertEqual(restored.map([UInt8].init), original)
    }

    func testLZ4ReturnsNilOnWrongSize() {
        let compressed = lz4Compress([1, 2, 3, 4, 5])
        XCTAssertNil(TexDecoder.lz4Decompress(Data(compressed), decompressedSize: 9999))
    }

    // MARK: - Raw RGBA

    func testRGBA8888BuildsImageOfRightSize() throws {
        let pixels = [UInt8](repeating: 0xFF, count: 4 * 4 * 4) // 4×4 RGBA
        let image = try TexDecoder.rgba8888Image(Data(pixels), width: 4, height: 4)
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)
    }

    func testRGBA8888ThrowsWhenTruncated() {
        let tooFew = [UInt8](repeating: 0, count: 8)
        XCTAssertThrowsError(try TexDecoder.rgba8888Image(Data(tooFew), width: 4, height: 4))
    }

    // MARK: - Full decode paths

    func testDecodesFreeImageTexture() throws {
        let png = try pngBytes(width: 12, height: 8)
        let tex = makeTex(format: 0, container: "TEXB0003", freeImageFormat: 0,
                          mipW: 12, mipH: 8, isLZ4: false, decompressedSize: 0, payload: png)
        let image = try XCTUnwrap(TexDecoder.decodeImage(from: tex))
        XCTAssertEqual(image.width, 12)
        XCTAssertEqual(image.height, 8)
    }

    func testDecodesLZ4CompressedFreeImageTexture() throws {
        let png = try pngBytes(width: 6, height: 6)
        let compressed = lz4Compress(png)
        let tex = makeTex(format: 0, container: "TEXB0003", freeImageFormat: 0,
                          mipW: 6, mipH: 6, isLZ4: true, decompressedSize: png.count,
                          payload: compressed)
        let image = try XCTUnwrap(TexDecoder.decodeImage(from: tex))
        XCTAssertEqual(image.width, 6)
        XCTAssertEqual(image.height, 6)
    }

    func testDecodesRawRGBA8888Texture() throws {
        let pixels = [UInt8](repeating: 0x80, count: 8 * 8 * 4)
        let tex = makeTex(format: 0, container: "TEXB0001", freeImageFormat: nil,
                          mipW: 8, mipH: 8, isLZ4: false, decompressedSize: 0, payload: pixels)
        let image = try XCTUnwrap(TexDecoder.decodeImage(from: tex))
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 8)
    }

    func testRejectsNonTexture() {
        // A well-formed length-prefixed string whose magic isn't "TEXV…".
        let notTex = Data(str("NOPEMAGIC"))
        XCTAssertThrowsError(try TexDecoder.decode(notTex)) { error in
            XCTAssertEqual(error as? TexDecoder.TexError, .notATexture)
        }
    }

    func testDoesNotTrapOnGarbage() {
        // Random/short bytes must throw, never crash.
        XCTAssertThrowsError(try TexDecoder.decode(Data([1, 2, 3, 4, 5, 6, 7, 8])))
        XCTAssertNil(TexDecoder.decodeImage(from: Data((0..<40).map { UInt8($0) })))
    }

    func testUnsupportedFormatReturnsNilNotCrash() {
        // DXT5 (format 4) with non-image raw bytes → unsupported, but safe.
        let raw = [UInt8](repeating: 0xAB, count: 64)
        let tex = makeTex(format: 4, container: "TEXB0001", freeImageFormat: nil,
                          mipW: 8, mipH: 8, isLZ4: false, decompressedSize: 0, payload: raw)
        XCTAssertNil(TexDecoder.decodeImage(from: tex))
    }
}
