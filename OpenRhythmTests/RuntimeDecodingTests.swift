import XCTest
import UIKit
import Metal
import SwiftUI
import AVFoundation
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

  func testShakeItHard18WithStationaryContactFrames() async throws {
    try await checkChart(engineFolder: "sekai", chart: "shake-it.gz",
      repeatedContacts: true, pooledContacts: true)
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

  // The community `cgss` engine (Cinderella Girls Starlight Stage). Its
  // fixtures are optional within an installed fixture root, so devices set up
  // before it was added keep passing.
  func testCGSSDebutLifecycleAndRestart() async throws {
    try await checkCGSSChart("debut.gz")
  }

  func testCGSSMasterPlusLifecycleAndRestart() async throws {
    try await checkCGSSChart("masterp.gz")
  }

  func testCGSSWitchLifecycleAndRestart() async throws {
    try await checkCGSSChart("witch.gz")
  }

  private func checkCGSSChart(_ chart: String) async throws {
    let folder = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures/cgss")
    guard FileManager.default.fileExists(atPath: folder.path) else {
      throw XCTSkip("Optional cached CGSS fixtures are not installed.")
    }
    try await checkChart(engineFolder: "cgss", chart: "cgss/\(chart)")
  }

  func testNanaonStageTouchesWriteSignedStreamAcrossRestart() throws {
    let root = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures/nanaon")
    guard FileManager.default.fileExists(atPath: root.path) else {
      throw XCTSkip("Optional cached chart fixtures are not installed.")
    }
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: Data(contentsOf: root.appendingPathComponent("level.gz")))
    let resources = try Dictionary(uniqueKeysWithValues:
      ["configuration", "skinData", "skinTexture", "particleData",
        "particleTexture"].map {
        ($0, try Data(contentsOf: root.appendingPathComponent($0)))
      })
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: RuntimePresentation(resources: resources))
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: assets.configuration.options.map(\.def), aspectRatio: 1.8,
      skinSpriteIDs: Set(assets.skin.keys),
      effectClipIDs: Set(engine.effect.clips.map(\.id)),
      particleEffectIDs: Set(assets.particles.keys))
    for _ in 0..<2 {
      runtime.restart()
      try runtime.update(at: 0)
      XCTAssertEqual(try runtime.host.call(function: "StreamHas",
        arguments: [-9999, 1.0 / 60]), 0)
      let point = EnginePoint(x: 0, y: -0.75)
      let touch = EngineTouch(id: 1, started: true, ended: false,
        time: 1.0 / 60, startTime: 1.0 / 60, position: point,
        startPosition: point, delta: EnginePoint(x: 0, y: 0))
      try runtime.update(at: 1.0 / 60, touches: [touch])
      XCTAssertEqual(try runtime.host.call(function: "StreamHas",
        arguments: [-9999, 1.0 / 60]), 1,
        "22/7's stage contact callback writes the signed stream ID -9999")
      XCTAssertFalse(runtime.host.draws.isEmpty)
    }
  }

  func testSekaiStartupSkipsUnchangedStageUntilFirstVisibleNotes() async throws {
    let cache = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures")
    guard FileManager.default.fileExists(atPath: cache.path) else {
      throw XCTSkip("Optional cached chart fixtures are not installed.")
    }
    let root = cache.appendingPathComponent("sekai")
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    var resources = [String: Data]()
    for key in ["configuration", "skinData", "skinTexture", "particleData",
      "particleTexture", "effectData", "effectAudio"] {
      resources[key] = try Data(contentsOf: root.appendingPathComponent(key))
    }
    let rom = try Data(contentsOf: root.appendingPathComponent("rom.bin"))
    // Cached charts/engine, but generated audio: a known silent lead-in ends
    // at chart zero. This isolates the actual GameplayModel startup path from
    // codec/acoustic timing and requires no downloaded BGM or server request.
    for (chart, expectedSkip) in [("eleventh.gz", 7.716666667),
      ("hikari.gz", 7.016666667), ("shake-it.gz", 8.4)] {
      let level = try CompressedJSONDecoder.decode(LevelData.self,
        from: Data(contentsOf: cache.appendingPathComponent(chart)))
      let music = FileManager.default.temporaryDirectory
        .appendingPathComponent("cached-startup-\(UUID()).caf")
      defer { try? FileManager.default.removeItem(at: music) }
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000,
        channels: 1))
      let onset = Int(ceil(level.bgmOffset * 8000))
      XCTAssertTrue((1...240000).contains(onset))
      guard (1...240000).contains(onset) else { return }
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: AVAudioFrameCount(onset + 8000)))
      buffer.frameLength = buffer.frameCapacity
      for frame in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][frame] = frame < onset ? 0 : 0.1
      }
      do {
        let file = try AVAudioFile(forWriting: music, settings: format.settings)
        try file.write(from: buffer)
      }
      let empty = ResourceLocator(hash: nil, url: nil)
      let item = SonolusLevelItem(name: chart, source: nil, version: 1, rating: 1,
        title: LocalizedText(chart), artists: LocalizedText("Fixture"),
        author: "Fixture", tags: [], cover: empty, bgm: empty, data: empty)
      let model = GameplayModel()
      model.prepare(bundle: RuntimeBundle(engine: engine, level: level,
        bgmURL: music, isOffline: true,
        presentation: RuntimePresentation(resources: resources), engineROM: rom),
        level: item, server: ServerDescriptor(id: UUID().uuidString,
          name: "Cached startup", baseURL: URL(string: "https://fixture.example")!
            .appendingPathComponent(UUID().uuidString)),
        title: chart)
      defer { model.stop() }
      for _ in 0..<2 {
        model.start()
        for _ in 0..<3000 {
          model.engineFrame(size: CGSize(width: 1800, height: 1000), touches: [])
          if !model.isStartingPlayback { break }
          try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(model.isStartingPlayback, chart)
        XCTAssertEqual(model.skippedIntroDuration, expectedSkip,
          accuracy: 1.0 / 60 + 1e-6, chart)
        let runtime = try XCTUnwrap(model.engineRuntime)
        XCTAssertEqual(runtime.resolvedInputCount, 0, "No input may be skipped")
        XCTAssertTrue(runtime.host.draws.contains(where: \.isInputVisual),
          "Start with the first note visible, not with the stage alone")
        model.stop(deactivateAudio: false)
      }
    }
  }

  func testSekaiFlickRequiresMeasuredMovementAndSurvivesRestart() async throws {
    let cache = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures")
    guard FileManager.default.fileExists(atPath: cache.path) else {
      throw XCTSkip("Optional cached chart fixtures are not installed.")
    }
    let root = cache.appendingPathComponent("sekai")
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: Data(contentsOf: cache.appendingPathComponent("eleventh.gz")))
    var resources = [String: Data]()
    for key in ["configuration", "skinData", "skinTexture", "particleData",
      "particleTexture", "effectData", "effectAudio"] {
      resources[key] = try Data(contentsOf: root.appendingPathComponent(key))
    }
    let presentation = RuntimePresentation(resources: resources)
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine, presentation: presentation)
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: assets.configuration.options.map(\.def), aspectRatio: 1.8,
      skinSpriteIDs: Set(assets.skin.keys), effectClipIDs: audio.clipIDs,
      particleEffectIDs: Set(assets.particles.keys),
      rom: Data(contentsOf: root.appendingPathComponent("rom.bin")))
    let index = try XCTUnwrap(level.entities.firstIndex {
      $0.archetype == "NormalFlickNote"
    })
    let beat = try XCTUnwrap(level.entities[index].data.first {
      $0.name == "#BEAT"
    }?.value)
    let target = try runtime.host.call(function: "BeatToTime", arguments: [beat])
    let start = BGMClockMapping(offset: level.bgmOffset).initialChartTime
    let contactFrame = Int(ceil((target - start) * 60))
    XCTAssertTrue((0..<2400).contains(contactFrame), "Keep this probe bounded")
    guard (0..<2400).contains(contactFrame) else { return }
    var movingResults = [Double]()
    // Same engine/chart/window and start time in each run. Only the measured
    // gesture changes. Eight fixture lane positions cover the opening chord;
    // this is neither an autoplay feature nor a physical input measurement.
    for moving in [false, true, true] {
      runtime.restart()
      var pool = EngineTouchPool<Int>()
      var result: EngineJudgment?
      var burstStarted = ProcessInfo.processInfo.systemUptime
      for frame in 0...(contactFrame + 24) {
        let time = start + Double(frame) / 60
        let phase = frame - contactFrame
        if (0...11).contains(phase) {
          for lane in 0..<8 {
            let x = -1.05 + Double(lane) * 0.3
            let y = -0.75 + (moving ? Double(min(phase, 4)) * 0.04 : 0)
            var samples = [EngineTouchSample]()
            if moving && (1...4).contains(phase) {
              samples.append(EngineTouchSample(
                position: EnginePoint(x: x, y: y - 0.02),
                time: time - 1.0 / 120,
                timestamp: 100 + Double(frame) / 60 - 1.0 / 120))
            }
            samples.append(EngineTouchSample(position: EnginePoint(x: x, y: y),
              time: time, timestamp: 100 + Double(frame) / 60))
            pool.receive(key: lane, samples: samples,
              started: phase == 0, ended: phase == 11)
          }
        }
        try runtime.update(at: time, touches: pool.touches)
        if let judgment = runtime.judgments.first(where: { $0.entityIndex == index }) {
          result = judgment
          break
        }
        pool.nextFrame(at: time)
        // Match the existing opt-in harness's bounded CPU bursts if this is
        // later included in the authorized physical validation batch.
        if ProcessInfo.processInfo.systemUptime - burstStarted >= 0.1 {
          #if !targetEnvironment(simulator)
          try await Task.sleep(for: .milliseconds(100))
          #else
          await Task.yield()
          #endif
          burstStarted = ProcessInfo.processInfo.systemUptime
        }
      }
      let judgment = try XCTUnwrap(result, "The selected flick must resolve")
      if moving {
        XCTAssertGreaterThan(judgment.grade, 0, "Measured motion must hit the flick")
        XCTAssertEqual(judgment.accuracy, 1.0 / 60, accuracy: 1e-6)
        movingResults.append(judgment.accuracy)
      } else {
        XCTAssertEqual(judgment.grade, 0, "A stationary press is not a flick")
      }
    }
    XCTAssertEqual(movingResults.count, 2)
    XCTAssertEqual(movingResults.first, movingResults.last)
  }

  private struct Judgment: Equatable {
    let entityIndex: Int
    let grade: Int
    let accuracyBits: UInt64
    let haptic: EngineHaptic
  }

  private struct Frame: Equatable {
    let draws: [EngineDrawCommand]
    let particles: [Int: EngineParticleInstance]
    let audio: [EngineAudioCommand]
    let loops: [EngineLoopCommand]
    let resolved: Int
    let judgments: [Judgment]
    let score: EngineScoreSnapshot?
    let accuracyScore: EngineScoreSnapshot?
    let life: EngineLife
    let presentationBits: [[UInt64]]
    let exports: [Int: [Int: UInt64]]

    init(_ runtime: EnginePlayRuntime) {
      draws = runtime.host.draws
      particles = runtime.host.particles
      audio = runtime.host.takeAudioCommands()
      loops = runtime.host.takeLoopCommands()
      resolved = runtime.resolvedInputCount
      judgments = runtime.judgments.map {
        Judgment(entityIndex: $0.entityIndex, grade: $0.grade,
          accuracyBits: $0.accuracy.bitPattern, haptic: $0.haptic)
      }
      score = runtime.arcadeScore?.snapshot
      accuracyScore = runtime.accuracyScore.snapshot(noteCount: runtime.inputCount)
      life = runtime.life
      // Include engine-owned transforms, background and HUD state; equal draw
      // commands alone do not imply equal visible output. Keep NaN/-0 bits.
      presentationBits = [(1000, 9), (1003, 16), (1004, 16), (1005, 8),
        (1006, 80), (1007, 10), (2004, 12), (2005, 8)].map { block, count in
        (0..<count).map { runtime.memory.value(block: block, index: $0).bitPattern }
      }
      exports = runtime.host.exports.mapValues { $0.mapValues(\.bitPattern) }
    }
  }

  private func checkChart(engineFolder: String, chart: String,
    repeatedContacts: Bool = false, pooledContacts: Bool = false) async throws {
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
    func makeRuntime(dense: Bool) throws -> EnginePlayRuntime {
      try EnginePlayRuntime(engine: engine, level: level,
        options: assets.configuration.options.map(\.def), aspectRatio: 1.8,
        skinSpriteIDs: Set(assets.skin.keys), effectClipIDs: audio.clipIDs,
        particleEffectIDs: Set(assets.particles.keys), rom: rom,
        denseTemporaryMemory: dense)
    }
    let runtime = try makeRuntime(dense: true)
    let sparse = try makeRuntime(dense: false)
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
    var sparseDurations = [Double]()
    var peaks = [String: (weight: Double, time: Double,
      draws: Int, segments: Int, particles: Int, sprites: [EngineRenderSprite])]()
    var lastTime = startTime
    var successfulInputs = 0
    var successfulTypes = [String: Int]()
    var gradeCounts = [Int: Int]()
    var touchPool = EngineTouchPool<Int>()
    var stationaryContactFrames = 0
    var stationarySuccessfulTypes = [String: Int]()
    // A deterministic load case, not an autoplay implementation or a captured
    // physical play. Eight contacts exercise touch callbacks, holds and hit
    // effects; every contact ends before its next ID is introduced.
    func contacts(_ frame: Int, _ time: Double) -> [EngineTouch] {
      guard repeatedContacts else { return [] }
      let phase = frame % 12
      if pooledContacts {
        // Deliver only begin/end events, as UIKit does for a stationary hold.
        // Still expose every held contact during the intervening update frames.
        if phase == 0 || phase == 11 {
          for lane in 0..<8 {
            touchPool.receive(key: lane,
              position: EnginePoint(x: -1.05 + Double(lane) * 0.3, y: -0.75),
              time: time, started: phase == 0, ended: phase == 11)
          }
        }
        return touchPool.touches
      }
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
      let stationary = pooledContacts && !touches.isEmpty
        && frame % 12 != 0 && frame % 12 != 11
      if stationary { stationaryContactFrames += 1 }
      var runtimeDuration = 0.0
      func updateDense() throws {
        let started = ProcessInfo.processInfo.systemUptime
        try runtime.update(at: lastTime, touches: touches)
        runtimeDuration = ProcessInfo.processInfo.systemUptime - started
      }
      func updateSparse() throws {
        let started = ProcessInfo.processInfo.systemUptime
        try sparse.update(at: lastTime, touches: touches)
        sparseDurations.append(ProcessInfo.processInfo.systemUptime - started)
      }
      // Alternate order to reduce systematic warm-cache/order bias. Timers
      // exclude comparisons, presentation work and the other runtime's update.
      if frame.isMultiple(of: 2) {
        try updateSparse()
        try updateDense()
      } else {
        try updateDense()
        try updateSparse()
      }
      let renderStarted = ProcessInfo.processInfo.systemUptime
      let sprites = EngineRenderer.sprites(host: runtime.host, assets: assets)
      let spriteDuration = ProcessInfo.processInfo.systemUptime - renderStarted
      durations.append(runtimeDuration + spriteDuration)
      runtimeDurations.append(runtimeDuration)
      spriteDurations.append(spriteDuration)
      let segments = runtime.host.draws.reduce(0) { $0 + ($1.curve?.segments ?? 0) }
      for (name, weight) in [("runtime", runtimeDuration),
        ("sprites", spriteDuration), ("draws", Double(runtime.host.draws.count)),
        ("curves", Double(segments)), ("particles", Double(runtime.host.particles.count))] {
        if weight > peaks[name]?.weight ?? -1 {
          peaks[name] = (weight, lastTime, runtime.host.draws.count, segments,
            runtime.host.particles.count, sprites)
        }
      }
      for input in runtime.judgments {
        gradeCounts[input.grade, default: 0] += 1
        if input.grade > 0 {
          successfulInputs += 1
          if level.entities.indices.contains(input.entityIndex) {
            let type = level.entities[input.entityIndex].archetype
            successfulTypes[type, default: 0] += 1
            if stationary { stationarySuccessfulTypes[type, default: 0] += 1 }
          }
        }
        XCTAssertTrue(seen.insert(input.entityIndex).inserted,
          "Duplicate input resolution in \(chart): \(input.entityIndex)")
      }
      let snapshot = Frame(runtime)
      XCTAssertEqual(snapshot, Frame(sparse), "\(chart), frame \(frame)")
      if firstResolutionFrame == nil, !runtime.judgments.isEmpty {
        firstResolutionFrame = frame
      }
      if frame == 0 || firstResolutionFrame.map({ frame < $0 + 120 }) == true {
        opening.append((frame, snapshot))
      }
      touchPool.nextFrame(at: lastTime)
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
    if pooledContacts {
      XCTAssertGreaterThan(stationaryContactFrames, 0)
      XCTAssertGreaterThan(stationarySuccessfulTypes["NormalTickNote", default: 0],
        0, "Held contacts must still resolve hold ticks without new events")
    }
    runtime.restart()
    sparse.restart()
    touchPool = EngineTouchPool<Int>()
    var sample = 0
    for frame in 0...opening.last!.index {
      let time = startTime + Double(frame) / 60
      let touches = contacts(frame, time)
      try runtime.update(at: time, touches: touches)
      let actual = Frame(runtime)
      try sparse.update(at: time, touches: touches)
      XCTAssertEqual(actual, Frame(sparse), "\(chart), restart frame \(frame)")
      touchPool.nextFrame(at: time)
      try await yieldToDevice()
      guard frame == opening[sample].index else { continue }
      let expected = opening[sample].snapshot
      XCTAssertEqual(actual, expected, chart)
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
    print("GRADES \(chart): \(gradeCounts.sorted { $0.key < $1.key })")
    print("Pooled contacts: \(pooledContacts); "
      + "\(stationaryContactFrames) stationary frames.")
    if repeatedContacts { print("SUCCESSFUL INPUT TYPES: \(successfulTypes)") }
    for (name, values) in [("runtime", runtimeDurations), ("sprites", spriteDurations)] {
      let sorted = values.sorted()
      print("CPU PHASE \(chart) \(name): mean "
        + "\(values.reduce(0, +) * 1000 / Double(values.count)) ms, "
        + "p95 \(sorted[Int(Double(sorted.count) * 0.95)] * 1000) ms")
    }
    for (name, values) in [("sparse", sparseDurations),
      ("dense", runtimeDurations)] {
      let sorted = values.sorted()
      print("TEMPORARY MEMORY \(chart) contacts=\(repeatedContacts) \(name): "
        + "\(values.count) updates, mean "
        + "\(values.reduce(0, +) * 1000 / Double(values.count)) ms, "
        + "p95 \(sorted[Int(Double(sorted.count) * 0.95)] * 1000) ms, "
        + "p99 \(sorted[Int(Double(sorted.count) * 0.99)] * 1000) ms; "
        + "paired Debug CPU timings, not live FPS.")
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
  func testEngineResourceIDsPreserveNumericIdentity() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"name":"#STAGE_MIDDLE","id":0.5}]},
       "effect":{"clips":[{"name":"clip","id":-9999.5}]},
       "particle":{"effects":[{"name":"effect","id":1e100}]},
       "buckets":[{"sprites":[{"id":0.5,"x":0,"y":0,
         "w":1,"h":1,"rotation":0}]}],"archetypes":[],"nodes":[]}
      """#.utf8))
    XCTAssertEqual(Double(engine.skin.sprites[0].id), 0.5)
    XCTAssertEqual(Double(engine.effect.clips[0].id), -9999.5)
    XCTAssertEqual(Double(engine.particle.effects[0].id), 1e100)
    XCTAssertEqual(Double(engine.buckets[0].sprites[0].id), 0.5)
    XCTAssertEqual(engine.introStageSpriteIDs.map { Double($0) }, [0.5])
    for function in ["HasSkinSprite", "HasEffectClip", "HasParticleEffect"] {
      let host = CommandEngineRuntimeHost(memory: EngineMemory(),
        level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [],
        effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0)
      XCTAssertEqual(try host.call(function: function, arguments: [0.5]), 0)
    }
  }

  @MainActor
  func testFractionalResourceIDsPrepareAndRenderWithoutAliasing() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"name":"a","id":0.5},{"name":"b","id":0.75}]},
       "effect":{"clips":[]},"particle":{"effects":[
         {"name":"a","id":-0.5},{"name":"b","id":-0.75}]},
       "buckets":[],"archetypes":[],"nodes":[]}
      """#.utf8))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let texture = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1),
      format: format).pngData {
        UIColor.red.setFill()
        $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        UIColor.blue.setFill()
        $0.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
      }
    let identity = Dictionary(uniqueKeysWithValues:
      ["x1", "y1", "x2", "y2", "x3", "y3", "x4", "y4"].map { ($0, [$0: 1]) })
    let skin: [String: Any] = ["width": 2, "height": 1, "interpolation": false,
      "sprites": ["a", "b"].enumerated().map { index, name in
        ["name": name, "x": index, "y": 0, "w": 1, "h": 1,
          "transform": identity] as [String: Any]
      }]
    func property(_ value: Double) -> [String: Any] {
      ["from": ["c": value], "to": ["c": value]]
    }
    let particle: [String: Any] = ["width": 2, "height": 1, "interpolation": false,
      "sprites": [["x": 0, "y": 0, "w": 1, "h": 1]],
      "effects": ["a", "b"].enumerated().map { index, name in
        ["name": name, "transform": identity, "groups": [["count": 1,
          "particles": [["sprite": 0, "color": "#fff", "start": 0,
            "duration": 1, "x": property(Double(index) / 2), "y": property(0),
            "w": property(0.1), "h": property(0.1), "r": property(0),
            "a": property(1)]]]]] as [String: Any]
      }]
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8),
        "skinData": try JSONSerialization.data(withJSONObject: skin),
        "skinTexture": texture,
        "particleData": try JSONSerialization.data(withJSONObject: particle),
        "particleTexture": texture]))
    XCTAssertEqual(Set(assets.skin.keys), [0.5, 0.75])
    XCTAssertEqual(Set(assets.particles.keys), [-0.5, -0.75])
    XCTAssertFalse(assets.skin[0.5]?.image === assets.skin[0.75]?.image)
    let host = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: Set(assets.skin.keys),
      effectClipIDs: [], particleEffectIDs: Set(assets.particles.keys), archetypeCount: 0)
    let quad: [Double] = [-1, -1, -1, 1, 1, 1, 1, -1]
    for id in [0.5, 0.75] {
      _ = try host.call(function: "Draw", arguments: [id] + quad + [0, 1])
    }
    for id in [-0.5, -0.75] {
      _ = try host.call(function: "SpawnParticleEffect", arguments: [id] + quad + [1, 0])
    }
    let rendered = EngineRenderer.sprites(host: host, assets: assets)
    XCTAssertEqual(rendered.count, 4)
    XCTAssertTrue(rendered[0].image === assets.skin[0.5]?.image)
    XCTAssertTrue(rendered[1].image === assets.skin[0.75]?.image)
    XCTAssertNotEqual(rendered[2].points, rendered[3].points,
      "Distinct effect definitions must not alias in lookup or endpoint caches")
    func icon(_ id: Double, fallback: Double? = nil,
      rotation: Double = 0) throws -> Data {
      try XCTUnwrap(assets.bucketImage(EngineBucket(sprites: [EngineBucketSprite(
        id: id, fallbackId: fallback, x: 0, y: 0, w: 2, h: 1,
        rotation: rotation)], unit: nil)))
    }
    let primary = try icon(0.5)
    XCTAssertEqual(try icon(100, fallback: 0.5), primary)
    XCTAssertEqual(try icon(0.5, fallback: 0.75), primary,
      "An available primary must win over the fallback")
    XCTAssertNotEqual(try icon(0.75), primary)
    let rotated = try icon(0.5, rotation: 90)
    XCTAssertNotEqual(rotated, primary, "Degree rotation changes rectangular geometry")
    XCTAssertEqual(try icon(0.5, rotation: 450), rotated)
    XCTAssertNil(try assets.bucketImage(EngineBucket(sprites: [EngineBucketSprite(
      id: 100, x: 0, y: 0, w: 2, h: 1, rotation: 0)], unit: nil)))
    let decoded = try XCTUnwrap(UIImage(data: primary)?.cgImage)
    XCTAssertEqual(decoded.width, 128)
    XCTAssertEqual(decoded.height, 128)
  }

  func testTemporaryMemoryEpochWrapAndCopyOnWrite() {
    var storage = EngineTemporaryMemory(generation: .max - 1)
    storage[0] = 42
    storage[4095] = -0.0
    let prepared = storage
    storage.clear()
    XCTAssertEqual(storage[0], 0)
    XCTAssertEqual(storage[4095].bitPattern, Double(0).bitPattern)
    storage[17] = 8
    storage.clear() // Wrap must not resurrect either generation's writes.
    XCTAssertEqual(storage[0], 0)
    XCTAssertEqual(storage[17], 0)
    storage[0] = 99
    XCTAssertEqual(prepared[0], 42)
    XCTAssertEqual(prepared[4095].bitPattern, (-0.0 as Double).bitPattern)
    storage = prepared
    XCTAssertEqual(storage[0], 42)
    storage.clear()
    XCTAssertEqual(storage[0], 0)
  }

  func testDenseTemporaryMemoryMatchesSparseBoundsCallbacksAndRestore() throws {
    for dense in [false, true] {
      let memory = EngineMemory(denseTemporaryMemory: dense)
      let samples: [Double] = [0, -0.0, 3.5, .infinity, -.infinity,
        Double(bitPattern: 0x7ff8000000000042)]
      let addresses = [0, 1, 17, 4095, 4096, Int.max]
      // Standalone memory retains its sparse, unbounded test/host semantics.
      for (index, value) in zip(addresses, samples) {
        memory.set(block: 10000, index: index, value: value)
        XCTAssertEqual(memory.value(block: 10000, index: index).bitPattern,
          value.bitPattern)
      }
      let unbounded = memory.makeRestorePoint()
      try memory.configurePlayBlocks(entityCount: 1, optionCount: 0,
        bucketCount: 0, archetypeCount: 1)
      XCTAssertEqual(memory.value(block: 10000, index: 4096), 0)
      let bounded = memory.makeRestorePoint()
      memory.selectEntity(key: 0, index: 0)
      for callback in EngineMemory.Callback.allCases {
        memory.callback = callback
        for index in [0, 17, 4095] {
          XCTAssertEqual(try memory.read(block: 10000, index: index), 0)
          XCTAssertEqual(try memory.write(block: 10000, index: index,
            value: 37), 37)
          XCTAssertEqual(try memory.read(block: 10000, index: index), 37)
        }
        for index in [-1, 4096, Int.max] {
          XCTAssertEqual(try memory.write(block: 10000, index: index,
            value: 88), 88)
          XCTAssertEqual(try memory.read(block: 10000, index: index), 0)
        }
        // Even a new callback on the same entity gets fresh scratch space.
        memory.selectEntity(key: 0, index: 0)
      }
      memory.selectEntity(key: 1, index: nil) // Spawned entities have scratch too.
      XCTAssertEqual(try memory.write(block: 10000, index: 4095, value: 7), 7)
      XCTAssertEqual(try memory.read(block: 10000, index: 4095), 7)
      for restore in [unbounded, bounded, unbounded] {
        restore()
        XCTAssertEqual(memory.value(block: 10000, index: 17), 3.5)
        XCTAssertEqual(memory.value(block: 10000, index: 4095), .infinity)
        memory.set(block: 10000, index: 17, value: 77)
        memory.selectEntity(key: 0, index: 0)
        XCTAssertEqual(memory.value(block: 10000, index: 17), 0)
      }
      unbounded()
      XCTAssertEqual(memory.value(block: 10000, index: Int.max).bitPattern,
        samples.last!.bitPattern)
      bounded()
      XCTAssertEqual(memory.value(block: 10000, index: Int.max), 0)
    }
  }

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

  func testStandardEngineTextResolvesAcrossSettingsAndSavedOverrides() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"optionCategories":[{"name":"stage","title":"#STAGE_ALPHA"}],
       "options":[
       {"name":"mode","title":"#JUDGMENT_STRICT","category":"stage",
        "type":"select","def":0,"standard":true,
        "values":["#OFF","#JUDGELINE","Custom label"]},
       {"name":"#MIRROR","category":"stage","type":"toggle",
        "def":0,"standard":true}]}
      """#.utf8))
    XCTAssertNoThrow(try config.validateOptions())
    XCTAssertEqual(config.options[0].displayName, "Strict Judgment")
    XCTAssertEqual(config.options[0].valueLabel(1), "Judgment Line")
    XCTAssertEqual(config.options[0].valueLabel(2), "Custom label")
    XCTAssertEqual(config.optionGroups.first?.title, "Stage Transparency")
    let settings = GameplayPreferences(engineOptions: ["mode": 1, "#MIRROR": 1])
    XCTAssertEqual(config.runtimeOptions(preferences: settings), [1, 1])
    XCTAssertEqual(config.modifiedStandardOptions(preferences: settings), [
      EngineOptionOverride(name: "Strict Judgment", value: "Judgment Line"),
      EngineOptionOverride(name: "Mirror Level", value: "On")])
    XCTAssertEqual(EngineConfiguration.Option.label("literal_Aa"), "literal_Aa")
    XCTAssertEqual(EngineConfiguration.Option.label("#NEW_FUTURE_LABEL"),
      "New Future Label")
    XCTAssertEqual(EngineConfiguration.Option.label("#NOTE_EFFECT_ALPHA"),
      "Note Effect Transparency")
  }

  func testEngineOptionTimeUnitsFormatWithoutChangingRuntimeValues() throws {
    let units = [
      ("#YEAR_UNIT", "yr"), ("#MONTH_UNIT", "mo"), ("#DAY_UNIT", "d"),
      ("#HOUR_UNIT", "h"), ("#MINUTE_UNIT", "m"), ("#SECOND_UNIT", "s"),
      ("#MILLISECOND_UNIT", "ms"), ("samples", " samples"),
      ("#FUTURE_UNIT", " Future Unit"), ("", "")
    ]
    for (unit, suffix) in units {
      let config = try JSONDecoder().decode(EngineConfiguration.self,
        from: JSONSerialization.data(withJSONObject: ["options": [[
          "name": "Offset", "type": "slider", "def": -20, "standard": true,
          "min": -100, "max": 100, "step": 0.25, "unit": unit
        ]]]))
      let option = config.options[0]
      for value in [-20.0, 0, 1.25] {
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        XCTAssertEqual(option.valueLabel(value), number + suffix, unit)
      }
      XCTAssertEqual(config.runtimeOptions(preferences: GameplayPreferences()),
        [-20], "Units are presentation only, never a timing conversion")
      XCTAssertEqual(config.modifiedStandardOptions(preferences:
        GameplayPreferences(engineOptions: ["Offset": 1.25])), [
          EngineOptionOverride(name: "Offset", value: option.valueLabel(1.25))
        ])
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
      EngineOptionOverride(name: "Mirror Level", value: "On"),
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

  func testEngineOptionCategoriesPreserveRuntimeOrderAndDedicatedPreferences() throws {
    let config = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"optionCategories":[{"name":"display","title":"#DISPLAY"},
      {"name":"play","title":"Play Options"},{"name":"empty","title":"Unused"}],
      "options":[
      {"name":"#NOTE_SPEED","category":"play","type":"slider","def":5,
       "min":1,"max":12,"step":0.1},
      {"name":"Score Mode","category":"display","type":"select","def":0,
       "values":["Flat","Combo"]},
      {"name":"#MIRROR","category":"play","type":"toggle","def":0},
      {"name":"Future","category":"display","type":"future","def":7}]}
      """#.utf8))
    XCTAssertNoThrow(try config.validateOptions())
    XCTAssertEqual(config.optionGroups.map(\.id), ["display", "play"])
    XCTAssertEqual(config.optionGroups.map(\.title), ["Display", "Play Options"])
    XCTAssertEqual(config.optionGroups.map(\.optionIndices), [[1,3], [0,2]])
    var settings = GameplayPreferences(engineOptions: ["#NOTE_SPEED": 3,
      "Score Mode": 1, "Future": 99])
    XCTAssertEqual(config.runtimeOptions(preferences: settings), [3,1,0,7])
    config.options[0].setPreferredValue(9, in: &settings)
    config.options[1].setPreferredValue(0, in: &settings)
    config.options[2].setPreferredValue(1, in: &settings)
    XCTAssertEqual(settings.noteSpeed, 9)
    XCTAssertEqual(settings.scoreMode, 0)
    XCTAssertEqual(settings.engineOptions["#MIRROR"], 1)
    let restored = try JSONDecoder().decode(GameplayPreferences.self,
      from: JSONEncoder().encode(settings))
    XCTAssertEqual(config.runtimeOptions(preferences: restored), [9,0,1,7],
      "Category presentation must not reorder Level Option memory")
    for option in config.options { option.setPreferredValue(nil, in: &settings) }
    XCTAssertNil(settings.noteSpeed)
    XCTAssertNil(settings.scoreMode)
    XCTAssertTrue(settings.engineOptions.isEmpty,
      "Reset must also clear legacy generic overrides of dedicated controls")
    XCTAssertEqual(config.runtimeOptions(preferences: settings), [5,0,0,7])
    var legacy = config
    legacy.optionCategories = nil
    XCTAssertNoThrow(try legacy.validateOptions())
    XCTAssertEqual(legacy.optionGroups.map(\.optionIndices), [[2],[3]],
      "Without categories, dedicated controls stay in their existing sections")
    XCTAssertEqual(legacy.runtimeOptions(preferences: restored), [9,0,1,7])
  }

  func testMalformedOptionCategoriesFailBeforeControlsCanDisappear() throws {
    let category = ["name": "play", "title": "Play"]
    let valid: [String: Any] = ["name": "Mirror", "category": "play",
      "type": "toggle", "def": 0]
    for categories in [[category], [], [category, category]] {
      for value: Any in ["play", "missing", NSNull()] {
        var option = valid
        option["category"] = value
        let config = try JSONDecoder().decode(EngineConfiguration.self,
          from: JSONSerialization.data(withJSONObject: [
            "optionCategories": categories, "options": [option]]))
        if categories.count == 1, value as? String == "play" {
          XCTAssertNoThrow(try config.validateOptions())
        } else {
          XCTAssertThrowsError(try config.validateOptions()) { error in
            XCTAssertTrue(error.localizedDescription.contains("category"))
          }
        }
      }
    }
    let missing = try JSONDecoder().decode(EngineConfiguration.self, from: Data(#"""
      {"optionCategories":[{"name":"play","title":"Play"}],
       "options":[{"name":"Mirror","type":"toggle","def":0}]}
      """#.utf8))
    XCTAssertThrowsError(try missing.validateOptions())
    let empty = try JSONDecoder().decode(EngineConfiguration.self,
      from: Data(#"{"optionCategories":[],"options":[]}"#.utf8))
    XCTAssertNoThrow(try empty.validateOptions())
    XCTAssertTrue(empty.optionGroups.isEmpty)
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
    func assertError(_ arguments: [Double], limit: Int = 1_000_000,
      _ expected: String) {
      XCTAssertThrowsError(try evaluate("Copy", arguments, limit: limit)) {
        XCTAssertEqual($0.localizedDescription, expected)
      }
    }
    let budget = EngineInterpreterError.operationLimitExceeded
    let invalid = EngineInterpreterError.invalidArguments("Copy")
    assertError([2000, 0, 2001, 0, 100], limit: 20, budget.localizedDescription)
    // Malformed arguments are not a budget overrun.
    assertError([2000, 0, 2001, 0, -1], invalid.localizedDescription)
    assertError([2000, -1, 2001, 0, 1], invalid.localizedDescription)
    assertError([2000, 0, 2001, 0x1p62, 0x1p62], invalid.localizedDescription)
    XCTAssertEqual(try evaluate("GetPointed", [2000, .infinity, 0]), 0)
  }

  func testPlayMemoryCallbackAccessMatrix() throws {
    // Independent transcription of the public play-block access tables.
    let prepareOnly = [1000, 1006, 1007, 2001, 2003, 2004, 2005, 4001,
      4006, 4007, 4101, 4106, 4107, 5000, 5001]
    let sequential = [1003, 1004, 1005, 2000, 4002, 4102]
    let always = [4000, 4004, 4005, 10000]
    let readOnly = [1001, 1002, 2002, 3000, 4003, 4103]
    for phase in EngineMemory.Callback.allCases {
      let memory = EngineMemory()
      memory.selectEntity(key: 2, index: 2)
      memory.callback = phase
      let allowed = Set(always
        + (phase == .preprocess ? prepareOnly : [])
        + ([.preprocess, .updateSequential, .touch].contains(phase)
          ? sequential : []))
      for block in prepareOnly + sequential + always + readOnly {
        XCTAssertNoThrow(try memory.read(block: block, index: 0))
        if allowed.contains(block) {
          XCTAssertEqual(try memory.write(block: block, index: 0, value: 3), 3)
          XCTAssertEqual(try memory.read(block: block, index: 0), 3)
        } else {
          XCTAssertThrowsError(try memory.write(block: block, index: 0, value: 3),
            "\(phase) must not write \(block)")
          XCTAssertEqual(memory.value(block: block, index: 0), 0)
        }
      }
      XCTAssertEqual(try memory.read(block: 9999, index: 0), 0)
      XCTAssertThrowsError(try memory.write(block: 9999, index: 0, value: 1))
    }
  }

  func testPlayBlockBoundsDoNotCreateExtraStorage() throws {
    let memory = EngineMemory()
    try memory.configurePlayBlocks(entityCount: 3, optionCount: 2,
      bucketCount: 4, archetypeCount: 5)
    memory.selectEntity(key: 2, index: 2)
    let counts = [1000: 9, 1001: 5, 1003: 16, 1004: 16, 1005: 8,
      1006: 80, 1007: 10, 2000: 4096, 2001: 4096, 2002: 2, 2003: 24,
      2004: 12, 2005: 8, 4000: 64, 4001: 32, 4002: 32, 4003: 3,
      4004: 1, 4005: 5, 4006: 1, 4007: 4,
      4101: 96, 4102: 96, 4103: 9, 4106: 3, 4107: 12,
      5000: 20, 5001: 5, 10000: 4096]
    for (block, count) in counts {
      // Seed through the host path, including otherwise read-only blocks.
      memory.set(block: block, index: count - 1, value: 37)
      memory.set(block: block, index: count, value: 99)
      memory.set(block: block, index: -1, value: 99)
      memory.set(block: block, index: Int.max, value: 99)
      XCTAssertEqual(memory.value(block: block, index: count - 1), 37)
      XCTAssertEqual(memory.value(block: block, index: count), 0, "\(block)")
      XCTAssertEqual(memory.value(block: block, index: -1), 0)
      XCTAssertEqual(memory.value(block: block, index: Int.max), 0)
    }
    memory.set(block: 9999, index: 0, value: 99)
    XCTAssertEqual(memory.value(block: 9999, index: 0), 0)
    XCTAssertThrowsError(try memory.configurePlayBlocks(entityCount: -1,
      optionCount: 0, bucketCount: 0, archetypeCount: 0))
    XCTAssertThrowsError(try memory.configurePlayBlocks(entityCount: Int.max,
      optionCount: 0, bucketCount: 0, archetypeCount: 0))
  }

  func testBoundedGetVariantsAndCopyZeroPadMissingAddresses() throws {
    for optimized in [false, true] {
      let memory = EngineMemory()
      try memory.loadROM(Data([0, 0, 128, 63])) // Float32 1
      try memory.configurePlayBlocks(entityCount: 1, optionCount: 0,
        bucketCount: 0, archetypeCount: 1)
      memory.selectEntity(key: 0, index: 0)
      memory.callback = .preprocess
      memory.set(block: 4000, index: 63, value: 12)
      memory.set(block: 4000, index: 0, value: 4000)
      memory.set(block: 4000, index: 1, value: 63)
      let cases: [(String, [Double], Double)] = [
        ("Get", [4000, 63], 12), ("Get", [4000, 64], 0),
        ("Get", [4000, -1], 0), ("Get", [9999, 0], 0),
        ("Get", [3000, 0], 1), ("Get", [3000, 1], 0),
        ("Get", [2002, 0], 0), ("Get", [2003, 0], 0),
        ("GetShifted", [4000, 62, 1, 1], 12),
        ("GetShifted", [4000, 62, 1, 2], 0),
        ("GetPointed", [4000, 0, 0], 12),
        ("GetPointed", [4000, 0, 1], 0),
        ("GetPointed", [9999, 0, 0], 0),
        ("Get", [4000, 1e20], 0), ("Get", [4000, -1e20], 0),
        ("Get", [1e20, 0], 0), ("Get", [4000, .infinity], 0),
        ("GetShifted", [4000, 0, 1e20, 2], 0),
        ("GetPointed", [4000, 1e20, 0], 0),
        ("GetPointed", [4000, 0, 1e20], 0),
        ("Copy", [4000, 63, 2000, 0, 2], 0),
        ("Set", [4000, 64, 99], 99),
        ("Get", [4000, 64], 0)
      ]
      for (name, arguments, expected) in cases {
        let nodes = arguments.map { EngineDataNode(value: $0) } + [
          EngineDataNode(function: name, arguments: Array(arguments.indices))]
        let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
          optimizeLiteralAddresses: optimized)
        XCTAssertEqual(try interpreter.execute(nodeAt: arguments.count), expected,
          "\(name) \(arguments), optimized: \(optimized)")
      }
      XCTAssertEqual(memory.value(block: 2000, index: 0), 12)
      XCTAssertEqual(memory.value(block: 2000, index: 1), 0)
      // A pointer at the final slot has a zero index component past the end.
      memory.set(block: 4000, index: 63, value: 2000)
      XCTAssertEqual(try evaluate("GetPointed", [4000, 63, 0], memory: memory), 12)
      memory.set(block: 4000, index: 63, value: 0)
      XCTAssertEqual(try evaluate("Copy", [2000, 0, 4000, 63, 2], memory: memory), 0)
      XCTAssertEqual(memory.value(block: 4000, index: 63), 12)
      XCTAssertEqual(memory.value(block: 4000, index: 64), 0)
      let nodes = [EngineDataNode(value: 1e20), EngineDataNode(value: 4000),
        EngineDataNode(value: 4), EngineDataNode(value: 8),
        EngineDataNode(function: "Set", arguments: [1, 2, 3]),
        EngineDataNode(function: "Get", arguments: [0, 4]),
        EngineDataNode(function: "GetPointed", arguments: [0, 2, 4])]
      let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
        optimizeLiteralAddresses: optimized)
      for root in [5, 6] {
        memory.set(block: 4000, index: 4, value: 0)
        XCTAssertEqual(try interpreter.execute(nodeAt: root), 0)
        XCTAssertEqual(memory.value(block: 4000, index: 4), 8,
          "Invalid reads must still evaluate index/offset side effects")
      }
    }
  }

  func testEntityViewBoundsDoNotAliasAdjacentEntities() throws {
    let memory = EngineMemory()
    try memory.configurePlayBlocks(entityCount: 2, optionCount: 0,
      bucketCount: 0, archetypeCount: 1)
    for (block, stride) in [(4001, 32), (4002, 32), (4003, 3), (4006, 1), (4007, 4)] {
      memory.selectEntity(key: 1, index: 1)
      memory.set(block: block, index: 0, value: 42)
      memory.selectEntity(key: 0, index: 0)
      memory.set(block: block, index: stride - 1, value: 17)
      memory.set(block: block, index: stride, value: 99)
      XCTAssertEqual(memory.value(block: block, index: stride), 0)
      XCTAssertEqual(memory.value(block: block + 100, index: stride - 1), 17)
      XCTAssertEqual(memory.value(block: block + 100, index: stride), 42)
      XCTAssertEqual(memory.value(block: block + 100, index: stride * 2), 0)
    }
  }

  func testAbsentEntityLengthsKeepTheStandardLayout() throws {
    // Engines written before Sonolus 1.1.5 omit the fields entirely.
    let absent = try RuntimeNodeBuilder().engine(archetypes: [])
    XCTAssertEqual(absent.entityLayout, .standard)
    XCTAssertEqual(EngineEntityLayout.standard,
      EngineEntityLayout(memory: 64, data: 32, sharedMemory: 32))
    let explicit = try RuntimeNodeBuilder().engine(archetypes: [], fields: [
      "entityMemoryLength": 64, "entityDataLength": 32.0,
      "entitySharedMemoryLength": 32])
    XCTAssertEqual(explicit.entityLayout, .standard)
    let null = try RuntimeNodeBuilder().engine(archetypes: [], fields: [
      "entityMemoryLength": NSNull(), "entityDataLength": NSNull(),
      "entitySharedMemoryLength": NSNull()])
    XCTAssertEqual(null.entityLayout, .standard)
    let runtime = try EnginePlayRuntime(engine: absent,
      level: LevelData(bgmOffset: 0, entities: []), options: [],
      aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    XCTAssertEqual(runtime.memory.entityLayout, .standard)
  }

  func testEntityLengthsAreValidatedWithTheirDeclaredValue() throws {
    let fields = ["entityMemoryLength", "entityDataLength",
      "entitySharedMemoryLength"]
    for field in fields {
      for raw in [-1, 32.5, 1_048_577, 1e300, -0.5] as [Double] {
        XCTAssertThrowsError(try RuntimeNodeBuilder().engine(archetypes: [],
          fields: [field: raw])) { error in
          guard case EngineInterpreterError.invalidEntityLength(
            let name, let value) = error else {
            return XCTFail("\(field) \(raw): \(error)")
          }
          XCTAssertEqual(name, field)
          XCTAssertEqual(value, raw)
        }
      }
      XCTAssertThrowsError(try RuntimeNodeBuilder().engine(archetypes: [],
        fields: [field: "8"])) { XCTAssertTrue($0 is DecodingError) }
      for accepted in [0, EngineEntityLayout.maximumLength] {
        let engine = try RuntimeNodeBuilder().engine(archetypes: [],
          fields: [field: accepted])
        XCTAssertEqual([engine.entityLayout.memory, engine.entityLayout.data,
          engine.entityLayout.sharedMemory][fields.firstIndex(of: field)!],
          accepted)
      }
    }
    XCTAssertEqual(EngineInterpreterError.invalidEntityLength(
      field: "entityDataLength", value: -1).localizedDescription,
      "The engine's entityDataLength must be a whole number from 0 to "
        + "1048576, but it is -1.")
    XCTAssertEqual(EngineInterpreterError.invalidEntityLength(
      field: "entityMemoryLength", value: 32.5).localizedDescription,
      "The engine's entityMemoryLength must be a whole number from 0 to "
        + "1048576, but it is 32.5.")
    // Memory re-checks a layout that did not come through decoding.
    let memory = EngineMemory()
    for layout in [EngineEntityLayout(memory: -1, data: 32, sharedMemory: 32),
      EngineEntityLayout(memory: 64, data: 1 << 21, sharedMemory: 32)] {
      XCTAssertThrowsError(try memory.configurePlayBlocks(entityCount: 1,
        optionCount: 0, bucketCount: 0, archetypeCount: 0,
        entityLayout: layout))
    }
    let widest = EngineEntityLayout(memory: 1 << 20, data: 1 << 20,
      sharedMemory: 1 << 20)
    XCTAssertNoThrow(try memory.configurePlayBlocks(entityCount: 100_000,
      optionCount: 0, bucketCount: 0, archetypeCount: 0, entityLayout: widest))
    XCTAssertThrowsError(try memory.configurePlayBlocks(
      entityCount: Int.max / 32, optionCount: 0, bucketCount: 0,
      archetypeCount: 0, entityLayout: widest), "Array length overflows")
  }

  func testCustomEntityLengthsSizeViewsAndArrayStrides() throws {
    let layout = EngineEntityLayout(memory: 8, data: 4, sharedMemory: 2)
    for optimized in [false, true] {
      let memory = EngineMemory()
      try memory.configurePlayBlocks(entityCount: 3, optionCount: 0,
        bucketCount: 0, archetypeCount: 1, entityLayout: layout)
      XCTAssertEqual(memory.entityLayout, layout)
      for (block, count) in [4000: 8, 4001: 4, 4002: 2, 4101: 12, 4102: 6] {
        memory.selectEntity(key: 2, index: 2)
        memory.set(block: block, index: count - 1, value: 37)
        memory.set(block: block, index: count, value: 99)
        XCTAssertEqual(memory.value(block: block, index: count - 1), 37)
        XCTAssertEqual(memory.value(block: block, index: count), 0, "\(block)")
      }
      // Entity 1's view starts at its own stride in each array.
      memory.selectEntity(key: 1, index: 1)
      memory.callback = .preprocess
      func get(_ block: Double, _ index: Double) throws -> Double {
        let nodes = [EngineDataNode(value: block), EngineDataNode(value: index),
          EngineDataNode(function: "Get", arguments: [0, 1])]
        return try EngineInterpreter(nodes: nodes, memory: memory,
          optimizeLiteralAddresses: optimized).execute(nodeAt: 2)
      }
      memory.set(block: 4101, index: 4, value: 5)
      memory.set(block: 4101, index: 8, value: 6)
      memory.set(block: 4102, index: 2, value: 7)
      memory.set(block: 4102, index: 4, value: 8)
      XCTAssertEqual(try get(4001, 0), 5)
      XCTAssertEqual(try get(4001, 4), 0, "Must not alias entity 2")
      XCTAssertEqual(try get(4002, 0), 7)
      XCTAssertEqual(try get(4002, 2), 0, "Must not alias entity 2")
      XCTAssertEqual(try get(4101, 8), 6)
      XCTAssertEqual(try get(4102, 4), 8)
      memory.set(block: 4000, index: 7, value: 1)
      XCTAssertEqual(try get(4000, 7), 1)
      XCTAssertEqual(try get(4000, 8), 0)
      // Out-of-range writes keep their value and permission semantics.
      let nodes = ([4002, 2, 9] as [Double]).map { EngineDataNode(value: $0) }
        + [EngineDataNode(function: "Set", arguments: [0, 1, 2])]
      let set = EngineInterpreter(nodes: nodes, memory: memory,
        optimizeLiteralAddresses: optimized)
      XCTAssertEqual(try set.execute(nodeAt: 3), 9)
      XCTAssertEqual(memory.value(block: 4102, index: 4), 8)
      memory.callback = .updateParallel
      XCTAssertThrowsError(try set.execute(nodeAt: 3))
      // The layout belongs to the prepared state that restart restores.
      let restore = memory.makeRestorePoint()
      try memory.configurePlayBlocks(entityCount: 3, optionCount: 0,
        bucketCount: 0, archetypeCount: 1)
      XCTAssertEqual(memory.entityLayout, .standard)
      restore()
      XCTAssertEqual(memory.entityLayout, layout)
    }
  }

  func testCustomEntityLengthsReachLevelImportsAndSpawn() throws {
    let b = RuntimeNodeBuilder()
    let fields: [String: Any] = ["entityMemoryLength": 3,
      "entityDataLength": 4, "entitySharedMemoryLength": 2]
    func probe(importIndex: Int) -> [[String: Any]] {
      [["name": "Probe", "hasInput": false, "exports": [],
        "imports": [["name": "value", "index": importIndex]]]]
    }
    let level = LevelData(bgmOffset: 0, entities: [7.0, 9.0].map {
      LevelEntity(archetype: "Probe", name: nil,
        data: [LevelEntityData(name: "value", value: $0, ref: nil)])
    })
    func runtime(_ engine: EnginePlayData) throws -> EnginePlayRuntime {
      try EnginePlayRuntime(engine: engine, level: level, options: [],
        aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
        particleEffectIDs: [])
    }
    let prepared = try runtime(b.engine(archetypes: probe(importIndex: 3),
      fields: fields))
    let memory = prepared.memory
    XCTAssertEqual(memory.value(block: 4101, index: 3), 7)
    XCTAssertEqual(memory.value(block: 4101, index: 7), 9)
    memory.selectEntity(key: 0, index: 0)
    XCTAssertEqual(memory.value(block: 4001, index: 3), 7)
    XCTAssertEqual(memory.value(block: 4001, index: 7), 0)
    memory.selectEntity(key: 1, index: 1)
    XCTAssertEqual(memory.value(block: 4001, index: 3), 9)
    XCTAssertThrowsError(try runtime(b.engine(
      archetypes: probe(importIndex: 4), fields: fields))) {
      XCTAssertTrue($0.localizedDescription.contains(
        "entity import index 4 (Entity Data length 4)"), "\($0)")
    }
    // The standard layout keeps accepting imports through index 31 only.
    XCTAssertNoThrow(try runtime(b.engine(archetypes: probe(importIndex: 31))))
    XCTAssertThrowsError(
      try runtime(b.engine(archetypes: probe(importIndex: 32))))
    // Spawn data fills Entity Memory; it may not exceed its length.
    XCTAssertEqual(try prepared.host.call(function: "Spawn",
      arguments: [0, 1, 2, 3]), 0)
    XCTAssertThrowsError(try prepared.host.call(function: "Spawn",
      arguments: [0, 1, 2, 3, 4]))
    let standard = try runtime(b.engine(archetypes: probe(importIndex: 0)))
    XCTAssertNoThrow(try standard.host.call(function: "Spawn",
      arguments: [0] + Array(repeating: 1, count: 64)))
    XCTAssertThrowsError(try standard.host.call(function: "Spawn",
      arguments: [0] + Array(repeating: 1, count: 65)))
  }

  func testEveryMemoryMutationRespectsCallbackAccess() throws {
    let bases = ["Set", "SetAdd", "SetSubtract", "SetMultiply", "SetDivide",
      "SetPower", "SetMod", "SetRem", "IncrementPre", "IncrementPost",
      "DecrementPre", "DecrementPost"]
    for optimized in [false, true] {
      for suffix in ["", "Shifted", "Pointed"] {
        for base in bases {
          let memory = EngineMemory()
          memory.selectEntity(key: 0, index: 0)
          memory.set(block: 2000, index: 0, value: 9)
          memory.set(block: 4000, index: 0, value: 2000)
          memory.set(block: 4000, index: 1, value: 0)
          memory.callback = .updateParallel
          var args: [Double] = switch suffix {
          case "Shifted": [2000, 0, 0, 1]
          case "Pointed": [4000, 0, 0]
          default: [2000, 0]
          }
          if base.hasPrefix("Set") { args.append(2) }
          let nodes = args.map { EngineDataNode(value: $0) } + [
            EngineDataNode(function: base + suffix,
              arguments: Array(args.indices))]
          let interpreter = EngineInterpreter(nodes: nodes, memory: memory,
            optimizeLiteralAddresses: optimized)
          XCTAssertThrowsError(try interpreter.execute(nodeAt: args.count),
            base + suffix)
          XCTAssertEqual(memory.value(block: 2000, index: 0), 9)
          memory.callback = .updateSequential
          XCTAssertNoThrow(try interpreter.execute(nodeAt: args.count))
        }
      }
    }
    let memory = EngineMemory()
    memory.selectEntity(key: 0, index: 0)
    memory.set(block: 4000, index: 0, value: 12)
    memory.callback = .updateParallel
    XCTAssertThrowsError(try evaluate("Copy", [4000, 0, 2000, 0, 2],
      memory: memory))
    XCTAssertEqual(memory.value(block: 2000, index: 0), 0)
    memory.callback = .touch
    XCTAssertNoThrow(try evaluate("Copy", [4000, 0, 2000, 0, 2], memory: memory))
    XCTAssertEqual(memory.value(block: 2000, index: 0), 12)
  }

  func testAbsentSpawnedMemoryViewsReadZeroAndRejectWrites() throws {
    let memory = EngineMemory()
    memory.selectEntity(key: 9, index: nil)
    memory.callback = .updateSequential
    for block in [4001, 4002, 4003, 4005] {
      XCTAssertEqual(try evaluate("Get", [Double(block), 0], memory: memory), 0)
      XCTAssertEqual(try evaluate("GetShifted", [Double(block), 0, 0, 1],
        memory: memory), 0)
      memory.set(block: 4000, index: 0, value: Double(block))
      XCTAssertEqual(try evaluate("GetPointed", [4000, 0, 0], memory: memory), 0)
      XCTAssertEqual(try evaluate("GetPointed", [Double(block), 0, 0],
        memory: memory), 0, "A missing pointer reads (0, 0)")
      memory.set(block: 4000, index: 2, value: 99)
      XCTAssertEqual(try evaluate("Copy", [Double(block), 0, 4000, 2, 1],
        memory: memory), 0)
      XCTAssertEqual(memory.value(block: 4000, index: 2), 0)
      XCTAssertThrowsError(try evaluate("Set", [Double(block), 0, 1], memory: memory))
    }
    for block in [4000, 4004, 10000] {
      XCTAssertEqual(try evaluate("Set", [Double(block), 0, 7], memory: memory), 7)
      XCTAssertEqual(try evaluate("Get", [Double(block), 0], memory: memory), 7)
    }
    for block in [4006, 4007] {
      XCTAssertEqual(try evaluate("Get", [Double(block), 0], memory: memory), 0,
        "Do not infer restrictions beyond the Spawn contract")
    }
    // A spawned entity can still read the arrays for original level entities.
    memory.set(block: 4102, index: 31, value: 42)
    XCTAssertEqual(try evaluate("Get", [4102, 31], memory: memory), 42)
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

  func testRandomBoundsAndEmptyOrReversedRanges() throws {
    for _ in 0..<100 {
      XCTAssertTrue((-3...2).contains(try evaluate("Random", [-3, 2])))
      XCTAssertTrue((1...2).contains(try evaluate("Random", [2, 1])))
      let integer = try evaluate("RandomInteger", [-1.5, 2.2])
      XCTAssertTrue((-1...2).contains(integer))
      XCTAssertEqual(integer, integer.rounded())
    }
    XCTAssertEqual(try evaluate("Random", [4, 4]), 4)
    XCTAssertEqual(try evaluate("RandomInteger", [4, 4]), 4)
    XCTAssertEqual(try evaluate("RandomInteger", [3.5, 1]), 4)
    XCTAssertThrowsError(try evaluate("Random", [.nan, 1]))
    XCTAssertThrowsError(try evaluate("RandomInteger", [1, .infinity]))
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

  func testUIAnimationPreservesExtendedValuesAndEasingOvershoot() throws {
    func tween(_ from: Double, _ to: Double, _ duration: Double,
      _ ease: String = "linear") throws -> EngineConfiguration.UI.Animation.Tween {
      try JSONDecoder().decode(EngineConfiguration.UI.Animation.Tween.self,
        from: JSONSerialization.data(withJSONObject: ["from": from,
          "to": to, "duration": duration, "ease": ease]))
    }
    let overshoot = try tween(0, 1024, 1, "outBack")
    // Independent polynomial: outBack(0.5) = 1 + 0.125 * 1.70158 - 0.125.
    XCTAssertEqual(overshoot.value(at: 0.5), 1113.80224, accuracy: 1e-8)
    let long = try tween(-2048, 2048, 7200)
    XCTAssertEqual(long.value(at: 0), -2048)
    XCTAssertEqual(long.value(at: 3600), 0)
    XCTAssertEqual(long.value(at: 7200), 2048)
    let large = try tween(-Double.greatestFiniteMagnitude,
      Double.greatestFiniteMagnitude, 1)
    XCTAssertEqual(large.value(at: 0.5), 0)
    let inward = try tween(0.95 * Double.greatestFiniteMagnitude,
      Double.greatestFiniteMagnitude, 1, "inBack")
    XCTAssertEqual(inward.value(at: 0.5) / Double.greatestFiniteMagnitude,
      0.945615125, accuracy: 1e-12)
  }

  @MainActor
  func testExtendedUIAnimationScalesRenderInBoundedViewport() throws {
    for scale in [1.0, 2048, -2048, 1e300, Double.greatestFiniteMagnitude] {
      let tween: [String: Any] = ["from": scale, "to": scale,
        "duration": 0, "ease": "linear"]
      let animation = try JSONDecoder().decode(
        EngineConfiguration.UI.Animation.self,
        from: JSONSerialization.data(withJSONObject: ["scale": tween,
          "alpha": ["from": 1, "to": 1, "duration": 0, "ease": "linear"]]))
      // Exercise the production scaleEffect path inside a screen-sized clip.
      // This guards framework safety, not native-client rasterization parity.
      let view = EngineComboText(combo: 123, animation: animation)
        .frame(width: 320, height: 120).clipped()
      let renderer = ImageRenderer(content: view)
      let image = try XCTUnwrap(renderer.cgImage, "scale \(scale)")
      XCTAssertEqual(image.width, 320)
      XCTAssertEqual(image.height, 120)
      if scale == 1 {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width,
          height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
            CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 120))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertTrue(stride(from: 3, to: 320 * 120 * 4, by: 4).contains {
          pixels[$0] != 0
        }, "The control must contain text, not only a blank viewport")
      }
    }
  }

  @MainActor
  func testPresentationEnumsValidateBeforeGameplayCanStart() throws {
    let metrics = ["arcade", "arcadePercentage", "accuracy", "accuracyPercentage",
      "life", "time", "perfect", "perfectPercentage", "greatGoodMiss",
      "greatGoodMissPercentage", "miss", "missPercentage", "errorHeatmap"]
    let fields = [
      ("primaryMetric", metrics), ("secondaryMetric", metrics),
      ("judgmentErrorStyle", ["none", "late", "early", "plus", "minus",
        "arrowUp", "arrowDown", "arrowLeft", "arrowRight", "triangleUp",
        "triangleDown", "triangleLeft", "triangleRight"]),
      ("judgmentErrorPlacement", ["left", "right", "leftRight", "top", "bottom",
        "topBottom", "center"])
    ]
    for (field, values) in fields {
      for value in values {
        let config = try JSONDecoder().decode(EngineConfiguration.self,
          from: JSONSerialization.data(withJSONObject: [
            "options": [], "ui": [field: value]]))
        XCTAssertNoThrow(try config.ui?.validate(), "\(field): \(value)")
      }
      let data = try JSONSerialization.data(withJSONObject: [
        "options": [], "ui": [field: "FutureValue"]])
      let config = try JSONDecoder().decode(EngineConfiguration.self, from: data)
      XCTAssertThrowsError(try config.ui?.validate()) { error in
        guard case RuntimeBundleError.unsupportedPresentationValue(
          let label, let value) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(label.isEmpty)
        XCTAssertEqual(value, "FutureValue")
      }
      let model = try gameplayModel(presentation:
        RuntimePresentation(resources: ["configuration": data]))
      guard case .failed(let message) = model.phase else {
        return XCTFail("Unknown \(field) must fail preparation, not enter Ready")
      }
      XCTAssertTrue(message.contains("FutureValue"))
      XCTAssertTrue(message.contains("unsupported"))
      model.start()
      XCTAssertEqual(model.phase, .failed(message))
      XCTAssertNil(model.engineRuntime)
    }
    let omitted = try JSONDecoder().decode(EngineConfiguration.self,
      from: Data(#"{"options":[],"ui":{}}"#.utf8))
    XCTAssertNoThrow(try omitted.ui?.validate())
  }

  func testUIEasingValidationCoversAllDocumentedCurvesAndAnimationSlots() throws {
    let documented = ["linear", "none"] + ["in", "out", "inOut", "outIn"].flatMap { mode in
      ["Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Back", "Elastic"]
        .map { mode + $0 }
    }
    XCTAssertEqual(EngineEasing.supportedNames, Set(documented))
    for name in documented {
      let tween = try JSONDecoder().decode(EngineConfiguration.UI.Animation.Tween.self,
        from: JSONSerialization.data(withJSONObject: [
          "from": 0, "to": 1, "duration": 1, "ease": name]))
      XCTAssertTrue(tween.value(at: 0.37).isFinite, name)
      XCTAssertEqual(tween.value(at: 1), 1, name)
    }
    for animation in ["judgmentAnimation", "comboAnimation"] {
      for component in ["scale", "alpha"] {
        let valid: [String: Any] = ["from": 0, "to": 1,
          "duration": 1, "ease": "linear"]
        var bad = valid
        bad["ease"] = "inFuture"
        var components = ["scale": valid, "alpha": valid]
        components[component] = bad
        let data = try JSONSerialization.data(withJSONObject: [
          "options": [], "ui": [animation: components]])
        XCTAssertThrowsError(try JSONDecoder().decode(EngineConfiguration.self,
          from: data)) { error in
          guard case RuntimeBundleError.unsupportedPresentationValue(
            let field, let value) = error else {
            return XCTFail("Unexpected error: \(error)")
          }
          XCTAssertEqual(field, "UI animation easing")
          XCTAssertEqual(value, "inFuture")
        }
      }
    }
  }

  func testInvalidEngineAnimationNumbersAreRejected() {
    for (from, duration) in [("1", "1e400"), ("1e400", "0.3"), ("1", "-1")] {
      let json = """
        {"options":[],"ui":{"judgmentAnimation":{
        "scale":{"from":\(from),"to":1,"duration":\(duration),"ease":"linear"},
        "alpha":{"from":1,"to":0,"duration":0.3,"ease":"none"}}}}
        """
      XCTAssertThrowsError(try JSONDecoder().decode(EngineConfiguration.self,
        from: Data(json.utf8)))
    }
  }

  func testEngineAnimationWaitUsesBoundedCancellableSleeps() async throws {
    var intervals = [Double]()
    try await EngineConfiguration.UI.Animation.wait(duration: 7200.5) {
      intervals.append($0)
    }
    XCTAssertEqual(intervals, [3600, 3600, 0.5])
    intervals.removeAll()
    try await EngineConfiguration.UI.Animation.wait(duration: 0) {
      intervals.append($0)
    }
    XCTAssertTrue(intervals.isEmpty)
    do {
      try await EngineConfiguration.UI.Animation.wait(duration: 1e300) {
        XCTAssertEqual($0, 3600)
        // Exercise the real conversion that previously could trap, without
        // actually sleeping: only a bounded interval reaches Duration.
        XCTAssertEqual(Duration.seconds($0), .seconds(3600))
        throw CancellationError()
      }
      XCTFail("Cancellation must propagate to the view task")
    } catch is CancellationError { }
    // Also cancel a real child task before it reaches the wait. This checks
    // cancellation itself, independently of a throwing fake sleep function.
    let gate = AsyncStream<Void>.makeStream()
    let task = Task {
      for await _ in gate.stream { }
      try await EngineConfiguration.UI.Animation.wait(duration: 1e300) { _ in
        XCTFail("A canceled wait must not schedule another timer")
      }
    }
    task.cancel()
    gate.continuation.finish()
    do {
      try await task.value
      XCTFail("A canceled task must fail its animation wait")
    } catch is CancellationError { }
  }

  @MainActor
  func testTimeMetricRejectsUnrepresentableTimes() throws {
    // The chart clock starts at -bgmOffset.
    let model = try gameplayModel(bgmOffset: -1e20)
    model.start()
    defer { model.stop() }
    XCTAssertEqual(model.currentTime, 1e20)
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
  func testHeatmapHUDSelectionUsesTheSharedInputPipelineAndResetsOnRestart()
    async throws {
    for metrics in [("errorHeatmap", "life"), ("arcade", "errorHeatmap"),
      ("arcade", "life")] {
      let configuration = try JSONSerialization.data(withJSONObject: [
        "options": [], "ui": ["primaryMetric": metrics.0, "secondaryMetric": metrics.1]
      ] as [String: Any])
      let model = try gameplayModel(presentation: RuntimePresentation(resources: [
        "configuration": configuration
      ]), entities: [input(beat: 1, grade: 2, accuracy: 0.02)])
      model.start()
      defer { model.stop() }
      try await judgeSpawnedInputs(model, count: 1)
      XCTAssertEqual(model.latestJudgement?.text(for: .timing), "Late GREAT")
      let expected = metrics.0 == "errorHeatmap" || metrics.1 == "errorHeatmap" ? 1 : 0
      XCTAssertEqual(model.errorHeatmap.count, expected)
      if expected == 1 {
        XCTAssertEqual(model.errorHeatmap.meanMS!, 20, accuracy: 1e-8)
        XCTAssertEqual(model.engineMetric("errorHeatmap")?.text, "+20.0 ms")
      }
      model.restart()
      XCTAssertNil(model.latestJudgement)
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
    let model = try gameplayModel(engine: engine, presentation: presentation,
      entities: [entity("TapNote", values: [:]), entity("SwingNote", values: [:])])
    XCTAssertEqual(model.phase, .ready)
    XCTAssertNil(model.engineRuntime)
    XCTAssertEqual(model.noteCount, 1,
      "Count engine-defined inputs, not guessed archetype names")
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
          "playData": {"url": "/data/play"},
          "configuration": {"url": "/data/configuration"}
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
      references.engineDataURL?.absoluteString,
      "https://engine.example/v13/data/play"
    )
    XCTAssertEqual(
      references.levelDataURL?.absoluteString,
      "https://levels.example/game/data/chart"
    )
    XCTAssertEqual(
      references.bgmURL?.absoluteString,
      "https://levels.example/game/music.mp3"
    )
  }

  func testRuntimeResourcesRejectMissingConfigurationAndMalformedOverrides() throws {
    let base = URL(string: "https://server.example")!
    let valid: [String: Any] = ["bgm": ["url": "music"],
      "data": ["url": "level"], "engine": ["version": 13,
        "playData": ["url": "play"], "configuration": ["url": "config"]]]
    func references(_ item: [String: Any]) throws -> RuntimeResourceReferences {
      try RuntimeResourceReferences(itemData: JSONSerialization.data(
        withJSONObject: item), serverBaseURL: base)
    }
    XCTAssertNil(try references(valid).engineROMURL)
    for field in ["configuration", "rom"] {
      for locator: Any in [NSNull(), [:], ["url": ""],
        ["url": "file:///private/tmp/not-a-server-resource"],
        ["url": "data:text/plain,not-a-server-resource"]] {
        var item = valid
        var engine = item["engine"] as! [String: Any]
        engine[field] = locator
        item["engine"] = engine
        if field == "rom", locator is NSNull {
          XCTAssertNil(try references(item).engineROMURL)
        } else {
          XCTAssertThrowsError(try references(item), "Invalid \(field): \(locator)")
        }
      }
      var item = valid
      var engine = item["engine"] as! [String: Any]
      engine[field] = nil
      item["engine"] = engine
      if field == "configuration" { XCTAssertThrowsError(try references(item)) }
      else { XCTAssertNil(try references(item).engineROMURL) }
    }
    for (name, key) in [("skin", "useSkin"), ("background", "useBackground"),
      ("effect", "useEffect"), ("particle", "useParticle")] {
      var item = valid
      item[key] = ["useDefault": false]
      XCTAssertThrowsError(try references(item)) { error in
        guard case RuntimeBundleError.missingResource(let missing) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(missing, "selected \(name)")
      }
      let assets: [String: Any] = ["data": ["url": "data"],
        "texture": ["url": "texture"], "audio": ["url": "audio"],
        "image": ["url": "image"], "configuration": ["url": "config"]]
      let required = name == "background" ? ["data", "image", "configuration"]
        : ["data", name == "effect" ? "audio" : "texture"]
      for missing in required {
        var selected = assets
        selected[missing] = ["url": ""]
        item[key] = ["useDefault": false, "item": selected]
        XCTAssertThrowsError(try references(item), "Missing \(name) \(missing)")
      }
      item[key] = ["useDefault": false, "item": assets]
      XCTAssertNotNil(try references(item).presentationURLs[name + "Data"])
    }
  }

  @MainActor
  func testMissingPresentationFailsInsteadOfEnteringReady() throws {
    for presentation in [nil, RuntimePresentation(resources: [:])] {
      let model = try gameplayModel(presentation: presentation)
      guard case .failed(let message) = model.phase else {
        return XCTFail("A missing configuration must fail, not enter Ready")
      }
      XCTAssertTrue(message.contains("configuration"))
      model.start()
      XCTAssertEqual(model.phase, .failed(message))
      XCTAssertNil(model.engineRuntime)
    }
  }

  @MainActor
  func testGameplayRecordsEngineJudgmentsAtTheirChartTimes() async throws {
    let model = try gameplayModel(entities: [
      entity("#BPM_CHANGE", values: ["#BEAT": 0, "#BPM": 120]),
      input(beat: 2, grade: 1), input(beat: 4, grade: 1, accuracy: -0.01),
      input(beat: 6, grade: 1)
    ])
    model.start()
    defer { model.stop() }
    try await judgeSpawnedInputs(model, count: 3)
    XCTAssertEqual(model.noteCount, 3, "Tempo changes are not inputs")
    XCTAssertEqual(model.score, NoteJudgement.maximumScore)
    XCTAssertEqual(model.combo, 3)
    XCTAssertEqual(model.maxCombo, 3)
    XCTAssertEqual(model.judgements[.perfect], 3)
    XCTAssertEqual(model.noteTimings.map(\.noteType), ["Input", "Input", "Input"])
    XCTAssertEqual(model.noteTimings.map(\.songTime), [1, 2, 3])
    XCTAssertEqual(model.noteTimings.map(\.accuracy), [0, -0.01, 0])
  }

  func testInputCalibrationDecodesDefaultsAndClampsInvalidValues() throws {
    let legacy = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data("{}".utf8))
    XCTAssertEqual(legacy.inputOffsetMilliseconds, 0)
    XCTAssertEqual(legacy.visualOffsetMilliseconds, 0)
    XCTAssertFalse(legacy.engineDebugMode)
    XCTAssertTrue(try JSONDecoder().decode(GameplayPreferences.self,
      from: JSONEncoder().encode(GameplayPreferences(engineDebugMode: true)))
      .engineDebugMode)
    var settings = GameplayPreferences(inputOffsetMilliseconds: 300)
    XCTAssertEqual(settings.inputOffsetMilliseconds, 250)
    settings.inputOffsetMilliseconds = -.infinity
    XCTAssertEqual(settings.inputOffsetMilliseconds, 0)
    settings.inputOffsetMilliseconds = -500
    XCTAssertEqual(settings.inputOffsetSeconds, -0.25)
    let decoded = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data(#"{"inputOffsetMilliseconds":900}"#.utf8))
    XCTAssertEqual(decoded.inputOffsetMilliseconds, 250)
    var visual = GameplayPreferences(visualOffsetMilliseconds: -500)
    XCTAssertEqual(visual.visualOffsetSeconds, -0.25)
    visual.visualOffsetMilliseconds = .nan
    XCTAssertEqual(visual.visualOffsetMilliseconds, 0)
    visual.visualOffsetMilliseconds = 500
    XCTAssertEqual(visual.visualOffsetMilliseconds, 250)
    let restored = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data(#"{"visualOffsetMilliseconds":-900}"#.utf8))
    XCTAssertEqual(restored.visualOffsetMilliseconds, -250)
    visual.visualOffsetMilliseconds = 0
    XCTAssertEqual(try JSONDecoder().decode(GameplayPreferences.self,
      from: JSONEncoder().encode(visual)).visualOffsetSeconds, 0)
  }

  @MainActor
  func testCalibrationIsSnapshotForEachPlayAndReported() throws {
    let model = try gameplayModel()
    let original = model.settings
    defer { model.stop(); model.settings = original }
    for visual in [-120.0, 0, 120] {
      for inputOffset in [-30.0, 0, 30] {
        model.settings = GameplayPreferences(inputOffsetMilliseconds: inputOffset,
          visualOffsetMilliseconds: visual)
        model.start()
        model.settings = GameplayPreferences() // Applies only next play.
        XCTAssertEqual(model.playInputOffset, inputOffset / 1000)
        XCTAssertEqual(model.playAudioOffset, visual / 1000)
        // Visual timing delays the chart against the music. Input timing
        // goes to the engine and does not move the chart clock.
        XCTAssertEqual(model.currentTime, 0.05 - visual / 1000, accuracy: 1e-12)
        let modified = [("Input Timing", inputOffset), ("Visual Timing", visual)]
          .filter { $0.1 != 0 }
        XCTAssertEqual(model.modifiedOptions.map(\.name), modified.map(\.0))
        XCTAssertEqual(model.modifiedOptions.map(\.value),
          modified.map { String(format: "%+.0f ms", $0.1) })
        model.stop()
      }
    }
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
  func testSavedScoreModeMatchesEffectiveRuntimeOption() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("score-mode-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"""
        {"options":[{"name":"Score Mode","type":"select","def":0,
          "standard":true,"values":["Flat","#COMBO"]}]}
        """#.utf8)
    ])
    let cases: [(dedicated: Int?, generic: Double?, effective: Double)] = [
      (nil, 1, 1), (1, nil, 1), (0, 1, 0),
      (nil, nil, 0), (nil, 99, 0), (nil, 0.5, 0)
    ]
    for (index, selection) in cases.enumerated() {
      let model = try gameplayModel(resultStore: store,
        presentation: presentation)
      let original = model.settings
      defer { model.stop(); model.settings = original }
      model.settings = GameplayPreferences()
      model.settings.scoreMode = selection.dedicated
      model.settings.engineOptions["Score Mode"] = selection.generic
      model.start()
      model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
      let runtime = try XCTUnwrap(model.engineRuntime)
      XCTAssertEqual(runtime.memory.value(block: 2002, index: 0),
        selection.effective, "Case \(index)")
      // Exercise normal completion/persistence without waiting on audio.
      // The fixture has no input entities; this is not an audio-clock check.
      model.playbackEnded(uptime: 100)
      XCTAssertEqual(model.phase, .finished)
      await model.resultSaveTask?.value
      XCTAssertNil(model.resultSaveError)
      let results = try await store.allResults()
      XCTAssertEqual(results.count, index + 1)
      let result = try XCTUnwrap(results.first)
      let label = selection.effective == 1 ? "Combo" : "Flat"
      XCTAssertEqual(result.scoreMode, label, "Case \(index)")
      XCTAssertEqual(result.modifiedOptions?.first {
        $0.name == "Score Mode"
      }?.value, selection.effective == 1 ? label : nil)
    }
  }

  @MainActor
  func testGameplayCompletesAndSavesAfterAudioEnds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let misses = (2...5).map { input(beat: Double($0), grade: 0) }
    let model = try gameplayModel(resultStore: store,
      entities: [input(beat: 1, grade: 1)] + misses)
    let original = model.settings
    defer { model.stop(); model.settings = original }
    model.settings.recordTimingDiagnostics = true
    model.start()
    let recorder = try XCTUnwrap(model.timingRecorder)
    recorder.record(.runtime, seconds: 0.004)
    try await judgeSpawnedInputs(model, count: 5)
    XCTAssertEqual(model.phase, .playing, "Wait for the music to end")
    model.playbackEnded(uptime: 100)

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
    XCTAssertFalse(model.engineFrame(size: CGSize(width: 800, height: 400),
      touches: []))
    XCTAssertEqual(model.judgements[.miss], 4)
  }

  @MainActor
  func testGameplayWaitsForMusicAfterLastNote() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try gameplayModel(resultStore: ResultStore(rootURL: root),
      entities: [input(beat: 1, grade: 1)])
    model.start()
    try await judgeSpawnedInputs(model, count: 1)
    XCTAssertEqual(model.phase, .playing)
    XCTAssertNil(model.resultSaveTask)
    model.playbackEnded(uptime: 100)
    XCTAssertEqual(model.phase, .finished)
    await model.resultSaveTask?.value
    model.restart()
    XCTAssertEqual(model.phase, .playing)
    model.stop()
    XCTAssertEqual(model.phase, .ready)
    model.playbackEnded(uptime: 200)
    XCTAssertEqual(model.phase, .ready, "A stopped play is not a result")
    XCTAssertFalse(model.engineFrame(size: CGSize(width: 800, height: 400),
      touches: []))
  }

  @MainActor
  func testRestartClearsJudgementsAndAudioTail() async throws {
    let model = try gameplayModel(entities: [input(beat: 1, grade: 1),
      entity("Pending", values: ["#BEAT": 2])])
    model.start()
    try await judgeSpawnedInputs(model, count: 1)
    XCTAssertEqual(model.combo, 1)
    model.playbackEnded(uptime: 100)
    XCTAssertEqual(model.phase, .playing, "An input is still pending")
    let generation = model.playbackGeneration
    model.restart()
    defer { model.stop() }
    XCTAssertEqual(model.phase, .playing)
    XCTAssertGreaterThan(model.playbackGeneration, generation)
    XCTAssertNil(model.engineRuntime)
    XCTAssertEqual(model.score, 0)
    XCTAssertEqual(model.combo, 0)
    XCTAssertEqual(model.maxCombo, 0)
    XCTAssertNil(model.latestJudgement)
    XCTAssertTrue(model.noteTimings.isEmpty)
    XCTAssertEqual(model.playbackTime, 0.05, "The old audio tail clock is gone")
    model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
    XCTAssertEqual(model.phase, .playing)
    XCTAssertEqual(model.judgements.values.reduce(0, +), 0)
    XCTAssertNil(model.resultSaveTask)
  }

  @MainActor
  private func gameplayModel(
    resultStore: ResultStore = ResultStore(), engine: EnginePlayData? = nil,
    presentation: RuntimePresentation? = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8)]),
    bgmOffset: Double = -0.05, entities: [LevelEntity] = []
  ) throws -> GameplayModel {
    let engine = try engine ?? judgingEngine()
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
        engine: engine,
        level: LevelData(bgmOffset: bgmOffset, entities: entities),
        bgmURL: try silentMusic(), isOffline: true, presentation: presentation
      ),
      level: level, server: server, title: "Gameplay"
    )
    return model
  }

  /// "Input" entities judge themselves when they spawn, with their own
  /// `grade` (1 perfect, 2 great, 3 good, 0 miss) and `accuracy`. "Pending"
  /// inputs never resolve.
  private func judgingEngine() throws -> EnginePlayData {
    try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[
         {"name":"Input","hasInput":true,"exports":[],
          "imports":[{"name":"grade","index":0},{"name":"accuracy","index":1}],
          "initialize":{"index":10}},
         {"name":"Pending","hasInput":true,"imports":[],"exports":[]}],
       "nodes":[{"value":4005},{"value":0},{"value":4001},{"value":1},
         {"func":"Get","args":[2,1]},{"func":"Set","args":[0,1,4]},
         {"func":"Get","args":[2,3]},{"func":"Set","args":[0,3,6]},
         {"value":4004},{"func":"Set","args":[8,1,3]},
         {"func":"Execute","args":[5,7,9]}]}
      """#.utf8))
  }

  private func input(beat: Double, grade: Double, accuracy: Double = 0)
    -> LevelEntity {
    entity("Input", values: ["#BEAT": beat, "grade": grade, "accuracy": accuracy])
  }

  /// A real file: the player fails missing music while a test awaits.
  private func silentMusic() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("gameplay-silence-\(UUID()).caf")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000,
      channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: 2000))
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].initialize(repeating: 0, count: 2000)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }

  /// Startup simulation commits judgments of inputs that resolve on spawn.
  /// Returns right after that frame, before the startup task can start the
  /// music, so callers continue from a deterministic state.
  @MainActor
  private func judgeSpawnedInputs(_ model: GameplayModel, count: Int)
    async throws {
    for _ in 0..<1000 {
      model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
      if model.noteTimings.count >= count { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("Inputs were not judged: \(model.startupDiagnostics)")
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

// The rhythm-lab `sfp` engine (Shiny Colors Song for Prism). Its fixtures are
// optional within an installed fixture root: an `sfp` folder holding the
// engine files and converted charts: MASTER `001.gz`, `110.gz`, `189.gz`,
// `041.gz` (speed changes, including a scroll stop), `189.gz` converted with
// a tempo for preview measure lines (a BeatGrid entity), `004.gz` and `102.gz`
// (slides moving against their end flick's arrow) and EXPERT `001-4.gz`
// (slides under 0.2 s, a fast slide into an end flick).
@MainActor
extension CachedEngineIntegrationTests {
  func testSFPAmbeveMasterLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sfp", chart: try sfpChart("001.gz"))
  }

  func testSFPMellowMasterLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sfp", chart: try sfpChart("110.gz"))
  }

  func testSFPTokyoMasterLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sfp", chart: try sfpChart("189.gz"))
  }

  func testSFPSpeedChangesLifecycleAndRestart() async throws {
    try await checkChart(engineFolder: "sfp", chart: try sfpChart("041.gz"))
  }

  /// Scripted contacts that press, hold, follow and flick every note on time
  /// must judge every input once, all Perfect, except flicks deliberately
  /// flicked against their arrow, which are REVERSE: one grade lower (Great).
  /// Free flicks are often flicked by a finger already down (resting after a
  /// tap) and streams of flicks by one finger without lifting.
  /// Slide fingers move with their slide and flick held flicks themselves,
  /// so fast slides into end flicks (001 EXPERT at 74.41 s) and slides moving
  /// against their end flick's arrow (004 and 102 MASTER) are covered.
  func testSFPScriptedPerfectPlay() throws {
    _ = try sfpChart("001.gz")
    var resting = 0, streams = 0
    for chart in ["001.gz", "110.gz", "189.gz", "041.gz", "001-4.gz", "004.gz",
      "102.gz"] {
      let counts = try checkSFPScriptedPlay(chart, sloppy: false)
      resting += counts.resting
      streams += counts.streams
    }
    // Free flicks need no fresh press, and one finger can flick a stream.
    XCTAssertGreaterThan(resting, 0, "No free flick by a finger already down")
    XCTAssertGreaterThan(streams, 0, "No one-finger flick stream")
  }

  /// Slides pressed a frame late and released 100 ms early, including slides
  /// shorter than 0.2 s: the game does not judge release timing, so every
  /// slide end, tap, flick and every tick inside the end's grace is still
  /// Perfect.
  func testSFPScriptedLooseSlides() throws {
    _ = try sfpChart("001-4.gz")
    for chart in ["001-4.gz", "001.gz", "110.gz", "004.gz"] {
      try checkSFPScriptedPlay(chart, sloppy: true)
    }
  }

  private func sfpChart(_ chart: String) throws -> String {
    let folder = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures/sfp")
    guard FileManager.default.fileExists(atPath: folder.path) else {
      throw XCTSkip("Optional cached SfP fixtures are not installed.")
    }
    return "sfp/\(chart)"
  }

  @discardableResult
  private func checkSFPScriptedPlay(_ chart: String, sloppy: Bool) throws
    -> (resting: Int, streams: Int) {
    let cache = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures")
    let root = cache.appendingPathComponent("sfp")
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: Data(contentsOf: root.appendingPathComponent(chart)))
    var resources = [String: Data]()
    for key in ["configuration", "skinData", "skinTexture", "particleData",
      "particleTexture", "effectData", "effectAudio"] {
      resources[key] = try Data(contentsOf: root.appendingPathComponent(key))
    }
    let presentation = RuntimePresentation(resources: resources)
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine, presentation: presentation)
    let aspectRatio = 1.8
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: assets.configuration.options.map(\.def), aspectRatio: aspectRatio,
      skinSpriteIDs: Set(assets.skin.keys), effectClipIDs: audio.clipIDs,
      particleEffectIDs: Set(assets.particles.keys))
    let start = BGMClockMapping(offset: level.bgmOffset).initialChartTime
    let script = SFPScript(level: level, aspectRatio: aspectRatio, start: start,
      sloppy: sloppy, reverseEvery: sloppy ? 0 : 5)
    let label = "\(chart)\(sloppy ? " (loose slides)" : "")"
    var seen = Set<Int>()
    var grades = [Int: Int]()
    var failures = [String: Int]()
    var reversed = [Int: Int]()
    var frame = 0
    while runtime.resolvedInputCount < runtime.inputCount, frame < 30000 {
      let time = start + Double(frame) / 60
      try runtime.update(at: time, touches: script.touches(frame: frame, time: time))
      for judgment in runtime.judgments {
        XCTAssertTrue(seen.insert(judgment.entityIndex).inserted,
          "Duplicate input resolution in \(chart): \(judgment.entityIndex)")
        grades[judgment.grade, default: 0] += 1
        if script.reversed.contains(judgment.entityIndex) {
          reversed[judgment.grade, default: 0] += 1
          if judgment.grade != 2 {
            print("SFP REVERSE NOT GREAT \(label) grade \(judgment.grade) "
              + "accuracy \(judgment.accuracy) at \(time): "
              + level.entities[judgment.entityIndex].data
                .map { "\($0.name)=\($0.value ?? .nan)" }.joined(separator: " "))
          }
          continue
        }
        let entity = level.entities[judgment.entityIndex]
        // Loose slides may miss ticks in their first two frames, before the
        // late finger is down.
        if judgment.grade != 1
          && !(sloppy && entity.archetype == "SlideTickNote"
            && script.nearChainStart(entity.data.first { $0.name == "#BEAT" }?
              .value ?? 0)) {
          failures[entity.archetype, default: 0] += 1
          if failures.values.reduce(0, +) <= 20 {
            print("SFP NOT PERFECT \(label) \(entity.archetype) grade "
              + "\(judgment.grade) accuracy \(judgment.accuracy) at \(time): "
              + entity.data.map { "\($0.name)=\($0.value ?? .nan)" }
                .joined(separator: " "))
          }
        }
      }
      frame += 1
    }
    print("SFP SCRIPTED \(label): \(seen.count)/\(runtime.inputCount) inputs, "
      + "\(script.restingFlicks) flicks by a resting finger, "
      + "\(script.flickStreams) one-finger flick streams, "
      + "grades \(grades.sorted { $0.key < $1.key }), reversed flicks "
      + "\(reversed.sorted { $0.key < $1.key }), not perfect \(failures)")
    XCTAssertEqual(runtime.resolvedInputCount, runtime.inputCount, label)
    XCTAssertEqual(seen.count, runtime.inputCount, label)
    XCTAssertEqual(failures, [:], label)
    // Reverse flicks are one grade below their (perfect) timing: Great.
    XCTAssertEqual(reversed, script.reversed.isEmpty ? [:]
      : [2: script.reversed.count], label)
    return (script.restingFlicks, script.flickStreams)
  }
}

