import Foundation
import QuartzCore
import CoreGraphics

/// A Wallpaper Engine particle definition (`particles/*.json`), reduced to the
/// parameters Baka maps onto a `CAEmitterCell`. WE's field names vary across
/// versions, so parsing is defensive: emitters/initializers/operators are
/// matched by name substring with sensible fallbacks.
struct ParticleSystem {
    enum Shape { case point, sphere, box }

    let spriteRef: String?
    let maxCount: Int
    let rate: Double
    let lifetimeMin: Double
    let lifetimeMax: Double
    let sizeMin: Double
    let sizeMax: Double
    let alpha: Double
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let speedMin: Double
    let speedMax: Double
    let gravityX: Double
    let gravityY: Double
    let fadesOut: Bool
    let shape: Shape
    let emitterSize: Double

    static func parse(_ data: Data) -> ParticleSystem? {
        guard let root = try? JSONSerialization.jsonObject(
            with: SteamWorkshopClient.sanitizeJSON(data)) as? [String: Any] else { return nil }

        let emitters = array(root["emitter"])
        let initializers = array(root["initializer"])
        let operators = array(root["operator"])
        let emitter = emitters.first ?? [:]

        // Lifetime / size / alpha / color / velocity from initializers.
        let lifetime = byName(initializers, "lifetime")
        let size = byName(initializers, "size")
        let alphaInit = byName(initializers, "alpha")
        let colorInit = byName(initializers, "color")
        let velocity = byName(initializers, "velocity")

        let lifeMin = SceneDocument.double(lifetime?["min"]) ?? 2
        let lifeMax = SceneDocument.double(lifetime?["max"]) ?? lifeMin
        let szMin = SceneDocument.double(size?["min"]) ?? 20
        let szMax = SceneDocument.double(size?["max"]) ?? szMin
        let alpha = SceneDocument.double(alphaInit?["max"])
            ?? SceneDocument.double(alphaInit?["min"])
            ?? SceneDocument.double(alphaInit?["value"]) ?? 1

        let colorVec = SceneDocument.vector(colorInit?["max"] ?? colorInit?["color"], count: 3)
        let hasColor = (colorInit?["max"] ?? colorInit?["color"]) != nil
        let (cr, cg, cb) = hasColor ? (colorVec[0], colorVec[1], colorVec[2]) : (1, 1, 1)

        // Speed: prefer explicit emitter speed, else velocity-initializer magnitude.
        let speedMin = SceneDocument.double(emitter["speedmin"])
            ?? magnitude(velocity?["min"]) ?? 0
        let speedMax = SceneDocument.double(emitter["speedmax"])
            ?? magnitude(velocity?["max"]) ?? max(speedMin, 50)

        // Gravity from a movement/gravity operator.
        let gravityOp = byName(operators, "gravity") ?? byName(operators, "movement")
        let gravity = SceneDocument.vector(gravityOp?["gravity"], count: 3)
        let fades = byName(operators, "alphafade") != nil
            || byName(operators, "alphachange") != nil
            || byName(operators, "fade") != nil

        // Emitter shape + size.
        let name = (emitter["name"] as? String)?.lowercased() ?? ""
        let shape: Shape = name.contains("sphere") ? .sphere
            : (name.contains("box") || name.contains("cube")) ? .box : .point
        let emitterSize = SceneDocument.double(emitter["distancemax"])
            ?? magnitude(emitter["size"]) ?? 0

        let sprite = (root["material"] as? String) ?? (root["texture"] as? String)
        let maxCount = Int(SceneDocument.double(root["maxcount"]) ?? 1000)

        return ParticleSystem(
            spriteRef: sprite, maxCount: max(1, maxCount),
            rate: SceneDocument.double(emitter["rate"]) ?? 30,
            lifetimeMin: lifeMin, lifetimeMax: lifeMax,
            sizeMin: szMin, sizeMax: szMax, alpha: alpha,
            colorR: cr, colorG: cg, colorB: cb,
            speedMin: speedMin, speedMax: speedMax,
            gravityX: gravity[0], gravityY: gravity[1],
            fadesOut: fades, shape: shape, emitterSize: emitterSize
        )
    }

    // MARK: - JSON helpers

    private static func array(_ value: Any?) -> [[String: Any]] {
        if let arr = value as? [[String: Any]] { return arr }
        if let dict = value as? [String: Any] { return [dict] }
        return []
    }

