import XCTest
import UIKit
import Metal
@testable import OpenRhythm

/// Opt-in integration tests: independently obtained assets stay in the app's
/// cache, never in the repository or test bundle. No network access is used.
@MainActor
final class CachedEngineIntegrationTests: XCTestCase {
  func testShakeItHard18LifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sekai", chart: "shake-it.gz")
  }

  func testShakeItHard18WithRepeatedContacts() async throws {
    try await checkChart(engineFolder: "sekai", chart: "shake-it.gz",
      repeatedContacts: true)
  }
  func testEleventhLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sekai", chart: "eleventh.gz")
  }

  func testHikariLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sekai", chart: "hikari.gz")
  }

  func testSIFCustomLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sif", chart: "sif/level.gz")
  }

  func testNanaonLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "nanaon", chart: "nanaon/level.gz")
  }

  private struct Frame {
    let draws: [EngineDrawCommand]
    let particles: [Int: EngineParticleInstance]
    let audio: [EngineAudioCommand]
    let loops: [EngineLoopCommand]
    let resolved: Int

    init(_ runtime: EnginePlayRuntime) {
      draws = runtime.host.draws
      particles = runtime.host.particles
      audio = runtime.host.takeAudioCommands()
      loops = runtime.host.takeLoopCommands()
      resolved = runtime.resolvedInputCount
    }
  }

  private func checkChart(engineFolder: String, chart: String,
    repeatedContacts: Bool = false) async throws {
    let cache = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures")
    guard FileManager.default.fileExists(atPath: cache.path) else {
      throw XCTSkip("Optional cached chart fixtures are not installed.")
    }
    let root = cache.appendingPathComponent(engineFolder)
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: Data(contentsOf: cache.appendingPathComponent(chart)))
    var resources = [String: Data]()
    for key in ["configuration", "skinData", "skinTexture", "particleData",
      "particleTexture", "effectData", "effectAudio"] {
      resources[key] = try Data(contentsOf: root.appendingPathComponent(key))
    }
    let presentation = RuntimePresentation(resources: resources)
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine, presentation: presentation)
    let romURL = root.appendingPathComponent("rom.bin")
    let rom = FileManager.default.fileExists(atPath: romURL.path)
      ? try Data(contentsOf: romURL) : nil
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: assets.options, aspectRatio: 1.8,
      skinSpriteIDs: Set(assets.skin.keys), effectClipIDs: audio.clipIDs,
      particleEffectIDs: Set(assets.particles.keys), rom: rom)
    XCTAssertGreaterThan(runtime.inputCount, 0)
    let wasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    defer { UIApplication.shared.isIdleTimerDisabled = wasIdleDisabled }
    let startTime = BGMClockMapping(offset: level.bgmOffset).initialChartTime
    // This offline simulation otherwise consumes a core continuously, unlike
    // display-driven gameplay, and iOS can terminate it for CPU resource use.
    // Yield between bounded work bursts, outside every measured frame. Never
    // report these intentionally throttled runs as real-time frame pacing.
    #if !targetEnvironment(simulator)
    var burstStarted = ProcessInfo.processInfo.systemUptime
    #endif
    func yieldToDevice() async throws {
      #if !targetEnvironment(simulator)
      if ProcessInfo.processInfo.systemUptime - burstStarted >= 0.1 {
        try await Task.sleep(nanoseconds: 100_000_000)
        burstStarted = ProcessInfo.processInfo.systemUptime
      }
      #endif
    }
    #if !targetEnvironment(simulator)
    print("Device lifecycle simulation is throttled between work bursts; "
      + "reported CPU samples exclude those pauses and are not live FPS.")
    #endif
    var seen = Set<Int>()
    var opening = [(index: Int, snapshot: Frame)]()
    var firstResolutionFrame: Int?
    var durations = [Double]()
    var runtimeDurations = [Double](), spriteDurations = [Double]()
    var peaks = [String: (weight: Double, time: Double,
      draws: Int, segments: Int, particles: Int, sprites: [EngineRenderSprite])]()
    var lastTime = startTime
    var successfulInputs = 0
    var successfulTypes = [String: Int]()
    // A deterministic load case, not an autoplay implementation or a captured
    // physical play. Eight contacts exercise touch callbacks, holds and hit
    // effects; every contact ends before its next ID is introduced.
    func contacts(_ frame: Int, _ time: Double) -> [EngineTouch] {
      guard repeatedContacts else { return [] }
      let phase = frame % 12
      return (0..<8).map { lane in
        let point = EnginePoint(x: -1.05 + Double(lane) * 0.3, y: -0.75)
        return EngineTouch(id: (frame / 12) * 8 + lane + 1,
          started: phase == 0, ended: phase == 11, time: time,
          startTime: time - Double(phase) / 60,
          position: point, startPosition: point, delta: EnginePoint(x: 0, y: 0))
      }
    }
    for frame in 0..<18000 {
      lastTime = startTime + Double(frame) / 60
      let touches = contacts(frame, lastTime)
      let started = ProcessInfo.processInfo.systemUptime
      try runtime.update(at: lastTime, touches: touches)
      let updated = ProcessInfo.processInfo.systemUptime
      let sprites = EngineRenderer.sprites(host: runtime.host, assets: assets)
      let rendered = ProcessInfo.processInfo.systemUptime
      durations.append(rendered - started)
      runtimeDurations.append(updated - started)
      spriteDurations.append(rendered - updated)
      let segments = runtime.host.draws.reduce(0) { $0 + ($1.curve?.segments ?? 0) }
      for (name, weight) in [("runtime", updated - started),
        ("sprites", rendered - updated), ("draws", Double(runtime.host.draws.count)),
        ("curves", Double(segments)), ("particles", Double(runtime.host.particles.count))] {
        if weight > peaks[name]?.weight ?? -1 {
          peaks[name] = (weight, lastTime, runtime.host.draws.count, segments,
            runtime.host.particles.count, sprites)
        }
      }
      for input in runtime.judgments {
        if input.grade > 0 {
          successfulInputs += 1
          if level.entities.indices.contains(input.entityIndex) {
            successfulTypes[level.entities[input.entityIndex].archetype,
              default: 0] += 1
          }
        }
        XCTAssertTrue(seen.insert(input.entityIndex).inserted,
          "Duplicate input resolution in \(chart): \(input.entityIndex)")
      }
      let snapshot = Frame(runtime)
      if firstResolutionFrame == nil, !runtime.judgments.isEmpty {
        firstResolutionFrame = frame
      }
      if frame == 0 || firstResolutionFrame.map({ frame < $0 + 120 }) == true {
        opening.append((frame, snapshot))
      }
      try await yieldToDevice()
      if runtime.resolvedInputCount == runtime.inputCount { break }
    }
    XCTAssertEqual(seen.count, runtime.inputCount, chart)
    XCTAssertEqual(runtime.resolvedInputCount, runtime.inputCount, chart)
    XCTAssertNotNil(firstResolutionFrame)
    if repeatedContacts {
      XCTAssertGreaterThan(successfulInputs, 0)
      XCTAssertGreaterThan(peaks["particles"]?.particles ?? 0, 0)
      XCTAssertTrue(level.entities.contains { entity in
        entity.data.contains { $0.name == "connectorEase" && ($0.value ?? 0) > 1 }
      }, "The stress fixture must retain its non-linear hold connectors")
      for type in ["NormalHeadTapNote", "NormalTickNote", "NormalTailReleaseNote"] {
        XCTAssertGreaterThan(successfulTypes[type, default: 0], 0, type)
      }
    }
    runtime.restart()
    var sample = 0
    for frame in 0...opening.last!.index {
      let time = startTime + Double(frame) / 60
      try runtime.update(at: time, touches: contacts(frame, time))
      let actual = Frame(runtime)
      try await yieldToDevice()
      guard frame == opening[sample].index else { continue }
      let expected = opening[sample].snapshot
      XCTAssertEqual(actual.draws, expected.draws, chart)
      XCTAssertEqual(actual.particles, expected.particles, chart)
      XCTAssertEqual(actual.audio, expected.audio, chart)
      XCTAssertEqual(actual.loops, expected.loops, chart)
      XCTAssertEqual(actual.resolved, expected.resolved, chart)
      sample += 1
    }
    let sorted = durations.sorted()
    let mean = durations.reduce(0, +) / Double(durations.count)
    let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
    print("CACHED CHART \(chart): \(seen.count) inputs, last \(lastTime)s, "
      + "\(durations.count) frames, runtime+sprite CPU mean \(mean * 1000)ms, "
      + "p95 \(p95 * 1000)ms, p99 \(p99 * 1000)ms; "
      + "restart matched \(opening.count) sampled frames "
      + "through frame \(opening.last!.index). "
      + "\(successfulInputs) successful inputs; repeated contacts: \(repeatedContacts). "
      + "Lifecycle loop excludes physical touches, music and GPU submission.")
    if repeatedContacts { print("SUCCESSFUL INPUT TYPES: \(successfulTypes)") }
    for (name, values) in [("runtime", runtimeDurations), ("sprites", spriteDurations)] {
      let sorted = values.sorted()
      print("CPU PHASE \(chart) \(name): mean "
        + "\(values.reduce(0, +) * 1000 / Double(values.count)) ms, "
        + "p95 \(sorted[Int(Double(sorted.count) * 0.95)] * 1000) ms")
    }
    guard let device = MTLCreateSystemDefaultDevice() else {
      XCTFail("Metal unavailable for cached frame profiling")
      return
    }
    let renderer = try EngineMetalRenderer(device: device)
    try renderer.prepare(assets)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 1800, height: 1000, mipmapped: false)
    descriptor.usage = [.renderTarget]
    let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    let size = CGSize(width: 1800, height: 1000)
    for name in peaks.keys.sorted() {
      let peak = peaks[name]!
      var encodeTimes = [Double](), gpuTimes = [Double]()
      for iteration in 0..<12 {
        let command = try XCTUnwrap(renderer.queue.makeCommandBuffer())
        let start = ProcessInfo.processInfo.systemUptime
        try renderer.encode(peak.sprites, size: size, target: target,
          commandBuffer: command)
        let encoded = ProcessInfo.processInfo.systemUptime
        command.commit()
        await command.completed()
        XCTAssertNil(command.error)
        if iteration >= 2 {
          encodeTimes.append(encoded - start)
          if command.gpuEndTime > command.gpuStartTime {
            gpuTimes.append(command.gpuEndTime - command.gpuStartTime)
          }
        }
      }
      let vertices = peak.sprites.reduce(0) {
        $0 + EngineMetalRenderer.vertices(for: $1, size: size).count
      }
      let gpu = gpuTimes.isEmpty ? "unavailable"
        : String(gpuTimes.reduce(0, +) * 1000 / Double(gpuTimes.count))
      print("PEAK FRAME \(chart) \(name) at \(peak.time)s: "
        + "\(peak.draws) draws, \(peak.segments) curve segments, "
        + "\(peak.particles) effects, \(peak.sprites.count) sprites, \(vertices) vertices; "
        + "encode mean \(encodeTimes.reduce(0, +) * 1000 / Double(encodeTimes.count)) ms, "
        + "GPU mean \(gpu) ms. Replayed offline frame, not live FPS.")
    }
  }
}