/// Contacts that play an `sfp` level: one finger per slide chain following
/// its band, and a short press or flick for every other note. The engine's
/// lane geometry is mirrored here (half width min(0.42 w, 1.9)). `sloppy`
/// presses slides a frame late and lifts a frame before their end;
/// `reverseEvery` flicks every n-th directional flick against its arrow.
private struct SFPScript {
  private struct Segment {
    let head: Double, tail: Double
    let headL: Double, headW: Double, tailL: Double, tailW: Double
    let curve: Double, c1: Double, c2: Double

    func center(at time: Double) -> Double {
      let q = min(max((time - head) / (tail - head), 0), 1)
      let r = 1 - q
      let e: Double
      switch curve {
      case 1: e = q * q
      case 2: e = 1 - r * r
      case 3:
        // Quadratic Bezier through control point (c1, c2) / 255.
        let cx = c1 / 255, cy = c2 / 255, a = 1 - 2 * cx
        let s = abs(a) < 1e-6 ? q : (-cx + (max(cx * cx + a * q, 0)).squareRoot()) / a
        e = 2 * (1 - s) * s * cy + s * s
      default: e = q
      }
      let l = headL + (tailL - headL) * e
      let right = headL + headW + (tailL + tailW - headL - headW) * e
      return (l + right) / 2
    }
  }