    /// First entry whose `name` contains `needle` (case-insensitive).
    private static func byName(_ items: [[String: Any]], _ needle: String) -> [String: Any]? {
        items.first { ($0["name"] as? String)?.lowercased().contains(needle) == true }
    }

    /// Euclidean magnitude of an "x y z" vector value.
    private static func magnitude(_ value: Any?) -> Double? {
        guard value != nil else { return nil }
        let v = SceneDocument.vector(value, count: 3)
        return (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot()
    }
}

/// Plain numeric emitter parameters derived from a `ParticleSystem` — the bridge
/// to `CAEmitterCell`. Pure and unit-testable; no Core Animation here.
struct EmitterConfig: Equatable {
    var birthRate: Float
    var lifetime: Float
    var lifetimeRange: Float
    var velocity: Double
    var velocityRange: Double
    var scale: Double
    var scaleRange: Double
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var alphaSpeed: Float
    var xAcceleration: Double
    var yAcceleration: Double

    /// Maps a parsed system onto cell parameters. `spriteBaseSize` is the sprite
    /// texture's pixel width, used to convert WE's pixel particle size to a CA
    /// scale factor.
    static func from(_ system: ParticleSystem, spriteBaseSize: Double) -> EmitterConfig {
        let lifeMid = (system.lifetimeMin + system.lifetimeMax) / 2
        let lifeRange = abs(system.lifetimeMax - system.lifetimeMin) / 2
        let speedMid = (system.speedMin + system.speedMax) / 2
        let speedRange = abs(system.speedMax - system.speedMin) / 2
        let sizeMid = (system.sizeMin + system.sizeMax) / 2
        let sizeRange = abs(system.sizeMax - system.sizeMin) / 2
        let base = max(spriteBaseSize, 1)

        return EmitterConfig(
            birthRate: Float(max(system.rate, 0)),
            lifetime: Float(max(lifeMid, 0.01)),
            lifetimeRange: Float(lifeRange),
            velocity: speedMid,
            velocityRange: speedRange,
            scale: sizeMid / base,
            scaleRange: sizeRange / base,
            red: system.colorR, green: system.colorG, blue: system.colorB,
            alpha: system.alpha,
            // Fade to nothing over the particle's life when an alpha-fade op exists.
            alphaSpeed: system.fadesOut ? Float(-system.alpha / max(lifeMid, 0.01)) : 0,
            xAcceleration: system.gravityX,
            yAcceleration: system.gravityY
        )
    }
}

/// Builds a hardware-accelerated `CAEmitterLayer` from an `EmitterConfig` and a
/// sprite. The simulation can be frozen by setting the returned layer's `speed`
/// to 0 (done on pause to keep a covered/idle scene free).
@MainActor
enum ParticleEmitterBuilder {
    static func makeLayer(config: EmitterConfig, sprite: CGImage,
                          shape: ParticleSystem.Shape, emitterSize: Double) -> CAEmitterLayer {
        let cell = CAEmitterCell()
        cell.contents = sprite
        cell.birthRate = config.birthRate
        cell.lifetime = config.lifetime
        cell.lifetimeRange = config.lifetimeRange
        cell.velocity = CGFloat(config.velocity)
        cell.velocityRange = CGFloat(config.velocityRange)
        cell.scale = CGFloat(config.scale)
        cell.scaleRange = CGFloat(config.scaleRange)
        cell.color = CGColor(red: CGFloat(config.red), green: CGFloat(config.green),
                             blue: CGFloat(config.blue), alpha: CGFloat(config.alpha))
        cell.alphaSpeed = config.alphaSpeed
        cell.xAcceleration = CGFloat(config.xAcceleration)
        cell.yAcceleration = CGFloat(config.yAcceleration)
        // Emit in all in-plane directions; gravity/velocity shape the motion.
        cell.emissionRange = .pi * 2

        let layer = CAEmitterLayer()
        layer.emitterCells = [cell]
        layer.emitterMode = .surface
        switch shape {
        case .point:  layer.emitterShape = .point
        case .sphere: layer.emitterShape = .circle
        case .box:    layer.emitterShape = .rectangle
        }
        let size = max(emitterSize, 1)
        layer.emitterSize = CGSize(width: size, height: size)
        return layer
    }
}