private struct DepthFixtureHost: EngineRuntimeHost {
  func call(function: String, arguments: [Double]) throws -> Double {
    arguments.first ?? 0
  }
}

final class RuntimeDecodingTests: XCTestCase {
  @MainActor
  func testDeepDispatchFamiliesRespectDepthLimitWithoutNativeStackOverflow() {
    Self.checkDeepDispatchFamilies()
  }

  func testDeepDispatchFamiliesOnOneMiBStack() {
    // Simulator main threads have a larger stack than iPhones. Keep a bounded
    // stack regression there too, so simulator-only validation catches this.
    let finished = expectation(description: "Bounded-stack evaluation")
    let thread = Thread {
      Self.checkDeepDispatchFamilies()
      finished.fulfill()
    }
    thread.stackSize = 1024 * 1024
    thread.start()
    wait(for: [finished], timeout: 30)
  }

  private static func checkDeepDispatchFamilies() {
    // Exercise every dispatch family, not only the unary cases that first
    // crashed on the phone's 1 MiB main-thread stack.
    let functions = ["Abs", "Equal", "Add", "Divide", "EaseInQuad", "Random",
      "Copy", "GetShifted", "GetPointed", "SetShifted", "SetAdd",
      "SetMod", "SetModShifted", "Execute", "Block", "DoWhile",
      "If", "Switch", "SwitchInteger", "FixtureHost"]
    for function in functions {
      for optimized in [false, true] {
        var nodes = [EngineDataNode(value: 0), EngineDataNode(value: 1),
          EngineDataNode(value: 2), EngineDataNode(value: 2000)]
        func arguments(_ child: Int) -> [Int] {
          switch function {
          case "Equal", "Add", "Divide", "Random": return [child, 2]
          case "Copy": return [3, 0, 3, 0, child]
          case "GetShifted": return [3, 0, child, 0]
          case "GetPointed": return [child, 0, 0]
          case "SetShifted", "SetModShifted": return [3, 0, 0, 0, child]
          case "SetAdd", "SetMod": return [3, 0, child]
          case "DoWhile": return [child, 0]
          case "If": return [1, child, 0]
          case "Switch": return [0, 0, child]
          case "SwitchInteger": return [0, child]
          default: return [child]
          }
        }
        var root = 1
        for _ in 0..<255 {
          nodes.append(EngineDataNode(function: function,
            arguments: arguments(root)))
          root = nodes.count - 1
        }
        let cycle = nodes.count
        nodes.append(EngineDataNode(function: function,
          arguments: arguments(cycle)))
        let interpreter = EngineInterpreter(nodes: nodes,
          host: DepthFixtureHost(), optimizeLiteralAddresses: optimized)
        XCTAssertNoThrow(try interpreter.execute(nodeAt: root), function)
        XCTAssertThrowsError(try interpreter.execute(nodeAt: cycle), function) {
          guard case EngineInterpreterError.operationLimitExceeded = $0 else {
            return XCTFail("Unexpected error for \(function): \($0)")
          }
        }
        XCTAssertEqual(try interpreter.execute(nodeAt: 1), 1,
          "An exhausted evaluation must unwind its depth state")
      }
    }
  }

