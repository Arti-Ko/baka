import XCTest
@testable import baka

/// Scene phase 4 — particle JSON parsing, the emitter-config mapping, and
/// scene-level particle object collection.
final class ParticleSystemTests: XCTestCase {

    // MARK: - Particle JSON parsing

    func testParsesCommonSnowLikeParticle() throws {
        let json = """
        {
          "maxcount": 800,
          "material": "materials/snow.json",
          "emitter": [{ "name": "boxrandom", "rate": 60, "distancemax": 1000,
                        "speedmin": 10, "speedmax": 30 }],
          "initializer": [
            { "name": "lifetimerandom", "min": 4, "max": 8 },
            { "name": "sizerandom", "min": 10, "max": 40 },
            { "name": "alpharandom", "max": 0.8 },
            { "name": "colorrandom", "max": "1 1 1" }
          ],
          "operator": [
            { "name": "movement", "gravity": "0 -50 0" },
            { "name": "alphafade" }
          ]
        }
        """.data(using: .utf8)!

        let system = try XCTUnwrap(ParticleSystem.parse(json))
        XCTAssertEqual(system.spriteRef, "materials/snow.json")
        XCTAssertEqual(system.maxCount, 800)
        XCTAssertEqual(system.rate, 60)
        XCTAssertEqual(system.lifetimeMin, 4)
        XCTAssertEqual(system.lifetimeMax, 8)
        XCTAssertEqual(system.sizeMin, 10)
        XCTAssertEqual(system.sizeMax, 40)
        XCTAssertEqual(system.alpha, 0.8, accuracy: 0.001)
        XCTAssertEqual(system.speedMin, 10)
        XCTAssertEqual(system.speedMax, 30)
        XCTAssertEqual(system.gravityY, -50)
        XCTAssertTrue(system.fadesOut)
        XCTAssertEqual(system.shape, .box)
    }

    func testFallsBackToVelocityInitializerForSpeed() throws {
        let json = """
        {
          "material": "m.json",
          "emitter": [{ "name": "sphere", "rate": 10 }],
          "initializer": [{ "name": "velocityrandom", "min": "0 0 0", "max": "0 40 30" }]
        }
        """.data(using: .utf8)!
        let system = try XCTUnwrap(ParticleSystem.parse(json))
        XCTAssertEqual(system.shape, .sphere)
        XCTAssertEqual(system.speedMin, 0, accuracy: 0.001)
        XCTAssertEqual(system.speedMax, 50, accuracy: 0.001) // |(0,40,30)| = 50
    }

    func testUsesSensibleDefaultsForSparseDefinition() throws {
        let system = try XCTUnwrap(ParticleSystem.parse(#"{"material":"m.json"}"#.data(using: .utf8)!))
        XCTAssertEqual(system.rate, 30)         // default rate
        XCTAssertFalse(system.fadesOut)
        XCTAssertEqual(system.shape, .point)
    }

    func testReturnsNilOnMalformedJSON() {
        XCTAssertNil(ParticleSystem.parse(Data("not json".utf8)))
    }

    // MARK: - EmitterConfig mapping

    func testEmitterConfigMidpointsAndRanges() {
        let system = makeSystem(lifeMin: 2, lifeMax: 6, sizeMin: 20, sizeMax: 60,
                                speedMin: 10, speedMax: 30, alpha: 1, fades: false,
                                gravityX: 0, gravityY: -100)
        let config = EmitterConfig.from(system, spriteBaseSize: 100)
        XCTAssertEqual(config.lifetime, 4, accuracy: 0.001)        // (2+6)/2
        XCTAssertEqual(config.lifetimeRange, 2, accuracy: 0.001)   // (6-2)/2
        XCTAssertEqual(config.velocity, 20, accuracy: 0.001)
        XCTAssertEqual(config.velocityRange, 10, accuracy: 0.001)
        XCTAssertEqual(config.scale, 0.4, accuracy: 0.001)         // size 40 / sprite 100
        XCTAssertEqual(config.scaleRange, 0.2, accuracy: 0.001)    // (60-20)/2 / 100
        XCTAssertEqual(config.yAcceleration, -100, accuracy: 0.001)
        XCTAssertEqual(config.alphaSpeed, 0)                       // no fade op
    }

    func testEmitterConfigFadeProducesNegativeAlphaSpeed() {
        let system = makeSystem(lifeMin: 4, lifeMax: 4, sizeMin: 10, sizeMax: 10,
                                speedMin: 0, speedMax: 0, alpha: 1, fades: true,
                                gravityX: 0, gravityY: 0)
        let config = EmitterConfig.from(system, spriteBaseSize: 50)
        // Fades fully over the ~4s lifetime → -1/4 per second.
        XCTAssertEqual(config.alphaSpeed, -0.25, accuracy: 0.001)
    }

    // MARK: - Scene-level particle collection

    func testSceneDocumentCollectsParticlesAlongsideLayers() throws {
        let json = """
        { "objects": [
          { "image": "models/bg.json", "origin": "960 540 0" },
          { "particle": "particles/snow.json", "origin": "960 1000 0", "parallaxDepth": "0.3 0.3" }
        ]}
        """.data(using: .utf8)!
        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.particles.count, 1)
        XCTAssertEqual(doc.particles[0].particleRef, "particles/snow.json")
        XCTAssertEqual(doc.particles[0].originY, 1000)
        XCTAssertEqual(doc.particles[0].parallaxX, 0.3, accuracy: 0.001)
    }

    func testSceneWithOnlyParticlesStillParses() throws {
        let json = #"{"objects":[{"particle":"p.json","origin":"0 0 0"}]}"#.data(using: .utf8)!
        let doc = try XCTUnwrap(SceneDocument.parse(json))
        XCTAssertTrue(doc.layers.isEmpty)
        XCTAssertEqual(doc.particles.count, 1)
    }

    // MARK: - Helper

    private func makeSystem(lifeMin: Double, lifeMax: Double, sizeMin: Double, sizeMax: Double,
                            speedMin: Double, speedMax: Double, alpha: Double, fades: Bool,
                            gravityX: Double, gravityY: Double) -> ParticleSystem {
        ParticleSystem(
            spriteRef: "m.json", maxCount: 100, rate: 30,
            lifetimeMin: lifeMin, lifetimeMax: lifeMax,
            sizeMin: sizeMin, sizeMax: sizeMax, alpha: alpha,
            colorR: 1, colorG: 1, colorB: 1,
            speedMin: speedMin, speedMax: speedMax,
            gravityX: gravityX, gravityY: gravityY,
            fadesOut: fades, shape: .point, emitterSize: 0)
    }
}
