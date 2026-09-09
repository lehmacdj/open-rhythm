import XCTest
import UIKit
import Metal
@testable import OpenRhythm

final class EngineHostTests: XCTestCase {
  private let quad: [Double] = [-1, -1, -1, 1, 1, 1, 1, -1]

  func testInterpreterDispatchesHostFunctions() throws {
    let host = makeHost()
    let nodes = [
      EngineDataNode(value: 7),
      EngineDataNode(function: "HasSkinSprite", arguments: [0]),
      EngineDataNode(value: 123),
      EngineDataNode(function: "HasSkinSprite", arguments: [2])
    ]
    let interpreter = EngineInterpreter(nodes: nodes, host: host)
    XCTAssertEqual(try interpreter.execute(nodeAt: 1), 1)
    XCTAssertEqual(try interpreter.execute(nodeAt: 3), 0)
    XCTAssertEqual(try host.call(function: "HasParticleEffect", arguments: [9]), 1)
    XCTAssertEqual(try host.call(function: "HasParticleEffect", arguments: [7]), 0)
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

  func testJudgeUsesSignedInclusiveWindowsAndBestMatchingGrade() throws {
    let host = makeHost()
    let windows = [-0.02, 0.03, -0.05, 0.06, -0.10, 0.12]
    for (distance, expected) in [
      (-0.101, 0), (-0.1, 3), (-0.05, 2), (-0.02, 1),
      (0, 1), (0.03, 1), (0.06, 2), (0.12, 3), (0.121, 0)
    ] {
      XCTAssertEqual(try host.call(
        function: "Judge", arguments: [distance, 0] + windows
      ), Double(expected))
    }
    XCTAssertEqual(try host.call(
      function: "Judge", arguments: [10, 10] + windows
    ), 1)
  }

  func testBeatToTimeIntegratesChangesWithoutBGMOffset() throws {
    let host = makeHost(level: LevelData(bgmOffset: 0.25, entities: [
      bpm(beat: 0, value: 120), bpm(beat: 4, value: 60)
    ]))
    for (beat, time) in [(-2.0, -1.0), (0, 0), (2, 1), (4, 2), (6, 4)] {
      XCTAssertEqual(try host.call(
        function: "BeatToTime", arguments: [beat]
      ), time)
    }
  }

  func testAudioSeparationUsesPlaybackOrderAndClipIdentity() throws {
    let host = makeHost()
    try host.beginFrame(at: 1)
    _ = try host.call(function: "PlayScheduled", arguments: [8, 2, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [10, 0.1])
    _ = try host.call(function: "Play", arguments: [999, 0.1])
    var scheduler = EngineAudioScheduler()
    try scheduler.enqueue(host.takeAudioCommands())
    XCTAssertTrue(host.takeAudioCommands().isEmpty)
    XCTAssertEqual(scheduler.due(at: 1).map(\.clipID), [8, 10])
    XCTAssertTrue(scheduler.due(at: 1.5).isEmpty)
    XCTAssertEqual(scheduler.due(at: 2).map(\.clipID), [8])
    XCTAssertTrue(scheduler.due(at: 3).isEmpty)
  }

  @MainActor
  func testAudioPrewarmsAndReusesVoicesAcrossHitsAndRestart() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    XCTAssertEqual(voices.count, 8)
    for time in 0..<30 {
      try audio.update([EngineAudioCommand(clipID: 1,
        time: Double(time), minimumDistance: 0)], at: Double(time))
      for voice in voices { voice.isPlaying = false }
    }
    XCTAssertEqual(voices.count, 8, "Hits must reuse prewarmed decoders")
    XCTAssertEqual(voices.flatMap(\.delays).count, 30)
    audio.stop()
    try audio.update([EngineAudioCommand(clipID: 1,
      time: 0, minimumDistance: 0)], at: 0)
    XCTAssertEqual(voices.count, 8, "Restart must retain the prepared pool")
  }

  @MainActor
  func testSuppressedFutureAudioIsReconsideredAfterEarlierClipIsCancelled() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.25, minimumDistance: 0.25),
      EngineAudioCommand(clipID: 1, time: 0.375, minimumDistance: 0.25)
    ], at: 0)
    XCTAssertEqual(voices.flatMap(\.delays), [0.25])
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.125, minimumDistance: 0.25)
    ], at: 0.125)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 1)
    XCTAssertEqual(voices.flatMap(\.delays).sorted(), [0, 0.25, 0.25],
      "The later clip becomes valid after the middle clip is cancelled")
    try audio.update([], at: 0.375)
    XCTAssertEqual(voices.flatMap(\.delays).count, 3)
    audio.stop()
  }

  @MainActor
  func testScheduledVoicesRemainReservedAndRescheduleAfterBuffering() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.3, minimumDistance: 0),
      EngineAudioCommand(clipID: 1, time: 0.4, minimumDistance: 0)
    ], at: 0)
    XCTAssertEqual(voices.filter { !$0.delays.isEmpty }.count, 2)
    // A scheduled native player need not report isPlaying before it starts.
    for voice in voices { voice.isPlaying = false }
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.flatMap(\.delays).count, 2)
    try audio.update([], at: 0.1, advancing: false)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 2)
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.flatMap(\.delays).count, 4)
    XCTAssertEqual(audio.allocatedVoiceCount, 8)
    audio.stop()
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

  func testExtendedDrawAndCumulativeAudioLimits() throws {
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
    var scheduler = EngineAudioScheduler()
    let command = EngineAudioCommand(clipID: 8, time: 100, minimumDistance: 0)
    try scheduler.enqueue(Array(repeating: command, count: 16_384))
    XCTAssertTrue(scheduler.due(at: 0).isEmpty)
    XCTAssertThrowsError(try scheduler.enqueue([command]))
    XCTAssertEqual(scheduler.due(at: 100).count, 16_384)
    XCTAssertNoThrow(try scheduler.enqueue([command]))
  }

  func testSpawnsAreDeferredAndExportsAreEntityScoped() throws {
    let host = makeHost()
    _ = try host.call(function: "Spawn", arguments: [1, 20, 30])
    XCTAssertEqual(host.takeSpawnCommands(), [
      EngineSpawnCommand(archetypeID: 1, memory: [20, 30])
    ])
    XCTAssertTrue(host.takeSpawnCommands().isEmpty)
    host.selectEntity(index: 12, exportCount: 2)
    _ = try host.call(function: "ExportValue", arguments: [0, 5])
    _ = try host.call(function: "ExportValue", arguments: [0, 6])
    host.selectEntity(index: 13, exportCount: 1)
    _ = try host.call(function: "ExportValue", arguments: [0, 7])
    XCTAssertEqual(host.exports[12], [0: 6])
    XCTAssertEqual(host.exports[13], [0: 7])
    XCTAssertThrowsError(try host.call(
      function: "ExportValue", arguments: [1, 8]
    ))
    host.selectEntity(index: nil, exportCount: 0)
    XCTAssertThrowsError(try host.call(
      function: "ExportValue", arguments: [0, 8]
    ))
  }

  func testMalformedCommandsThrowInsteadOfCrashingOrGrowingState() throws {
    let host = makeHost()
    for (function, arguments) in [
      ("Draw", [7.0]), ("BeatToTime", [Double.nan]),
      ("Spawn", [Double.infinity]), ("Spawn", [-1]), ("Spawn", [2]),
      ("HasSkinSprite", [Double.greatestFiniteMagnitude]),
      ("DestroyParticleEffect", [0.5]), ("Judge", []),
      ("UnknownFunction", [])
    ] {
      XCTAssertThrowsError(try host.call(
        function: function, arguments: arguments
      ), function)
    }
    XCTAssertTrue(host.draws.isEmpty)
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertTrue(host.takeSpawnCommands().isEmpty)
  }

  private func makeHost(
    level: LevelData = LevelData(bgmOffset: 0, entities: [])
  ) -> CommandEngineRuntimeHost {
    CommandEngineRuntimeHost(
      memory: EngineMemory(), level: level, skinSpriteIDs: [7],
      effectClipIDs: [8, 10], particleEffectIDs: [9], archetypeCount: 2
    )
  }

  func testEntityMemoryViewsAndInterpreterLimits() throws {
    let memory = EngineMemory()
    memory.selectEntity(key: 0, index: 0)
    memory.set(block: 4000, index: 0, value: 10)
    memory.set(block: 4002, index: 2, value: 20)
    memory.selectEntity(key: 1, index: 1)
    XCTAssertEqual(memory.value(block: 4000, index: 0), 0)
    XCTAssertEqual(memory.value(block: 4002, index: 2), 0)
    XCTAssertEqual(memory.value(block: 4102, index: 2), 20)
    memory.set(block: 4102, index: 2, value: 30)
    memory.selectEntity(key: 0, index: 0)
    XCTAssertEqual(memory.value(block: 4000, index: 0), 10)
    XCTAssertEqual(memory.value(block: 4002, index: 2), 30)
    let invalid = EngineInterpreter(nodes: [
      EngineDataNode(value: .infinity), EngineDataNode(value: 0),
      EngineDataNode(function: "Get", arguments: [0, 1])
    ])
    XCTAssertThrowsError(try invalid.execute(nodeAt: 2))
    let cycle = EngineInterpreter(nodes: [
      EngineDataNode(function: "Abs", arguments: [0])
    ])
    XCTAssertThrowsError(try cycle.execute(nodeAt: 0))
  }

  func testRuntimeDefersSpawnInjectsMemoryAndResolvesInputOnce() throws {
    let builder = RuntimeNodeBuilder()
    let spawn = builder.call("Spawn", [builder.value(1), builder.value(7)])
    let despawn = builder.call("Set", [
      builder.value(4004), builder.value(0), builder.value(1)
    ])
    let initUpdate = builder.call("Execute", [spawn, despawn])
    let getInjected = builder.call("Get", [builder.value(4000), builder.value(0)])
    let writeShared = builder.call("Set", [
      builder.value(2000), builder.value(0), getInjected
    ])
    let dynamicUpdate = builder.call("Execute", [writeShared, despawn])
    let input = builder.call("Set", [
      builder.value(4005), builder.value(0), builder.value(1)
    ])
    let touch = builder.call("Execute", [input, despawn])
    let archetypes: [[String: Any]] = [
      ["name": "Init", "hasInput": false, "imports": [], "exports": [],
       "updateSequential": ["index": initUpdate]],
      ["name": "Dynamic", "hasInput": true, "imports": [], "exports": [],
       "updateParallel": ["index": dynamicUpdate]],
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "touch": ["index": touch]]
    ]
    let engine = try builder.engine(archetypes: archetypes)
    let runtime = try EnginePlayRuntime(
      engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Init", name: nil, data: []),
        LevelEntity(archetype: "Note", name: nil, data: []),
        LevelEntity(archetype: "EditorMetadata", name: nil, data: [])
      ]), options: [], aspectRatio: 1, skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: []
    )
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 0)
    let point = EnginePoint(x: 0, y: 0)
    try runtime.update(at: 1, touches: [EngineTouch(
      id: 1, started: true, ended: false, time: 1, startTime: 1,
      position: point, startPosition: point, delta: point
    )])
    XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 7)
    XCTAssertEqual(runtime.judgments.map(\.grade), [1])
    XCTAssertEqual(runtime.resolvedInputCount, 1)
    XCTAssertEqual(runtime.inputCount, 1, "Dynamic entities never score")
    try runtime.update(at: 2)
    XCTAssertTrue(runtime.judgments.isEmpty)
    XCTAssertEqual(runtime.resolvedInputCount, 1)
    XCTAssertEqual(runtime.memory.value(block: 4103, index: 5), 2)
    XCTAssertEqual(runtime.memory.value(block: 4103, index: 8), 2)
  }

  func testArchiveValidatesBoundsChecksumAndCompressionLimits() throws {
    let encoded = "UEsDBBQAAAAAAAAAAACGphA2BQAAAAUAAAAIAAAAdG9uZS50eHRoZWxs"
      + "b1BLAQIUABQAAAAAAAAAAACGphA2BQAAAAUAAAAIAAAAAAAAAAAAAAAAAAAAAAB0"
      + "b25lLnR4dFBLBQYAAAAAAQABADYAAAArAAAAAAA="
    let data = try XCTUnwrap(Data(base64Encoded: encoded))
    let archive = try EffectAudioArchive(data: data)
    XCTAssertEqual(archive.files["tone.txt"], Data("hello".utf8))
    for length in [0, 10, 21, data.count - 1] {
      XCTAssertThrowsError(try EffectAudioArchive(data: data.prefix(length)))
    }
    var corrupt = data
    corrupt[38] ^= 0xff
    XCTAssertThrowsError(try EffectAudioArchive(data: corrupt))
    let compressed = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAAA8tIzcnJBwCGphA2BQAAAA=="))
    XCTAssertEqual(try GzipDecoder.decompress(compressed), Data("hello".utf8))
    XCTAssertThrowsError(try GzipDecoder.decompress(compressed, maximumSize: 4))
  }

  func testPresentationReferencesHonorOverridesAndEachResourceSource() throws {
    let item = Data(#"""
      {"source":"https://level.example/game",
       "bgm":{"url":"bgm"},"data":{"url":"level"},
       "useSkin":{"useDefault":false,"item":{
         "source":"https://skin.example/custom",
         "data":{"url":"data"},"texture":{"url":"texture"}}},
       "useParticle":{"useDefault":true},
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
    func render(_ image: UIImage, points: [EnginePoint]) throws -> [UInt8] {
      let command = try XCTUnwrap(renderer.queue.makeCommandBuffer())
      try renderer.encode([EngineRenderSprite(image: image, points: points,
        matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
        alpha: 0.5, interpolation: false)],
        size: CGSize(width: 20, height: 20), target: target, commandBuffer: command)
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
  func testParticleTintPreservesTransparencyAndDrawRespectsAlpha() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let size = CGSize(width: 20, height: 20)
    let original = UIGraphicsImageRenderer(size: size, format: format).image {
      UIColor.white.setFill()
      $0.fill(CGRect(x: 5, y: 5, width: 10, height: 10))
    }
    let tinted = EnginePresentationAssets.tinted(original, color: .red)
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image {
      EngineRenderer.drawImage(tinted,
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
    let unchanged = EnginePresentationAssets.tinted(translucent, color: .white)
    context.clear(CGRect(origin: .zero, size: size))
    context.draw(try XCTUnwrap(unchanged.cgImage),
      in: CGRect(origin: .zero, size: size))
    XCTAssertEqual(Double(pixels[center]), 128, accuracy: 1)
    XCTAssertEqual(pixels[center + 1], 0,
      "White tint must not bleach translucent red to pink")
    XCTAssertEqual(pixels[center + 2], 0)
    XCTAssertEqual(Double(pixels[center + 3]), 128, accuracy: 1)
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
      EngineRenderer.drawImage(image,
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

  private func bpm(beat: Double, value: Double) -> LevelEntity {
    LevelEntity(archetype: "#BPM_CHANGE", name: nil, data: [
      LevelEntityData(name: "#BEAT", value: beat, ref: nil),
      LevelEntityData(name: "#BPM", value: value, ref: nil)
    ])
  }
}

@MainActor
private final class MockEffectVoice: EngineEffectVoice {
  var isPlaying = false
  var delays = [Double]()
  var stopCount = 0

  func play(after delay: Double) {
    delays.append(delay)
    isPlaying = true
  }

  func stop() {
    stopCount += 1
    isPlaying = false
  }
}

private final class RuntimeNodeBuilder {
  private var nodes = [[String: Any]]()

  func value(_ value: Double) -> Int {
    nodes.append(["value": value])
    return nodes.count - 1
  }

  func call(_ function: String, _ arguments: [Int]) -> Int {
    nodes.append(["func": function, "args": arguments])
    return nodes.count - 1
  }

  func engine(archetypes: [[String: Any]]) throws -> EnginePlayData {
    let data = try JSONSerialization.data(withJSONObject: [
      "skin": ["sprites": []], "effect": ["clips": []],
      "particle": ["effects": []], "buckets": [],
      "nodes": nodes, "archetypes": archetypes
    ])
    return try JSONDecoder().decode(EnginePlayData.self, from: data)
  }
}
