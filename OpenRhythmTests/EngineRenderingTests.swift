import XCTest
import UIKit
import Metal
@testable import OpenRhythm

final class EngineRenderingTests: EngineHostTestCase {
  func testTextureBudgetBoundsWithoutAllocatingLargeImages() throws {
    var budget = EngineTextureBudget(byteLimit: 32_000_000)
    for (width, height) in [(Int.max, 1), (1, Int.max), (-1, 1), (0, 1),
      (4000, 2001), (8193, 1)] {
      XCTAssertThrowsError(try budget.reserve(width: width, height: height)) {
        XCTAssertEqual($0 as? EngineTextureBudget.LimitError, .imageSize)
      }
      XCTAssertEqual(budget.bytes, 0)
    }
    try budget.reserve(width: 4000, height: 2000)
    XCTAssertEqual(budget.bytes, 32_000_000)
    XCTAssertThrowsError(try budget.reserve(width: 1, height: 1))
    XCTAssertEqual(budget.bytes, 32_000_000)
  }

  @MainActor
  func testEngineRenderModePrecedenceAndLegacyPreferenceDefault() throws {
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8)
    ])
    for configured in [nil, "default", "standard", "lightweight"] {
      let skin = EngineSkinDefinition(renderMode: configured, sprites: [])
      for preference in EngineSkinRenderMode.allCases {
        let expected = configured == "standard" ? EngineSkinRenderMode.standard
          : configured == "lightweight" ? .lightweight : preference
        var object: [String: Any] = [
          "skin": ["sprites": []], "effect": ["clips": []],
          "particle": ["effects": []], "nodes": [], "archetypes": [], "buckets": []
        ]
        if let configured { object["skin"] = ["sprites": [], "renderMode": configured] }
        let engine = try JSONDecoder().decode(EnginePlayData.self,
          from: JSONSerialization.data(withJSONObject: object))
        let assets = try EnginePresentationAssets(engine: engine, presentation: presentation)
        assets.configureRenderMode(preferred: preference)
        XCTAssertEqual(assets.skinRenderMode, expected)
        XCTAssertEqual(assets.forcedSkinRenderMode, try skin.forcedRenderMode)
      }
    }
    XCTAssertThrowsError(try EngineSkinDefinition(renderMode: "future",
      sprites: []).forcedRenderMode)
    let legacy = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data(#"{"scoreDisplay":"countDown","noteSpeed":8}"#.utf8))
    XCTAssertEqual(legacy.skinRenderMode, .standard)
    XCTAssertEqual(legacy.noteSpeed, 8)
  }

  @MainActor
  func testLightweightSkinMeshUsesTwoTrianglesWithoutChangingCornersOrFiltering() {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
    let points = [EnginePoint(x: -1, y: -1), EnginePoint(x: -0.2, y: 1),
      EnginePoint(x: 0.2, y: 1), EnginePoint(x: 1, y: -1)]
    var sprite = EngineRenderSprite(image: image, points: points,
      matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      alpha: 0.5, interpolation: true)
    let size = CGSize(width: 400, height: 200)
    let standard = EngineMetalRenderer.vertices(for: sprite, size: size)
    sprite.renderMode = .lightweight
    let lightweight = EngineMetalRenderer.vertices(for: sprite, size: size)
    XCTAssertGreaterThan(standard.count, 6)
    XCTAssertEqual(lightweight.count, 6)
    XCTAssertEqual(Set(lightweight.map(\.position)).count, 4)
    XCTAssertEqual(sprite.points, points)
    XCTAssertTrue(sprite.interpolation)
    XCTAssertTrue(lightweight.allSatisfy { $0.alpha == 0.5 })
    for corner in lightweight {
      XCTAssertTrue(standard.contains { $0.position == corner.position && $0.uv == corner.uv })
    }
  }

  @MainActor
  func testBackgroundAssetsPrepareBlurAndRejectPartialResources() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image {
      UIColor.red.setFill()
      $0.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
      UIColor.blue.setFill()
      $0.fill(CGRect(x: 40, y: 0, width: 40, height: 40))
    }
    var resources = [
      "backgroundData": Data(##"{"fit":"contain","color":"#123"}"##.utf8),
      "backgroundConfiguration": Data(##"{"blur":0,"mask":"#0008"}"##.utf8),
      "backgroundImage": try XCTUnwrap(image.pngData())
    ]
    let plain = try EngineBackgroundAssets(presentation: RuntimePresentation(resources: resources))
    XCTAssertEqual(plain.image.width, 80)
    XCTAssertEqual(plain.image.height, 40)
    XCTAssertEqual(try plain.initialQuad(screenAspect: 1),
      [-1, -0.5, -1, 0.5, 1, 0.5, 1, -0.5])
    resources["backgroundConfiguration"] = Data(##"{"blur":0.8,"mask":"#0000"}"##.utf8)
    let blurred = try EngineBackgroundAssets(presentation: RuntimePresentation(resources: resources))
    XCTAssertEqual(blurred.image.width, 80)
    XCTAssertEqual(blurred.image.height, 40)
    XCTAssertNotEqual(blurred.image.dataProvider?.data as Data?, plain.image.dataProvider?.data as Data?)
    let large = UIGraphicsImageRenderer(size: CGSize(width: 4097, height: 40),
      format: format).image { _ in }
    resources["backgroundImage"] = try XCTUnwrap(large.pngData())
    let bounded = try EngineBackgroundAssets(presentation: RuntimePresentation(resources: resources))
    XCTAssertLessThanOrEqual(bounded.image.width, 2048)
    XCTAssertLessThanOrEqual(bounded.image.height, 2048)
    XCTAssertEqual(bounded.imageAspect, 4097.0 / 40)
    resources["backgroundConfiguration"] = Data(##"{"blur":2,"mask":"#0000"}"##.utf8)
    XCTAssertThrowsError(try EngineBackgroundAssets(presentation: RuntimePresentation(resources: resources)))
    resources.removeValue(forKey: "backgroundConfiguration")
    XCTAssertThrowsError(try EngineBackgroundAssets(presentation: RuntimePresentation(resources: resources)))
  }

  @MainActor
  func testBackgroundLayersCanBeCopiedAndInvalidQuadsHideOnlyTheImage() {
    let background = EngineBackgroundLayer()
    background.prepare(nil)
    background.update(quad: [-1, -1, -1, 1, 1, 1, 1, -1],
      size: CGSize(width: 200, height: 200))
    XCTAssertEqual(background.layer.sublayers?.count, 2)
    XCTAssertEqual(background.layer.sublayers?.first?.isHidden, false)
    // Core Animation presentation copies use init(layer:), not init().
    let copy = CALayer(layer: background.layer)
    XCTAssertFalse(copy === background.layer)
    for child in background.layer.sublayers ?? [] {
      XCTAssertFalse(CALayer(layer: child) === child)
    }
    background.update(quad: Array(repeating: 0, count: 8),
      size: CGSize(width: 200, height: 200))
    XCTAssertEqual(background.layer.sublayers?.first?.isHidden, true)
    XCTAssertEqual(background.layer.sublayers?.last?.isHidden, false)
  }

  func testBackgroundFitScaleAndColorContracts() throws {
    for (fit, expected) in [
      ("width", [-2.0, -0.5, -2, 0.5, 2, 0.5, 2, -0.5]),
      ("contain", [-2.0, -0.5, -2, 0.5, 2, 0.5, 2, -0.5]),
      ("height", [-4.0, -1, -4, 1, 4, 1, 4, -1]),
      ("cover", [-4.0, -1, -4, 1, 4, 1, 4, -1])
    ] {
      let data = EngineBackgroundData(aspectRatio: nil, fit: fit, color: "#000",
        scaleX: nil, scaleY: nil)
      XCTAssertEqual(try data.quad(imageAspect: 4, screenAspect: 2), expected)
    }
    let scaled = EngineBackgroundData(aspectRatio: 2, fit: "height", color: "#abc",
      scaleX: -0.5, scaleY: 2)
    XCTAssertEqual(try scaled.quad(imageAspect: 4, screenAspect: 1),
      [1, -2, 1, 2, -1, 2, -1, -2])
    XCTAssertThrowsError(try EngineBackgroundData(aspectRatio: 0, fit: "cover",
      color: "#000", scaleX: nil, scaleY: nil).quad(imageAspect: 1, screenAspect: 1))
    XCTAssertThrowsError(try EngineBackgroundData(aspectRatio: nil, fit: "future",
      color: "#000", scaleX: nil, scaleY: nil).quad(imageAspect: 1, screenAspect: 1))
    XCTAssertEqual(try EngineHTMLColor("#aBc", allowsAlpha: false),
      try EngineHTMLColor("#aabbcc", allowsAlpha: false))
    XCTAssertEqual(try EngineHTMLColor("#aBc8", allowsAlpha: true),
      try EngineHTMLColor("#aabbcc88", allowsAlpha: true))
    XCTAssertEqual(try EngineHTMLColor("#00000080", allowsAlpha: true).alpha,
      128.0 / 255, accuracy: 0.00001)
    for invalid in ["red", "abc", "#xxf", "#12345", "#123456789", "#１２３"] {
      XCTAssertThrowsError(try EngineHTMLColor(invalid, allowsAlpha: true))
    }
    XCTAssertThrowsError(try EngineHTMLColor("#1234", allowsAlpha: false))
  }

  func testBackgroundPerspectiveMatchesCornersAndNotBilinearInterior() throws {
    let size = CGSize(width: 400, height: 200)
    let quad = [-2.0, -1, -1, 1, 1, 1, 2, -1]
    let transform = try XCTUnwrap(EngineBackgroundProjection.transform(quad: quad, size: size))
    func project(_ u: Double, _ v: Double) -> CGPoint {
      let w = transform.m14 * u + transform.m24 * v + transform.m44
      return CGPoint(x: (transform.m11 * u + transform.m21 * v + transform.m41) / w,
        y: (transform.m12 * u + transform.m22 * v + transform.m42) / w)
    }
    XCTAssertEqual(project(0, 0), CGPoint(x: 100, y: 0))
    XCTAssertEqual(project(1, 0), CGPoint(x: 300, y: 0))
    XCTAssertEqual(project(0, 1), CGPoint(x: 0, y: 200))
    XCTAssertEqual(project(1, 1), CGPoint(x: 400, y: 200))
    XCTAssertEqual(project(0.5, 0.5).x, 200, accuracy: 0.0001)
    XCTAssertEqual(project(0.5, 0.5).y, 200.0 / 3, accuracy: 0.0001)
    XCTAssertNotNil(EngineBackgroundProjection.transform(
      quad: [2, -1, 1, 1, -1, 1, -2, -1], size: size))
    XCTAssertNil(EngineBackgroundProjection.transform(quad: Array(repeating: 0, count: 8), size: size))
    XCTAssertNil(EngineBackgroundProjection.transform(quad: [.nan], size: size))
    XCTAssertNil(EngineBackgroundProjection.transform(quad: quad, size: .zero))
    XCTAssertNil(EngineBackgroundProjection.transform(
      quad: [-1, -1, 1, 1, -1, 1, 1, -1], size: size))
  }

  func testBackgroundInitializedBeforePreprocessAndWritableDuringUpdate() throws {
    let b = RuntimeNodeBuilder()
    let read = b.call("Get", [b.value(1005), b.value(0)])
    let preprocess = b.call("Set", [b.value(2000), b.value(0), read])
    let update = b.call("Set", [b.value(1005), b.value(0), b.value(-0.5)])
    let engine = try b.engine(archetypes: [["name": "stage", "hasInput": false,
      "imports": [], "exports": [], "preprocess": ["index": preprocess],
      "updateSequential": ["index": update]]])
    let level = try JSONDecoder().decode(LevelData.self,
      from: Data(#"{"bgmOffset":0,"entities":[{"archetype":"stage","data":[]}]}"#.utf8))
    for quad in [nil, [-3.0, -2, -3, 2, 3, 2, 3, -2]] {
      let runtime = try EnginePlayRuntime(engine: engine, level: level,
        options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
        particleEffectIDs: [], backgroundQuad: quad)
      XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), quad?[0] ?? -2)
      try runtime.update(at: 0)
      XCTAssertEqual(runtime.memory.value(block: 1005, index: 0), -0.5)
    }
  }

  @MainActor
  func testMetalTextureBudgetCountsUniqueImagesAndRejectsBeforeCaching()
    throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let renderer = try EngineMetalRenderer(device: device, textureByteLimit: 32)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    func image(_ color: UIColor, width: Int = 2) -> UIImage {
      UIGraphicsImageRenderer(size: CGSize(width: width, height: 2),
        format: format).image {
        color.setFill()
        $0.fill(CGRect(x: 0, y: 0, width: width, height: 2))
      }
    }
    let red = image(.red), blue = image(.blue), green = image(.green)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    func encode(_ images: [UIImage], with renderer: EngineMetalRenderer) throws {
      let command = try XCTUnwrap(renderer.queue.makeCommandBuffer())
      let sprites = images.map {
        EngineRenderSprite(image: $0,
          points: [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
            EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)],
          matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
          alpha: 1, interpolation: false)
      }
      try renderer.encode(sprites, size: CGSize(width: 2, height: 2),
        target: target, commandBuffer: command)
      command.commit()
      command.waitUntilCompleted()
      XCTAssertNil(command.error)
    }
    try encode([red, red], with: renderer)
    XCTAssertEqual(renderer.textureBytes, 16, "An alias is not an allocation")
    try encode([red, blue], with: renderer)
    XCTAssertEqual(renderer.textureBytes, 32, "The exact boundary is accepted")
    for _ in 0..<2 {
      XCTAssertThrowsError(try encode([green], with: renderer)) {
        XCTAssertEqual($0 as? EngineMetalRenderer.TextureBudgetError, .totalSize)
        XCTAssertTrue($0.localizedDescription.contains("graphics-memory budget"))
      }
      XCTAssertEqual(renderer.textureBytes, 32, "Rejected uploads are not cached")
    }
    try encode([red, blue], with: renderer)
    let small = try EngineMetalRenderer(device: device, textureByteLimit: 15)
    XCTAssertThrowsError(try encode([red], with: small))
    XCTAssertEqual(small.textureBytes, 0)
    let normal = try EngineMetalRenderer(device: device)
    // About 64 KiB, safely checks the dimension guard without an OOM probe.
    XCTAssertThrowsError(try encode([image(.white, width: 8193)], with: normal)) {
      XCTAssertEqual($0 as? EngineMetalRenderer.TextureBudgetError, .imageSize)
    }
    XCTAssertEqual(normal.textureBytes, 0)
  }

  @MainActor
  func testSkinAliasesShareCropsWithoutSharingTransformsOrResourceLifetime()
    throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"id":1,"name":"one"},
        {"id":2,"name":"alias"},{"id":3,"name":"other"}]},
       "effect":{"clips":[]},"particle":{"effects":[]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4),
      format: format).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 4))
      UIColor.blue.setFill()
      context.fill(CGRect(x: 2, y: 0, width: 2, height: 4))
    }
    for x in [0.0, 0.25] {
      let skin: [String: Any] = ["width": 4, "height": 4,
        "interpolation": true, "sprites": [
          ["name": "one", "x": x, "y": 0, "w": 1, "h": 2,
           "transform": ["x1": ["c": 1]]],
          ["name": "alias", "x": x, "y": 0, "w": 1, "h": 2,
           "transform": ["x1": ["c": 2]]],
          ["name": "other", "x": 2, "y": 0, "w": 1, "h": 2,
           "transform": ["x1": ["c": 3]]]
        ]]
      let presentation = RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8),
        "skinData": try JSONSerialization.data(withJSONObject: skin),
        "skinTexture": png
      ])
      let assets = try EnginePresentationAssets(engine: engine,
        presentation: presentation)
      let one = try XCTUnwrap(assets.skin[1])
      let alias = try XCTUnwrap(assets.skin[2])
      let other = try XCTUnwrap(assets.skin[3])
      XCTAssertTrue(one.image === alias.image,
        "Metal's identity cache must upload one texture per exact crop")
      XCTAssertEqual(Set(assets.preparedImages.map(ObjectIdentifier.init)).count, 2)
      XCTAssertEqual(one.textureRegion, alias.textureRegion)
      XCTAssertEqual(one.transform, ["x1": ["c": 1]])
      XCTAssertEqual(alias.transform, ["x1": ["c": 2]])
      XCTAssertEqual(other.transform, ["x1": ["c": 3]])
      XCTAssertFalse(one.image === other.image)
      XCTAssertNotEqual(one.image.pngData(), other.image.pngData())
      let replacement = try EnginePresentationAssets(engine: engine,
        presentation: presentation)
      XCTAssertFalse(one.image === replacement.skin[1]?.image,
        "Crop reuse must not retain or mix different presentation lifetimes")
    }
  }

  @MainActor
  func testFractionalResourceSpritesPreserveExactAtlasRegions() throws {
    try checkFractionalResourceSprites(x: 1.25, y: 0.5, w: 2.5, h: 1.25)
  }

  @MainActor
  func testFractionalResourceSpritesAtAtlasEdgesAndBelowOnePixel() throws {
    try checkFractionalResourceSprites(x: 4.25, y: 2.25, w: 1.75, h: 1.75)
    try checkFractionalResourceSprites(x: 0.1, y: 0.2, w: 0.25, h: 0.3)
  }

  @MainActor
  private func checkFractionalResourceSprites(
    x: Double, y: Double, w: Double, h: Double
  ) throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let metal = try EngineMetalRenderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 40, height: 40, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    func gpuBytes(_ sprite: EngineRenderSprite) throws -> [UInt8] {
      let command = try XCTUnwrap(metal.queue.makeCommandBuffer())
      try metal.encode([sprite], size: CGSize(width: 40, height: 40),
        target: target, commandBuffer: command)
      command.commit()
      command.waitUntilCompleted()
      XCTAssertNil(command.error)
      var bytes = [UInt8](repeating: 0, count: 40 * 40 * 4)
      target.getBytes(&bytes, bytesPerRow: 160,
        from: MTLRegionMake2D(0, 0, 40, 40), mipmapLevel: 0)
      return bytes
    }
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"id":7,"name":"note"}]},"effect":{"clips":[]},
       "particle":{"effects":[{"id":9,"name":"hit"}]},
       "archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let atlas = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 4),
      format: format).image { context in
      for y in 0..<4 {
        for x in 0..<6 {
          UIColor(red: Double(x) / 5, green: Double(y) / 3,
            blue: (x + y).isMultiple(of: 2) ? 1 : 0, alpha: 1).setFill()
          context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
      }
    }
    let transform = Dictionary(uniqueKeysWithValues: (1...4).flatMap { index in
      ["x\(index)", "y\(index)"].map { ($0, [$0: 1.0]) }
    })
    let rectangle: [String: Any] = ["x": x, "y": y, "w": w, "h": h]
    var skinSprite = rectangle
    skinSprite["name"] = "note"
    skinSprite["transform"] = transform
    var particle: [String: Any] = ["sprite": 0, "color": "#6c9",
      "start": 0, "duration": 1]
    for key in ["x", "y", "w", "h", "r", "a"] {
      let value = ["w", "h", "a"].contains(key) ? 1.0 : 0.0
      particle[key] = ["from": ["c": value], "to": ["c": value]]
    }
    let fullRegion = EngineTextureRegion(minU: x / 6,
      minV: 1 - (y + h) / 4, maxU: (x + w) / 6, maxV: 1 - y / 4)
    for linear in [false, true] {
      let skin: [String: Any] = ["width": 6, "height": 4,
        "interpolation": linear, "sprites": [skinSprite]]
      let particles: [String: Any] = ["width": 6, "height": 4,
        "interpolation": linear, "sprites": [rectangle], "effects": [
          ["name": "hit", "transform": transform,
           "groups": [["count": 1, "particles": [particle]]]]]]
      let assets = try EnginePresentationAssets(engine: engine,
        presentation: RuntimePresentation(resources: [
          "configuration": Data(#"{"options":[]}"#.utf8),
          "skinData": try JSONSerialization.data(withJSONObject: skin),
          "particleData": try JSONSerialization.data(withJSONObject: particles),
          "skinTexture": try XCTUnwrap(atlas.pngData()),
          "particleTexture": try XCTUnwrap(atlas.pngData())]))
      let host = makeHost()
      _ = try host.call(function: "Draw", arguments: [7] + quad + [0, 1])
      _ = try host.call(function: "SpawnParticleEffect",
        arguments: [9] + quad + [1, 0])
      let rendered = EngineRenderer.sprites(host: host, assets: assets)
      XCTAssertEqual(rendered.count, 2)
      for (index, sprite) in rendered.enumerated() {
        let source = try index == 0 ? atlas : EnginePresentationAssets.tinted(atlas,
          color: UIColor(red: 0.4, green: 0.8, blue: 0.6, alpha: 1))
        let reference = EngineRenderSprite(image: source, points: sprite.points,
          matrix: sprite.matrix, alpha: sprite.alpha, interpolation: linear,
          textureRegion: fullRegion)
        let actual = try EngineSoftwareRenderer.render([sprite],
          size: CGSize(width: 40, height: 40))
        let expected = try EngineSoftwareRenderer.render([reference],
          size: CGSize(width: 40, height: 40))
        let actualBytes = try XCTUnwrap(actual.dataProvider?.data) as Data
        let expectedBytes = try XCTUnwrap(expected.dataProvider?.data) as Data
        // Independent whole-atlas UVs catch both rounded bounds and loss of
        // neighboring texels needed by linear interpolation near crop edges.
        let maximumError = zip(actualBytes, expectedBytes).map {
          abs(Int($0) - Int($1))
        }.max() ?? 0
        XCTAssertLessThanOrEqual(maximumError, 1, "linear=\(linear)")
        let actualGPU = try gpuBytes(sprite)
        let expectedGPU = try gpuBytes(reference)
        let maximumGPUError = zip(actualGPU, expectedGPU).map {
          abs(Int($0) - Int($1))
        }.max() ?? 0
        XCTAssertLessThanOrEqual(maximumGPUError, 1, "GPU linear=\(linear)")
      }
      _ = try host.call(function: "DrawCurvedLR", arguments:
        [7] + quad + [1, 1, 2, -1, 0, 1, 0])
      _ = try host.call(function: "DrawCurvedBT", arguments:
        [7] + quad + [2, 1, 2, 0, -1, 0, 1])
      let curves = EngineRenderer.sprites(host: host, assets: assets)
      let region = rendered[0].textureRegion
      XCTAssertEqual(curves[1].textureRegion.minU, region.minU)
      XCTAssertEqual(curves[1].textureRegion.maxU, region.maxU)
      XCTAssertEqual(curves[1].textureRegion.minV, region.minV)
      XCTAssertEqual(curves[1].textureRegion.maxV,
        (region.minV + region.maxV) / 2, accuracy: 1e-12)
      XCTAssertEqual(curves[2].textureRegion.minV,
        curves[1].textureRegion.maxV, accuracy: 1e-12)
      XCTAssertEqual(curves[2].textureRegion.maxV, region.maxV)
      XCTAssertEqual(curves[3].textureRegion.minV, region.minV)
      XCTAssertEqual(curves[3].textureRegion.maxV, region.maxV)
      XCTAssertEqual(curves[3].textureRegion.minU, region.minU)
      XCTAssertEqual(curves[3].textureRegion.maxU,
        (region.minU + region.maxU) / 2, accuracy: 1e-12)
      XCTAssertEqual(curves[4].textureRegion.minU,
        curves[3].textureRegion.maxU, accuracy: 1e-12)
      XCTAssertEqual(curves[4].textureRegion.maxU, region.maxU)
    }
  }

  @MainActor
  func testCurvesApplyCornerCoupledSkinTransformBeforeControlInterpolation() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"id":7,"name":"note"}]},"effect":{"clips":[]},
       "particle":{"effects":[]},"archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let png = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData {
      UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8),
        "skinData": Data(#"""
          {"width":1,"height":1,"interpolation":false,"sprites":[
            {"name":"note","x":0,"y":0,"w":1,"h":1,"transform":{
              "x1":{"x1":0.5,"x3":0.5},"y1":{"y1":0.5,"y3":0.5},
              "x2":{"x2":1},"y2":{"y2":1},
              "x3":{"x3":1},"y3":{"y3":1},
              "x4":{"x4":1},"y4":{"y4":1}}}]}
          """#.utf8),
        "skinTexture": png,
        "particleData": Data(#"""
          {"width":1,"height":1,"interpolation":false,"sprites":[],"effects":[]}
          """#.utf8),
        "particleTexture": png
      ]))
    let host = makeHost()
    host.memory.set(block: 1003, index: 3, value: 0.1)
    XCTAssertEqual(assets.skin[7]?.textureRegion, .full,
      "Integral sprites retain the full-region affine fast path")
    XCTAssertEqual(assets.skin[7]?.image.cgImage?.width, 1)
    XCTAssertEqual(assets.skin[7]?.image.cgImage?.height, 1)
    _ = try host.call(function: "DrawCurvedLR", arguments:
      [7] + quad + [0, 1, 2, 0, 0, 1, 0])
    host.memory.set(block: 1003, index: 3, value: 0.9)
    let sprites = EngineRenderer.sprites(host: host, assets: assets)
    XCTAssertEqual(sprites.count, 2)
    XCTAssertEqual(sprites[0].points[0], EnginePoint(x: 0, y: 0))
    XCTAssertEqual(sprites[0].points[1], EnginePoint(x: -0.125, y: 0.375))
    XCTAssertEqual(sprites[0].points[2], EnginePoint(x: 1, y: 0))
    XCTAssertEqual(sprites[0].matrix[3], 0.1)
    let vertices = EngineMetalRenderer.vertices(for: sprites[0],
      size: CGSize(width: 200, height: 100))
    XCTAssertEqual(try XCTUnwrap(vertices.first).position.x, 0.05, accuracy: 1e-6)
    _ = try host.call(function: "Draw", arguments: [7] + quad + [1, 1])
    assets.configureRenderMode(preferred: .lightweight)
    let lightweight = EngineRenderer.sprites(host: host, assets: assets)
    XCTAssertEqual(lightweight.count, 3)
    XCTAssertTrue(lightweight.allSatisfy { $0.renderMode == .lightweight })
    for sprite in lightweight {
      XCTAssertEqual(EngineMetalRenderer.vertices(for: sprite,
        size: CGSize(width: 200, height: 100)).count, 6)
    }
    XCTAssertEqual(lightweight[0].points, sprites[0].points)
    XCTAssertEqual(lightweight[1].textureRegion, sprites[1].textureRegion)
  }

  @MainActor
  func testOrdinaryWarpedDrawsShareOneSoftwareFrameBudget() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1),
      format: format).image {
      UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    let sprite = EngineRenderSprite(image: image,
      points: [EnginePoint(x: -1, y: -1), EnginePoint(x: -0.5, y: 1),
        EnginePoint(x: 0.5, y: 1), EnginePoint(x: 1, y: -1)],
      matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      alpha: 0.5, interpolation: false)
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40,
      bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    XCTAssertNoThrow(try EngineRenderer.draw([sprite], context: context,
      size: CGSize(width: 40, height: 40), pixelBudget: 10000))
    XCTAssertThrowsError(try EngineRenderer.draw(Array(repeating: sprite, count: 64),
      context: context, size: CGSize(width: 40, height: 40), pixelBudget: 10000)) {
      XCTAssertTrue($0.localizedDescription.contains("software pixel work per frame"))
      XCTAssertFalse($0.localizedDescription.contains("callback"))
    }
  }

  @MainActor
  func testSoftwarePixelBudgetScalesWithFramePixels() {
    // Thumbnails keep the old fixed floor; a 13-inch iPad frame gets more.
    XCTAssertEqual(EngineSoftwareRenderer.pixelBudget(width: 128, height: 128),
      64_000_000)
    XCTAssertEqual(EngineSoftwareRenderer.pixelBudget(width: 2752, height: 2064),
      16 * 2752 * 2064)
    XCTAssertGreaterThan(
      EngineSoftwareRenderer.pixelBudget(width: 2752, height: 2064), 64_000_000)
  }

  @MainActor
  func testSoftwareCoveragePreservesTranslucentReflectedAndFoldedCurves() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal is unavailable on this test device")
    }
    let metal = try EngineMetalRenderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 40, height: 40, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4),
      format: format).image {
      UIColor.red.withAlphaComponent(0.5).setFill()
      $0.fill(CGRect(x: 0, y: 0, width: 2, height: 4))
    }
    let blue = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1),
      format: format).image {
      UIColor.blue.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    let reflected: [Double] = [-1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    let full = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)]
    let folded = [EnginePoint(x: -0.8, y: -0.8), EnginePoint(x: -0.8, y: 0.2),
      EnginePoint(x: 0.8, y: 0.2), EnginePoint(x: 0.8, y: -0.8)]
    let cases = EngineSkinRenderMode.allCases.flatMap { mode in
      [(false, false), (false, true), (true, false), (true, true)].map {
        (mode, $0.0, $0.1)
      }
    }
    for (mode, folding, linear) in cases {
      let patches = EngineGeometry.curvedPatches(folding ? folded : full,
        curve: EngineCurve(edge: .leftRight, segments: 8,
          controls: [EnginePoint(x: -1, y: folding ? 3 : 0),
            EnginePoint(x: 1, y: folding ? 3 : 0)]))
      let background = EngineRenderSprite(image: blue, points: full,
        matrix: identity, alpha: 1, interpolation: false)
      let sprites = [background] + patches.map {
        EngineRenderSprite(image: image, points: $0.points, matrix: reflected,
          alpha: 0.5, interpolation: linear, textureRegion: $0.region,
          renderMode: mode)
      }
      let cpu = try EngineSoftwareRenderer.render(sprites, size: CGSize(width: 40, height: 40))
      let bytes = try XCTUnwrap(cpu.dataProvider?.data) as Data
      let command = try XCTUnwrap(metal.queue.makeCommandBuffer())
      try metal.encode(sprites, size: CGSize(width: 40, height: 40),
        target: target, commandBuffer: command)
      command.commit(); command.waitUntilCompleted()
      XCTAssertNil(command.error)
      var gpu = [UInt8](repeating: 0, count: 40 * 40 * 4)
      target.getBytes(&gpu, bytesPerRow: 160,
        from: MTLRegionMake2D(0, 0, 40, 40), mipmapLevel: 0)
      for y in 12..<28 {
        for x in [14, 19, 20, 26] {
          let offset = (y * 40 + x) * 4
          for channel in 0..<3 {
            XCTAssertEqual(Double(bytes[offset + channel]),
              Double(gpu[offset + 2 - channel]), accuracy: 1)
          }
        }
      }
      let red = bytes[(13 * 40 + 26) * 4]
      XCTAssertEqual(Double(red), folding ? 112 : 64, accuracy: 1,
        "Real folded overlap blends twice; shared triangle edges blend once")
      XCTAssertEqual(bytes[(13 * 40 + 14) * 4 + 2], 255,
        "Transparent texels must leave the earlier blue sprite intact")
      XCTAssertThrowsError(try EngineSoftwareRenderer.render(sprites,
        size: CGSize(width: 40, height: 40), pixelBudget: 1))
      XCTAssertThrowsError(try EngineSoftwareRenderer.render(sprites,
        size: CGSize(width: 1e100, height: 40)))
      let scaled = try EngineSoftwareRenderer.render(sprites,
        size: CGSize(width: 40, height: 40), scale: 2)
      XCTAssertEqual(scaled.width, 80)
    }
  }

  func testEveryCurvedDrawRetainsControlsDepthAndSharesAFrameBudget() throws {
    let host = makeHost()
    let base: [Double] = [7, -1, -1, -1, 1, 1, 1, 1, -1, 4, 0.5]
    for suffix in ["B", "T", "L", "R", "BT", "LR"] {
      try host.beginFrame(at: 0)
      let controls: [Double] = suffix.count == 2 ? [0, 0, 0.5, 0.5] : [0, 0]
      let function = "DrawCurved" + suffix
      XCTAssertTrue(CommandEngineRuntimeHost.supportedFunctions.contains(function))
      _ = try host.call(function: function, arguments: base + [8] + controls + [5, 6, 7])
      let draw = try XCTUnwrap(host.draws.first)
      XCTAssertEqual(draw.curve?.edge.rawValue, suffix)
      XCTAssertEqual(draw.curve?.segments, 8)
      XCTAssertEqual(draw.curve?.controls.count, suffix.count)
      XCTAssertEqual(draw.zValues, [4, 5, 6, 7])
      XCTAssertEqual(draw.alpha, 0.5)
      XCTAssertThrowsError(try host.call(function: function, arguments: base + [0] + controls))
      XCTAssertThrowsError(try host.call(function: function, arguments: base + [0.5] + controls))
      XCTAssertNoThrow(try host.call(function: function, arguments: base + [1025] + controls))
    }
    try host.beginFrame(at: 0)
    for _ in 0..<16 {
      _ = try host.call(function: "DrawCurvedB", arguments: base + [1024, 0, 0])
    }
    XCTAssertThrowsError(try host.call(function: "Draw", arguments: base))
    try host.beginFrame(at: 1)
    XCTAssertNoThrow(try host.call(function: "Draw", arguments: base))
    XCTAssertThrowsError(try host.call(function: "DrawCurvedB",
      arguments: base + [16_384, 0, 0]))
    XCTAssertEqual(host.draws.count, 1, "Rejected work must not append a command")
    XCTAssertNoThrow(try host.call(function: "DrawCurvedB",
      arguments: base + [16_383, 0, 0]))
    XCTAssertEqual(host.draws.count, 2)
    try host.beginFrame(at: 2)
    XCTAssertThrowsError(try host.call(function: "DrawCurvedB",
      arguments: base + [16_385, 0, 0])) {
      guard case EngineInterpreterError.resourceLimitExceeded("draw segments per frame") = $0 else {
        return XCTFail("Expected shared work-budget error, got \($0)")
      }
    }
  }

  func testLongCurvesRetainEverySegmentWithinTheSharedFrameBudget() throws {
    let host = makeHost()
    let quad = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)]
    let base: [Double] = [7, -1, -1, -1, 1, 1, 1, 1, -1, 0, 1]
    for segments in [0, -1, 16_385, Int.max] {
      XCTAssertTrue(EngineGeometry.curvedPatches(quad, curve: EngineCurve(
        edge: .bottom, segments: segments,
        controls: [EnginePoint(x: 0, y: 0)])).isEmpty)
    }
    for suffix in ["B", "T", "L", "R", "BT", "LR"] {
      let controls: [Double] = suffix.count == 2 ? [0, 0, 0.5, 0.5] : [0, 0]
      for segments in [1025, 4096, 16_384] {
        try host.beginFrame(at: 0)
        XCTAssertEqual(try host.call(function: "DrawCurved" + suffix,
          arguments: base + [Double(segments)] + controls), 0)
        guard let curve = host.draws.first?.curve else {
          XCTFail("Missing curve: \(suffix), \(segments)")
          continue
        }
        XCTAssertEqual(curve.segments, segments)
        let patches = EngineGeometry.curvedPatches(quad, curve: curve)
        XCTAssertEqual(patches.count, segments)
        guard patches.count == segments else { continue }
        let vertical = ["L", "R", "LR"].contains(suffix)
        XCTAssertEqual(vertical ? patches[0].region.minV : patches[0].region.minU, 0)
        XCTAssertEqual(vertical ? patches.last!.region.maxV : patches.last!.region.maxU, 1)
        for index in 1..<patches.count {
          let previous = patches[index - 1], current = patches[index]
          XCTAssertEqual(vertical ? previous.region.maxV : previous.region.maxU,
            vertical ? current.region.minV : current.region.minU)
          XCTAssertEqual(previous.points[vertical ? 1 : 3], current.points[0])
          XCTAssertEqual(previous.points[2], current.points[vertical ? 3 : 1])
        }
        // A regular Draw consumes one segment from the same budget.
        if segments == 16_384 {
          XCTAssertThrowsError(try host.call(function: "Draw", arguments: base)) {
            guard case EngineInterpreterError.resourceLimitExceeded("draw segments per frame") = $0 else {
              return XCTFail("Expected shared work-budget error, got \($0)")
            }
          }
        }
      }
    }
    try host.beginFrame(at: 1)
    XCTAssertNoThrow(try host.call(function: "Draw", arguments: base))
  }

  func testCurvedEdgesUseBilinearControlsAndContiguousTextureSlices() throws {
    let quad = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)]
    for edge in [EngineCurve.Edge.bottom, .top, .left, .right, .bottomTop, .leftRight] {
      let paired = edge == .bottomTop || edge == .leftRight
      let patches = EngineGeometry.curvedPatches(quad,
        curve: EngineCurve(edge: edge, segments: 2,
          controls: Array(repeating: EnginePoint(x: 0, y: 0), count: paired ? 2 : 1)))
      XCTAssertEqual(patches.count, 2)
      let vertical = [.left, .right, .leftRight].contains(edge)
      if vertical {
        XCTAssertEqual(patches[0].points[1], patches[1].points[0])
        XCTAssertEqual(patches[0].points[2], patches[1].points[3])
        XCTAssertEqual(patches[0].region.maxV, patches[1].region.minV)
        XCTAssertEqual(patches[0].points[1].x, edge == .right ? -1 : -0.5)
        XCTAssertEqual(patches[0].points[2].x, edge == .left ? 1 : 0.5)
      } else {
        XCTAssertEqual(patches[0].points[3], patches[1].points[0])
        XCTAssertEqual(patches[0].points[2], patches[1].points[1])
        XCTAssertEqual(patches[0].region.maxU, patches[1].region.minU)
        XCTAssertEqual(patches[0].points[3].y, edge == .top ? -1 : -0.5)
        XCTAssertEqual(patches[0].points[2].y, edge == .bottom ? 1 : 0.5)
      }
      XCTAssertEqual(patches[0].points[0], quad[0])
      XCTAssertEqual(patches[1].points[2], quad[2])
      XCTAssertTrue(patches.allSatisfy { $0.region.isValid })
    }
    let warped = [EnginePoint(x: -2, y: -1), EnginePoint(x: -1, y: 2),
      EnginePoint(x: 3, y: 1), EnginePoint(x: 1, y: -2)]
    let patches = EngineGeometry.curvedPatches(warped,
      curve: EngineCurve(edge: .left, segments: 2,
        controls: [EnginePoint(x: 0.5, y: -0.5)]))
    // Bilinear weights at (u=.75,v=.25): 3/16,1/16,3/16,9/16.
    let control = EnginePoint(x: 0.6875, y: -1)
    XCTAssertEqual(patches[0].points[1].x,
      0.25 * warped[0].x + 0.5 * control.x + 0.25 * warped[1].x)
    XCTAssertEqual(patches[0].points[1].y,
      0.25 * warped[0].y + 0.5 * control.y + 0.25 * warped[1].y)
  }

  @MainActor
  func testCurveTextureSlicesRenderOnceAndWithoutAlphaSeamsInBothBackends() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal is unavailable on this test device")
    }
    let metal = try EngineMetalRenderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 40, height: 40, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4),
      format: format).image {
      for (rect, color) in [(CGRect(x: 0, y: 0, width: 2, height: 2), UIColor.red),
        (CGRect(x: 2, y: 0, width: 2, height: 2), .green),
        (CGRect(x: 0, y: 2, width: 2, height: 2), .blue),
        (CGRect(x: 2, y: 2, width: 2, height: 2), .white)] {
        color.setFill(); $0.fill(rect)
      }
    }
    let quad = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)]
    let matrix: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    for (edge, segments) in [EngineCurve.Edge.leftRight, .bottomTop].flatMap({ edge in
      [8, 1025].map { (edge, $0) }
    }) {
      let patches = EngineGeometry.curvedPatches(quad, curve: EngineCurve(
        edge: edge, segments: segments, controls: [EnginePoint(x: 0, y: 0),
          EnginePoint(x: 0, y: 0)]))
      let sprites = patches.map {
        EngineRenderSprite(image: image, points: $0.points, matrix: matrix,
          alpha: 0.5, interpolation: false, textureRegion: $0.region)
      }
      let command = try XCTUnwrap(metal.queue.makeCommandBuffer())
      try metal.encode(sprites, size: CGSize(width: 40, height: 40),
        target: target, commandBuffer: command)
      command.commit(); command.waitUntilCompleted()
      XCTAssertNil(command.error)
      var gpu = [UInt8](repeating: 0, count: 40 * 40 * 4)
      target.getBytes(&gpu, bytesPerRow: 160,
        from: MTLRegionMake2D(0, 0, 40, 40), mipmapLevel: 0)
      let output = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40),
        format: format).image { output in
        output.cgContext.interpolationQuality = .none
        try! EngineRenderer.draw(sprites, context: output.cgContext,
          size: CGSize(width: 40, height: 40))
      }
      var cpu = [UInt8](repeating: 0, count: 40 * 40 * 4)
      let context = try XCTUnwrap(CGContext(data: &cpu, width: 40, height: 40,
        bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(try XCTUnwrap(output.cgImage),
        in: CGRect(x: 0, y: 0, width: 40, height: 40))
      for (x, y, rgb) in [(14, 14, [128, 0, 0]), (26, 14, [0, 128, 0]),
        (14, 26, [0, 0, 128]), (26, 26, [128, 128, 128])] {
        let pixel = (y * 40 + x) * 4
        for channel in 0..<3 {
          XCTAssertEqual(Double(gpu[pixel + 2 - channel]), Double(rgb[channel]), accuracy: 1)
          XCTAssertEqual(Double(cpu[pixel + channel]), Double(rgb[channel]), accuracy: 1)
        }
      }
      for y in 12..<28 {
        for x in 18..<22 {
          XCTAssertEqual(Double(cpu[(y * 40 + x) * 4 + 3]), 128, accuracy: 1)
        }
      }
    }
  }

  func testDrawRetainsGeometryAlphaDepthAndTransformForOneFrame() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    host.memory.set(block: 1003, index: 0, value: 0.5)
    XCTAssertEqual(try host.call(
      function: "Draw", arguments: [7] + quad + [42, 0.75]
    ), 0)
    host.memory.set(block: 1003, index: 0, value: 1)
    let draw = try XCTUnwrap(host.draws.first)
    XCTAssertEqual(draw.points, [
      EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)
    ])
    XCTAssertEqual(draw.spriteID, 7)
    XCTAssertEqual(draw.z, 42)
    XCTAssertEqual(draw.alpha, 0.75)
    XCTAssertEqual(draw.transform[0], 0.5)
    _ = try host.call(function: "Draw", arguments: [88] + quad + [0, 1])
    XCTAssertEqual(host.draws.count, 1, "Missing sprites must not be drawn")
    try host.beginFrame(at: 3)
    XCTAssertTrue(host.draws.isEmpty)
  }

  func testExtendedDrawPadsZValues() throws {
    let host = makeHost()
    for extra in 0...3 {
      _ = try host.call(
        function: "Draw",
        arguments: [7] + quad + [100, 1] + Array([-2.0, -3, 4].prefix(extra))
      )
      XCTAssertEqual(host.draws.last?.zValues,
        [100] + Array([-2.0, -3, 4].prefix(extra))
          + Array(repeating: 0, count: 3 - extra))
    }
  }

  func testPresentationReferencesHonorOverridesAndEachResourceSource() throws {
    let item = Data(#"""
      {"source":"https://level.example/game",
       "bgm":{"url":"bgm"},"data":{"url":"level"},
       "useSkin":{"useDefault":false,"item":{
         "source":"https://skin.example/custom",
         "data":{"url":"data"},"texture":{"url":"texture"}}},
       "useParticle":{"useDefault":true},
       "useBackground":{"useDefault":false,"item":{
         "source":"https://background.example/custom",
         "data":{"url":"data"},"image":{"url":"image"},
         "configuration":{"url":"config"}}},
       "engine":{"version":13,"source":"https://engine.example/game",
         "playData":{"url":"play"},"configuration":{"url":"config"},
         "skin":{"data":{"url":"ignored"},"texture":{"url":"ignored"}},
         "effect":{"data":{"url":"effects"},"audio":{"url":"audio"}},
         "particle":{"source":"https://particle.example",
           "data":{"url":"data"},"texture":{"url":"texture"}}}}
      """#.utf8)
    let references = try RuntimeResourceReferences(
      itemData: item, serverBaseURL: URL(string: "https://fallback.example")!
    )
    XCTAssertEqual(references.presentationURLs["skinTexture"]?.absoluteString,
      "https://skin.example/custom/texture")
    XCTAssertEqual(references.presentationURLs["effectAudio"]?.absoluteString,
      "https://engine.example/game/audio")
    XCTAssertEqual(references.presentationURLs["particleData"]?.absoluteString,
      "https://particle.example/data")
    XCTAssertEqual(references.presentationURLs["configuration"]?.absoluteString,
      "https://engine.example/game/config")
    XCTAssertEqual(references.presentationURLs["backgroundData"]?.absoluteString,
      "https://background.example/custom/data")
    XCTAssertEqual(references.presentationURLs["backgroundImage"]?.absoluteString,
      "https://background.example/custom/image")
    XCTAssertEqual(references.presentationURLs["backgroundConfiguration"]?.absoluteString,
      "https://background.example/custom/config")
  }

  func testGeometryUsesRowMajorTransformsAndBilinearCoordinates() {
    let point = EnginePoint(x: 0, y: 1)
    let matrix: [Double] = [
      1.25,0,0,0, 0,-1.25,0,0.5, 0,0,1,0, 0,0,0,1
    ]
    XCTAssertEqual(EngineGeometry.screenPoint(point, matrix: matrix,
      size: CGSize(width: 900, height: 500)), CGPoint(x: 450, y: 437.5))
    let points = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 2, y: 1), EnginePoint(x: 1, y: -1)]
    XCTAssertEqual(EngineGeometry.bilinear(points, u: 0.5, v: 0.5),
      EnginePoint(x: 0.25, y: 0))
    let variables = EngineGeometry.randomVariables(seed: 123)
    XCTAssertEqual(variables, EngineGeometry.randomVariables(seed: 123))
    XCTAssertEqual(variables["sinr1"]!, sin(2 * .pi * variables["r1"]!))
    XCTAssertEqual(EngineEasing.value("outCubic", 0.5), 0.875)
  }

  @MainActor
  func testTessellationGridMatchesBilinearGeometryAndUVs() {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .image { _ in }
    let size = CGSize(width: 1800, height: 1000)
    let quads = [
      [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
       EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)],
      [EnginePoint(x: -1.3, y: -0.9), EnginePoint(x: -0.2, y: 0.8),
       EnginePoint(x: 0.4, y: 0.6), EnginePoint(x: 1.4, y: -0.5)]
    ]
    for points in quads {
      let sprite = EngineRenderSprite(image: image, points: points,
        matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
        alpha: 0.4, interpolation: true)
      let vertices = EngineMetalRenderer.vertices(for: sprite, size: size)
      XCTAssertFalse(vertices.isEmpty)
      XCTAssertTrue(vertices.count.isMultiple(of: 6))
      for vertex in vertices {
        let point = EngineGeometry.bilinear(points,
          u: Double(vertex.uv.x), v: 1 - Double(vertex.uv.y))
        XCTAssertEqual(Double(vertex.position.x), point.x / 1.8, accuracy: 0.000001)
        XCTAssertEqual(Double(vertex.position.y), point.y, accuracy: 0.000001)
        XCTAssertEqual(vertex.alpha, 0.4)
      }
      for offset in stride(from: 0, to: vertices.count, by: 6) {
        XCTAssertEqual(vertices[offset].position, vertices[offset + 3].position)
        XCTAssertEqual(vertices[offset + 2].position, vertices[offset + 4].position)
      }
    }
  }

  @MainActor
  func testMetalPresentationDiagnosticsUseNativeDrawableDelivery() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal is unavailable on this test device")
    }
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.first)
    let priorKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; priorKeyWindow?.makeKey() }
    let renderer = try EngineMetalRenderer(device: device)
    controller.view.layer.addSublayer(renderer.layer)
    let size = CGSize(width: 100, height: 100)
    renderer.resize(to: size, scale: 1)
    let engine = try RuntimeNodeBuilder().engine(archetypes: [])
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8)]))
    let recorder = PlaybackTimingRecorder()
    let host = makeHost()
    for _ in 0..<12 {
      try renderer.draw(host: host, assets: assets, size: size,
        timing: PlaybackFrameTiming(recorder: recorder,
          sampleHostTime: CACurrentMediaTime()))
      try await Task.sleep(for: .milliseconds(20))
    }
    #if !targetEnvironment(simulator)
    let deadline = CACurrentMediaTime() + 2
    while recorder.snapshot().metrics[PlaybackTimingMetric.presentation.rawValue] == nil,
      CACurrentMediaTime() < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #endif
    let report = recorder.snapshot()
    XCTAssertGreaterThan(report.counters[PlaybackTimingCounter.submitted.rawValue] ?? 0, 0)
    XCTAssertGreaterThan(report.metrics[PlaybackTimingMetric.encoding.rawValue]?.count ?? 0, 0)
    #if targetEnvironment(simulator)
    XCTAssertNil(report.metrics[PlaybackTimingMetric.presentation.rawValue])
    XCTAssertEqual(report.counters[PlaybackTimingCounter.unavailable.rawValue],
      report.counters[PlaybackTimingCounter.submitted.rawValue])
    #else
    let presentation = try XCTUnwrap(report.metrics[
      PlaybackTimingMetric.presentation.rawValue])
    XCTAssertGreaterThan(presentation.count, 0)
    XCTAssertGreaterThanOrEqual(presentation.minimumMS, 0)
    #endif
    print(report.text)
  }

  @MainActor
  func testMetalRendersUprightSpritesAndSeamlessTranslucentConnectors() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal is unavailable on this test device")
    }
    let renderer = try EngineMetalRenderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 20, height: 20, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).image {
      UIColor.red.setFill()
      $0.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
      UIColor.blue.setFill()
      $0.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
    }
    func render(_ image: UIImage, points: [EnginePoint], layers: [UIImage]? = nil,
      transparent: Bool = false)
      throws -> [UInt8] {
      let command = try XCTUnwrap(renderer.queue.makeCommandBuffer())
      let sprites = (layers ?? [image]).map {
        EngineRenderSprite(image: $0, points: points,
          matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
          alpha: 0.5, interpolation: false)
      }
      try renderer.encode(sprites,
        size: CGSize(width: 20, height: 20), target: target, commandBuffer: command,
        transparent: transparent)
      command.commit()
      command.waitUntilCompleted()
      XCTAssertNil(command.error)
      var bytes = [UInt8](repeating: 0, count: 20 * 20 * 4)
      target.getBytes(&bytes, bytesPerRow: 80,
        from: MTLRegionMake2D(0, 0, 20, 20), mipmapLevel: 0)
      return bytes
    }
    let quad = [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)]
    let pixels = try render(image, points: quad)
    let foreground = try render(image, points: [
      EnginePoint(x: -0.5, y: -0.5), EnginePoint(x: -0.5, y: 0.5),
      EnginePoint(x: 0.5, y: 0.5), EnginePoint(x: 0.5, y: -0.5)
    ], transparent: true)
    XCTAssertEqual(foreground[3], 0, "Empty pixels must reveal the background")
    XCTAssertEqual(Double(foreground[(10 * 20 + 10) * 4 + 3]), 128, accuracy: 1)
    XCTAssertFalse(renderer.layer.isOpaque)
    XCTAssertEqual(Double(pixels[(2 * 20 + 10) * 4 + 2]), 128, accuracy: 1)
    XCTAssertEqual(Double(pixels[(17 * 20 + 10) * 4]), 128, accuracy: 1)
    let white = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).image {
      UIColor.white.setFill()
      $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    let connector = try render(white, points: [
      EnginePoint(x: -1, y: -1), EnginePoint(x: -0.5, y: 1),
      EnginePoint(x: 0.5, y: 1), EnginePoint(x: 1, y: -1)
    ])
    let merged = try render(white, points: quad, layers: [white, white])
    XCTAssertEqual(Double(merged[(2 * 20 + 10) * 4 + 2]), 192, accuracy: 1)
    let ordered = try render(white, points: quad, layers: [white, image, white])
    XCTAssertEqual(Double(ordered[(2 * 20 + 10) * 4 + 2]), 224, accuracy: 1)
    XCTAssertEqual(Double(ordered[(2 * 20 + 10) * 4 + 1]), 160, accuracy: 1,
      "A-B-A textures must not be reordered to combine the A draws")
    for row in 2..<18 {
      for column in 8..<12 {
        XCTAssertEqual(Double(connector[(row * 20 + column) * 4]),
          128, accuracy: 1, "Shared triangle edges must not create alpha seams")
      }
    }
  }

  @MainActor
  func testConnectorTessellationAdaptsToWarpWithinBoundedBudget() {
    for (warp, divisions) in [(0.0, 1), (1, 1), (4, 2), (16, 4), (64, 8)] {
      XCTAssertEqual(EngineRenderer.tessellationDivisions(warp: warp), divisions)
      XCTAssertLessThanOrEqual(warp / (4 * Double(divisions * divisions)), 0.25)
    }
    XCTAssertEqual(EngineRenderer.tessellationDivisions(warp: .infinity), 8)
    XCTAssertEqual(EngineRenderer.tessellationDivisions(warp: 1e300), 8)
  }

  @MainActor
  func testRendererPlacesAnAsymmetricSpriteWithoutFlipping() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: format).image { output in
      UIColor.red.setFill()
      output.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
      UIColor.blue.setFill()
      output.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
    }
    let output = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20),
      format: format).image { output in
      output.cgContext.interpolationQuality = .none
      try! EngineRenderer.drawImage(image,
        points: [EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
          EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)],
        matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
        alpha: 1, context: output.cgContext, size: CGSize(width: 20, height: 20))
    }
    let cgImage = try XCTUnwrap(output.cgImage)
    var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
    let context = try XCTUnwrap(CGContext(data: &pixels,
      width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 20, height: 20))
    XCTAssertGreaterThan(pixels[(2 * 20 + 10) * 4], 240)
    XCTAssertGreaterThan(pixels[(17 * 20 + 10) * 4 + 2], 240)
  }
}
