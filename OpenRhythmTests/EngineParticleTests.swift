import XCTest
import UIKit
@testable import OpenRhythm

final class EngineParticleTests: EngineHostTestCase {
  func testParticleRandomCacheIsBoundedAndPreservesEverySeed() {
    for capacity in [0, 1, 3, 512] {
      var cache = EngineParticleRandomCache(capacity: capacity)
      let seeds = [UInt64(0), 1, 65_537, .max, 2, 1, .max, 0]
        + (0..<600).map(UInt64.init) + [0, 1, .max]
      for (index, seed) in seeds.enumerated() {
        if index.isMultiple(of: 37) { cache.beginFrame() }
        let expected = EngineGeometry.randomVariables(seed: seed)
        var value = cache.variables(seed: seed)
        XCTAssertEqual(value, expected)
        value["r1"] = -123 // A caller's mutation must not corrupt the cache.
        XCTAssertEqual(cache.variables(seed: seed), expected)
        XCTAssertLessThanOrEqual(cache.count, capacity * 2)
      }
      for _ in 0..<3 {
        cache.beginFrame()
        for seed in 0..<600 {
          XCTAssertEqual(cache.variables(seed: UInt64(seed)),
            EngineGeometry.randomVariables(seed: UInt64(seed)))
          XCTAssertLessThanOrEqual(cache.count, capacity * 2)
        }
      }
      cache.beginFrame()
      cache.beginFrame()
      XCTAssertEqual(cache.count, 0, "Unused seeds must age out")
    }
  }

  func testParticlePropertyCacheIsBoundedAndSeparatesDefinitions() {
    func particle(_ value: Double) -> ParticleData.Particle {
      func property(_ index: Int) -> ParticleData.Property {
        let offset = Double(index)
        return ParticleData.Property(from: ["c": value + offset, "r1": 2 + offset],
          to: ["c": value + offset + 1, "r2": -3 - offset],
          ease: ["none", "linear", "inOutCubic", "outQuad", "inSine", "outBack"][index])
      }
      return ParticleData.Particle(sprite: 0, color: "#fff", start: 0,
        duration: 1, x: property(0), y: property(1), w: property(2),
        h: property(3), r: property(4), a: property(5))
    }
    for capacity in [0, 1, 8, 128] {
      var cache = EngineParticlePropertyCache(capacity: capacity)
      for _ in 0..<4 {
        cache.beginFrame()
        for seed in UInt64(0)..<4 {
          let variables = EngineGeometry.randomVariables(seed: seed)
          for effect in 0..<2 {
            for group in 0..<2 {
              for index in 0..<2 {
                let definition = particle(Double(effect * 100 + group * 10 + index))
                let actual = cache.properties(for: definition,
                  key: .init(seed: seed, effect: 0.5 + Double(effect) / 4,
                    group: group, particle: index),
                  variables: variables)
                let originals = [definition.x, definition.y, definition.w,
                  definition.h, definition.r, definition.a]
                let endpoints = [actual.x, actual.y, actual.w, actual.h, actual.r, actual.a]
                for (original, cached) in zip(originals, endpoints) {
                  for time in [0.0, 0.25, 0.75, 1] {
                    XCTAssertEqual(original.value(at: time, endpoints: cached),
                      original.value(at: time, variables: variables))
                  }
                }
                XCTAssertLessThanOrEqual(cache.count, capacity * 2)
              }
            }
          }
        }
      }
      cache.beginFrame()
      cache.beginFrame()
      XCTAssertEqual(cache.count, 0, "Expired effects cannot accumulate")
    }
  }

