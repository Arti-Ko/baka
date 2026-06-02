import Foundation

/// Decodes block-compressed (S3TC / DXT / BCn) textures into straight RGBA8888.
///
/// Wallpaper Engine ships most scene textures as DXT5, with DXT1/DXT3 also
/// common. macOS has no API to expand these to a `CGImage`-friendly buffer, so
/// we decode the 4×4 blocks on the CPU. Pure and fully unit-testable.
///
/// References: the S3TC block layout — DXT1 is 8 bytes/block (color only, with a
/// 1-bit punch-through alpha mode); DXT3 adds 8 bytes of explicit 4-bit alpha;
/// DXT5 adds 8 bytes of interpolated alpha.
enum BlockTextureCodec {
    enum Format { case dxt1, dxt3, dxt5 }

    /// Decodes `data` (whole texture) to a `width*height*4` RGBA buffer, or nil
    /// if there aren't enough bytes for the full block grid.
    static func decode(_ data: Data, width: Int, height: Int, format: Format) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let blocksX = (width + 3) / 4
        let blocksY = (height + 3) / 4
        let blockSize = (format == .dxt1) ? 8 : 16
        let bytes = [UInt8](data)
        guard bytes.count >= blocksX * blocksY * blockSize else { return nil }

        var output = [UInt8](repeating: 0, count: width * height * 4)
        var offset = 0
        for blockY in 0..<blocksY {
            for blockX in 0..<blocksX {
                var block = [UInt8](repeating: 0, count: 16 * 4) // 4×4 RGBA
                switch format {
                case .dxt1:
                    decodeColorBlock(bytes, at: offset, into: &block, punchThroughAlpha: true)
                case .dxt3:
                    decodeExplicitAlpha(bytes, at: offset, into: &block)
                    decodeColorBlock(bytes, at: offset + 8, into: &block, punchThroughAlpha: false)
                case .dxt5:
                    decodeInterpolatedAlpha(bytes, at: offset, into: &block)
                    decodeColorBlock(bytes, at: offset + 8, into: &block, punchThroughAlpha: false)
                }
                blit(block, blockX: blockX, blockY: blockY,
                     into: &output, width: width, height: height)
                offset += blockSize
            }
        }
        return output
    }

    // MARK: - Color block (shared by all three)

    /// Decodes the 8-byte color portion: two RGB565 endpoints + 16 two-bit
    /// indices. Writes RGB for every pixel; writes alpha only in DXT1
    /// punch-through mode (DXT3/DXT5 set alpha from their own blocks).
    private static func decodeColorBlock(_ bytes: [UInt8], at offset: Int,
                                         into block: inout [UInt8], punchThroughAlpha: Bool) {
        let c0 = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        let c1 = UInt16(bytes[offset + 2]) | (UInt16(bytes[offset + 3]) << 8)

        var r = [Int](repeating: 0, count: 4)
        var g = [Int](repeating: 0, count: 4)
        var b = [Int](repeating: 0, count: 4)
        var a = [Int](repeating: 255, count: 4)

        (r[0], g[0], b[0]) = rgb565(c0)
        (r[1], g[1], b[1]) = rgb565(c1)

        let opaque = !punchThroughAlpha || c0 > c1
        if opaque {
            r[2] = (2 * r[0] + r[1]) / 3; g[2] = (2 * g[0] + g[1]) / 3; b[2] = (2 * b[0] + b[1]) / 3
            r[3] = (r[0] + 2 * r[1]) / 3; g[3] = (g[0] + 2 * g[1]) / 3; b[3] = (b[0] + 2 * b[1]) / 3
        } else {
            r[2] = (r[0] + r[1]) / 2; g[2] = (g[0] + g[1]) / 2; b[2] = (b[0] + b[1]) / 2
            r[3] = 0; g[3] = 0; b[3] = 0; a[3] = 0 // transparent black
        }

        for row in 0..<4 {
            let indexByte = bytes[offset + 4 + row]
            for col in 0..<4 {
                let index = Int((indexByte >> (UInt8(col) * 2)) & 0x3)
                let pixel = (row * 4 + col) * 4
                block[pixel] = UInt8(r[index])
                block[pixel + 1] = UInt8(g[index])
                block[pixel + 2] = UInt8(b[index])
                if punchThroughAlpha { block[pixel + 3] = UInt8(a[index]) }
            }
        }
    }

    // MARK: - Alpha blocks

    /// DXT3: 16 explicit 4-bit alpha values (8 bytes), expanded to 8-bit.
    private static func decodeExplicitAlpha(_ bytes: [UInt8], at offset: Int, into block: inout [UInt8]) {
        for i in 0..<16 {
            let byte = bytes[offset + i / 2]
            let nibble = (i % 2 == 0) ? (byte & 0x0F) : (byte >> 4)
            block[i * 4 + 3] = nibble * 17 // 0x0→0, 0xF→255
        }
    }

    /// DXT5: two alpha endpoints + a 6-byte stream of 16 three-bit indices.
    private static func decodeInterpolatedAlpha(_ bytes: [UInt8], at offset: Int, into block: inout [UInt8]) {
        let a0 = Int(bytes[offset])
        let a1 = Int(bytes[offset + 1])
        var alpha = [Int](repeating: 0, count: 8)
        alpha[0] = a0; alpha[1] = a1
        if a0 > a1 {
            for i in 2..<8 { alpha[i] = ((8 - i) * a0 + (i - 1) * a1) / 7 }
        } else {
            for i in 2..<6 { alpha[i] = ((6 - i) * a0 + (i - 1) * a1) / 5 }
            alpha[6] = 0
            alpha[7] = 255
        }

        var bits: UInt64 = 0
        for k in 0..<6 { bits |= UInt64(bytes[offset + 2 + k]) << (8 * k) }
        for i in 0..<16 {
            let index = Int((bits >> (UInt64(i) * 3)) & 0x7)
            block[i * 4 + 3] = UInt8(alpha[index])
        }
    }

    // MARK: - Helpers

    /// Expands RGB565 to 8-bit-per-channel with bit replication.
    private static func rgb565(_ value: UInt16) -> (Int, Int, Int) {
        let r5 = Int((value >> 11) & 0x1F)
        let g6 = Int((value >> 5) & 0x3F)
        let b5 = Int(value & 0x1F)
        let r = (r5 << 3) | (r5 >> 2)
        let g = (g6 << 2) | (g6 >> 4)
        let b = (b5 << 3) | (b5 >> 2)
        return (r, g, b)
    }

    /// Copies a decoded 4×4 block into the output buffer, clipping at the edges
    /// for textures whose dimensions aren't multiples of four.
    private static func blit(_ block: [UInt8], blockX: Int, blockY: Int,
                             into output: inout [UInt8], width: Int, height: Int) {
        for py in 0..<4 {
            let y = blockY * 4 + py
            if y >= height { continue }
            for px in 0..<4 {
                let x = blockX * 4 + px
                if x >= width { continue }
                let src = (py * 4 + px) * 4
                let dst = (y * width + x) * 4
                output[dst] = block[src]
                output[dst + 1] = block[src + 1]
                output[dst + 2] = block[src + 2]
                output[dst + 3] = block[src + 3]
            }
        }
    }
}