  private struct Press {
    let time: Double, lane: Double, direction: Double, flick: Bool
    var held = false
    var l = 0.0, w = 0.0
    /// A held flick's slide centre every 30 ms from -120 ms (s0..s6).
    var samples = [Double]()
    var entity = -1
  }

  private var chains = [[Segment]]()
  /// The flick direction a chain's finger starts with, when the slide
  /// starts with a flick: that finger flicks and keeps holding. Other
  /// presses that start a slide are made by the slide's finger too.
  private var chainFlicks = [Int: Double]()
  /// Flicks inside or at the end of a slide, made by the finger tracing it:
  /// (time, direction) per chain.
  private var heldFlicks = [Int: [(time: Double, direction: Double,
    samples: [Double])]]()
  private var presses = [Press]()
  /// Fingers for notes outside slides. Each goes down at its first note and
  /// lifts three frames after its last, without lifting in between: a free
  /// flick may follow a tap with the same finger still resting (within
  /// 0.5 s, same lanes), and flicks up to 0.2 s apart and two lanes away
  /// form one stream flicked by one finger.
  private var strokes = [[Press]]()
  /// Free flicks made by a finger already down, and strokes of two or more
  /// flicks (streams).
  private(set) var restingFlicks = 0, flickStreams = 0
  /// Entity indices of flicks flicked against their arrow.
  private(set) var reversed = Set<Int>()
  private let halfWidth: Double
  private let start: Double
  private let sloppy: Bool

