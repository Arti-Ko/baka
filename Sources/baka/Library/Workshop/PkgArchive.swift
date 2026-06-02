import Foundation

/// Reads Wallpaper Engine's proprietary `.pkg` container format so we can
/// salvage directly-renderable assets (video / image / HTML) bundled inside a
/// Scene wallpaper. The compiled scene graph and `.tex` textures still need
/// WE's engine, but a great many scenes ship a plain video or image background
/// inside the package — extracting it turns a static poster into a live video.
///
/// Format (RePKG-compatible), all integers little-endian:
/// ```
/// int32   versionLen
/// bytes   version        e.g. "PKGV0001"
/// int32   entryCount
/// repeat entryCount times:
///   int32 nameLen
///   bytes name           forward-slash relative path
///   int32 offset         relative to the end of the header
///   int32 length
/// <data section>          entry bytes at (headerEnd + offset), length bytes
/// ```
enum PkgArchive {
    struct Entry: Equatable {
        let path: String
        let data: Data
    }

    enum PkgError: Error, Equatable {
        case truncated
        case notAPackage
        case malformed(String)
    }

    /// Sanity caps so a malformed/hostile file can't drive huge allocations.
    private static let maxEntries = 100_000
    private static let maxNameLength = 4_096

    /// Parses `data` and returns every entry with its bytes sliced out. Pure and
    /// fully bounds-checked — never traps on malformed input, only throws.
    static func extract(from data: Data) throws -> [Entry] {
        var reader = ByteReader(data)

        let version = try reader.readString()
        guard version.hasPrefix("PKG") else { throw PkgError.notAPackage }

        let count = try reader.readInt32()
        guard count >= 0, count <= maxEntries else { throw PkgError.malformed("entry count \(count)") }

        struct Descriptor { let path: String; let offset: Int; let length: Int }
        var descriptors: [Descriptor] = []
        descriptors.reserveCapacity(count)
        for _ in 0..<count {
            let name = try reader.readString()
            let offset = try reader.readInt32()
            let length = try reader.readInt32()
            guard offset >= 0, length >= 0 else { throw PkgError.malformed("negative offset/length") }
            descriptors.append(Descriptor(path: name, offset: offset, length: length))
        }

        let dataStart = reader.position
        var entries: [Entry] = []
        entries.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            let start = dataStart + descriptor.offset
            let end = start + descriptor.length
            guard start >= dataStart, end <= data.count, start <= end else {
                throw PkgError.truncated
            }
            let slice = data.subdata(in: start..<end)
            entries.append(Entry(path: descriptor.path, data: slice))
        }
        return entries
    }

    /// Extensions worth writing to disk — assets a Baka renderer can actually
    /// use. Everything else (`.tex`, `.mdl`, `scene.json`, shaders…) is skipped.
    static func isRenderableAsset(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return WallpaperFormats.video.contains(ext)
            || WallpaperFormats.image.contains(ext)
            || ext == "html" || ext == "htm"
    }

    /// Unpacks renderable assets from a single `.pkg` into `dir`, preserving the
    /// archive's relative layout. Path-traversal entries are rejected. Failures
    /// are swallowed per-entry — extraction is always best-effort.
    static func unpack(_ pkgURL: URL, into dir: URL) {
        guard let data = try? Data(contentsOf: pkgURL),
              let entries = try? extract(from: data) else { return }

        let fm = FileManager.default
        let root = dir.standardizedFileURL
        for entry in entries where isRenderableAsset(entry.path) {
            guard let dest = safeDestination(for: entry.path, under: root) else { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? entry.data.write(to: dest, options: .atomic)
        }
    }

    /// Finds every `.pkg` in `dir` (recursively) and unpacks it in place.
    static func unpackAll(in dir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pkg" {
            unpack(url, into: url.deletingLastPathComponent())
        }
    }

    /// Resolves `relativePath` under `root`, returning nil if it would escape
    /// the directory (e.g. via `..` or an absolute path).
    static func safeDestination(for relativePath: String, under root: URL) -> URL? {
        let cleaned = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = cleaned.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              !components.contains(".."),
              !cleaned.hasPrefix("/")
        else { return nil }

        let dest = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard dest.path.hasPrefix(root.path + "/") else { return nil }
        return dest
    }
}

/// Minimal little-endian byte cursor with bounds checking, so parsing untrusted
/// package data can never trap — it throws instead.
private struct ByteReader {
    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func readInt32() throws -> Int {
        guard position + 4 <= bytes.count else { throw PkgArchive.PkgError.truncated }
        let value = UInt32(bytes[position])
            | UInt32(bytes[position + 1]) << 8
            | UInt32(bytes[position + 2]) << 16
            | UInt32(bytes[position + 3]) << 24
        position += 4
        return Int(Int32(bitPattern: value))
    }

    mutating func readString() throws -> String {
        let length = try readInt32()
        guard length >= 0, length <= PkgArchive.maxNameLengthInternal,
              position + length <= bytes.count else {
            throw PkgArchive.PkgError.malformed("string length \(length)")
        }
        let slice = bytes[position..<position + length]
        position += length
        return String(decoding: slice, as: UTF8.self)
    }
}

extension PkgArchive {
    /// Exposed to `ByteReader` (a private type can't see a private static).
    fileprivate static var maxNameLengthInternal: Int { maxNameLength }
}