  func testLiteralAddressesPreserveReadModifyWriteOrderAndLiveValues() throws {
    let cases: [(String, Double, Double)] = [
      ("Get", 4, 4), ("Set", 9, 9), ("SetAdd", 13, 13),
      ("SetSubtract", -5, -5), ("SetMultiply", 36, 36),
      ("SetDivide", 4.0 / 9, 4.0 / 9), ("SetPower", 262144, 262144),
      ("IncrementPre", 4, 5), ("IncrementPost", 5, 5),
      ("DecrementPre", 4, 3), ("DecrementPost", 3, 3)
    ]
    for (function, expected, stored) in cases {
      for optimized in [false, true] {
        let memory = EngineMemory()
        memory.set(block: 2000, index: 2, value: 4)
        let nodes = [
          EngineDataNode(value: 2000.9), EngineDataNode(value: 2.75),
          EngineDataNode(value: 9),
          EngineDataNode(function: "Set", arguments: [0, 1, 2]),
          EngineDataNode(function: function,
            arguments: function.hasPrefix("Set") ? [0, 1, 3] : [0, 1])
        ]
        let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
          optimizeLiteralAddresses: optimized)
        XCTAssertEqual(try interpreter.execute(nodeAt: 4), expected, function)
        XCTAssertEqual(memory.value(block: 2000, index: 2), stored, function)
        memory.set(block: 2000, index: 2, value: 123)
        let reader = EngineInterpreter(nodes: nodes + [
          EngineDataNode(function: "Get", arguments: [0, 1])], memory: memory,
          optimizeLiteralAddresses: optimized)
        XCTAssertEqual(try reader.execute(nodeAt: 5), 123)
        memory.set(block: 2000, index: 2, value: -7)
        XCTAssertEqual(try reader.execute(nodeAt: 5), -7,
          "Only the address can be cached, never its value")
      }
    }
  }

  func testLiteralAddressesRespectEntitySelectionTemporaryMemoryAndROM() throws {
    for optimized in [false, true] {
      let memory = EngineMemory()
      try memory.loadROM(Data([0, 0, 128, 63])) // Float32 1
      for block in [4000, 4001, 10000, 2000, 3000] {
        let interpreter = EngineInterpreter(nodes: [
          EngineDataNode(value: Double(block)), EngineDataNode(value: 0),
          EngineDataNode(value: 8),
          EngineDataNode(function: "Get", arguments: [0, 1]),
          EngineDataNode(function: "Set", arguments: [0, 1, 2])
        ], memory: memory, optimizeLiteralAddresses: optimized)
        memory.selectEntity(key: 0, index: 0)
        _ = try interpreter.execute(nodeAt: 4)
        XCTAssertEqual(try interpreter.execute(nodeAt: 3), block == 3000 ? 1 : 8)
        memory.selectEntity(key: 1, index: 1)
        XCTAssertEqual(try interpreter.execute(nodeAt: 3),
          block == 3000 ? 1 : block == 2000 ? 8 : 0)
        memory.selectEntity(key: 0, index: 0)
        XCTAssertEqual(try interpreter.execute(nodeAt: 3),
          block == 3000 ? 1 : block == 10000 ? 0 : 8)
      }
    }
  }

  func testLiteralAddressOptimizationPreservesBudgetsAndPartialSideEffects() {
    let nodes = [
      EngineDataNode(value: 2000), EngineDataNode(value: 0),
      EngineDataNode(value: 1), EngineDataNode(value: 9),
      EngineDataNode(function: "Set", arguments: [0, 1, 3]),
      EngineDataNode(function: "SetAdd", arguments: [0, 2, 4]),
      EngineDataNode(function: "Get", arguments: [0, 2]),
      EngineDataNode(function: "Execute", arguments: [5, 6])
    ]
    for limit in 0...20 {
      assertAddressOptimizationEquivalent(nodes, root: 7, limit: limit)
    }
    for nesting in [253, 254, 255, 256] {
      var deep = Array(nodes.prefix(4))
      deep.append(EngineDataNode(function: "Get", arguments: [0, 1]))
      for _ in 0..<nesting {
        deep.append(EngineDataNode(function: "Negate", arguments: [deep.count - 1]))
      }
      assertAddressOptimizationEquivalent(deep, root: deep.count - 1, limit: 1000)
    }
  }

  func testDynamicAndInvalidAddressesKeepTheirOriginalEvaluationBehavior() {
    let nodes = [
      EngineDataNode(value: 2000), EngineDataNode(value: 0),
      EngineDataNode(value: 1), EngineDataNode(value: 12),
      EngineDataNode(function: "Set", arguments: [0, 1, 2]),
      EngineDataNode(function: "Set", arguments: [0, 4, 3]),
      EngineDataNode(function: "Get", arguments: [0, 4]),
      EngineDataNode(function: "Get", arguments: [99, 1]),
      EngineDataNode(function: "Set", arguments: [0, 1]),
      EngineDataNode(value: .infinity),
      EngineDataNode(function: "Get", arguments: [0, 9]),
      EngineDataNode(function: "Set", arguments: [9, 1, 4]),
      EngineDataNode(function: "Break", arguments: [2, 3]),
      EngineDataNode(function: "SetAdd", arguments: [0, 1, 12]),
      EngineDataNode(function: "Block", arguments: [13])
    ]
    for root in [5, 6, 7, 8, 10, 11, 13, 14] {
      for limit in 0...18 {
        assertAddressOptimizationEquivalent(nodes, root: root, limit: limit)
      }
    }
  }

  private func assertAddressOptimizationEquivalent(_ nodes: [EngineDataNode],
    root: Int, limit: Int, file: StaticString = #filePath, line: UInt = #line) {
    var outputs = [Double?](), errors = [String?](), snapshots = [[Double]]()
    for optimized in [false, true] {
      let memory = EngineMemory()
      let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
        operationLimit: limit, optimizeLiteralAddresses: optimized)
      do {
        outputs.append(try interpreter.execute(nodeAt: root))
        errors.append(nil)
      } catch {
        outputs.append(nil)
        errors.append(error.localizedDescription)
      }
      snapshots.append((0..<16).map { memory.value(block: 2000, index: $0) })
    }
    XCTAssertEqual(outputs[0], outputs[1], "root \(root), limit \(limit)",
      file: file, line: line)
    XCTAssertEqual(errors[0], errors[1], "root \(root), limit \(limit)",
      file: file, line: line)
    XCTAssertEqual(snapshots[0], snapshots[1], "root \(root), limit \(limit)",
      file: file, line: line)
  }

  @MainActor
  func testSkinOnlyAndParticleOnlyEnginesPrepareWithoutOtherFamily() throws {
    let png = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .pngData { UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1)) }
    for family in ["skin", "particle"] {
      let list = family == "skin" ? "sprites" : "effects"
      var object: [String: Any] = ["skin": ["sprites": []],
        "effect": ["clips": []], "particle": ["effects": []],
        "nodes": [], "buckets": [], "archetypes": []]
      object[family] = [list: [["id": 1, "name": "required"]]]
      let engine = try JSONDecoder().decode(EnginePlayData.self,
        from: JSONSerialization.data(withJSONObject: object))
      let data = family == "skin" ? #"""
        {"width":1,"height":1,"interpolation":true,"sprites":[
        {"name":"required","x":0,"y":0,"w":1,"h":1,"transform":{}}]}
        """# : #"""
        {"width":1,"height":1,"interpolation":true,"sprites":[],"effects":[
        {"name":"required","transform":{},"groups":[]}]}
        """#
      let assets = try EnginePresentationAssets(engine: engine,
        presentation: RuntimePresentation(resources: [
          "configuration": Data(#"{"options":[]}"#.utf8),
          family + "Data": Data(data.utf8), family + "Texture": png
        ]))
      XCTAssertEqual(assets.skin.count, family == "skin" ? 1 : 0)
      XCTAssertEqual(assets.particles.count, family == "particle" ? 1 : 0)
      XCTAssertEqual(assets.interpolation, family == "skin")
      XCTAssertEqual(assets.particleInterpolation, family == "particle")
    }
  }

  @MainActor
  func testUnusedPresentationFamiliesDoNotRequirePlaceholderAssets() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},"particle":{"effects":[]},
       "nodes":[],"buckets":[],"archetypes":[]}
      """#.utf8))
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8)
    ])
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine, presentation: presentation)
    XCTAssertTrue(assets.skin.isEmpty)
    XCTAssertTrue(assets.particles.isEmpty)
    XCTAssertTrue(assets.preparedImages.isEmpty)
    XCTAssertTrue(audio.clipIDs.isEmpty)
    XCTAssertEqual(audio.allocatedVoiceCount, 0)
    XCTAssertNoThrow(try audio.start())
    audio.stop()
  }

  @MainActor
  func testDeclaredPresentationFamiliesStillRequireTheirResources() throws {
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8)
    ])
    for (family, list) in [("skin", "sprites"), ("effect", "clips"),
      ("particle", "effects")] {
      var object: [String: Any] = ["skin": ["sprites": []],
        "effect": ["clips": []], "particle": ["effects": []],
        "nodes": [], "buckets": [], "archetypes": []]
      object[family] = [list: [["id": 1, "name": "required"]]]
      let engine = try JSONDecoder().decode(EnginePlayData.self,
        from: JSONSerialization.data(withJSONObject: object))
      if family == "effect" {
        XCTAssertThrowsError(try EngineAudioPlayback(engine: engine,
          presentation: presentation))
      } else {
        XCTAssertThrowsError(try EnginePresentationAssets(engine: engine,
          presentation: presentation))
      }
    }
  }

  func testGenericEngineOptionsValidatePersistedValuesAndKeepProtocolOrder() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"options":[
      {"name":"#NOTE_SIZE","type":"slider","def":1,"min":0.5,"max":2,
       "step":0.25,"unit":"#PERCENTAGE_UNIT"},
      {"name":"#MIRROR","type":"toggle","def":0,"standard":true},
      {"name":"Mode","title":"Input Mode","type":"select","def":1,
       "values":["#OFF","#ON","Strict"],"standard":true},
      {"name":"#SPEED","type":"slider","def":1,"min":0.5,"max":2,"step":0.05},
      {"name":"Future","type":"future","def":17},
      {"name":"#NOTE_SPEED","def":5,"min":1,"max":12,"step":0.1},
      {"name":"Score Mode","def":1,"values":["Flat","Combo"]}]}
      """#.utf8))
    var settings = GameplayPreferences(noteSpeed: 9, scoreMode: 0,
      engineOptions: ["#NOTE_SIZE": 1.37, "#MIRROR": 1, "Mode": 2,
        "#SPEED": 1.5, "Future": 999, "#NOTE_SPEED": 2, "removed": 99])
    XCTAssertNoThrow(try config.validateOptions())
    XCTAssertEqual(config.runtimeOptions(preferences: settings),
      [1.25, 1, 2, 1.5, 17, 9, 0])
    XCTAssertEqual(config.playbackSpeed(preferences: settings), 1.5)
    XCTAssertEqual(config.modifiedStandardOptions(preferences: settings), [
      EngineOptionOverride(name: "Mirror", value: "On"),
      EngineOptionOverride(name: "Input Mode", value: "Strict")])
    XCTAssertEqual(config.options[0].valueLabel(1.25), "125%")
    settings.engineOptions["Mode"] = 99
    settings.engineOptions["#MIRROR"] = 0.5
    settings.engineOptions["#NOTE_SIZE"] = 999
    XCTAssertEqual(Array(config.runtimeOptions(preferences: settings).prefix(3)), [2, 0, 1])
    settings.engineOptions["Mode"] = 0.5
    XCTAssertEqual(config.runtimeOptions(preferences: settings)[2], 1)
    settings.engineOptions["Mode"] = .infinity
    XCTAssertEqual(config.runtimeOptions(preferences: settings)[2], 1)
    let restored = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data(#"{"scoreDisplay":"countDown"}"#.utf8))
    XCTAssertEqual(restored.engineOptions, [:])
    XCTAssertEqual(config.runtimeOptions(preferences: restored), [1, 0, 1, 1, 17, 5, 1])
  }

  func testMalformedEngineOptionsCannotReachSliderOrPickerControls() throws {
    for option in [
      #"{"name":"bad","type":"slider","def":3,"min":0,"max":1,"step":0.1}"#,
      #"{"name":"bad","type":"slider","def":0,"min":1,"max":0}"#,
      #"{"name":"bad","type":"slider","def":0,"min":0,"max":1,"step":0}"#,
      #"{"name":"bad","type":"select","def":0,"values":[]}"#,
      #"{"name":"bad","type":"select","def":0.5,"values":["a"]}"#,
      #"{"name":"bad","type":"toggle","def":2}"#
    ] {
      let config = try JSONDecoder().decode(EngineConfiguration.self,
        from: Data("{\"options\":[\(option)]}".utf8))
      XCTAssertThrowsError(try config.validateOptions())
    }
    let duplicate = try JSONDecoder().decode(EngineConfiguration.self,
      from: Data(#"{"options":[{"name":"same","def":0},{"name":"same","def":1}]}"#.utf8))
    XCTAssertThrowsError(try duplicate.validateOptions())
  }

  func testSpecialOptionNamesRouteByDeclaredControlKind() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self,
      from: Data(#"""
      {"options":[{"name":"Score Mode","type":"toggle","def":0},
      {"name":"#NOTE_SPEED","type":"select","def":0,"values":["Slow","Fast"]}]}
      """#.utf8))
    XCTAssertFalse(config.options[0].usesScoreModeControl)
    XCTAssertFalse(config.options[1].usesNoteSpeedControl)
    XCTAssertEqual(config.options.map(\.controlType), ["toggle", "select"])
    let preferences = GameplayPreferences(noteSpeed: 9, scoreMode: 9,
      engineOptions: ["Score Mode": 1, "#NOTE_SPEED": 1])
    XCTAssertEqual(config.runtimeOptions(preferences: preferences), [1, 1],
      "Dedicated preferences from an old definition must not override a new kind")
  }

  func testComboAnimationUsesEngineTweenAndRetainsItsFinalState() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"options":[],"ui":{"comboAnimation":{
      "scale":{"from":1.5,"to":1,"duration":0.2,"ease":"linear"},
      "alpha":{"from":0,"to":0.8,"duration":0.1,"ease":"linear"}}}}
      """#.utf8))
    let animation = try XCTUnwrap(config.ui?.comboAnimation)
    XCTAssertEqual(animation.duration, 0.2)
    XCTAssertEqual(animation.scale.value(at: 0.1), 1.25)
    XCTAssertEqual(animation.alpha.value(at: 0.05), 0.4)
    XCTAssertEqual(animation.scale.value(at: 9), 1)
    XCTAssertEqual(animation.alpha.value(at: 9), 0.8)
  }

  func testFractionalCallbackOrderIsNotRestrictedToKnownEngineFixtures() throws {
    let callback = try JSONDecoder().decode(EngineCallback.self,
      from: Data(#"{"index":0,"order":-0.5}"#.utf8))
    XCTAssertEqual(callback.order, -0.5)
  }

  func testOptionalProtocolFieldsAreNotMadeMandatoryByFixtures() throws {
    let tag = try JSONDecoder().decode(SonolusTag.self,
      from: Data(#"{"icon":"heart"}"#.utf8))
    XCTAssertNil(tag.title)
    XCTAssertEqual(tag.icon, "heart")
    XCTAssertEqual(Difficulty(tags: [tag]), .unknown)
    let bucket = try JSONDecoder().decode(EngineBucket.self,
      from: Data(#"{"sprites":[]}"#.utf8))
    XCTAssertNil(bucket.unit)
  }
  func testExecuteZeroEvaluatesAllChildrenInOrderAndReturnsZero() throws {
    let memory = EngineMemory()
    let nodes = [EngineDataNode(value: 2000), EngineDataNode(value: 0),
      EngineDataNode(value: 3), EngineDataNode(value: 4),
      EngineDataNode(function: "Set", arguments: [0, 1, 2]),
      EngineDataNode(function: "SetMultiply", arguments: [0, 1, 3]),
      EngineDataNode(function: "Execute0", arguments: [4, 5]),
      EngineDataNode(function: "Execute0", arguments: [])]
    let interpreter = EngineInterpreter(nodes: nodes, memory: memory)
    XCTAssertEqual(try interpreter.execute(nodeAt: 6), 0)
    XCTAssertEqual(memory.value(block: 2000, index: 0), 12)
    XCTAssertEqual(try interpreter.execute(nodeAt: 7), 0)
  }
  private func evaluate(_ name: String, _ values: [Double],
    memory: EngineMemory = EngineMemory(), limit: Int = 1_000_000) throws -> Double {
    let nodes = values.map { EngineDataNode(value: $0) }
      + [EngineDataNode(function: name, arguments: Array(values.indices))]
    return try EngineInterpreter(nodes: nodes, memory: memory,
      operationLimit: limit).execute(nodeAt: values.count)
  }

  func testExtendedMathAndVariadicFolds() throws {
    let cases: [(String, [Double], Double)] = [
      ("Arccos", [0], .pi / 2), ("Arcsin", [1], .pi / 2),
      ("Cosh", [0], 1), ("Sinh", [0], 0), ("Tan", [0], 0),
      ("Tanh", [0], 0), ("Degree", [.pi], 180), ("Radian", [180], .pi),
      ("Frac", [1.25], 0.25), ("Sign", [-2], -1), ("Sign", [0], 0),
      ("Divide", [24, 2, 3], 4), ("Divide", [7], 7),
      ("Power", [2, 3, 2], 64), ("Rem", [-17, 5, 2], 0),
      ("Rem", [-17, 5], -2)
    ]
    for (name, args, expected) in cases {
      XCTAssertEqual(try evaluate(name, args), expected, accuracy: 1e-10, name)
    }
    for name in ["Divide", "Power", "Rem"] {
      XCTAssertThrowsError(try evaluate(name, []), name)
    }
  }

  func testAllMemoryAddressingAndCompoundFamilies() throws {
    let mutations: [(String, Double, Double)] = [
      ("Get", 10, 10), ("Set", 3, 3), ("SetAdd", 13, 13),
      ("SetSubtract", 7, 7), ("SetMultiply", 30, 30),
      ("SetDivide", 10.0 / 3, 10.0 / 3), ("SetPower", 1000, 1000),
      ("SetMod", 1, 1), ("SetRem", 1, 1),
      ("IncrementPre", 10, 11), ("IncrementPost", 11, 11),
      ("DecrementPre", 10, 9), ("DecrementPost", 9, 9)
    ]
    for suffix in ["", "Shifted", "Pointed"] {
      for (base, returned, stored) in mutations {
        let memory = EngineMemory()
        memory.set(block: 2000, index: 8, value: 10)
        memory.set(block: 2001, index: 0, value: 2000)
        memory.set(block: 2001, index: 1, value: 6)
        var args: [Double] = switch suffix {
        case "Shifted": [2000, 2, 2, 3] // 2 + 2 * 3
        case "Pointed": [2001, 0, 2] // pointer (2000, 6) + 2
        default: [2000, 8]
        }
        if base.hasPrefix("Set") { args.append(3) }
        XCTAssertEqual(try evaluate(base + suffix, args, memory: memory),
          returned, accuracy: 1e-10, base + suffix)
        XCTAssertEqual(memory.value(block: 2000, index: 8), stored,
          accuracy: 1e-10, base + suffix)
      }
    }
    for suffix in ["", "Shifted", "Pointed"] {
      let memory = EngineMemory()
      memory.set(block: 2000, index: 0, value: -10)
      memory.set(block: 2001, index: 0, value: 2000)
      let address: [Double] = suffix == "Pointed" ? [2001, 0, 0]
        : suffix == "Shifted" ? [2000, 0, 0, 1] : [2000, 0]
      XCTAssertEqual(try evaluate("SetMod" + suffix, address + [3], memory: memory), 2)
      memory.set(block: 2000, index: 0, value: -10)
      XCTAssertEqual(try evaluate("SetRem" + suffix, address + [3], memory: memory), -1)
    }
  }

  func testCopyOverlapsInBothDirectionsAndChargesItsBudget() throws {
    for destination in [0, 2] {
      let memory = EngineMemory()
      for index in 0..<6 { memory.set(block: 2000, index: index, value: Double(index)) }
      XCTAssertEqual(try evaluate("Copy", [2000, 1, 2000, Double(destination), 4],
        memory: memory), 0)
      XCTAssertEqual((destination..<(destination + 4)).map {
        memory.value(block: 2000, index: $0)
      }, [1, 2, 3, 4])
    }
    XCTAssertThrowsError(try evaluate("Copy", [2000, 0, 2001, 0, 100], limit: 20))
    XCTAssertThrowsError(try evaluate("Copy", [2000, 0, 2001, 0, -1]))
    XCTAssertThrowsError(try evaluate("GetPointed", [2000, .infinity, 0]))
  }

  func testLoopReturnsAndDoWhileExecutesBeforeCondition() throws {
    let memory = EngineMemory()
    let nodes = [EngineDataNode(value: 2000), EngineDataNode(value: 0),
      EngineDataNode(function: "IncrementPost", arguments: [0, 1]),
      EngineDataNode(function: "DoWhile", arguments: [2, 1]),
      EngineDataNode(function: "While", arguments: [1, 2])]
    let interpreter = EngineInterpreter(nodes: nodes, memory: memory)
    XCTAssertEqual(try interpreter.execute(nodeAt: 3), 0)
    XCTAssertEqual(memory.value(block: 2000, index: 0), 1)
    XCTAssertEqual(try interpreter.execute(nodeAt: 4), 0)
    XCTAssertEqual(memory.value(block: 2000, index: 0), 1)
    XCTAssertThrowsError(try evaluate("DoWhile", [1, 1], limit: 20))
  }

  func testEveryEasingFunctionIsRecognizedAndHasCorrectEndpoints() throws {
    XCTAssertEqual(EngineInterpreter.easingFunctions.count, 36)
    for name in EngineInterpreter.easingFunctions {
      XCTAssertEqual(try evaluate(name, [0]), 0, accuracy: 1e-10, name)
      XCTAssertEqual(try evaluate(name, [1]), 1, accuracy: 1e-10, name)
      XCTAssertTrue(try evaluate(name, [0.3]).isFinite, name)
    }
    XCTAssertEqual(try evaluate("EaseInOutBack", [0.25]),
      -0.09968184375, accuracy: 1e-10)
    XCTAssertEqual(try evaluate("EaseInOutElastic", [0.25]),
      0.011969444423734, accuracy: 1e-10)
    XCTAssertEqual(try evaluate("EaseInOutBack", [0.75]),
      1.09968184375, accuracy: 1e-10)
    XCTAssertEqual(try evaluate("EaseInOutElastic", [0.75]),
      0.988030555576266, accuracy: 1e-10)
  }

  func testPointedAddressSnapshotPrecedesOffsetSideEffects() throws {
    for name in ["GetPointed", "SetAddPointed", "IncrementPostPointed"] {
      let memory = EngineMemory()
      memory.set(block: 2000, index: 0, value: 2001)
      memory.set(block: 2001, index: 0, value: 7)
      memory.set(block: 2002, index: 0, value: 9)
      var nodes = [EngineDataNode(value: 2000), EngineDataNode(value: 0),
        EngineDataNode(value: 2002),
        EngineDataNode(function: "Set", arguments: [0, 1, 2]),
        EngineDataNode(function: "Execute", arguments: [3, 1]),
        EngineDataNode(value: 3)]
      nodes.append(EngineDataNode(function: name,
        arguments: name == "SetAddPointed" ? [0, 1, 4, 5] : [0, 1, 4]))
      let result = try EngineInterpreter(nodes: nodes, memory: memory).execute(nodeAt: 6)
      XCTAssertEqual(result, name == "GetPointed" ? 7 : name == "SetAddPointed" ? 10 : 8)
      XCTAssertEqual(memory.value(block: 2002, index: 0), 9)
    }
  }

  func testRandomBoundsAndInvalidRanges() throws {
    for _ in 0..<100 {
      XCTAssertTrue((-3...2).contains(try evaluate("Random", [-3, 2])))
      let integer = try evaluate("RandomInteger", [-1.5, 2.2])
      XCTAssertTrue((-1...2).contains(integer))
      XCTAssertEqual(integer, integer.rounded())
    }
    XCTAssertEqual(try evaluate("Random", [4, 4]), 4)
    XCTAssertThrowsError(try evaluate("RandomInteger", [4, 4]))
    XCTAssertThrowsError(try evaluate("Random", [2, 1]))
    XCTAssertThrowsError(try evaluate("Random", [.nan, 1]))
  }

  func testUIVisibilityDecodesInRuntimeBlockOrder() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"options":[],"ui":{"menuVisibility":{"scale":0.5,"alpha":0},
      "comboVisibility":{"scale":2,"alpha":0.3},
      "secondaryMetricVisibility":{"scale":1.5,"alpha":0.8}}}
      """#.utf8))
    XCTAssertEqual(config.ui?.runtimeValues, [0.5, 0, 1, 1, 2, 0.3, 1, 1, 1.5, 0.8])
  }

  func testEngineUILayoutMapsCoordinatesPivotsAndHiddenElements() throws {
    let memory = EngineMemory()
    let values = [-1.5, 0.8, 1.0, 1, 0, 0.08, 0, 0.7, 1, 0]
    for (index, value) in values.enumerated() {
      memory.set(block: 1006, index: 50 + index, value: value)
    }
    let element = EngineUIElement(memory: memory, index: 5)
    XCTAssertTrue(element.isVisible)
    XCTAssertEqual(element.anchor(in: CGSize(width: 800, height: 400)),
      CGPoint(x: 100, y: 40))
    XCTAssertEqual(element.pivot, CGPoint(x: 1, y: 0))
    memory.set(block: 1006, index: 57, value: 0)
    XCTAssertFalse(EngineUIElement(memory: memory, index: 5).isVisible)
  }

  func testEngineJudgmentAnimationControlsDurationAndEasing() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"options":[],"ui":{"primaryMetric":"arcade","secondaryMetric":"life",
      "judgmentAnimation":{"scale":{"from":0,"to":1,"duration":0.1,"ease":"linear"},
      "alpha":{"from":1,"to":0,"duration":0.3,"ease":"none"}}}}
      """#.utf8))
    let animation = try XCTUnwrap(config.ui?.judgmentAnimation)
    XCTAssertEqual(animation.duration, 0.3)
    XCTAssertEqual(animation.scale.value(at: 0.05), 0.5)
    XCTAssertEqual(animation.alpha.value(at: 0.29), 1)
    XCTAssertEqual(animation.alpha.value(at: 0.3), 0)
    XCTAssertEqual(config.ui?.primaryMetric, "arcade")
    XCTAssertEqual(config.ui?.secondaryMetric, "life")
  }

  func testOversizedEngineAnimationsAreRejectedWithoutDurationTraps() {
    for (from, duration) in [("1", "1e300"), ("1e300", "0.3"), ("1", "-1")] {
      let json = """
        {"options":[],"ui":{"judgmentAnimation":{
        "scale":{"from":\(from),"to":1,"duration":\(duration),"ease":"linear"},
        "alpha":{"from":1,"to":0,"duration":0.3,"ease":"none"}}}}
        """
      XCTAssertThrowsError(try JSONDecoder().decode(EngineConfiguration.self,
        from: Data(json.utf8)))
    }
  }

  @MainActor
  func testTimeMetricRejectsUnrepresentableTimes() throws {
    let model = try gameplayModel()
    model.start()
    defer { model.stop() }
    model.update(mediaTime: 1e20)
    XCTAssertNil(model.engineMetric("time"))
  }

  func testStartupPreservesAudioWithoutAddingLeadIn() {
    for offset in [9.0, 1, 0, -2] {
      let mapping = BGMClockMapping(offset: offset)
      XCTAssertEqual(mapping.initialChartTime, -offset)
      XCTAssertEqual(mapping.initialMediaTime, 0)
      XCTAssertEqual(mapping.chartTime(mediaTime: 10), 10 - offset)
    }
  }

  func testJudgementFeedbackModesAndTimingDirection() {
    let early = JudgementFeedback(sequence: 1, judgement: .good, accuracy: -0.12)
    let late = JudgementFeedback(sequence: 2, judgement: .great, accuracy: 0.07)
    XCTAssertEqual(early.text(for: .timing), "Early GOOD")
    XCTAssertEqual(late.text(for: .timing), "Late GREAT")
    XCTAssertEqual(early.text(for: .judgement), "GOOD")
    XCTAssertNil(early.text(for: .off))
    XCTAssertEqual(JudgementFeedback(sequence: 3, judgement: .perfect,
      accuracy: -0.01).text(for: .timing), "PERFECT")
    XCTAssertEqual(JudgementFeedback(sequence: 4, judgement: .miss,
      accuracy: 0.2).text(for: .timing), "MISS")
  }

  @MainActor
  func testHeatmapHUDSelectionUsesTheSharedInputPipelineAndResetsOnRestart() throws {
    for metrics in [("errorHeatmap", "life"), ("arcade", "errorHeatmap"),
      ("arcade", "life")] {
      let configuration = try JSONSerialization.data(withJSONObject: [
        "options": [], "ui": ["primaryMetric": metrics.0, "secondaryMetric": metrics.1]
      ] as [String: Any])
      let model = try gameplayModel(presentation: RuntimePresentation(resources: [
        "configuration": configuration
      ]))
      model.start()
      defer { model.stop() }
      model.press(lane: 0, at: 1.02)
      model.release(lane: 0)
      XCTAssertEqual(model.noteTimings.count, 1)
      let expected = metrics.0 == "errorHeatmap" || metrics.1 == "errorHeatmap" ? 1 : 0
      XCTAssertEqual(model.errorHeatmap.count, expected)
      if expected == 1 {
        XCTAssertEqual(model.errorHeatmap.meanMS!, 20, accuracy: 1e-8)
        XCTAssertEqual(model.engineMetric("errorHeatmap")?.text, "+20.0 ms")
      }
      model.restart()
      XCTAssertEqual(model.errorHeatmap.count, 0)
      XCTAssertNil(model.errorHeatmap.meanMS)
      XCTAssertEqual(model.errorHeatmap.peak, 0)
    }
  }

  func testTimingPlacementUsesEngineSettingWithoutChangingTheGrade() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"options":[],"ui":{"judgmentErrorPlacement":"bottom"}}
      """#.utf8))
    let early = JudgementFeedback(sequence: 1, judgement: .perfect,
      accuracy: -0.03, minimumError: 0.02)
    let late = JudgementFeedback(sequence: 2, judgement: .great, accuracy: 0.03)
    XCTAssertEqual(early.timingPlacement(config.ui?.judgmentErrorPlacement), "bottom")
    for fixed in ["top", "bottom", "left", "right", "center"] {
      XCTAssertEqual(early.timingPlacement(fixed), fixed)
      XCTAssertEqual(late.timingPlacement(fixed), fixed)
    }
    XCTAssertEqual(early.timingPlacement("leftRight"), "left")
    XCTAssertEqual(late.timingPlacement("leftRight"), "right")
    XCTAssertEqual(early.timingPlacement("topBottom"), "top")
    XCTAssertEqual(late.timingPlacement("topBottom"), "bottom")
    XCTAssertEqual(early.text(for: .timing), "Early PERFECT")
    XCTAssertEqual(early.timingPlacement(nil), "top")
  }

  func testPerfectTimingLabelUsesEngineMinimumError() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self,
      from: Data(#"{"options":[],"ui":{"judgmentErrorMin":20}}"#.utf8))
    let minimum = try XCTUnwrap(config.ui?.judgmentErrorMin) / 1000
    for (error, expected) in [(-0.03, "Early"), (0.025, "Late"),
      (-0.02, ""), (0.02, ""), (-0.019, ""), (0, "")] {
      let feedback = JudgementFeedback(sequence: 1, judgement: .perfect,
        accuracy: error, minimumError: minimum)
      XCTAssertEqual(feedback.timingText(for: .timing) ?? "", expected)
      XCTAssertNil(feedback.timingText(for: .judgement))
    }
  }

  func testAllEngineTimingStylesUseSignedErrorWithoutChangingJudgment() throws {
    let pairs = [
      "late": ["Late", "Early"], "early": ["Early", "Late"],
      "plus": ["+", "-"], "minus": ["-", "+"],
      "arrowUp": ["↑", "↓"], "arrowDown": ["↓", "↑"],
      "arrowLeft": ["←", "→"], "arrowRight": ["→", "←"],
      "triangleUp": ["▲", "▼"], "triangleDown": ["▼", "▲"],
      "triangleLeft": ["◄", "►"], "triangleRight": ["►", "◄"]
    ]
    XCTAssertEqual(pairs.count + 1, EngineJudgmentErrorStyle.allCases.count)
    for (style, pair) in pairs {
      let config = try JSONDecoder().decode(EngineConfiguration.self,
        from: Data("{\"options\":[],\"ui\":{\"judgmentErrorStyle\":\"\(style)\"}}".utf8))
      XCTAssertEqual(config.ui?.judgmentErrorStyle, style)
      for (index, error) in [0.03, -0.03].enumerated() {
        for grade in [NoteJudgement.perfect, .great, .good] {
          let feedback = JudgementFeedback(sequence: 1, judgement: grade,
            accuracy: error, minimumError: 0.02)
          XCTAssertEqual(feedback.timingText(for: .timing,
            style: config.ui?.judgmentErrorStyle), pair[index])
          XCTAssertEqual(feedback.accuracy, error)
          XCTAssertEqual(feedback.judgement, grade)
          XCTAssertNil(feedback.timingText(for: .off, style: style))
          XCTAssertNil(feedback.timingText(for: .judgement, style: style))
          XCTAssertNil(feedback.timingText(for: .timing, style: "none"))
        }
      }
    }
    for error in [0.0, Double.nan, .infinity, -.infinity] {
      XCTAssertNil(JudgementFeedback(sequence: 1, judgement: .great,
        accuracy: error).timingText(for: .timing, style: "plus"))
    }
    let miss = JudgementFeedback(sequence: 1, judgement: .miss, accuracy: 0.1)
    XCTAssertNil(miss.timingText(for: .timing, style: "arrowUp"))
    let feedback = JudgementFeedback(sequence: 1, judgement: .great, accuracy: -0.03)
    XCTAssertEqual(feedback.timingText(for: .timing, style: "future"), "Early")
  }

  @MainActor
  func testFallbackJudgementsRetainSignedAccuracyAndResetOnRestart() throws {
    let model = try gameplayModel()
    model.start()
    defer { model.stop() }
    model.update(mediaTime: 1.02)
    model.press(lane: 0)
    model.release(lane: 0)
    XCTAssertEqual(model.latestJudgement?.text(for: .timing), "Late GREAT")
    model.update(mediaTime: 2.82)
    model.press(lane: 2)
    XCTAssertEqual(model.latestJudgement?.text(for: .timing), "Early GOOD")
    model.restart()
    XCTAssertNil(model.latestJudgement)
  }

  @MainActor
  func testReadyNoteCountUsesEngineInputDefinitionsBeforeRuntimeStarts() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"nodes":[],"buckets":[],
       "archetypes":[
         {"name":"TapNote","hasInput":false,"imports":[],"exports":[]},
         {"name":"SwingNote","hasInput":true,"imports":[],"exports":[]}
       ]}
      """#.utf8))
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .pngData { _ in }
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8),
      "skinData": Data(#"""
        {"width":1,"height":1,"interpolation":false,"sprites":[]}
        """#.utf8),
      "skinTexture": image,
      "particleData": Data(#"""
        {"width":1,"height":1,"interpolation":false,"sprites":[],"effects":[]}
        """#.utf8),
      "particleTexture": image,
      "effectData": Data(#"{"clips":[]}"#.utf8),
      "effectAudio": Data([0x50, 0x4b, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
    ])
    let model = try gameplayModel(engine: engine, presentation: presentation)
    XCTAssertEqual(model.phase, .ready)
    XCTAssertNil(model.engineRuntime)
    XCTAssertEqual(model.noteCount, 1,
      "Count engine-defined inputs, not guessed archetype names")
    let fallback = try gameplayModel(engine: engine)
    XCTAssertEqual(fallback.phase, .ready)
    XCTAssertNil(fallback.presentationAssets)
    XCTAssertEqual(fallback.noteCount, fallback.chart.judgementCount,
      "The fallback player's count and score denominator must match its chart")
  }

  func testBGMOffsetPreservesSuppliedAudioAndMapsChartTime() {
    let eleventh = BGMClockMapping(offset: 9)
    XCTAssertEqual(eleventh.initialMediaTime, 0)
    XCTAssertEqual(eleventh.initialChartTime, -9)
    XCTAssertEqual(eleventh.chartTime(mediaTime: 9.75), 0.75)
    XCTAssertEqual(eleventh.mediaTime(chartTime: 0.75), 9.75)
    let negative = BGMClockMapping(offset: -0.05)
    XCTAssertEqual(negative.initialMediaTime, 0)
    XCTAssertEqual(negative.initialChartTime, 0.05)
    XCTAssertEqual(negative.chartTime(mediaTime: 0.95), 1)
  }
  func testDecodesGzippedLevelData() throws {
    let encoded = """
      H4sIAAAAAAAAA6tWSkrP9U9LK04tUbLSNdAzMNVRSs0rySzJTC1WsoquVkosSs5I\
      LaksSFWyUgpJLPDLL0lV0lHKS8wFCRgAmSmJJYlglVAxZSdXxxCgeFliTimQb6Rn\
      YVGrA5ctKEotA0oWpaYBOfklGalFSrWxQAgAJEa/z4gAAAA=
      """
    let compressed = try XCTUnwrap(Data(base64Encoded: encoded))

    let level = try CompressedJSONDecoder.decode(
      LevelData.self,
      from: compressed
    )

    XCTAssertEqual(level.bgmOffset, -0.05)
    XCTAssertEqual(level.entities.count, 1)
    XCTAssertEqual(level.entities[0].archetype, "TapNote")
    XCTAssertEqual(level.entities[0].data[0].value, 2.88)
    XCTAssertEqual(level.entities[0].data[1].ref, "other")
  }

  func testDecodesEngineValueAndFunctionNodes() throws {
    let json = #"""
      {
        "skin": {"sprites": []},
        "effect": {"clips": []},
        "particle": {"effects": []},
        "archetypes": [],
        "nodes": [{"value": 2}, {"func": "Add", "args": [0, 0]}],
        "buckets": []
      }
      """#
    let data = Data(json.utf8)

    let engine = try CompressedJSONDecoder.decode(
      EnginePlayData.self,
      from: data
    )

    XCTAssertEqual(engine.nodes[0].value, 2)
    XCTAssertEqual(engine.nodes[1].function, "Add")
    XCTAssertEqual(engine.nodes[1].arguments, [0, 0])
  }

  func testInterpreterExecutesMemoryAndLazyControlFlow() throws {
    let nodes = [
      EngineDataNode(value: 10),
      EngineDataNode(value: 4),
      EngineDataNode(value: 7),
      EngineDataNode(function: "Set", arguments: [0, 1, 2]),
      EngineDataNode(value: 1),
      EngineDataNode(value: 99),
      EngineDataNode(function: "If", arguments: [4, 3, 5]),
      EngineDataNode(function: "Get", arguments: [0, 1])
    ]
    let interpreter = EngineInterpreter(nodes: nodes)

    XCTAssertEqual(try interpreter.execute(nodeAt: 6), 7)
    XCTAssertEqual(try interpreter.execute(nodeAt: 7), 7)
  }

  func testInterpreterHandlesSwitchAndBreak() throws {
    let nodes = [
      EngineDataNode(value: 1),
      EngineDataNode(value: 11),
      EngineDataNode(value: 22),
      EngineDataNode(function: "SwitchInteger", arguments: [0, 1, 2]),
      EngineDataNode(function: "Break", arguments: [0, 2]),
      EngineDataNode(function: "Block", arguments: [4])
    ]
    let interpreter = EngineInterpreter(nodes: nodes)

    XCTAssertEqual(try interpreter.execute(nodeAt: 3), 22)
    XCTAssertEqual(try interpreter.execute(nodeAt: 5), 22)
  }

  func testIntegerSwitchMatchesExactlyAndEvaluatesOnlySelectedBranches() throws {
    let discriminants: [Double] = [-0.0, 1, -0.25, 0.25, 1.25, -1, 2,
      Double(Int.max), 1e100, .infinity, -.infinity, .nan]
    for discriminant in discriminants {
      for hasDefault in [false, true] {
        let memory = EngineMemory()
        let nodes = [
          EngineDataNode(value: 2000), // 0: block
          EngineDataNode(value: 0),    // 1: discriminator counter slot
          EngineDataNode(value: 1),    // 2: branch-zero slot / increment
          EngineDataNode(value: 2),    // 3: branch-one slot
          EngineDataNode(value: 11),   // 4: branch-zero result
          EngineDataNode(value: 22),   // 5: branch-one result
          EngineDataNode(value: 33),   // 6: default slot and result
          EngineDataNode(value: discriminant),
          EngineDataNode(function: "SetAdd", arguments: [0, 1, 2]),
          EngineDataNode(function: "Execute", arguments: [8, 7]),
          EngineDataNode(function: "Set", arguments: [0, 2, 4]),
          EngineDataNode(function: "Set", arguments: [0, 3, 5]),
          EngineDataNode(function: "Set", arguments: [0, 6, 6]),
          EngineDataNode(function: hasDefault
            ? "SwitchIntegerWithDefault" : "SwitchInteger",
            arguments: [9, 10, 11] + (hasDefault ? [12] : []))
        ]
        let interpreter = EngineInterpreter(nodes: nodes, memory: memory)
        let zero = discriminant == 0
        let one = discriminant == 1
        let useDefault = !zero && !one && hasDefault
        XCTAssertEqual(try interpreter.execute(nodeAt: 13),
          zero ? 11 : one ? 22 : useDefault ? 33 : 0,
          "Discriminant \(discriminant), default \(hasDefault)")
        XCTAssertEqual(memory.value(block: 2000, index: 0), 1)
        XCTAssertEqual(memory.value(block: 2000, index: 1), zero ? 11 : 0)
        XCTAssertEqual(memory.value(block: 2000, index: 2), one ? 22 : 0)
        XCTAssertEqual(memory.value(block: 2000, index: 33), useDefault ? 33 : 0)
      }
    }
  }

  func testJumpLoopUnmatchedTargetsDoNotExecuteOrRepeatBranches() throws {
    for target: Double in [-0.25, 0.25, 1.25, -1, 2, Double(Int.max),
      1e100, .infinity, -.infinity, .nan] {
      let memory = EngineMemory()
      let nodes = [
        EngineDataNode(value: 2000),
        EngineDataNode(value: 0),
        EngineDataNode(value: 1),
        EngineDataNode(value: target),
        EngineDataNode(function: "SetAdd", arguments: [0, 1, 2]),
        EngineDataNode(function: "Execute", arguments: [4, 3]),
        EngineDataNode(function: "UnselectedBranch", arguments: []),
        EngineDataNode(function: "JumpLoop", arguments: [5, 6])
      ]
      let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
        operationLimit: 100)
      XCTAssertEqual(try interpreter.execute(nodeAt: 7), 0, "Target \(target)")
      XCTAssertEqual(memory.value(block: 2000, index: 0), 1,
        "An invalid target must exit, not re-enter branch zero")
    }
  }

  func testJumpLoopDispatchIsLazyAndReturnsFinalBranch() throws {
    let nodes = [
      EngineDataNode(value: 2),
      EngineDataNode(function: "UnsupportedUnvisitedBranch", arguments: []),
      EngineDataNode(value: 42),
      EngineDataNode(function: "JumpLoop", arguments: [0, 1, 2]),
      EngineDataNode(value: -1),
      EngineDataNode(function: "JumpLoop", arguments: [4, 1]),
      EngineDataNode(function: "JumpLoop", arguments: []),
      EngineDataNode(function: "JumpLoop", arguments: [2])
    ]
    let interpreter = EngineInterpreter(nodes: nodes)
    XCTAssertEqual(try interpreter.execute(nodeAt: 3), 42)
    XCTAssertEqual(try interpreter.execute(nodeAt: 5), 0)
    XCTAssertEqual(try interpreter.execute(nodeAt: 6), 0)
    XCTAssertEqual(try interpreter.execute(nodeAt: 7), 42)
  }

  func testJumpLoopHonorsOperationLimitAndPropagatesBreaks() throws {
    let nodes = [
      EngineDataNode(value: 0),
      EngineDataNode(value: 1),
      EngineDataNode(value: 42),
      EngineDataNode(function: "Break", arguments: [1, 2]),
      EngineDataNode(function: "JumpLoop", arguments: [3, 2]),
      EngineDataNode(function: "Block", arguments: [4]),
      EngineDataNode(function: "JumpLoop", arguments: [0, 2]),
      EngineDataNode(value: .nan),
      EngineDataNode(function: "JumpLoop", arguments: [7, 2])
    ]
    let interpreter = EngineInterpreter(nodes: nodes, operationLimit: 20)
    XCTAssertEqual(try interpreter.execute(nodeAt: 5), 42)
    XCTAssertThrowsError(try interpreter.execute(nodeAt: 6)) { error in
      guard case EngineInterpreterError.operationLimitExceeded = error else {
        return XCTFail("Expected an operation limit, got \(error)")
      }
    }
    XCTAssertEqual(try interpreter.execute(nodeAt: 8), 0)
    XCTAssertEqual(try interpreter.execute(nodeAt: 5), 42,
      "A failed callback must not poison the next execution")
  }

  func testNumericFunctionsUsedBySEKAI() throws {
    let examples: [(String, [Double], Double)] = [
      ("Clamp", [-2, 0, 1], 0), ("Clamp", [2, 0, 1], 1),
      ("Clamp", [0.5, 0, 1], 0.5), ("Arctan", [1], .pi / 4),
      ("Ceil", [-1.7], -1), ("Floor", [-1.2], -2),
      ("Round", [1.6], 2), ("Trunc", [-1.7], -1),
      ("Log", [exp(2)], 2), ("Mod", [-5, 3], 1),
      ("Mod", [5, -3], -1), ("Mod", [25, 7, 3], 1),
      ("Mod", [Double.greatestFiniteMagnitude, 0.5], 0),
      ("Remap", [0, 10, 100, 200, 5], 150),
      ("RemapClamped", [0, 10, 200, 100, 20], 100),
      ("RemapClamped", [10, 0, 100, 200, 20], 100),
      ("UnlerpClamped", [0, 10, 20], 1),
      ("UnlerpClamped", [10, 0, 20], 0),
      ("LerpClamped", [10, 20, -1], 10),
      ("EaseInQuad", [0.5], 0.25), ("EaseOutQuad", [0.5], 0.75),
      ("EaseInOutQuad", [0.25], 0.125), ("EaseOutInQuad", [0.25], 0.375),
      ("EaseInCubic", [0.5], 0.125), ("EaseOutCubic", [0.5], 0.875),
      ("EaseInQuad", [2], 4)
    ]
    for (function, arguments, expected) in examples {
      let nodes = arguments.map { EngineDataNode(value: $0) } + [
        EngineDataNode(function: function, arguments: Array(arguments.indices))
      ]
      XCTAssertEqual(try EngineInterpreter(nodes: nodes)
        .execute(nodeAt: arguments.count), expected, accuracy: 0.000001, function)
    }
  }

  func testEngineROMDecodesLittleEndianFloatsAndIsReadOnly() throws {
    let memory = EngineMemory()
    // IEEE-754 little-endian Float32 values 1, -2.5, 0.125.
    try memory.loadROM(Data([0, 0, 128, 63, 0, 0, 32, 192, 0, 0, 0, 62]))
    XCTAssertEqual(memory.value(block: 3000, index: 0), 1)
    XCTAssertEqual(memory.value(block: 3000, index: 1), -2.5)
    XCTAssertEqual(memory.value(block: 3000, index: 2), 0.125)
    XCTAssertEqual(memory.value(block: 3000, index: 3), 0)
    memory.set(block: 3000, index: 0, value: 999)
    XCTAssertEqual(memory.value(block: 3000, index: 0), 1)
    let compressed = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAAA2NgaLBnYFA4wMDAYAcAKzCAQwwAAAA="))
    try memory.loadROM(compressed)
    XCTAssertEqual(memory.value(block: 3000, index: 1), -2.5)
    XCTAssertThrowsError(try memory.loadROM(Data([0x1f, 0x8b, 0])))
    XCTAssertThrowsError(try memory.loadROM(Data([1, 2, 3])))
    XCTAssertThrowsError(try memory.loadROM(Data(repeating: 0,
      count: 16 * 1024 * 1024 + 4)))
    try memory.loadROM(nil)
    XCTAssertEqual(memory.value(block: 3000, index: 0), 0)
  }

  func testExtendedMemoryOperators() throws {
    let memory = EngineMemory()
    memory.set(block: 2000, index: 7, value: 10)
    func call(_ function: String, _ arguments: [Double]) throws -> Double {
      let nodes = arguments.map { EngineDataNode(value: $0) } + [
        EngineDataNode(function: function, arguments: Array(arguments.indices))
      ]
      return try EngineInterpreter(nodes: nodes, memory: memory)
        .execute(nodeAt: arguments.count)
    }
    XCTAssertEqual(try call("SetSubtract", [2000, 7, 2]), 8)
    XCTAssertEqual(try call("SetDivide", [2000, 7, 2]), 4)
    XCTAssertEqual(try call("SetPower", [2000, 7, 2]), 16)
    XCTAssertEqual(try call("IncrementPost", [2000, 7]), 17)
    XCTAssertEqual(try call("DecrementPost", [2000, 7]), 16)
    XCTAssertEqual(try call("IncrementPre", [2000, 7]), 16)
    XCTAssertEqual(memory.value(block: 2000, index: 7), 17)
    XCTAssertEqual(try call("DecrementPre", [2000, 7]), 17)
    XCTAssertEqual(memory.value(block: 2000, index: 7), 16)
    XCTAssertEqual(try call("SetShifted", [2000, 1, 2, 3, 99]), 99)
    XCTAssertEqual(memory.value(block: 2000, index: 7), 99)
    XCTAssertThrowsError(try call("SetShifted", [2000, 1, .infinity, 3, 99]))
    XCTAssertEqual(memory.value(block: 2000, index: 7), 99)
  }

  func testSwitchWithDefaultEvaluatesOnlyMatchingConsequence() throws {
    let nodes = [
      EngineDataNode(value: 1.5),
      EngineDataNode(value: 2),
      EngineDataNode(value: 42),
      EngineDataNode(function: "UnvisitedBranch", arguments: []),
      EngineDataNode(function: "SwitchWithDefault", arguments: [0, 1, 3, 0, 2, 3]),
      EngineDataNode(function: "SwitchWithDefault", arguments: [0, 1, 3, 2]),
      EngineDataNode(function: "Switch", arguments: [0, 1, 3]),
      EngineDataNode(function: "SwitchWithDefault", arguments: [0, 1, 2])
    ]
    let interpreter = EngineInterpreter(nodes: nodes)
    XCTAssertEqual(try interpreter.execute(nodeAt: 4), 42)
    XCTAssertEqual(try interpreter.execute(nodeAt: 5), 42)
    XCTAssertEqual(try interpreter.execute(nodeAt: 6), 0)
    XCTAssertThrowsError(try interpreter.execute(nodeAt: 7))
  }

  func testCompoundWritesCaptureCurrentValueBeforeOperandSideEffects() throws {
    for (function, expected) in [
      ("SetAdd", 12.0), ("SetMultiply", 20.0), ("SetSubtract", 8.0),
      ("SetDivide", 5.0), ("SetPower", 100.0)
    ] {
      let memory = EngineMemory()
      memory.set(block: 2000, index: 7, value: 10)
      let nodes = [
        EngineDataNode(value: 2000), EngineDataNode(value: 7),
        EngineDataNode(value: 2),
        EngineDataNode(function: "Set", arguments: [0, 1, 2]),
        EngineDataNode(function: function, arguments: [0, 1, 3])
      ]
      let interpreter = EngineInterpreter(nodes: nodes, memory: memory)
      XCTAssertEqual(try interpreter.execute(nodeAt: 4), expected, function)
      XCTAssertEqual(memory.value(block: 2000, index: 7), expected, function)
    }
  }

  func testRuntimeReferencesRespectItemSources() throws {
    let json = #"""
      {
        "source": "https://levels.example/game",
        "bgm": {"url": "music.mp3"},
        "data": {"url": "/data/chart"},
        "engine": {
          "source": "https://engine.example/v13",
          "version": 13,
          "playData": {"url": "/data/play"}
        }
      }
      """#
    let itemData = Data(json.utf8)

    let references = try RuntimeResourceReferences(
      itemData: itemData,
      serverBaseURL: URL(string: "https://fallback.example")!
    )

    XCTAssertEqual(references.engineVersion, 13)
    XCTAssertEqual(
      references.engineDataURL.absoluteString,
      "https://engine.example/v13/data/play"
    )
    XCTAssertEqual(
      references.levelDataURL.absoluteString,
      "https://levels.example/game/data/chart"
    )
    XCTAssertEqual(
      references.bgmURL.absoluteString,
      "https://levels.example/game/music.mp3"
    )
  }

  func testBuildsTimedTapAndHoldNotesAcrossBPMChanges() throws {
    let level = LevelData(
      bgmOffset: 0,
      entities: [
        entity("#BPM_CHANGE", values: ["#BEAT": 0, "#BPM": 120]),
        entity("#BPM_CHANGE", values: ["#BEAT": 4, "#BPM": 60]),
        entity(
          "TapNote",
          name: "head",
          values: ["#BEAT": 2, "lane": -1]
        ),
        entity("HoldNote", name: "tail", values: ["#BEAT": 6]),
        LevelEntity(
          archetype: "HoldConnector",
          name: nil,
          data: [
            LevelEntityData(name: "head", value: nil, ref: "head"),
            LevelEntityData(name: "tail", value: nil, ref: "tail")
          ]
        ),
        entity("SwingNote", values: ["#BEAT": 5, "lane": 2])
      ]
    )

    let chart = RhythmChart(level: level)

    XCTAssertEqual(chart.notes.count, 2)
    XCTAssertEqual(chart.notes[0].time, 1)
    XCTAssertEqual(chart.notes[0].endTime, 4)
    XCTAssertEqual(chart.notes[0].lane, -1)
    XCTAssertEqual(chart.notes[1].time, 3)
    XCTAssertEqual(chart.duration, 4)
    XCTAssertEqual(chart.judgementCount, 3)
  }

  @MainActor
  func testGameplayScoresTapsSlidesAndHoldReleaseOnce() throws {
    let model = try gameplayModel()
    defer { model.stop() }
    model.start()

    model.update(mediaTime: 0.95)
    model.press(lane: 0)
    model.press(lane: 0)
    XCTAssertEqual(model.score, 200_000)
    model.release(lane: 0)

    model.update(mediaTime: 1.95)
    model.slide(lane: 1)
    XCTAssertEqual(model.score, 400_000)
    model.release(lane: 1)

    model.update(mediaTime: 2.95)
    model.slide(lane: 2)
    XCTAssertEqual(model.score, 400_000, "Sliding cannot hit a tap note")
    model.release(lane: 2)
    model.press(lane: 2)
    model.release(lane: 2)

    model.update(mediaTime: 3.95)
    model.press(lane: 3)
    XCTAssertEqual(model.activeHoldIDs.count, 1)
    model.update(mediaTime: 4.95)
    model.release(lane: 3)
    model.release(lane: 3)

    XCTAssertEqual(model.score, NoteJudgement.maximumScore)
    XCTAssertEqual(model.maxCombo, 5)
    XCTAssertEqual(model.judgements[.perfect], 5)
    XCTAssertEqual(model.judgements[.miss], 0)
    XCTAssertEqual(model.noteTimings.count, 5)
    XCTAssertEqual(model.noteTimings.map(\.noteType),
      ["Tap", "Swing", "Tap", "Hold Start", "Hold End"])
    XCTAssertEqual(model.noteTimings.map(\.songTime), [1, 2, 3, 4, 5])
    XCTAssertTrue(model.noteTimings.allSatisfy { abs($0.accuracy ?? 1) < 0.001 })
  }

  func testInputCalibrationDecodesDefaultsAndClampsInvalidValues() throws {
    let legacy = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data("{}".utf8))
    XCTAssertEqual(legacy.inputOffsetMilliseconds, 0)
    var settings = GameplayPreferences(inputOffsetMilliseconds: 300)
    XCTAssertEqual(settings.inputOffsetMilliseconds, 250)
    settings.inputOffsetMilliseconds = -.infinity
    XCTAssertEqual(settings.inputOffsetMilliseconds, 0)
    settings.inputOffsetMilliseconds = -500
    XCTAssertEqual(settings.inputOffsetSeconds, -0.25)
    let decoded = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data(#"{"inputOffsetMilliseconds":900}"#.utf8))
    XCTAssertEqual(decoded.inputOffsetMilliseconds, 250)
  }

  @MainActor
  func testFallbackCalibrationShiftsInputsNotMusicAndSnapshotsEachPlay() throws {
    let model = try gameplayModel()
    let original = model.settings
    defer { model.stop(); model.settings = original }
    for offset in [-200.0, 200] {
      model.settings.inputOffsetMilliseconds = offset
      model.start()
      model.settings.inputOffsetMilliseconds = 0 // Applies only next play.
      XCTAssertEqual(model.playInputOffset, offset / 1000)
      model.update(mediaTime: 0.95 + offset / 1000)
      XCTAssertEqual(model.currentTime, 1 + offset / 1000, accuracy: 1e-12)
      model.press(lane: 0)
      model.release(lane: 0)
      model.update(mediaTime: 1.95 + offset / 1000)
      model.slide(lane: 1)
      model.release(lane: 1)
      model.update(mediaTime: 3.95 + offset / 1000)
      model.press(lane: 3)
      model.update(mediaTime: 4.95 + offset / 1000)
      model.release(lane: 3)
      XCTAssertEqual(model.judgements[.perfect], 4)
      let hits = model.noteTimings.filter { $0.accuracy != nil }
      XCTAssertEqual(hits.count, 4)
      XCTAssertTrue(hits.allSatisfy { abs($0.accuracy ?? 1) < 1e-12 })
      XCTAssertEqual(model.modifiedOptions.last?.value,
        String(format: "%+.0f ms", offset))
      model.stop()
    }
    model.settings.inputOffsetMilliseconds = 0
    model.start()
    XCTAssertEqual(model.playInputOffset, 0)
    XCTAssertTrue(model.modifiedOptions.isEmpty)
  }

  @MainActor
  func testTimingDiagnosticsSnapshotSettingAndIsolateRestarts() throws {
    let model = try gameplayModel()
    let original = model.settings
    defer { model.stop(); model.settings = original }
    model.settings.recordTimingDiagnostics = false
    model.start()
    XCTAssertNil(model.timingRecorder)
    model.settings.recordTimingDiagnostics = true
    XCTAssertNil(model.timingRecorder, "Setting applies to the next play")
    model.restart()
    let first = try XCTUnwrap(model.timingRecorder)
    first.record(.runtime, seconds: 0.001)
    model.restart()
    let second = try XCTUnwrap(model.timingRecorder)
    XCTAssertFalse(first === second)
    XCTAssertTrue(second.snapshot().metrics.isEmpty)
    XCTAssertNil(model.playbackTiming)
    model.settings.recordTimingDiagnostics = false
    XCTAssertTrue(model.timingRecorder === second)
    model.restart()
    XCTAssertNil(model.timingRecorder)
  }

  @MainActor
  func testGameplayCompletesAndSavesAfterAudioEnds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let model = try gameplayModel(resultStore: store)
    let original = model.settings
    defer { model.stop(); model.settings = original }
    model.settings.recordTimingDiagnostics = true
    model.start()
    let recorder = try XCTUnwrap(model.timingRecorder)
    recorder.record(.runtime, seconds: 0.004)
    model.update(mediaTime: 0.95)
    model.press(lane: 0)
    model.release(lane: 0)
    model.playbackEnded(uptime: 100)
    model.advanceAfterAudioEnd(uptime: 106)

    XCTAssertEqual(model.phase, .finished)
    XCTAssertEqual(model.score, 200_000)
    XCTAssertEqual(model.judgements[.miss], 4)
    await model.resultSaveTask?.value
    let results = try await store.results(
      for: "https://example.com\u{0}gameplay"
    )
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.score, 200_000)
    XCTAssertEqual(results.first?.miss, 4)
    XCTAssertEqual(results.first?.playbackTiming, model.playbackTiming)
    XCTAssertEqual(model.playbackTiming?.metrics[
      PlaybackTimingMetric.runtime.rawValue]?.count, 1)
    recorder.record(.runtime, seconds: 0.008)
    XCTAssertEqual(model.playbackTiming?.metrics[
      PlaybackTimingMetric.runtime.rawValue]?.count, 1,
      "Late callbacks must not mutate the frozen result")
    let savedTimings = try await store.noteTimings(for: XCTUnwrap(results.first))
    XCTAssertEqual(savedTimings?.count, 5)
    XCTAssertEqual(savedTimings?.filter {
      $0.judgement == .miss && $0.accuracy == nil
    }.count, 4)
    model.advanceAfterAudioEnd(uptime: 200)
    XCTAssertEqual(model.judgements[.miss], 4)
  }

  @MainActor
  func testGameplayWaitsForMusicAfterLastNote() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try gameplayModel(resultStore: ResultStore(rootURL: root))
    model.start()
    model.update(mediaTime: 10)
    XCTAssertEqual(model.phase, .playing)
    XCTAssertNil(model.resultSaveTask)
    model.playbackEnded(uptime: 100)
    XCTAssertEqual(model.phase, .finished)
    await model.resultSaveTask?.value
    model.restart()
    model.update(mediaTime: 10)
    XCTAssertEqual(model.phase, .playing)
    model.stop()
    XCTAssertEqual(model.phase, .ready)
  }

  @MainActor
  func testRestartClearsJudgementsTouchesAndAudioTail() throws {
    let model = try gameplayModel()
    model.start()
    model.update(mediaTime: 4.05)
    model.press(lane: 3)
    XCTAssertFalse(model.activeHoldIDs.isEmpty)
    model.playbackEnded(uptime: 100)
    let generation = model.playbackGeneration
    model.restart()
    defer { model.stop() }
    XCTAssertEqual(model.phase, .playing)
    XCTAssertGreaterThan(model.playbackGeneration, generation)
    XCTAssertEqual(model.score, 0)
    XCTAssertEqual(model.combo, 0)
    XCTAssertEqual(model.maxCombo, 0)
    XCTAssertTrue(model.activeHoldIDs.isEmpty)
    XCTAssertTrue(model.hitNoteIDs.isEmpty)
    XCTAssertTrue(model.noteTimings.isEmpty)
    XCTAssertEqual(model.playbackTime, 0.05)
    model.advanceAfterAudioEnd(uptime: 200)
    XCTAssertEqual(model.phase, .playing, "An old audio tail cannot finish a restart")
    model.release(lane: 3)
    XCTAssertEqual(model.judgements[.miss], 0)
    XCTAssertNil(model.resultSaveTask)
  }

  @MainActor
  func testEarlyHoldReleaseAndCancelledPlayback() throws {
    let model = try gameplayModel()
    model.start()
    model.update(mediaTime: 4.05)
    model.press(lane: 3)
    model.release(lane: 3)
    XCTAssertEqual(model.judgements[.miss], 4)
    model.update(mediaTime: 5.5)
    XCTAssertEqual(model.judgements[.miss], 4)
    model.stop()
    XCTAssertEqual(model.phase, .ready)
    model.update(mediaTime: 100)
    XCTAssertNil(model.resultSaveTask)
  }

  @MainActor
  private func gameplayModel(
    resultStore: ResultStore = ResultStore(), engine: EnginePlayData? = nil,
    presentation: RuntimePresentation? = nil
  ) throws -> GameplayModel {
    let engine = try engine ?? JSONDecoder().decode(
      EnginePlayData.self,
      from: Data(#"""
        {"skin":{"sprites":[]},"effect":{"clips":[]},
         "particle":{"effects":[]},"archetypes":[],"nodes":[],
         "buckets":[]}
        """#.utf8)
    )
    let data = LevelData(bgmOffset: -0.05, entities: [
      entity("TapNote", values: ["#BEAT": 1, "lane": 0]),
      entity("SwingNote", values: ["#BEAT": 2, "lane": 1]),
      entity("TapNote", values: ["#BEAT": 3, "lane": 2]),
      entity("TapNote", name: "head", values: ["#BEAT": 4, "lane": 3]),
      entity("HoldNote", name: "tail", values: ["#BEAT": 5]),
      LevelEntity(archetype: "HoldConnector", name: nil, data: [
        LevelEntityData(name: "head", value: nil, ref: "head"),
        LevelEntityData(name: "tail", value: nil, ref: "tail")
      ])
    ])
    let server = ServerDescriptor(
      id: "example", name: "Example",
      baseURL: URL(string: "https://example.com")!
    )
    let resource = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(
      name: "gameplay", source: nil, version: 1, rating: 1,
      title: LocalizedText("Gameplay"), artists: LocalizedText("Artist"),
      author: "Test", tags: [SonolusTag(title: "#EASY")],
      cover: resource, bgm: resource, data: resource
    )
    let model = GameplayModel(resultStore: resultStore)
    model.prepare(
      bundle: RuntimeBundle(
        engine: engine, level: data,
        bgmURL: URL(fileURLWithPath: "/nonexistent-test-audio.wav"),
        isOffline: true, presentation: presentation
      ),
      level: level, server: server, title: "Gameplay"
    )
    return model
  }

  private func entity(
    _ archetype: String,
    name: String? = nil,
    values: [String: Double]
  ) -> LevelEntity {
    LevelEntity(
      archetype: archetype,
      name: name,
      data: values.map {
        LevelEntityData(name: $0.key, value: $0.value, ref: nil)
      }
    )
  }
}
