import Foundation
import CoreGraphics
import ImageIO
import Compression

/// Decodes Wallpaper Engine `.tex` textures into `CGImage`s.
///
/// Supported in this phase:
/// - **FreeImage** textures — the mip bytes are a complete PNG/JPEG/GIF file
///   (the common case for scene backgrounds); decoded via ImageIO.
/// - **Uncompressed RGBA8888** — turned into a CGImage directly.
/// - **LZ4-compressed** mips — inflated with Apple's `Compression` framework
///   before either of the above.
///
/// Not yet supported: block-compressed formats (DXT1/DXT3/DXT5 / BC). For those
/// `decodeImage` returns nil and the caller falls back to the poster.
///
/// Format (RePKG-compatible), all integers little-endian:
/// ```
/// string  "TEXV0005"
/// string  "TEXI0001"
/// int     format            (0 = RGBA8888, 4 = DXT5, 6 = DXT3, 7 = DXT1, …)
/// int     flags
/// int     textureWidth / textureHeight
/// int     imageWidth  / imageHeight
/// uint    unk0
/// string  "TEXB000x"        container version
/// int     imageCount
/// int     freeImageFormat   (only when container == TEXB0003)
/// // first image, first mipmap:
/// int     mipmapCount
/// int     width / height
/// int     isLZ4 / decompressedSize   (only when container version >= 2)
/// int     byteCount
/// bytes   data
/// ```
enum TexDecoder {
    enum TexFormat: Int { case rgba8888 = 0, dxt5 = 4, dxt3 = 6, dxt1 = 7, rg88 = 8, r8 = 9 }

    enum TexError: Error, Equatable {
        case notATexture
        case unsupportedFormat(Int)
        case truncated
        case malformed(String)
    }

    /// Convenience: best-effort decode, nil on any failure (incl. unsupported
    /// formats), so callers can simply fall back.
    static func decodeImage(from data: Data) -> CGImage? {
        try? decode(data)
    }

    static func decode(_ data: Data) throws -> CGImage {
        var reader = LittleEndianReader(data)

        let magic = try reader.string()
        guard magic.hasPrefix("TEXV") else { throw TexError.notATexture }
        _ = try reader.string()                 // "TEXI0001"
        let rawFormat = try reader.int()
        _ = try reader.int()                     // flags
        _ = try reader.int()                     // textureWidth
        _ = try reader.int()                     // textureHeight
        let imageWidth = try reader.int()
        let imageHeight = try reader.int()
        _ = try reader.uint()                    // unk0

        let container = try reader.string()
        guard container.hasPrefix("TEXB") else { throw TexError.malformed("container \(container)") }
        let containerVersion = Int(container.drop { !$0.isNumber }) ?? 1

        let imageCount = try reader.int()
        guard imageCount > 0, imageCount < 4096 else { throw TexError.malformed("imageCount \(imageCount)") }
        if containerVersion >= 3 { _ = try reader.int() } // freeImageFormat hint

        let mipmapCount = try reader.int()
        guard mipmapCount > 0, mipmapCount < 64 else { throw TexError.malformed("mipmapCount \(mipmapCount)") }

        // The first mipmap of the first image is the full-resolution texture.
        let mipWidth = try reader.int()
        let mipHeight = try reader.int()
        var isLZ4 = false
        var decompressedSize = 0
        if containerVersion >= 2 {
            isLZ4 = (try reader.int()) != 0
            decompressedSize = try reader.int()
        }
        let byteCount = try reader.int()
        guard byteCount >= 0 else { throw TexError.malformed("byteCount \(byteCount)") }
        var bytes = try reader.data(byteCount)

        if isLZ4 {
            guard decompressedSize > 0,
                  let inflated = Self.lz4Decompress(bytes, decompressedSize: decompressedSize) else {
                throw TexError.malformed("LZ4")
            }
            bytes = inflated
        }

        // FreeImage path: the bytes are a standard image file. Sniff the magic so
        // we don't depend on the exact freeImageFormat enum semantics.
        if let cg = Self.cgImageFromFileBytes(bytes) {
            return cg
        }

        // Raw pixel path.
        let width = mipWidth > 0 ? mipWidth : imageWidth
        let height = mipHeight > 0 ? mipHeight : imageHeight
        switch TexFormat(rawValue: rawFormat) {
        case .rgba8888:
            return try Self.rgba8888Image(bytes, width: width, height: height)
        case .dxt1, .dxt3, .dxt5:
            return try Self.decodeBlockCompressed(bytes, width: width, height: height, format: rawFormat)
        default:
            throw TexError.unsupportedFormat(rawFormat)
        }
    }