  @MainActor
  func testParticleResourceValidationPreservesDocumentedBoundaries() throws {
    let selected = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"fixture"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let unused = try RuntimeNodeBuilder().engine(archetypes: [])
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    func presentation(_ overrides: [String: Any], unusedBadEffect: Bool = false)
      throws -> RuntimePresentation {
      var particle: [String: Any] = ["sprite": 0, "color": "#fff",
        "start": 0, "duration": 1]
      for key in ["x", "y", "w", "h", "r", "a"] { particle[key] = [:] as [String: Any] }
      particle.merge(overrides) { _, new in new }
      var effects: [[String: Any]] = [["name": "fixture", "transform": [:],
        "groups": [["count": 1, "particles": [particle]]]]]
      if unusedBadEffect {
        var invalid = particle
        invalid["color"] = "not a color"
        invalid["sprite"] = 42
        effects.append(["name": "unused", "transform": [:],
          "groups": [["count": 1, "particles": [invalid]]]])
      }
      let data: [String: Any] = ["width": 2, "height": 2, "interpolation": false,
        "sprites": [["x": 0, "y": 0, "w": 2, "h": 2]], "effects": effects]
      return RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8), "particleTexture": texture,
        "particleData": try JSONSerialization.data(withJSONObject: data)])
    }
    let invalid: [[String: Any]] = [
      ["color": "fff"], ["color": "#ff"], ["color": "#ffff"],
      ["color": "#ffffffff"], ["color": "#ggg"], ["color": "#１２３"],
      ["sprite": -1], ["sprite": 1], ["start": 1e308, "duration": 1e308]]
    for fields in invalid {
      let resource = try presentation(fields)
      XCTAssertThrowsError(try EnginePresentationAssets(engine: selected,
        presentation: resource), "Invalid selected particle: \(fields)") { error in
        XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("particle"),
          "Errors should identify the resource that needs repair: \(error)")
      }
      XCTAssertNoThrow(try EnginePresentationAssets(engine: unused,
        presentation: resource), "An unused particle family must remain optional")
    }
    for color in ["#000", "#fF0", "#123abc", "#ABCDEF"] {
      for start in [-0.25, 0.0, 0.75, 1.0, 1.125] {
        for duration in [-0.5, 0.0, 0.5, 1.0, 2.0] {
          XCTAssertNoThrow(try EnginePresentationAssets(engine: selected,
            presentation: presentation(["color": color, "start": start,
              "duration": duration], unusedBadEffect: true)),
            "Extended intervals are not clamped; unused effects stay ignored")
        }
      }
    }
  }

  @MainActor
  func testParticlePreparationIgnoresUnreferencedSpriteBounds() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"selected"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 2),
      format: format).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
      }
    let identity = Dictionary(uniqueKeysWithValues:
      ["x1", "y1", "x2", "y2", "x3", "y3", "x4", "y4"].map { ($0, [$0: 1]) })
    func presentation(selected: Int, copies: Int = 1,
      colors: [String] = ["#fff"], repetitions: Int = 1
    ) throws -> RuntimePresentation {
      let zero: [String: Any] = ["from": ["c": 0], "to": ["c": 0]]
      let one: [String: Any] = ["from": ["c": 1], "to": ["c": 1]]
      func effect(_ name: String, sprite: Int) -> [String: Any] {
        let particle: [String: Any] = ["sprite": sprite, "color": "#fff",
          "start": 0, "duration": 1, "x": zero, "y": zero,
          "w": one, "h": one, "r": zero, "a": one]
        let variants = colors.flatMap { color in
          var variant = particle
          variant["color"] = color
          return Array(repeating: variant, count: copies)
        }
        return ["name": name, "transform": identity, "groups": [
          ["count": repetitions, "particles": variants]]]
      }
      let data: [String: Any] = ["width": 4, "height": 2,
        "interpolation": true, "sprites": [
          ["x": -1, "y": 0, "w": 2, "h": 2],
          ["x": 0, "y": 0, "w": 0, "h": 2],
          ["x": 1.25, "y": 0, "w": 1.5, "h": 2],
          ["x": 0, "y": 0, "w": 1_000_000, "h": 1_000_000]],
        "effects": [effect("unused", sprite: 0),
          effect("selected", sprite: selected)]]
      return RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8),
        "particleData": try JSONSerialization.data(withJSONObject: data),
        "particleTexture": texture])
    }
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation(selected: 2))
    XCTAssertEqual(assets.particleSprites.count, 4,
      "Resource sprite indices must not shift during selective preparation")
    XCTAssertNil(assets.particleSprites[0])
    XCTAssertNil(assets.particleSprites[1])
    XCTAssertNotNil(assets.particleSprites[2])
    XCTAssertNil(assets.particleSprites[3])
    let host = makeHost()
    _ = try host.call(function: "SpawnParticleEffect", arguments: [9] + quad + [1, 0])
    let rendered = EngineRenderer.sprites(host: host, assets: assets)
    XCTAssertEqual(rendered.count, 1)
    let sprite = try XCTUnwrap(rendered.first)
    XCTAssertEqual(sprite.textureRegion.minU, 1.25 / 4)
    XCTAssertEqual(sprite.textureRegion.maxU, 2.75 / 4)
    XCTAssertEqual(sprite.points.map(\.x), [-1, -1, 1, 1])
    XCTAssertEqual(sprite.alpha, 1)
    let shared = try EnginePresentationAssets(engine: engine,
      presentation: presentation(selected: 2, copies: 3))
    XCTAssertEqual(shared.particleSprites.compactMap { $0 }.count, 1)
    for mode in 0..<4 {
      let sprites = EngineRenderer.sprites(host: host, assets: shared,
        cacheParticleRandomVariables: mode & 1 != 0,
        cacheParticleProperties: mode & 2 != 0)
      XCTAssertEqual(sprites.count, 3)
      XCTAssertTrue(sprites.allSatisfy { $0.image === sprites.first?.image },
        "Repeated references share the prepared tint without renumbering")
    }
    let white = try XCTUnwrap(shared.particleImage(index: 2, key: "#fff"))
    let green = try XCTUnwrap(shared.particleImage(index: 2, key: "#0f0"))
    XCTAssertFalse(white === green, "Different colors must not reuse a tint")
    XCTAssertTrue(green === shared.particleImage(index: 2, key: "#0f0"))
    // Fractional bounds use a padded 4x2 crop: 32 bytes per tint, not the
    // logical 1.5x2 area. Duplicate definitions/repetitions allocate only once.
    var tintCalls = 0
    let repeated = try presentation(selected: 2, copies: 3, repetitions: 4)
    let bounded = try EnginePresentationAssets(engine: engine,
      presentation: repeated, tintByteLimit: 32, makeTint: { image, color in
        tintCalls += 1
        return try EnginePresentationAssets.tinted(image, color: color)
      })
    XCTAssertEqual(tintCalls, 1)
    XCTAssertNotNil(bounded.particleImage(index: 2, key: "#fff"))
    XCTAssertNil(bounded.particleImage(index: 2, key: "#0f0"))
    XCTAssertEqual(tintCalls, 1, "Unplanned over-budget requests cannot allocate")
    for (colors, budget) in [(["#fff"], 31), (["#fff", "#0f0"], 63)] {
      tintCalls = 0
      XCTAssertThrowsError(try EnginePresentationAssets(engine: engine,
        presentation: presentation(selected: 2, colors: colors),
        tintByteLimit: budget, makeTint: { image, _ in
          tintCalls += 1
          return image
        })) {
          XCTAssertEqual($0 as? EngineTextureBudget.LimitError, .totalSize)
      }
      XCTAssertEqual(tintCalls, 0, "The whole plan must pass before any tint")
    }
    tintCalls = 0
    let two = try EnginePresentationAssets(engine: engine,
      presentation: presentation(selected: 2, colors: ["#fff", "#0f0"]),
      tintByteLimit: 64, makeTint: { image, color in
        tintCalls += 1
        return try EnginePresentationAssets.tinted(image, color: color)
      })
    XCTAssertEqual(tintCalls, 2)
    XCTAssertNotNil(two.particleImage(index: 2, key: "#0f0"))
    XCTAssertEqual(tintCalls, 2, "All declared images are ready before gameplay")
    XCTAssertThrowsError(try EnginePresentationAssets(engine: engine,
      presentation: repeated, makeTint: { _, _ in
        throw EngineInterpreterError.resourcePreparationFailed("particle tint bitmap")
      })) { error in
        XCTAssertTrue(error.localizedDescription.contains("particle tint bitmap"))
    }
    tintCalls = 0
    let retry = try EnginePresentationAssets(engine: engine,
      presentation: repeated, tintByteLimit: 64, makeTint: { image, color in
        tintCalls += 1
        if tintCalls == 2 {
          throw EngineInterpreterError.resourcePreparationFailed("particle tint bitmap")
        }
        return try EnginePresentationAssets.tinted(image, color: color)
      })
    XCTAssertNil(retry.particleImage(index: 2, key: "#0f0"))
    let retried = try XCTUnwrap(retry.particleImage(index: 2, key: "#0f0"),
      "A failed incidental tint must not consume budget or cache wrong pixels")
    XCTAssertEqual(tintCalls, 3)
    XCTAssertTrue(retried === retry.particleImage(index: 2, key: "#0f0"))
    XCTAssertEqual(tintCalls, 3)
    for index in [0, 1, 3, 4] {
      XCTAssertThrowsError(try EnginePresentationAssets(engine: engine,
        presentation: presentation(selected: index)),
        "Invalid selected bounds or indices must still fail: \(index)")
    }
  }

  @MainActor
  func testParticleEasingValidationCoversEveryPropertyAndOptionalDefault() throws {
    let engine = try RuntimeNodeBuilder().engine(archetypes: [])
    let selected = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"fixture"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
      .pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    func presentation(property name: String, ease: String?,
      unusedBadEffect: Bool = false) throws -> RuntimePresentation {
      var particle: [String: Any] = ["sprite": 0, "color": "#fff",
        "start": 0, "duration": 1]
      for key in ["x", "y", "w", "h", "r", "a"] {
        var property: [String: Any] = ["from": ["c": 1], "to": ["c": 2]]
        if key == name { property["ease"] = ease }
        particle[key] = property
      }
      var effects: [[String: Any]] = [["name": "fixture", "transform": [:],
        "groups": [["count": 1, "particles": [particle]]]]]
      if unusedBadEffect {
        var unused = particle
        unused["x"] = ["ease": "outFuture"]
        effects.append(["name": "unused", "transform": [:],
          "groups": [["count": 1, "particles": [unused]]]])
      }
      let data: [String: Any] = ["width": 2, "height": 2, "interpolation": false,
        "sprites": [["x": 0, "y": 0, "w": 2, "h": 2]],
        "effects": effects]
      return RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8), "particleTexture": texture,
        "particleData": try JSONSerialization.data(withJSONObject: data)])
    }
    for key in ["x", "y", "w", "h", "r", "a"] {
      let bad = try presentation(property: key, ease: "outFuture")
      XCTAssertThrowsError(try EnginePresentationAssets(engine: selected,
        presentation: bad)) { error in
        guard case RuntimeBundleError.unsupportedPresentationValue(
          let field, let value) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(field, "particle fixture \(key) easing")
        XCTAssertEqual(value, "outFuture")
      }
      XCTAssertNoThrow(try EnginePresentationAssets(engine: engine,
        presentation: bad), "Unused resource families must remain optional")
    }
    for ease in [nil] + EngineEasing.supportedNames.sorted().map(Optional.some) {
      XCTAssertNoThrow(try EnginePresentationAssets(engine: selected,
        presentation: presentation(property: "x", ease: ease)))
    }
    XCTAssertNoThrow(try EnginePresentationAssets(engine: selected,
      presentation: presentation(property: "x", ease: nil, unusedBadEffect: true)),
      "An unused effect must not reject the selected valid effect in the same resource")
    let omitted = ParticleData.Property(from: ["c": 1], to: ["c": 3], ease: nil)
    XCTAssertEqual(omitted.value(at: 0.25, variables: ["c": 1]), 1.5)
  }

  @MainActor
  func testParticleEasingKeepsResourceCurvesSeparateFromEngineMath() throws {
    let phases = [0.0, 0.25, 0.5, 0.75, 1]
    // Independent values from the pinned public Studio particle curves.
    // Back/Elastic concatenate the inward/outward half curves; Expo retains
    // its nonzero midpoint term. Numerical engine functions use easings.net.
    let examples: [(String, [Double])] = [
      ("inOutBack", [0, -0.04384875, 0.5, 1.04384875, 1]),
      ("inOutElastic", [0, -0.0078125, 0.5, 1.0078125, 1]),
      ("outInExpo", [0, 0.484375, 0.50048828125, 0.515625, 1]),
      ("outInElastic", [0, 0.5078125, 0.499755859375, 0.4921875, 1])]
    for (ease, expected) in examples {
      let data = try JSONSerialization.data(withJSONObject: [
        "from": ["c": 2], "to": ["c": 6], "ease": ease])
      let property = try JSONDecoder().decode(ParticleData.Property.self,
        from: data)
      let tweenData = try JSONSerialization.data(withJSONObject: [
        "from": 2, "to": 6, "duration": 1, "ease": ease])
      let tween = try JSONDecoder().decode(EngineConfiguration.UI.Animation.Tween.self,
        from: tweenData)
      let variables = EngineGeometry.randomVariables(seed: 7)
      let endpoints = property.endpoints(variables: variables)
      for (phase, value) in zip(phases, expected) {
        XCTAssertEqual(property.value(at: phase, variables: variables),
          2 + 4 * value, accuracy: 1e-12, "\(ease) at \(phase)")
        XCTAssertEqual(property.value(at: phase, endpoints: endpoints),
          2 + 4 * value, accuracy: 1e-12)
        XCTAssertEqual(tween.value(at: phase),
          2 + 4 * EngineEasing.value(ease, phase), accuracy: 1e-12,
          "HUD animation must not select the particle-specific curve")
      }
      XCTAssertEqual(property.value(at: -1, variables: variables), 2,
        accuracy: 1e-12)
      XCTAssertEqual(property.value(at: 2, variables: variables), 6,
        accuracy: 1e-12)
    }
    XCTAssertEqual(EngineEasing.value("inOutBack", 0.25), -0.09968184375,
      accuracy: 1e-12)
    XCTAssertEqual(EngineEasing.value("inOutElastic", 0.25),
      0.011969444423734, accuracy: 1e-12)
    XCTAssertEqual(EngineEasing.value("outInExpo", 0.5), 0.5)
    XCTAssertEqual(EngineEasing.value("outInElastic", 0.5), 0.5)
    let exceptions = Set(examples.map(\.0))
    for ease in EngineEasing.supportedNames.subtracting(exceptions) {
      let property = ParticleData.Property(from: ["c": 0], to: ["c": 1],
        ease: ease)
      for phase in phases {
        XCTAssertEqual(property.value(at: phase, variables: ["c": 1]),
          EngineEasing.value(ease, phase), accuracy: 1e-12,
          "Other resource curves must remain unchanged: \(ease)")
      }
    }
  }

  @MainActor
  func testParticleDimensionsAreLocalHalfExtentsBeforeRotation() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"fixture"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
      .pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    // At half duration: center (1/4, -1/8), half width 3/8,
    // half height 1/4. Corner expectations are independent of EngineGeometry.
    let cases: [(Double, Double, [(Double, Double)])] = [
      (0, 1, [(-0.125, -0.375), (-0.125, 0.125),
        (0.625, 0.125), (0.625, -0.375)]),
      (.pi / 2, 1, [(0.5, -0.5), (0, -0.5), (0, 0.25), (0.5, 0.25)]),
      (0, -1, [(0.625, -0.375), (0.625, 0.125),
        (-0.125, 0.125), (-0.125, -0.375)])]
    for (rotation, direction, corners) in cases {
      let particle: [String: Any] = [
        "sprite": 0, "color": "#fff", "start": 0, "duration": 1,
        "x": ["from": ["c": 0.25], "to": ["c": 0.25]],
        "y": ["from": ["c": -0.125], "to": ["c": -0.125]],
        "w": ["from": ["c": 0.25 * direction],
          "to": ["c": 0.5 * direction]],
        "h": ["from": ["c": 0.25], "to": ["c": 0.25]],
        "r": ["from": ["c": rotation], "to": ["c": rotation]],
        "a": ["from": ["c": 1], "to": ["c": 1]]]
      let data: [String: Any] = [
        "width": 2, "height": 2, "interpolation": false,
        "sprites": [["x": 0, "y": 0, "w": 2, "h": 2]],
        "effects": [["name": "fixture", "transform": [
          "x1": ["x1": 1], "y1": ["y1": 1],
          "x2": ["x2": 1], "y2": ["y2": 1],
          "x3": ["x3": 1], "y3": ["y3": 1],
          "x4": ["x4": 1], "y4": ["y4": 1]],
          "groups": [["count": 1, "particles": [particle]]]]]]
      let assets = try EnginePresentationAssets(engine: engine,
        presentation: RuntimePresentation(resources: [
          "configuration": Data(#"{"options":[]}"#.utf8),
          "particleData": try JSONSerialization.data(withJSONObject: data),
          "particleTexture": texture]))
      for xScale in [1.0, 2] {
        let host = makeHost()
        try host.beginFrame(at: 3)
        let spawnQuad = [-xScale, -1, -xScale, 1, xScale, 1, xScale, -1]
        _ = try host.call(function: "SpawnParticleEffect",
          arguments: [9] + spawnQuad + [2, 0])
        try host.beginFrame(at: 4)
        for mode in 0..<4 {
          let sprites = EngineRenderer.sprites(host: host, assets: assets,
            cacheParticleRandomVariables: mode & 1 != 0,
            cacheParticleProperties: mode & 2 != 0)
          XCTAssertEqual(sprites.count, 1)
          let sprite = try XCTUnwrap(sprites.first)
          XCTAssertEqual(sprite.points.count, corners.count)
          for (point, expected) in zip(sprite.points, corners) {
            XCTAssertEqual(point.x, expected.0 * xScale, accuracy: 1e-12)
            XCTAssertEqual(point.y, expected.1, accuracy: 1e-12)
          }
        }
      }
    }
  }

  @MainActor
  func testParticlePropertyDefaultsAndStepEndpoints() throws {
    // The official Studio importer supplies zero coefficients for missing
    // endpoints and linear easing. Its "none" curve steps at exactly 1.
    let examples: [(String, [Double])] = [
      (#"{}"#, [0, 0, 0, 0]),
      (#"{"to":{"c":4}}"#, [0, 1, 3, 4]),
      (#"{"from":{"c":4}}"#, [4, 3, 1, 0]),
      (#"{"from":{},"to":{},"ease":"none"}"#, [0, 0, 0, 0]),
      (#"{"from":{"c":2},"to":{"c":6},"ease":"none"}"#, [2, 2, 2, 6]),
      (#"{"from":{"c":6},"to":{"c":2},"ease":"none"}"#, [6, 6, 6, 2])]
    for (json, expected) in examples {
      let property = try JSONDecoder().decode(ParticleData.Property.self,
        from: Data(json.utf8))
      for variables in [["c": 1.0], EngineGeometry.randomVariables(seed: 123)] {
        let endpoints = property.endpoints(variables: variables)
        for (phase, value) in zip([0.0, 0.25, 0.75, 1], expected) {
          XCTAssertEqual(property.value(at: phase, variables: variables), value)
          XCTAssertEqual(property.value(at: phase, endpoints: endpoints), value)
        }
      }
    }
    XCTAssertEqual(EngineEasing.value("none", 1.0.nextDown), 0)
    XCTAssertEqual(EngineEasing.value("none", 1), 1)
    // Presentation clamps phases; this does not change any engine math API.
    XCTAssertEqual(EngineEasing.value("none", -0.5), 0)
    XCTAssertEqual(EngineEasing.value("none", 1.5), 1)
    XCTAssertFalse(EngineInterpreter.easingFunctions.contains("EaseNone"))
  }

  @MainActor
  func testParticleIntervalsWrapOnlyForLoopedEffects() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"fixture"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
      .pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    func assets(start: Double, duration: Double) throws -> EnginePresentationAssets {
      let particle: [String: Any] = [
        "sprite": 0, "color": "#fff", "start": start, "duration": duration,
        "x": ["from": ["c": 0], "to": ["c": 1]],
        "y": ["to": ["c": 0.5], "ease": "none"], "r": [:],
        "w": ["from": ["c": 0.2], "to": ["c": 0.2]],
        "h": ["from": ["c": 0.2], "to": ["c": 0.2]],
        "a": ["from": ["c": 1], "to": ["c": 0.5]]]
      let data: [String: Any] = [
        "width": 2, "height": 2, "interpolation": false,
        "sprites": [["x": 0, "y": 0, "w": 2, "h": 2]],
        "effects": [["name": "fixture", "transform": [
          "x1": ["x1": 1], "y1": ["y1": 1],
          "x2": ["x2": 1], "y2": ["y2": 1],
          "x3": ["x3": 1], "y3": ["y3": 1],
          "x4": ["x4": 1], "y4": ["y4": 1]],
          "groups": [["count": 1, "particles": [particle]]]]]]
      return try EnginePresentationAssets(engine: engine,
        presentation: RuntimePresentation(resources: [
          "configuration": Data(#"{"options":[]}"#.utf8),
          "particleData": try JSONSerialization.data(withJSONObject: data),
          "particleTexture": texture]))
    }
    // Expected phase values come from the public Studio interval contract,
    // not from the renderer under test. Binary fractions avoid fuzzy endpoints.
    let crossing: [(Double, Double?)] = [
      (0, 0.5), (0.125, 0.75), (0.25, 1), (0.375, nil),
      (0.625, nil), (0.75, 0), (0.875, 0.25),
      (1, 0.5), (1.125, 0.75), (1.25, 1), (1.375, nil), (2, 0.5)]
    let straight: [(Double, Double?)] = [
      (0, nil), (0.125, nil), (0.25, 0), (0.375, 0.5),
      (0.5, 1), (0.625, nil), (1, nil), (1.375, 0.5)]
    let extended: [(Double, Double?)] = [
      (0, nil), (0.125, 0), (0.25, 0.25), (0.375, 0.5),
      (0.625, 1), (0.75, nil), (1, nil), (1.125, 0), (1.625, 1)]
    let negativeStart: [(Double, Double?)] = [
      (0, 0.5), (0.125, 0.75), (0.25, 1), (0.375, nil),
      (1, 0.5), (1.25, 1)]
    let longDuration: [(Double, Double?)] = [
      (0, 0.5), (0.125, 7.0 / 12), (0.25, 0), (0.5, 1.0 / 6),
      (0.75, 1.0 / 3), (0.875, 5.0 / 12), (1, 0.5), (1.25, 0)]
    for (start, duration, samples) in [
      (0.75, 0.5, crossing), (0.25, 0.25, straight),
      (1.125, 0.5, extended), (-0.25, 0.5, negativeStart),
      (0.25, 1.5, longDuration)
    ] {
      let presentation = try assets(start: start, duration: duration)
      for looped in [false, true] {
        let host = makeHost()
        try host.beginFrame(at: 10)
        _ = try host.call(function: "SpawnParticleEffect",
          arguments: [9] + quad + [2, looped ? 1 : 0])
        for (progress, loopPhase) in samples {
          try host.beginFrame(at: 10 + 2 * progress)
          let phase: Double? = looped ? loopPhase
            : (progress >= start && progress <= start + duration && progress < 1
              ? (progress - start) / duration : nil)
          for mode in 0..<4 {
            let sprites = EngineRenderer.sprites(host: host, assets: presentation,
              cacheParticleRandomVariables: mode & 1 != 0,
              cacheParticleProperties: mode & 2 != 0)
            guard let phase else {
              XCTAssertTrue(sprites.isEmpty,
                "loop=\(looped), progress=\(progress), cache=\(mode)")
              continue
            }
            XCTAssertEqual(sprites.count, 1)
            let sprite = try XCTUnwrap(sprites.first)
            let centerX = sprite.points.map(\.x).reduce(0, +) / 4
            let centerY = sprite.points.map(\.y).reduce(0, +) / 4
            XCTAssertEqual(centerX, phase, accuracy: 1e-12)
            XCTAssertEqual(centerY, phase == 1 ? 0.5 : 0, accuracy: 1e-12)
            XCTAssertEqual(sprite.alpha, 1 - 0.5 * phase, accuracy: 1e-12)
          }
        }
      }
    }
  }

  @MainActor
  func testParticleRandomCachingPreservesAnimatedAndMovedSprites() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"fixture"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    let particle: [String: Any] = [
      "sprite": 0, "color": "#fc8", "start": 0, "duration": 1,
      "x": ["from": ["r1": 1], "to": ["sinr2": 1], "ease": "outCubic"],
      "y": ["from": ["cosr3": 1], "to": ["r4": 1]],
      "w": ["from": ["c": 0.1], "to": ["r5": 0.2]],
      "h": ["from": ["c": 0.2], "to": ["r6": 0.3]],
      "r": ["from": ["r7": 1], "to": ["sinr8": 1]],
      "a": ["from": ["c": 1], "to": ["c": 0.1]]]
    let group: [String: Any] = ["count": 4, "particles": [particle, particle]]
    let data: [String: Any] = [
      "width": 2, "height": 2, "interpolation": true,
      "sprites": [["x": 0, "y": 0, "w": 2, "h": 2]],
      "effects": [["name": "fixture", "transform": [
        "x1": ["x1": 1, "r1": 0.1], "y1": ["y1": 1],
        "x2": ["x2": 1], "y2": ["y2": 1],
        "x3": ["x3": 1], "y3": ["y3": 1],
        "x4": ["x4": 1], "y4": ["y4": 1]],
        "groups": Array(repeating: group, count: 4)]]]
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8),
        "particleData": try JSONSerialization.data(withJSONObject: data),
        "particleTexture": texture]))
    let host = makeHost()
    let restore = host.makeRestorePoint()
    for (effectCount, frameCount) in [(8, 120), (64, 35)] {
      for _ in 0..<2 {
        restore() // Reused particle IDs must be safe across restart.
        var elapsed = Array(repeating: 0.0, count: 4)
        var timedFrames = 0
        try host.beginFrame(at: 0)
        for _ in 0..<effectCount {
          _ = try host.call(function: "SpawnParticleEffect",
            arguments: [9] + quad + [0.5, 1])
        }
        for frame in 0..<frameCount {
          try host.beginFrame(at: Double(frame) / 60)
          if frame == 30 {
            _ = try host.call(function: "MoveParticleEffect",
              arguments: [1] + quad.map { $0 * 2 })
            host.memory.set(block: 1004, index: 0, value: 1.5)
          }
          var outputs = Array(repeating: [EngineRenderSprite](), count: 4)
          for mode in frame.isMultiple(of: 2) ? [0, 1, 2, 3] : [3, 2, 1, 0] {
            let started = ProcessInfo.processInfo.systemUptime
            outputs[mode] = EngineRenderer.sprites(host: host, assets: assets,
              cacheParticleRandomVariables: mode & 1 != 0,
              cacheParticleProperties: mode & 2 != 0)
            if frame >= 2 {
              elapsed[mode] += ProcessInfo.processInfo.systemUptime - started
            }
          }
          if frame >= 2 { timedFrames += 1 }
          XCTAssertEqual(outputs[0].count, effectCount * 32)
          let expectedMatrix = (0..<16).map {
            host.memory.value(block: 1004, index: $0)
          }
          for output in outputs.dropFirst() {
            XCTAssertEqual(outputs[0].count, output.count)
            for (original, cached) in zip(outputs[0], output) {
              XCTAssertEqual(original.points, cached.points)
              XCTAssertEqual(original.matrix, cached.matrix)
              XCTAssertEqual(cached.matrix, expectedMatrix,
                "Every particle must use this frame's current transform")
              XCTAssertEqual(original.alpha, cached.alpha)
              XCTAssertTrue(original.image === cached.image)
              XCTAssertEqual(original.interpolation, cached.interpolation)
            }
          }
        }
        print("PARTICLE CACHE \(effectCount * 32) sprites, \(timedFrames) frames: "
          + "mean milliseconds none/random/properties/both "
          + "\(elapsed.map { $0 * 1000 / Double(timedFrames) }); "
          + "paired CPU-only synthetic workload, not live FPS.")
      }
    }
  }

  func testMovingParticlesPreservesLifetime() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    let id = try host.call(function: "SpawnParticleEffect",
      arguments: [9] + quad + [3, 0])
    let before = try XCTUnwrap(host.particles[Int(id)])
    try host.beginFrame(at: 3)
    _ = try host.call(function: "MoveParticleEffect",
      arguments: [id] + quad.map { $0 * 2 })
    let moved = try XCTUnwrap(host.particles[Int(id)])
    XCTAssertEqual(moved.startTime, before.startTime)
    XCTAssertEqual(moved.duration, before.duration)
    XCTAssertEqual(moved.points[0], EnginePoint(x: -2, y: -2))
    _ = try host.call(function: "MoveParticleEffect", arguments: [999] + quad)
    XCTAssertEqual(host.particles.count, 1)
    try host.beginFrame(at: 5)
    XCTAssertTrue(host.particles.isEmpty)
  }

  func testParticlesHaveUniqueHandlesExpireAndCanBeDestroyed() throws {
    let host = makeHost()
    try host.beginFrame(at: 1)
    let first = try host.call(
      function: "SpawnParticleEffect", arguments: [9] + quad + [0.5, 0]
    )
    let loop = try host.call(
      function: "SpawnParticleEffect", arguments: [9] + quad + [0.5, 1]
    )
    XCTAssertNotEqual(first, loop)
    XCTAssertEqual(host.particles.count, 2)
    try host.beginFrame(at: 1.5)
    XCTAssertNil(host.particles[Int(first)])
    XCTAssertNotNil(host.particles[Int(loop)])
    _ = try host.call(function: "DestroyParticleEffect", arguments: [loop])
    _ = try host.call(function: "DestroyParticleEffect", arguments: [loop])
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertEqual(try host.call(
      function: "SpawnParticleEffect", arguments: [999] + quad + [1, 1]
    ), 0)
  }

  func testParticleRandomVariablesDecorrelateNeighboringSeeds() {
    // Repetitions of one group use consecutive seeds. An affine generator
    // advances every r_k by a constant step mod 1 between them.
    let seeds = (0..<256).map { UInt64(7) &* 65_537 &+ UInt64($0) }
    for name in ["r1", "r2", "r8"] {
      let values = seeds.map { EngineGeometry.randomVariables(seed: $0)[name]! }
      let steps = zip(values, values.dropFirst()).map { pair -> Double in
        let step = pair.1 - pair.0
        return ((step - floor(step)) * 1e6).rounded()
      }
      XCTAssertGreaterThan(Set(steps).count, 200, name)
      let mean = values.reduce(0, +) / Double(values.count)
      XCTAssertEqual(mean, 0.5, accuracy: 0.1, name)
      let deviations = values.map { $0 - mean }
      let lagged = zip(deviations, deviations.dropFirst())
        .reduce(0) { $0 + $1.0 * $1.1 }
      let variance = deviations.reduce(0) { $0 + $1 * $1 }
      XCTAssertLessThan(abs(lagged / variance), 0.25, name)
    }
  }

  @MainActor
  func testParticleTintMatchesArithmeticForEveryChannelByte() throws {
    for (width, height) in [(1, 1), (2, 2), (127, 2), (128, 2), (256, 2)] {
      try checkParticleTintArithmetic(width: width, height: height)
    }
  }

  @MainActor
  private func checkParticleTintArithmetic(width: Int, height: Int) throws {
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
      | CGBitmapInfo.byteOrder32Big.rawValue
    func context() throws -> CGContext {
      try XCTUnwrap(CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo))
    }
    let source = try context()
    let pixels = try XCTUnwrap(source.data).bindMemory(to: UInt8.self,
      capacity: source.bytesPerRow * height)
    for value in 0..<width {
      let offset = value * 4
      // Every byte value occurs in each RGB channel, in different orders.
      pixels[offset] = UInt8(value)
      pixels[offset + 1] = UInt8(255 - value)
      pixels[offset + 2] = UInt8((value * 37) % 256)
      pixels[offset + 3] = 255
      // Also exercise valid premultiplied pixels at every alpha, including 0.
      if height > 1 {
        let translucent = source.bytesPerRow + offset
        pixels[translucent] = UInt8(value)
        pixels[translucent + 1] = UInt8(value / 2)
        pixels[translucent + 2] = UInt8(value / 3)
        pixels[translucent + 3] = UInt8(value)
      }
    }
    let original = UIImage(cgImage: try XCTUnwrap(source.makeImage()),
      scale: 2, orientation: .left)
    for color in [UIColor.white, .black, .red,
      UIColor(white: 0.5, alpha: 0.2),
      UIColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 0.3),
      UIColor(red: 1.2, green: -0.2, blue: 1.0 / 3, alpha: 1)] {
      // Independent reference: the original per-pixel arithmetic after the
      // same Core Graphics conversion, without sharing any lookup table.
      let reference = try context()
      reference.draw(try XCTUnwrap(original.cgImage),
        in: CGRect(x: 0, y: 0, width: width, height: height))
      let length = reference.bytesPerRow * height
      let expected = try XCTUnwrap(reference.data).bindMemory(to: UInt8.self,
        capacity: length)
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
      let multipliers = [red, green, blue].map { min(1, max(0, $0)) }
      for offset in stride(from: 0, to: length, by: 4) {
        for channel in 0..<3 {
          expected[offset + channel] = UInt8(
            (CGFloat(expected[offset + channel]) * multipliers[channel]).rounded())
        }
      }
      var checked = false
      let tinted = try EnginePresentationAssets.tinted(original, color: color,
        makeImage: { actual in
          XCTAssertEqual(actual.bytesPerRow, reference.bytesPerRow)
          XCTAssertEqual(Data(bytes: actual.data!, count: length),
            Data(bytes: expected, count: length))
          checked = true
          return actual.makeImage()
        })
      XCTAssertTrue(checked)
      XCTAssertEqual(tinted.scale, original.scale)
      XCTAssertEqual(tinted.imageOrientation, original.imageOrientation)
    }
  }

  @MainActor
  func testParticleTintPreparationFailuresNeverSubstituteOriginalPixels() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let original = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    var contexts = 0, images = 0
    XCTAssertThrowsError(try EnginePresentationAssets.tinted(original, color: .red,
      makeContext: { width, height in
        XCTAssertEqual(width, 2)
        XCTAssertEqual(height, 2)
        contexts += 1
        return nil
      }, makeImage: { _ in images += 1; return nil })) { error in
        XCTAssertTrue(error.localizedDescription.contains("particle tint bitmap"))
    }
    XCTAssertEqual(contexts, 1)
    XCTAssertEqual(images, 0, "Context failure must stop before image creation")
    XCTAssertThrowsError(try EnginePresentationAssets.tinted(original, color: .red,
      makeImage: { _ in images += 1; return nil })) { error in
        XCTAssertTrue(error.localizedDescription.contains("particle tint image"))
    }
    XCTAssertEqual(images, 1)
    XCTAssertThrowsError(try EnginePresentationAssets.tinted(UIImage(), color: .red)) {
      XCTAssertTrue($0.localizedDescription.contains("particle tint source image"))
    }
  }

  @MainActor
  func testParticleTintPreservesTransparencyAndDrawRespectsAlpha() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let size = CGSize(width: 20, height: 20)
    let original = UIGraphicsImageRenderer(size: size, format: format).image {
      UIColor.white.setFill()
      $0.fill(CGRect(x: 5, y: 5, width: 10, height: 10))
    }
    let tinted = try EnginePresentationAssets.tinted(original, color: .red)
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image {
      try! EngineRenderer.drawImage(tinted,
        points: [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
          EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)],
        matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
        alpha: 0.5, context: $0.cgContext, size: size)
    }
    var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
    let context = try XCTUnwrap(CGContext(data: &pixels,
      width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(try XCTUnwrap(rendered.cgImage),
      in: CGRect(origin: .zero, size: size))
    XCTAssertEqual(pixels[(2 * 20 + 2) * 4 + 3], 0,
      "Tinting must not replace transparent pixels with an opaque square")
    let center = (10 * 20 + 10) * 4
    XCTAssertEqual(Double(pixels[center]), 128, accuracy: 1)
    XCTAssertEqual(pixels[center + 1], 0)
    XCTAssertEqual(pixels[center + 2], 0)
    XCTAssertEqual(Double(pixels[center + 3]), 128, accuracy: 1,
      "Sprite drawing must preserve the engine's fade alpha")
    let translucent = UIGraphicsImageRenderer(size: size, format: format).image {
      UIColor.red.withAlphaComponent(0.5).setFill()
      $0.cgContext.fill(CGRect(origin: .zero, size: size))
    }
    let unchanged = try EnginePresentationAssets.tinted(translucent, color: .white)
    context.clear(CGRect(origin: .zero, size: size))
    context.draw(try XCTUnwrap(unchanged.cgImage),
      in: CGRect(origin: .zero, size: size))
    XCTAssertEqual(Double(pixels[center]), 128, accuracy: 1)
    XCTAssertEqual(pixels[center + 1], 0,
      "White tint must not bleach translucent red to pink")
    XCTAssertEqual(pixels[center + 2], 0)
    XCTAssertEqual(Double(pixels[center + 3]), 128, accuracy: 1)
  }
}