  init(level: LevelData, aspectRatio: Double, start: Double, sloppy: Bool,
    reverseEvery: Int) {
    halfWidth = min(2 * aspectRatio * 0.42, 1.9)
    self.start = start
    self.sloppy = sloppy
    func value(_ entity: LevelEntity, _ name: String) -> Double {
      entity.data.first { $0.name == name }?.value ?? 0
    }
    var directional = 0
    let flickSpots = level.entities.filter { $0.archetype == "FlickNote" }
      .map { (time: value($0, "#BEAT"), lane: value($0, "l") + value($0, "w") / 2) }
    // Slides start at presses: taps, kime notes and flicks that are not held.
    let starts = level.entities.filter {
      $0.archetype == "TapNote" || $0.archetype == "KimeNote"
        || ($0.archetype == "FlickNote" && value($0, "held") == 0)
    }.map { (time: value($0, "#BEAT"), l: value($0, "l"), w: value($0, "w"),
      flick: $0.archetype == "FlickNote") }
    for (index, entity) in level.entities.enumerated() {
      let center = value(entity, "l") + value(entity, "w") / 2
      let time = value(entity, "#BEAT")
      switch entity.archetype {
      case "TapNote" where value(entity, "kind") != 1, "KimeNote":
        presses.append(Press(time: time, lane: center, direction: 0, flick: false,
          l: value(entity, "l"), w: value(entity, "w")))
      case "FlickNote":
        var direction = value(entity, "dir")
        if direction != 0 {
          directional += 1
          // Flicks with another flick close by (streams, sweeps) are not
          // reversed: a reversed swipe may legitimately hit the next one.
          let time = value(entity, "#BEAT"), lane = value(entity, "l")
            + value(entity, "w") / 2
          let alone = !flickSpots.contains { spot in
            spot.time != time && abs(spot.time - time) <= 0.2
              && abs(spot.lane - lane) <= 3 }
          if reverseEvery > 0 && directional % reverseEvery == 0 && alone {
            direction = -direction
            reversed.insert(index)
          }
        }
        presses.append(Press(time: time, lane: center, direction: direction,
          flick: true, held: value(entity, "held") != 0, l: value(entity, "l"),
          w: value(entity, "w"),
          samples: (0..<7).map { value(entity, "s\($0)") }, entity: index))
      case "SlideConnector":
        let segment = Segment(head: value(entity, "headBeat"),
          tail: value(entity, "tailBeat"), headL: value(entity, "headL"),
          headW: value(entity, "headW"), tailL: value(entity, "tailL"),
          tailW: value(entity, "tailW"), curve: value(entity, "curve"),
          c1: value(entity, "c1"), c2: value(entity, "c2"))
        // A segment starting at a pressed note starts a new finger.
        // Otherwise continue a chain whose last segment ends where this one
        // starts, preferring overlapping bands (else an instant jump).
        func continues(_ chain: [Segment], overlapping: Bool) -> Bool {
          let last = chain.last!
          return abs(last.tail - segment.head) < 1e-6 && (!overlapping
            || (last.tailL < segment.headL + segment.headW
              && segment.headL < last.tailL + last.tailW))
        }
        // A flick in the middle of a slide (a chain ends there) is flicked
        // without lifting the slide's finger; any other press starts anew.
        let press = starts.first { abs($0.time - segment.head) < 1e-6
          && $0.l < segment.headL + segment.headW
          && segment.headL < $0.l + $0.w }
        let overlapping = chains.firstIndex { continues($0, overlapping: true) }
        let pressed = press != nil
          && !(press!.flick && overlapping != nil)
        if !pressed, let index = overlapping
          ?? chains.firstIndex(where: { continues($0, overlapping: false) }) {
          chains[index].append(segment)
        } else {
          chains.append([segment])
        }
      default:
        break
      }
    }
    // Held flicks are flicked by the finger of the nearest slide through
    // them.
    for press in presses.indices.reversed() where presses[press].held {
      let flick = presses[press]
      var best: (chain: Int, distance: Double)?
      for (index, chain) in chains.enumerated() {
        for segment in chain where segment.head - 1e-6 <= flick.time
          && flick.time <= segment.tail + 1e-6 {
          let distance = abs(segment.center(at: flick.time) - flick.lane)
          if distance <= flick.w / 2 + 1.5, distance < (best?.distance ?? .infinity) {
            best = (index, distance)
          }
        }
      }
      if let best {
        heldFlicks[best.chain, default: []].append((flick.time, flick.direction,
          flick.samples))
        presses.remove(at: press)
      }
    }
    for (index, chain) in chains.enumerated() {
      let head = chain.first!
      // The note that starts the slide is pressed by the slide's finger.
      if let press = presses.firstIndex(where: { !$0.held
        && abs($0.time - head.head) < 1e-6
        && $0.l < head.headL + head.headW && head.headL < $0.l + $0.w }) {
        if presses[press].flick { chainFlicks[index] = presses[press].direction }
        presses.remove(at: press)
      }
    }
    buildStrokes()
  }

