import Foundation

/// A parsed Wallpaper Engine `scene.json`, reduced to what Baka can composite:
/// the orthographic projection size and the ordered list of image layers.
///
/// Particle systems, sound objects, shader effects and 3D models are ignored in
/// this phase — only objects that reference an image/texture are rendered.
struct SceneDocument {
    /// Logical projection size the layer coordinates are authored against.
    let projectionWidth: Double
    let projectionHeight: Double
    /// Layers in declaration order (first = back, last = front).
    let layers: [SceneLayer]

    static func parse(_ data: Data) -> SceneDocument? {
        guard let root = try? JSONSerialization.jsonObject(
            with: SteamWorkshopClient.sanitizeJSON(data)
        ) as? [String: Any] else { return nil }

        let general = root["general"] as? [String: Any]
        let ortho = general?["orthogonalprojection"] as? [String: Any]
        let width = Self.double(ortho?["width"]) ?? 1920
        let height = Self.double(ortho?["height"]) ?? 1080

        let objects = root["objects"] as? [[String: Any]] ?? []
        let layers = objects.compactMap(SceneLayer.init(object:))

        guard !layers.isEmpty else { return nil }
        return SceneDocument(projectionWidth: width, projectionHeight: height, layers: layers)
    }

    /// Parses a value that may be a number or a numeric string.
    static func double(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Parses "x y z" (or "x y") into components, padded/truncated to `count`.
    static func vector(_ value: Any?, count: Int) -> [Double] {
        guard let s = value as? String else { return Array(repeating: 0, count: count) }
        var parts = s.split(separator: " ").compactMap { Double($0) }
        while parts.count < count { parts.append(0) }
        return Array(parts.prefix(count))
    }
}

/// One renderable image layer from a scene.
struct SceneLayer {
    /// Reference to a model/material/texture asset (resolved later, relative to
    /// the scene folder).
    let imageRef: String
    /// Center position in projection space (x right, y up, origin at center).
    let originX: Double
    let originY: Double
    /// Z used only for stable ordering when present.
    let depth: Double
    /// Per-axis scale multipliers.
    let scaleX: Double
    let scaleY: Double
    /// Authored pixel size, when given.
    let sizeW: Double?
    let sizeH: Double?
    /// Rotation around the layer center, in degrees (z angle).
    let angleZ: Double
    let alpha: Double
    let visible: Bool
    /// Parallax depth per axis (0 = pinned, larger = moves more with the camera).
    let parallaxX: Double
    let parallaxY: Double

    init?(object: [String: Any]) {
        // Only image-backed objects are renderable; skip particles/sound/etc.
        guard let image = object["image"] as? String, !image.isEmpty else { return nil }
        imageRef = image

        let origin = SceneDocument.vector(object["origin"], count: 3)
        originX = origin[0]; originY = origin[1]; depth = origin[2]

        let scale = SceneDocument.vector(object["scale"], count: 3)
        scaleX = scale[0] == 0 ? 1 : scale[0]
        scaleY = scale[1] == 0 ? 1 : scale[1]

        let angles = SceneDocument.vector(object["angles"], count: 3)
        angleZ = angles[2]

        let size = SceneDocument.vector(object["size"], count: 2)
        sizeW = size[0] > 0 ? size[0] : nil
        sizeH = size[1] > 0 ? size[1] : nil

        alpha = SceneDocument.double(object["alpha"]) ?? 1
        // Default visible; WE omits the key for visible layers.
        if let v = object["visible"] as? Bool { visible = v }
        else if let v = object["visible"] as? Int { visible = v != 0 }
        else { visible = true }

        let parallax = SceneDocument.vector(object["parallaxDepth"], count: 2)
        parallaxX = parallax[0]
        parallaxY = parallax[1]
    }
}

/// Resolves a layer's `image` reference to a concrete texture/image file on
/// disk, walking WE's indirection: object → model `.json` → material → texture.
enum SceneAssetResolver {
    /// Texture/image extensions we can load directly.
    private static let directExtensions: Set<String> =
        WallpaperFormats.image.union(["tex"])

    /// Returns the on-disk texture/image file for `imageRef`, searching relative
    /// to `folder`. Returns nil when nothing resolvable is found.
    static func textureURL(for imageRef: String, in folder: URL) -> URL? {
        let ext = (imageRef as NSString).pathExtension.lowercased()

        if directExtensions.contains(ext) {
            return existing(imageRef, in: folder)
        }

        if ext == "json", let modelURL = existing(imageRef, in: folder),
           let textureName = textureName(fromModelOrMaterial: modelURL, folder: folder) {
            return resolveTextureName(textureName, in: folder)
        }

        // Last resort: treat the ref itself as a texture base name.
        return resolveTextureName(imageRef, in: folder)
    }

    /// Extracts the first texture base name from a model or material JSON,
    /// following a model → material file link when present.
    static func textureName(fromModelOrMaterial url: URL, folder: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(
                  with: SteamWorkshopClient.sanitizeJSON(data)) as? [String: Any]
        else { return nil }

        // A model file usually links to a material file by path…
        if let materialPath = root["material"] as? String,
           let materialURL = existing(materialPath, in: folder),
           let name = firstTexture(inMaterialJSON: materialURL) {
            return name
        }
        // …but the JSON may already be a material (has its own passes/textures).
        return firstTexture(inMaterial: root)
    }

    static func firstTexture(inMaterialJSON url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(
                  with: SteamWorkshopClient.sanitizeJSON(data)) as? [String: Any]
        else { return nil }
        return firstTexture(inMaterial: root)
    }

    /// Pulls the first non-empty texture name out of a material dictionary's
    /// `passes[].textures[]`.
    static func firstTexture(inMaterial root: [String: Any]) -> String? {
        guard let passes = root["passes"] as? [[String: Any]] else { return nil }
        for pass in passes {
            guard let textures = pass["textures"] as? [Any] else { continue }
            for texture in textures {
                if let name = texture as? String, !name.isEmpty { return name }
            }
        }
        return nil
    }

    /// Maps a texture base name (often extension-less, e.g. "materials/foo") to
    /// an actual file, trying `.tex` first then common image extensions.
    static func resolveTextureName(_ name: String, in folder: URL) -> URL? {
        if let direct = existing(name, in: folder) { return direct }
        for ext in ["tex"] + WallpaperFormats.image.sorted() {
            if let url = existing("\(name).\(ext)", in: folder) { return url }
        }
        return nil
    }

    /// Returns the URL for a relative path if the file exists under `folder`.
    private static func existing(_ relative: String, in folder: URL) -> URL? {
        let url = folder.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
