import XCTest
import UIKit
import Metal
@testable import OpenRhythm

final class EngineHostTests: XCTestCase {
  func testTouchPoolingPreservesShortTapsAndFlicksAfterStationaryHolds() throws {
    let p = EnginePoint(x: 0, y: 0)
    let start = EngineTouch(id: 1, started: true, ended: false,
      time: 1, startTime: 1, position: p, startPosition: p, delta: p)
    let moved = start.moved(to: EnginePoint(x: 0.1, y: 0.2),
      at: 1.01, ended: false)
    let end = moved.moved(to: moved.position, at: 1.02, ended: true)
    XCTAssertTrue(end.started && end.ended)
    XCTAssertEqual(end.startTime, 1)
    XCTAssertEqual(end.delta, EnginePoint(x: 0.1, y: 0.2))
    XCTAssertEqual(end.velocity?.y ?? 0, 20, accuracy: 0.001)
    let held = start.nextFrame(at: 3)
    XCTAssertEqual(held.time, 1, "Keep the OS event timestamp intact")
    let flick = held.moved(to: EnginePoint(x: 0, y: 0.2), at: 3.01, ended: false)
    XCTAssertFalse(flick.started)
    XCTAssertEqual(flick.velocity?.y ?? 0, 20, accuracy: 0.001)
    XCTAssertEqual(flick.nextFrame(at: 3.02).delta, p)

    let engine = try RuntimeNodeBuilder().engine(archetypes: [])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: []), options: [],
      aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    try runtime.update(at: 3.02, touches: [flick])
    XCTAssertEqual(runtime.memory.value(block: 1002, index: 13), 20, accuracy: 0.001)
    XCTAssertEqual(runtime.memory.value(block: 1002, index: 14), .pi / 2,
      accuracy: 0.001)
  }

  private let quad: [Double] = [-1, -1, -1, 1, 1, 1, 1, -1]

  func testLoopedAudioCommandsHaveIndependentHandlesAndScheduledStops() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    let first = try host.call(function: "PlayLooped", arguments: [8])
    let second = try host.call(function: "PlayLoopedScheduled", arguments: [8, 5])
    XCTAssertNotEqual(first, second)
    _ = try host.call(function: "StopLoopedScheduled", arguments: [second, 6])
    _ = try host.call(function: "StopLooped", arguments: [first])
    _ = try host.call(function: "StopLooped", arguments: [first])
    XCTAssertEqual(host.takeLoopCommands(), [
      .start(id: Int(first), clipID: 8, time: 2),
      .start(id: Int(second), clipID: 8, time: 5),
      .stop(id: Int(second), time: 6), .stop(id: Int(first), time: 2)
    ])
    XCTAssertTrue(host.takeLoopCommands().isEmpty)
    XCTAssertEqual(try host.call(function: "PlayLooped", arguments: [999]), 0)
    XCTAssertThrowsError(try host.call(function: "PlayLoopedScheduled",
      arguments: [8, .nan]))
    try host.beginFrame(at: 7)
    _ = try host.call(function: "StopLooped", arguments: [second])
    XCTAssertTrue(host.takeLoopCommands().isEmpty)
  }

  @MainActor
  func testStoppedLoopsReleaseCapacityWithinTheSameBatch() throws {
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      MockEffectVoice()
    }
    let commands = (1...257).flatMap { id -> [EngineLoopCommand] in
      [.start(id: id, clipID: 8, time: 0), .stop(id: id, time: 0)]
    }
    XCTAssertNoThrow(try audio.update([], at: 0, loopCommands: commands))
    let scheduled = (300..<556).flatMap { id -> [EngineLoopCommand] in
      [.start(id: id, clipID: 8, time: 10), .stop(id: id, time: 11)]
    }
    try audio.update([], at: 0, loopCommands: scheduled)
    XCTAssertNoThrow(try audio.update([], at: 11, loopCommands: [
      .start(id: 600, clipID: 8, time: 11)
    ]))
    audio.stop()
  }

  @MainActor
  func testLoopedPlaybackSchedulesStopsAndResumesAfterBuffering() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([], at: 0, loopCommands: [
      .start(id: 1, clipID: 8, time: 0),
      .start(id: 2, clipID: 8, time: 1), .stop(id: 2, time: 2)
    ])
    XCTAssertEqual(voices.filter(\.isPlaying).count, 1)
    let first = try XCTUnwrap(voices.first { $0.isPlaying })
    XCTAssertEqual(first.looping, [true])
    try audio.update([], at: 0.6)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 2)
    let second = try XCTUnwrap(voices.first { $0 !== first && $0.isPlaying })
    XCTAssertEqual(second.delays.last ?? -1, 0.4, accuracy: 0.000001)
    try audio.update([], at: 0.7, advancing: false)
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    try audio.update([], at: 0.7)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 2)
    try audio.update([], at: 1.6)
    XCTAssertTrue(voices.contains { abs(($0.stopDelays.last ?? -1) - 0.4) < 0.000001 })
    try audio.update([], at: 2.1)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 1)
    try audio.update([], at: 2.1, loopCommands: [.stop(id: 1, time: 2.1)])
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    try audio.update([], at: 3, loopCommands: [
      .start(id: 3, clipID: 8, time: 5), .stop(id: 3, time: 4)
    ])
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    try audio.update([], at: 3, loopCommands: [.start(id: 4, clipID: 8, time: 3)])
    audio.stop()
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    XCTAssertEqual(audio.allocatedVoiceCount, 8)
  }

  func testStreamsInterpolateAndPreserveKeysAcrossFrames() throws {
    let host = makeHost()
    func call(_ function: String, _ values: [Double]) throws -> Double {
      try host.call(function: function, arguments: values)
    }
    XCTAssertEqual(try call("StreamGetValue", [0, 2]), 0)
    XCTAssertEqual(try call("StreamGetNextKey", [0, 2]), 2)
    XCTAssertEqual(try call("StreamGetPreviousKey", [0, 2]), 2)
    _ = try call("StreamSet", [0, 10, 100])
    _ = try call("StreamSet", [0, 0, 0])
    _ = try call("StreamSet", [0, 5, 40])
    _ = try call("StreamSet", [0, 5, 50])
    _ = try call("StreamSet", [1, 5, 999])
    try host.beginFrame(at: 20)
    for (key, expected) in [(-1.0, 0.0), (0, 0), (2.5, 25),
      (5, 50), (7.5, 75), (10, 100), (11, 100)] {
      XCTAssertEqual(try call("StreamGetValue", [0, key]), expected)
    }
    XCTAssertEqual(try call("StreamGetValue", [1, 5]), 999)
    XCTAssertEqual(try call("StreamHas", [0, 5]), 1)
    XCTAssertEqual(try call("StreamHas", [0, 2.5]), 0)
    XCTAssertEqual(try call("StreamGetNextKey", [0, 5]), 10)
    XCTAssertEqual(try call("StreamGetNextKey", [0, 2.5]), 5)
    XCTAssertEqual(try call("StreamGetPreviousKey", [0, 5]), 0)
    XCTAssertEqual(try call("StreamGetPreviousKey", [0, 7.5]), 5)
    XCTAssertEqual(try call("StreamGetPreviousKey", [0, -1]), -1)
    XCTAssertEqual(try call("StreamGetNextKey", [0, 11]), 11)
    XCTAssertThrowsError(try call("StreamSet", [0, .nan, 1]))
    XCTAssertThrowsError(try call("StreamSet", [-1, 0, 1]))
    XCTAssertThrowsError(try call("StreamSet", [0.5, 0, 1]))
    _ = try call("StreamSet", [2, -Double.greatestFiniteMagnitude, -100])
    _ = try call("StreamSet", [2, Double.greatestFiniteMagnitude, 100])
    XCTAssertEqual(try call("StreamGetValue", [2, 0]), 0)
  }

  func testStreamBudgetCountsAllStreamsButAllowsReplacement() throws {
    let host = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0,
      streamEntryLimit: 2)
    _ = try host.call(function: "StreamSet", arguments: [0, 0, 1])
    _ = try host.call(function: "StreamSet", arguments: [1, 0, 2])
    _ = try host.call(function: "StreamSet", arguments: [0, 0, 3])
    XCTAssertThrowsError(try host.call(function: "StreamSet", arguments: [2, 0, 4]))
    XCTAssertEqual(try host.call(function: "StreamGetValue", arguments: [0, 0]), 3)
    XCTAssertEqual(try host.call(function: "StreamHas", arguments: [2, 0]), 0)
  }

  func testMovingParticlesPreservesLifetimeAndRefreshesTransform() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    let id = try host.call(function: "SpawnParticleEffect",
      arguments: [9] + quad + [3, 0])
    let before = try XCTUnwrap(host.particles[Int(id)])
    try host.beginFrame(at: 3)
    host.memory.set(block: 1004, index: 0, value: 2)
    _ = try host.call(function: "MoveParticleEffect",
      arguments: [id] + quad.map { $0 * 2 })
    let moved = try XCTUnwrap(host.particles[Int(id)])
    XCTAssertEqual(moved.startTime, before.startTime)
    XCTAssertEqual(moved.duration, before.duration)
    XCTAssertEqual(moved.points[0], EnginePoint(x: -2, y: -2))
    XCTAssertEqual(moved.transform[0], 2)
    _ = try host.call(function: "MoveParticleEffect", arguments: [999] + quad)
    XCTAssertEqual(host.particles.count, 1)
    try host.beginFrame(at: 5)
    XCTAssertTrue(host.particles.isEmpty)
  }

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
    for (beat, value) in [(-2.0, 120.0), (3.999, 120), (4, 60), (20, 60)] {
      XCTAssertEqual(try host.call(function: "BeatToBPM", arguments: [beat]), value)
    }
    XCTAssertEqual(try makeHost().call(function: "BeatToBPM", arguments: [10]), 60)
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
    func render(_ image: UIImage, points: [EnginePoint], layers: [UIImage]? = nil)
      throws -> [UInt8] {
      let command = try XCTUnwrap(renderer.queue.makeCommandBuffer())
      let sprites = (layers ?? [image]).map {
        EngineRenderSprite(image: $0, points: points,
          matrix: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
          alpha: 0.5, interpolation: false)
      }
      try renderer.encode(sprites,
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
  var looping = [Bool]()
  var stopDelays = [Double]()
  var stopCount = 0

  func play(after delay: Double, looped: Bool) {
    delays.append(delay)
    looping.append(looped)
    isPlaying = true
  }

  func stop(after delay: Double) {
    stopDelays.append(delay)
    if delay <= 0 { stop() }
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