  private mutating func unreverse(_ press: inout Press) {
    if reversed.remove(press.entity) != nil { press = Press(time: press.time,
      lane: press.lane, direction: -press.direction, flick: press.flick,
      held: press.held, l: press.l, w: press.w, samples: press.samples,
      entity: press.entity) }
  }

  private mutating func buildStrokes() {
    for press in presses.sorted(by: { $0.time < $1.time }) {
      let joined = press.flick ? strokes.indices.last { index in
        let last = strokes[index].last!
        let gap = press.time - last.time
        return last.flick
          ? gap > 1e-6 && gap <= 0.2 && abs(last.lane - press.lane) <= 2.5
          : gap >= 0.05 && gap <= 0.5 && abs(last.lane - press.lane) <= 1.5
      } : nil
      // Only extend a stroke whose finger is not needed elsewhere first.
      if let index = joined, !strokes.indices.contains(where: { other in
        other != index && strokes[other].last!.time > strokes[index].last!.time
          && strokes[other].last!.time < press.time
          && abs(strokes[other].last!.lane - press.lane) <= 1.5
      }) {
        var press = press
        if strokes[index].last!.flick {
          if strokes[index].count == 1 { flickStreams += 1 }
          // Flicks in a stream are flicked the arrow's way: a reversed one
          // would change which later flick the swipe may hit.
          var last = strokes[index].removeLast()
          unreverse(&last)
          strokes[index].append(last)
          unreverse(&press)
        } else {
          restingFlicks += 1
        }
        strokes[index].append(press)
      } else {
        strokes.append([press])
      }
    }
  }