    /// Expands a block-compressed (DXT) payload to RGBA8888 then wraps it.
    static func decodeBlockCompressed(_ bytes: Data, width: Int, height: Int, format: Int) throws -> CGImage {
        let codecFormat: BlockTextureCodec.Format
        switch TexFormat(rawValue: format) {
        case .dxt1: codecFormat = .dxt1
        case .dxt3: codecFormat = .dxt3
        case .dxt5: codecFormat = .dxt5
        default: throw TexError.unsupportedFormat(format)
        }
        guard let rgba = BlockTextureCodec.decode(bytes, width: width, height: height, format: codecFormat) else {
            throw TexError.truncated
        }
        return try rgba8888Image(Data(rgba), width: width, height: height)
    }

    // MARK: - Decoders

    /// Decodes a complete image file (PNG/JPEG/GIF/BMP/TIFF) via ImageIO.
    static func cgImageFromFileBytes(_ data: Data) -> CGImage? {
        guard data.count > 8 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Builds a CGImage from straight (non-premultiplied) RGBA8888 bytes.
    static func rgba8888Image(_ bytes: Data, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { throw TexError.malformed("dimensions") }
        let bytesPerRow = width * 4
        guard bytes.count >= bytesPerRow * height else { throw TexError.truncated }

        let trimmed = bytes.prefix(bytesPerRow * height)
        guard let provider = CGDataProvider(data: Data(trimmed) as CFData) else {
            throw TexError.malformed("provider")
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let image = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw TexError.malformed("CGImage")
        }
        return image
    }

    /// Inflates a raw LZ4 block (WE's format) using Apple's Compression library.
    static func lz4Decompress(_ source: Data, decompressedSize: Int) -> Data? {
        guard !source.isEmpty, decompressedSize > 0 else { return nil }
        var destination = Data(count: decompressedSize)
        let written = destination.withUnsafeMutableBytes { dst -> Int in
            source.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase, decompressedSize, srcBase, source.count, nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written == decompressedSize else { return nil }
        return destination
    }
}

/// Bounds-checked little-endian cursor for parsing untrusted binary blobs —
/// throws rather than trapping. Shared by the `.tex` decoder.
struct LittleEndianReader {
    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func uint() throws -> UInt32 {
        guard position + 4 <= bytes.count else { throw TexDecoder.TexError.truncated }
        let value = UInt32(bytes[position])
            | UInt32(bytes[position + 1]) << 8
            | UInt32(bytes[position + 2]) << 16
            | UInt32(bytes[position + 3]) << 24
        position += 4
        return value
    }

    mutating func int() throws -> Int { Int(Int32(bitPattern: try uint())) }

    mutating func data(_ count: Int) throws -> Data {
        guard count >= 0, position + count <= bytes.count else { throw TexDecoder.TexError.truncated }
        let slice = bytes[position..<position + count]
        position += count
        return Data(slice)
    }

    /// A length-prefixed UTF-8 string. WE also null-terminates these, so a
    /// trailing NUL is trimmed.
    mutating func string() throws -> String {
        let length = try int()
        guard length >= 0, length < 4096 else { throw TexDecoder.TexError.malformed("string length \(length)") }
        let raw = try data(length)
        let trimmed = raw.last == 0 ? raw.dropLast() : raw[...]
        return String(decoding: trimmed, as: UTF8.self)
    }
}