  private func x(_ lane: Double) -> Double { (lane / 6 - 1) * halfWidth }

  func nearChainStart(_ time: Double) -> Bool {
    chains.contains { time >= $0.first!.head - 1e-6
      && time <= $0.first!.head + 2.0 / 60 + 1e-6 }
  }

  func touches(frame: Int, time: Double) -> [EngineTouch] {
    let dt = 1.0 / 60
    var result = [EngineTouch]()
    for (index, chain) in chains.enumerated() {
      // On time: press on the first frame at or after the head and release
      // one frame after the tail. Loose: press a frame later and release
      // 100 ms before the tail, within the end's grace; a chain that ends in
      // a flick keeps its finger down to flick.
      let first = chain.first!.head + (sloppy ? dt : 0)
      let last = chain.last!.tail
      let flicks = heldFlicks[index] ?? []
      let endsInFlick = flicks.contains { abs($0.time - last) < 1e-6 }
      let release = sloppy && !endsInFlick ? last - 0.1 : last + dt
      let firstFrameTime = start + ((first - start) / dt - 1e-9).rounded(.up) * dt
      // Frame times carry rounding error; compare with a small tolerance so
      // the release frame always delivers an ended touch.
      guard time >= firstFrameTime - 1e-9, time - dt < release - 1e-9
      else { continue }
      func position(at time: Double) -> Double {
        let segment = chain.first { time <= $0.tail } ?? chain.last!
        return x(segment.center(at: time))
      }
      // A late press still lands where the slide starts.
      let started = time - dt < firstFrameTime - 1e-9
      let point = EnginePoint(
        x: position(at: started ? chain.first!.head : time), y: -0.6)
      // The finger traces the slide exactly in position; a flick adds a
      // quick motion on top.
      // Near a held flick the finger moves as the engine models the slide:
      // its centre samples, standing still above 40 lanes/s.
      func modelSpeed(at time: Double, flick: (time: Double, direction: Double,
        samples: [Double])) -> Double {
        let k = min(max(Int(((time - flick.time) / 0.03).rounded(.down)) + 4, 0), 5)
        let v = (flick.samples[k + 1] - flick.samples[k]) / 0.03
        return (abs(v) > 40 ? 0 : v) * halfWidth / 6
      }
      let h = 1e-3
      var velocity = EnginePoint(x: time + h <= last
        ? (position(at: time + h) - position(at: time)) / h : 0, y: 0)
      if let near = flicks.first(where: {
        time >= $0.time - 0.13 && time < $0.time + 0.07 }) {
        velocity = EnginePoint(x: modelSpeed(at: time, flick: near), y: 0)
      }
      if let direction = chainFlicks[index], time < firstFrameTime + 3 * dt {
        velocity = direction == 0 ? EnginePoint(x: 0, y: 3)
          : EnginePoint(x: 3 * direction, y: 0)
      }
      if let flick = flicks.first(where: {
        time >= $0.time - 1e-9 && time < $0.time + 3 * dt }) {
        // 8 screen units/s on top of the slide's motion: fast enough to
        // read as a flick even against a slide moving the other way.
        let band = modelSpeed(at: time, flick: flick)
        velocity = flick.direction == 0
          ? EnginePoint(x: band, y: 8)
          : EnginePoint(x: band + 8 * flick.direction, y: 0)
      }
      result.append(EngineTouch(id: 1 + index,
        started: started, ended: time >= release - 1e-9,
        time: time, startTime: firstFrameTime,
        position: point, startPosition: point, delta: EnginePoint(x: 0, y: 0),
        velocity: velocity))
    }
    for (index, stroke) in strokes.enumerated() {
      let first = stroke.first!.time, last = stroke.last!.time
      guard time >= first - 1e-9, time - dt < last + 3 * dt - 1e-9 else {
        continue
      }
      // The latest note reached; a flick moves for two frames after it.
      let note = stroke.last { $0.time <= time + 1e-9 }!
      let moving = note.flick && time < note.time + 2 * dt - 1e-9
      let speed = moving ? 3.0 : 0
      let vx = note.direction == 0 ? 0 : speed * note.direction
      let vy = note.direction == 0 ? speed : 0
      let position = EnginePoint(x: x(note.lane), y: -0.6)
      let startPosition = EnginePoint(x: x(stroke.first!.lane), y: -0.6)
      result.append(EngineTouch(id: 100_000 + index,
        started: time - dt < first - 1e-9,
        ended: time >= last + 3 * dt - 1e-9, time: time,
        startTime: start + ((first - start) / dt - 1e-9).rounded(.up) * dt,
        position: position, startPosition: startPosition,
        delta: EnginePoint(x: vx * dt, y: vy * dt),
        velocity: EnginePoint(x: vx, y: vy)))
    }
    return result
  }
}
