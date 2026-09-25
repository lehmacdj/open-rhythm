import XCTest
import UIKit
import Metal
import AVFoundation
@testable import OpenRhythm

final class EngineHostTests: XCTestCase {
  func testPlayMemoryInitialValuesPrecedeCallbacksAndSurviveRestart() throws {
    // Expected values come from the public play-block tables, not a sampled
    // engine's initialization code. Check full defined blocks, including zeros.
    // Temporary Memory has unpredictable initial values by contract; neither
    // callback selection nor restart promises to restore its scratch contents.
    let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    let background: [Double] = [-2,-0.8, -2,0.8, 2,0.8, 2,-0.8]
    let visibility: [Double] = [1,0.9, 0.8,0.7, 0.6,0.5, 0.4,0.3, 0.2,0.1]
    func zeros(_ count: Int) -> [Double] { Array(repeating: 0, count: count) }
    var data = zeros(64)
    data[3] = 7
    data[35] = 9
    let shared: [(Int, [Double])] = [
      (1000, [1,2,0.02,-0.03,0,-1.8,1.7,-0.9,0.8]),
      (1001, zeros(5)), (1002, []), (1003, identity), (1004, identity),
      (1005, background), (1006, zeros(80)), (1007, visibility),
      (2000, zeros(4096)), (2001, zeros(4096)), (2002, [0.25,0.75]),
      (2003, zeros(6)), (2004, zeros(12)),
      (2005, [0,0,0,0,0,0,1000,1000]), (3000, [1.5,-2]),
      (4101, data), (4102, zeros(64)), (4103, [0,0,0,1,1,0]),
      (4106, zeros(2)), (4107, zeros(8)), (5000, zeros(8)), (5001, [1,1])
    ]
    func entityBlocks(_ entity: Int) -> [(Int, [Double])] {
      [(4000, zeros(64)), (4001, Array(data[(entity * 32)..<(entity * 32 + 32)])),
       (4002, zeros(32)), (4003, [Double(entity),Double(entity),0]),
       (4004, [0]), (4005, [0,0,-1,0,0]), (4006, [0]), (4007, zeros(4))]
    }
    let b = RuntimeNodeBuilder()
    // Observe every nonzero default and each block's boundary from inside
    // preprocessing, before any engine writes can mask a missing host default.
    let sampled = (shared + entityBlocks(0)).flatMap { block, values in
      values.indices.filter { $0 == 0 || $0 == values.count - 1 || values[$0] != 0 }
        .map { (block, $0) }
    }
    let capture = b.call("Execute", sampled.enumerated().map { slot, address in
      b.call("ExportValue", [b.value(Double(slot)), b.call("Get", [
        b.value(Double(address.0)), b.value(Double(address.1))])])
    })
    let engine = try b.engine(archetypes: (0..<2).map { index in
      ["name": "Probe\(index)", "hasInput": true,
       "imports": [["name": "value", "index": 3]],
       "exports": sampled.indices.map { "value\($0)" },
       "preprocess": ["index": capture]]
    }, buckets: [["sprites": []]])
    let rom = Data([0x00,0x00,0xc0,0x3f, 0x00,0x00,0x00,0xc0])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: (0..<2).map { index in
        LevelEntity(archetype: "Probe\(index)", name: nil, data: [
          LevelEntityData(name: "value", value: index == 0 ? 7 : 9, ref: nil)])
      }), options: [0.25,0.75], aspectRatio: 2, skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [], rom: rom,
      uiConfiguration: visibility, safeArea: [-1.8,1.7,-0.9,0.8],
      inputOffset: -0.03, audioOffset: 0.02, debugMode: true,
      backgroundQuad: background)
    for _ in 0..<2 {
      for entity in 0..<2 {
        runtime.memory.selectEntity(key: entity, index: entity)
        let blocks = shared + entityBlocks(entity)
        let expected = Dictionary(uniqueKeysWithValues: blocks)
        for (block, values) in blocks {
          XCTAssertEqual(values.indices.map {
            runtime.memory.value(block: block, index: $0)
          }, values, "Initial block \(block), entity \(entity)")
        }
        for (slot, address) in sampled.enumerated() {
          XCTAssertEqual(runtime.host.exports[entity]?[slot],
            expected[address.0]?[address.1],
            "Preprocess observed block \(address.0), index \(address.1)")
        }
      }
      try runtime.update(at: 0.5)
      // Mutate the prepared state through host bookkeeping. Restart must
      // restore defaults as well as explicit engine preprocessing writes.
      for (block, values) in shared where block != 3000 {
        for index in values.indices {
          runtime.memory.set(block: block, index: index, value: 123)
        }
      }
      for entity in 0..<2 {
        runtime.memory.selectEntity(key: entity, index: entity)
        for (block, values) in entityBlocks(entity) {
          for index in values.indices {
            runtime.memory.set(block: block, index: index, value: 123)
          }
        }
      }
      runtime.restart()
    }
  }

  func testScheduledLifeRejectsEveryNonPreprocessingCallback() throws {
    for callback in EngineMemory.Callback.allCases {
      let builder = RuntimeNodeBuilder()
      let add = builder.call("AddLifeScheduled", [
        builder.value(-10), builder.value(2)])
      var archetype: [String: Any] = ["name": "Probe", "hasInput": false,
        "imports": [], "exports": [], callback.rawValue: ["index": add]]
      if callback == .terminate {
        archetype["updateSequential"] = ["index": builder.call("Set", [
          builder.value(4004), builder.value(0), builder.value(1)])]
      }
      let engine = try builder.engine(archetypes: [archetype])
      func prepare() throws -> EnginePlayRuntime {
        try EnginePlayRuntime(engine: engine,
          level: LevelData(bgmOffset: 0, entities: [
            LevelEntity(archetype: "Probe", name: nil, data: [])]),
          options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
          particleEffectIDs: [])
      }
      func check(_ error: Error) {
        guard case EngineInterpreterError.invalidFunctionCallback(
          let name, let phase) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(name, "AddLifeScheduled")
        XCTAssertEqual(phase, callback.rawValue)
        XCTAssertTrue(error.localizedDescription.contains(callback.rawValue))
      }
      if callback == .spawnOrder {
        XCTAssertThrowsError(try prepare(), "Only preprocessing may schedule life",
          check)
        continue
      }
      let runtime = try prepare()
      let point = EnginePoint(x: 0, y: 0)
      let touch = EngineTouch(id: 1, started: true, ended: false, time: 0,
        startTime: 0, position: point, startPosition: point, delta: point)
      if callback == .preprocess {
        for _ in 0..<2 {
          try runtime.update(at: 0)
          XCTAssertEqual(runtime.life.value, 1000)
          try runtime.update(at: 2)
          XCTAssertEqual(runtime.life.value, 990)
          try runtime.update(at: 3)
          XCTAssertEqual(runtime.life.value, 990)
          runtime.restart()
        }
      } else {
        XCTAssertThrowsError(try runtime.update(at: 0, touches: [touch]),
          "Only preprocessing may schedule life", check)
        XCTAssertTrue(runtime.host.takeScheduledLife(at: 10).isEmpty,
          "Rejected calls must not enqueue a life change")
      }
      XCTAssertNil(runtime.memory.callback)
    }
  }

  func testLifeScheduleOrdersEqualTimesAndRestoresConsumedCursor() throws {
    let host = makeHost()
    for (amount, time) in [(3.0, 3.0), (1, 1), (2, 1), (-5, 2)] {
      _ = try host.call(function: "AddLifeScheduled", arguments: [amount, time])
    }
    let prepared = host.makeRestorePoint()
    for _ in 0..<2 {
      XCTAssertTrue(host.takeScheduledLife(at: 0).isEmpty)
      XCTAssertEqual(host.takeScheduledLife(at: 1), [1, 2])
      let partial = host.makeRestorePoint()
      XCTAssertEqual(host.takeScheduledLife(at: 3), [-5, 3])
      XCTAssertTrue(host.takeScheduledLife(at: 4).isEmpty)
      partial()
      XCTAssertEqual(host.takeScheduledLife(at: 3), [-5, 3])
      prepared()
    }
    _ = host.takeScheduledLife(at: 1)
    _ = try host.call(function: "AddLifeScheduled", arguments: [8, 2])
    XCTAssertEqual(host.takeScheduledLife(at: 3), [-5, 8, 3],
      "Host bookkeeping must not replay consumed events when appending")
  }

  func testDebugFunctionsGateSideEffectsBoundLogsAndRestorePreprocessing() throws {
    let host = makeHost()
    XCTAssertEqual(try host.call(function: "DebugLog", arguments: [3]), 0)
    XCTAssertEqual(try host.call(function: "DebugPause", arguments: []), 0)
    XCTAssertTrue(host.debugLog.isEmpty)
    XCTAssertFalse(host.takeDebugPause())
    host.memory.set(block: 1000, index: 0, value: 1)
    XCTAssertThrowsError(try host.call(function: "DebugLog", arguments: []))
    XCTAssertThrowsError(try host.call(function: "DebugPause", arguments: [1]))
    _ = try host.call(function: "DebugLog", arguments: [42])
    _ = try host.call(function: "DebugPause", arguments: [])
    let restore = host.makeRestorePoint()
    XCTAssertTrue(host.takeDebugPause())
    XCTAssertFalse(host.takeDebugPause())
    for value in 0..<300 {
      _ = try host.call(function: "DebugLog", arguments: [Double(value)])
    }
    XCTAssertEqual(host.debugLog.count, 256)
    XCTAssertEqual(host.debugLog.first?.value, "44.0")
    XCTAssertEqual(host.debugLog.last?.value, "299.0")
    XCTAssertEqual(Set(host.debugLog.map(\.id)).count, 256)
    _ = try host.call(function: "DebugLog", arguments: [.nan])
    XCTAssertEqual(host.debugLog.last?.value, "nan")
    restore()
    XCTAssertEqual(host.debugLog.map(\.value), ["42.0"])
    XCTAssertTrue(host.takeDebugPause())
  }

  func testDebugGuardedGraphsPreflightAndUseEffectiveEnvironmentOnRestart() throws {
    let b = RuntimeNodeBuilder()
    let log = b.call("DebugLog", [b.value(8)])
    let pause = b.call("DebugPause", [])
    let debug = b.call("Get", [b.value(1000), b.value(0)])
    let guarded = b.call("If", [debug, b.call("Execute", [log, pause]), b.value(0)])
    let engine = try b.engine(archetypes: [["name": "Probe", "hasInput": false,
      "imports": [], "exports": [], "preprocess": ["index": guarded],
      "updateSequential": ["index": guarded]]])
    XCTAssertTrue(try engine.unsupportedFunctions().isEmpty)
    for enabled in [false, true] {
      let runtime = try EnginePlayRuntime(engine: engine,
        level: LevelData(bgmOffset: 0, entities: [
          LevelEntity(archetype: "Probe", name: nil, data: [])]), options: [],
        aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [],
        debugMode: enabled)
      XCTAssertEqual(runtime.host.debugLog.count, enabled ? 1 : 0)
      XCTAssertEqual(runtime.host.takeDebugPause(), enabled)
      try runtime.update(at: 1)
      XCTAssertEqual(runtime.host.debugLog.count, enabled ? 2 : 0)
      XCTAssertEqual(runtime.host.takeDebugPause(), enabled)
      runtime.restart()
      XCTAssertEqual(runtime.host.debugLog.count, enabled ? 1 : 0)
      XCTAssertEqual(runtime.host.takeDebugPause(), enabled)
    }
    for supplied in [false, true] {
      let override = b.call("Set", [b.value(1000), b.value(0),
        b.value(supplied ? 0 : 1)])
      let preprocess = b.call("Execute", [override, guarded])
      let overridingEngine = try b.engine(archetypes: [["name": "Probe",
        "hasInput": false, "imports": [], "exports": [],
        "preprocess": ["index": preprocess]]])
      let runtime = try EnginePlayRuntime(engine: overridingEngine,
        level: LevelData(bgmOffset: 0, entities: [
          LevelEntity(archetype: "Probe", name: nil, data: [])]), options: [],
        aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [],
        debugMode: supplied)
      XCTAssertEqual(runtime.host.isDebugMode, !supplied)
      XCTAssertEqual(runtime.host.takeDebugPause(), !supplied)
      XCTAssertEqual(runtime.host.debugLog.count, supplied ? 0 : 1)
    }
  }

  func testPauseClearsContactsWithoutReusingRuntimeTouchIDs() {
    var pool = EngineTouchPool<Int>()
    let point = EnginePoint(x: 0, y: 0)
    pool.beginPlayback(generation: 1)
    pool.receive(key: 1, position: point, time: 0, started: true, ended: false)
    let first = pool.touches.first?.id
    pool.beginPlayback(generation: 1, inputGeneration: 1)
    pool.receive(key: 1, position: point, time: 1, started: false, ended: false)
    XCTAssertTrue(pool.touches.isEmpty)
    pool.receive(key: 2, position: point, time: 1, started: true, ended: false)
    XCTAssertNotEqual(pool.touches.first?.id, first)
  }

  @MainActor
  func testNativeEffectPauseRetainsSamplePosition() throws {
    for looped in [false, true] {
      let engine = AVAudioEngine()
      defer { engine.stop() }
      let format = try XCTUnwrap(AVAudioFormat(
        standardFormatWithSampleRate: 48000, channels: 1))
      let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 4096))
      source.frameLength = 4096
      for frame in 0..<4096 {
        source.floatChannelData![0][frame] = Float(frame) / 8192
      }
      let voice = NativeEffectVoice(engine: engine, buffer: source)
      try engine.enableManualRenderingMode(.offline, format: format,
        maximumFrameCount: 512)
      let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 512))
      try engine.start()
      voice.play(after: 0, looped: looped)
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][511], Float(511) / 8192,
        accuracy: 1e-6)
      voice.pause()
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertTrue((0..<512).allSatisfy {
        abs(output.floatChannelData![0][$0]) < 1e-6
      })
      engine.pause()
      try engine.start()
      voice.resume()
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][0], Float(512) / 8192,
        accuracy: 1e-6, "Resume continues the sample; it must not replay or skip")
      voice.stop()
    }
  }

  @MainActor
  func testPauseRetainsReservationThatBecameDueBetweenFrames() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.04,
      minimumDistance: 0.1)], at: 0)
    let active = try XCTUnwrap(voices.first { !$0.delays.isEmpty })
    audio.pause(at: 0.05)
    XCTAssertEqual(active.stopCount, 0)
    XCTAssertEqual(active.pauseCount, 1)
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.06,
      minimumDistance: 0.1)], at: 0.05)
    XCTAssertEqual(active.resumeCount, 1)
    XCTAssertEqual(voices.flatMap(\.delays), [0.04],
      "Resume must neither replay a due reservation nor forget minimum distance")
    audio.stop()
  }

  @MainActor
  func testDebugPausePreservesActiveSamplesAndReschedulesFutureAudio() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0, minimumDistance: 0),
      EngineAudioCommand(clipID: 1, time: 0.4, minimumDistance: 0)
    ], at: 0, loopCommands: [
      .start(id: 1, clipID: 1, time: 0), .stop(id: 1, time: 0.5),
      .start(id: 2, clipID: 1, time: 0.4)])
    XCTAssertEqual(voices.flatMap(\.delays).count, 4)
    audio.pause(at: 0.1)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.pauseCount }, 2)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 2)
    try audio.update([], at: 0.1, advancing: false)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.resumeCount }, 0)
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.resumeCount }, 2)
    XCTAssertEqual(voices.flatMap(\.delays).count, 6)
    XCTAssertEqual(voices.flatMap(\.stopDelays).sorted(), [0.4, 0.5])
    audio.pause(at: 0.2)
    audio.stop()
    let starts = voices.flatMap(\.delays).count
    try audio.update([], at: 0.3)
    XCTAssertEqual(voices.flatMap(\.delays).count, starts,
      "Stop discards paused commands; they must not leak into another play")
  }

  func testRuntimeTouchBoundsShrinkAndRestoreOnRestart() throws {
    let b = RuntimeNodeBuilder()
    let secondID = b.call("Get", [b.value(1002), b.value(15)])
    let capture = b.call("Set", [b.value(4000), b.value(0), secondID])
    let engine = try b.engine(archetypes: [["name": "Probe", "hasInput": false,
      "imports": [], "exports": [], "updateSequential": ["index": capture]]])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Probe", name: nil, data: [])]), options: [],
      aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    let point = EnginePoint(x: 0, y: 0)
    func touch(_ id: Int) -> EngineTouch {
      EngineTouch(id: id, started: true, ended: false, time: 0, startTime: 0,
        position: point, startPosition: point, delta: point)
    }
    for _ in 0..<2 {
      XCTAssertEqual(runtime.memory.value(block: 1002, index: 15), 0)
      try runtime.update(at: 0, touches: [touch(10), touch(20)])
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 0), 20)
      try runtime.update(at: 1, touches: [touch(10)])
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 0), 0)
      XCTAssertEqual(runtime.memory.value(block: 1002, index: 15), 0)
      try runtime.update(at: 2)
      XCTAssertEqual(runtime.memory.value(block: 1002, index: 0), 0)
      runtime.restart()
    }
  }

  func testRuntimeEstablishesAndClearsEveryMemoryCallbackContext() throws {
    for phase in EngineMemory.Callback.allCases {
      let b = RuntimeNodeBuilder()
      let write = b.call("Set", [b.value(2001), b.value(0), b.value(1)])
      let despawn = b.call("Set", [b.value(4004), b.value(0), b.value(1)])
      var archetype: [String: Any] = ["name": "Probe", "hasInput": false,
        "imports": [], "exports": [], phase.rawValue: ["index": write]]
      if phase == .terminate {
        archetype["updateSequential"] = ["index": despawn]
      }
      let engine = try b.engine(archetypes: [archetype])
      func prepare() throws -> EnginePlayRuntime {
        try EnginePlayRuntime(engine: engine,
          level: LevelData(bgmOffset: 0, entities: [
            LevelEntity(archetype: "Probe", name: nil, data: [])]),
          options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
          particleEffectIDs: [])
      }
      func check(_ error: Error) {
        guard case EngineInterpreterError.invalidMemoryAccess(
          let block, let callback, let write) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(block, 2001)
        XCTAssertEqual(callback, phase.rawValue)
        XCTAssertTrue(write)
      }
      if phase == .spawnOrder {
        XCTAssertThrowsError(try prepare(), "spawnOrder cannot write LevelData",
          check)
        continue
      }
      let runtime = try prepare()
      XCTAssertNil(runtime.memory.callback)
      let point = EnginePoint(x: 0, y: 0)
      let touch = EngineTouch(id: 1, started: true, ended: false, time: 0,
        startTime: 0, position: point, startPosition: point, delta: point)
      if phase == .preprocess {
        try runtime.update(at: 0, touches: [touch])
        XCTAssertEqual(runtime.memory.value(block: 2001, index: 0), 1)
      } else {
        XCTAssertThrowsError(try runtime.update(at: 0, touches: [touch]),
          phase.rawValue, check)
        XCTAssertEqual(runtime.memory.value(block: 2001, index: 0), 0)
      }
      XCTAssertNil(runtime.memory.callback, "Clear context even after errors")
      runtime.restart()
      XCTAssertNil(runtime.memory.callback)
    }
  }

  func testActiveCallbackOrderSurvivesSpawnDespawnAndRestart() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Double, _ index: Double) -> Int {
      b.call("Get", [b.value(block), b.value(index)])
    }
    func set(_ block: Double, _ index: Double, _ value: Int) -> Int {
      b.call("Set", [b.value(block), b.value(index), value])
    }
    let marker = get(4000, 0)
    func log(_ index: Double) -> Int {
      set(2000, index, b.call("Add", [
        b.call("Multiply", [get(2000, index), b.value(10)]), marker]))
    }
    let now = get(1001, 0)
    let prepare = b.call("Execute", [set(4000, 0, get(4001, 0)),
      set(4000, 1, get(4001, 2))])
    let expire = set(4004, 0, b.call("GreaterOr", [now, get(4000, 1)]))
    let sequential = b.call("Execute", [log(0), expire])
    let spawnAt = get(4001, 1)
    func archetype(_ name: String, sequentialOrder: Double, touchOrder: Double)
      -> [String: Any] {
      ["name": name, "hasInput": false,
        "imports": [["name": "marker", "index": 0],
          ["name": "start", "index": 1], ["name": "end", "index": 2]],
        "exports": [], "preprocess": ["index": prepare],
        "spawnOrder": ["index": spawnAt],
        "shouldSpawn": ["index": b.call("GreaterOr", [now, spawnAt])],
        "updateSequential": ["index": sequential, "order": sequentialOrder],
        "touch": ["index": log(1), "order": touchOrder]]
    }
    let dynamic = b.call("Spawn", [b.value(0), b.value(9), b.value(3)])
    let engine = try b.engine(archetypes: [
      archetype("A", sequentialOrder: 0.5, touchOrder: -0.5),
      archetype("B", sequentialOrder: -0.5, touchOrder: 0.5),
      ["name": "Spawner", "hasInput": false, "imports": [], "exports": [],
        "initialize": ["index": dynamic]],
      ["name": "NoCallbacks", "hasInput": false, "imports": [], "exports": []]])
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[
        {"archetype":"A","data":[{"name":"marker","value":1},
          {"name":"start","value":0},{"name":"end","value":2}]},
        {"archetype":"B","data":[{"name":"marker","value":2},
          {"name":"start","value":0},{"name":"end","value":10}]},
        {"archetype":"A","data":[{"name":"marker","value":3},
          {"name":"start","value":1},{"name":"end","value":10}]},
        {"archetype":"Spawner","data":[]},
        {"archetype":"NoCallbacks","data":[]}]}
      """#.utf8))
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    let point = EnginePoint(x: 0, y: 0)
    for _ in 0..<2 {
      for (frame, expected) in [(21, 12), (2139, 1392), (2139, 1392),
        (239, 392), (23, 32)].enumerated() {
        runtime.memory.set(block: 2000, index: 0, value: 0)
        runtime.memory.set(block: 2000, index: 1, value: 0)
        try runtime.update(at: Double(frame), touches: [EngineTouch(id: 1,
          started: frame == 0, ended: false, time: Double(frame), startTime: 0,
          position: point, startPosition: point, delta: point)])
        XCTAssertEqual(runtime.memory.value(block: 2000, index: 0),
          Double(expected.0), "Sequential order at frame \(frame)")
        XCTAssertEqual(runtime.memory.value(block: 2000, index: 1),
          Double(expected.1), "Touch order at frame \(frame)")
      }
      runtime.restart()
    }
  }

  func testStableActiveCallbackWorkload() throws {
    let b = RuntimeNodeBuilder()
    let noOp = b.value(0)
    let archetypes: [[String: Any]] = (0..<32).map { index in
      ["name": "A\(index)", "hasInput": false, "imports": [], "exports": [],
        "updateSequential": ["index": noOp, "order": Double(31 - index) / 2],
        "touch": ["index": noOp, "order": Double(index) / 2]]
    }
    let engine = try b.engine(archetypes: archetypes)
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: (0..<512).map {
        LevelEntity(archetype: "A\($0 % 32)", name: nil, data: [])
      }), options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    try runtime.update(at: 0)
    let point = EnginePoint(x: 0, y: 0)
    let start = ProcessInfo.processInfo.systemUptime
    for frame in 1...300 {
      try runtime.update(at: Double(frame) / 60, touches: [EngineTouch(id: 1,
        started: false, ended: false, time: Double(frame) / 60, startTime: 0,
        position: point, startPosition: point, delta: point)])
    }
    let duration = ProcessInfo.processInfo.systemUptime - start
    print("Stable 512-entity callback workload: \(duration * 1000 / 300) ms/frame")
    XCTAssertEqual(runtime.memory.value(block: 4103, index: 511 * 3 + 2), 1)
  }

  @MainActor
  func testGameplayIntroStopsForVisualEffectBeforeMusic() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "OpeningEffect")
  }

  @MainActor
  func testGameplayIntroPreservesHeldInitialStageNamedEffect() async throws {
    try await checkGameplayIntro(appearanceTime: 0, spriteName: "#LANE")
  }

  @MainActor
  func testGameplayIntroRewindDiscardsFutureJudgmentAndSpawn() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
      rewind: true)
  }

  @MainActor
  func testGameplayIntroPassesEarlyInputActivationUntilNoteIsVisible() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "EarlyNote",
      earlyInput: true)
  }

  @MainActor
  func testGameplayIntroRewindsInsteadOfConsumingAnInvisibleInput() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "HiddenNote",
      earlyInput: true, resolveAt: 0.25)
  }

  @MainActor
  func testGameplayIntroStopsAtMusicBeforeEarlyActivatedNoteAppears() async throws {
    try await checkGameplayIntro(appearanceTime: 2.5, spriteName: "LaterNote",
      earlyInput: true)
  }

  @MainActor
  func testGameplayIntroRestoresDebugPauseWithInitialJudgment() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "DebugNote",
      earlyInput: true, resolveAt: 0, debugAtResolution: true)
  }

  @MainActor
  func testGameplayIntroVisualOnlyRewindDiscardsFutureSpawn() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
      rewind: true, resolvesFutureInput: false)
  }

  @MainActor
  func testGameplayIntroPreservesScheduledLifeChanges() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "LifeNote",
      earlyInput: true, lifeChangeAt: 0.25)
  }

  @MainActor
  private func checkGameplayIntro(appearanceTime: Double, spriteName: String,
    rewind: Bool = false, earlyInput: Bool = false,
    resolveAt: Double? = nil, debugAtResolution: Bool = false,
    resolvesFutureInput: Bool = true, lifeChangeAt: Double? = nil) async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("visual-intro-\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000,
      channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: 24000))
    buffer.frameLength = 24000
    for frame in 0..<24000 {
      buffer.floatChannelData![0][frame] = frame < 16000 ? 0 : 0.1
    }
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }
    let b = RuntimeNodeBuilder()
    let now = b.call("Get", [b.value(1001), b.value(0)])
    let visible = b.call("GreaterOr", [now, b.value(appearanceTime)])
    let draw = b.call("Draw", [b.value(1)] + quad.map(b.value)
      + [b.value(0), b.value(1)])
    let offscreenQuad = quad.enumerated().map { index, value in
      b.value(index.isMultiple(of: 2) ? value : value + 4)
    }
    let offscreenDraw = b.call("Draw", [b.value(1)] + offscreenQuad
      + [b.value(0), b.value(1)])
    let effect = b.call("If", [visible, draw,
      earlyInput ? offscreenDraw : b.value(0)])
    var archetypes: [[String: Any]] = [[
      "name": "OpeningEffect", "hasInput": earlyInput,
      "imports": [], "exports": [],
      "updateParallel": ["index": rewind ? draw : effect]]]
    if let resolveAt {
      let due = b.call("GreaterOr", [now, b.value(resolveAt)])
      var actions = [b.call("Set", [b.value(4004), b.value(0), b.value(1)])]
      if debugAtResolution {
        archetypes[0]["preprocess"] = ["index": b.call("Set",
          [b.value(1000), b.value(0), b.value(1)])]
        actions += [b.call("DebugLog", [b.value(17)]), b.call("DebugPause", [])]
      }
      archetypes[0]["updateSequential"] = ["index": b.call("If",
        [due, b.call("Execute", actions), b.value(0)])]
    }
    if let lifeChangeAt {
      archetypes[0]["preprocess"] = ["index": b.call("AddLifeScheduled",
        [b.value(-100), b.value(lifeChangeAt)])]
    }
    var entities = [LevelEntity(archetype: "OpeningEffect", name: nil, data: [])]
    if rewind {
      let actions = b.call("Execute", [
        b.call("Set", [b.value(1005), b.value(0), b.value(0)]),
        b.call("Set", [b.value(4005), b.value(0), b.value(1)]),
        b.call("Set", [b.value(4004), b.value(0), b.value(1)]),
        b.call("Spawn", [b.value(0)])])
      archetypes.append(["name": "FutureNote", "hasInput": resolvesFutureInput,
        "imports": [], "exports": [], "shouldSpawn": ["index": visible],
        "updateSequential": ["index": actions]])
      entities.append(LevelEntity(archetype: "FutureNote", name: nil, data: []))
    }
    let engine = try b.engine(archetypes: archetypes,
      sprites: [["name": spriteName, "id": 1]])
    if rewind { XCTAssertEqual(engine.staticIntroArchetypes, [0]) }
    let pngFormat = UIGraphicsImageRendererFormat()
    pngFormat.scale = 1
    let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2),
      format: pngFormat).pngData {
        UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    let resources = RuntimePresentation(resources: [
      "configuration": Data(#"{"options":[]}"#.utf8),
      "skinTexture": png,
      "skinData": Data(#"""
        {"width":2,"height":2,"interpolation":false,"sprites":[
          {"name":"\#(spriteName)","x":0,"y":0,"w":2,"h":2,"transform":{
            "x1":{"x1":1},"y1":{"y1":1},"x2":{"x2":1},"y2":{"y2":1},
            "x3":{"x3":1},"y3":{"y3":1},"x4":{"x4":1},"y4":{"y4":1}}}]}
        """#.utf8)])
    let locator = ResourceLocator(hash: nil, url: nil)
    let item = SonolusLevelItem(name: "visual-intro", source: nil,
      version: 1, rating: 1, title: LocalizedText("Visual Intro"),
      artists: LocalizedText("Fixture"), author: "Fixture", tags: [],
      cover: locator, bgm: locator, data: locator)
    let model = GameplayModel()
    model.prepare(bundle: RuntimeBundle(engine: engine,
      level: LevelData(bgmOffset: 0, entities: entities),
      bgmURL: url, isOffline: true, presentation: resources), level: item,
      server: ServerDescriptor(id: "visual-intro", name: "Fixture",
        baseURL: URL(string: "https://fixture.example")!), title: "Visual Intro")
    defer { model.stop() }
    model.start()
    for _ in 0..<1000 {
      model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
      if !model.isStartingPlayback || model.isDebugPaused { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    if debugAtResolution {
      XCTAssertTrue(model.isDebugPaused)
      XCTAssertTrue(model.isStartingPlayback,
        "Restored initial debug pause must prevent audio from starting")
      XCTAssertEqual(model.debugLog.count, 1)
      XCTAssertEqual(model.judgements.values.reduce(0, +), 1,
        "Only the original initial-time judgment is committed")
      model.resumeFromDebugPause()
      for _ in 0..<1000 {
        model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
        if !model.isStartingPlayback { break }
        try await Task.sleep(for: .milliseconds(5))
      }
      XCTAssertFalse(model.isStartingPlayback)
      XCTAssertFalse(model.isDebugPaused)
      XCTAssertEqual(model.judgements.values.reduce(0, +), 1)
      return
    }
    XCTAssertFalse(model.isStartingPlayback)
    XCTAssertEqual(model.skippedIntroDuration,
      rewind || resolveAt != nil || lifeChangeAt != nil
        ? 0 : min(appearanceTime, 1.95),
      accuracy: 1.0 / 60 + 1e-9,
      "Stop at visible content or 50 ms before the 2s audio onset")
    XCTAssertEqual(model.engineRuntime?.host.draws.count, 1)
    if earlyInput {
      let runtime = try XCTUnwrap(model.engineRuntime)
      XCTAssertTrue(runtime.hasActivatedInput)
      XCTAssertEqual(runtime.resolvedInputCount, 0)
      XCTAssertTrue(runtime.judgments.isEmpty)
      XCTAssertEqual(model.judgements.values.reduce(0, +), 0)
      XCTAssertGreaterThanOrEqual(model.startupSteps,
        resolveAt == nil && lifeChangeAt == nil ? 31 : 16,
        "Activation must not itself terminate intro simulation")
      if let resolveAt {
        try runtime.update(at: resolveAt)
        XCTAssertEqual(runtime.resolvedInputCount, 1,
          "The unplayed input must remain pending after rewind")
      }
      if let lifeChangeAt {
        XCTAssertEqual(runtime.life.value, 1000)
        try runtime.update(at: lifeChangeAt)
        XCTAssertEqual(runtime.life.value, 900,
          "The visible life change must remain pending after rewind")
      }
    }
    if rewind {
      XCTAssertGreaterThanOrEqual(model.startupSteps, 31,
        "Must actually simulate the future frame, not merely stop at time zero")
      let runtime = try XCTUnwrap(model.engineRuntime)
      XCTAssertEqual(runtime.resolvedInputCount, 0)
      XCTAssertTrue(runtime.judgments.isEmpty)
      XCTAssertTrue(runtime.host.takeSpawnCommands().isEmpty)
      XCTAssertEqual(runtime.memory.value(block: 1005, index: 0), -2)
      XCTAssertEqual(model.judgements.values.reduce(0, +), 0)
      // Confirm the future event is still pending, not suppressed forever.
      try runtime.update(at: appearanceTime)
      XCTAssertEqual(runtime.resolvedInputCount, resolvesFutureInput ? 1 : 0)
      XCTAssertEqual(runtime.host.takeSpawnCommands().count, 1)
    }
  }

  func testStaticIntroProofRejectsConditionalAndMutableStageDraws() throws {
    let b = RuntimeNodeBuilder()
    let draw = b.call("Draw", [b.value(1)] + quad.map(b.value)
      + [b.value(0), b.value(1)])
    let now = b.call("Get", [b.value(1001), b.value(0)])
    let conditional = b.call("If", [now, draw, b.value(0)])
    let base: [String: Any] = ["name": "Stage", "hasInput": false,
      "imports": [], "exports": [], "updateParallel": ["index": draw]]
    var archetypes = [base]
    for callback in ["shouldSpawn", "initialize", "updateSequential", "touch",
      "terminate"] {
      var candidate = base
      candidate[callback] = ["index": b.value(0)]
      archetypes.append(candidate)
    }
    var input = base
    input["hasInput"] = true
    archetypes.append(input)
    var changing = base
    changing["updateParallel"] = ["index": conditional]
    archetypes.append(changing)
    let engine = try b.engine(archetypes: archetypes,
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0])
    XCTAssertTrue(try b.engine(archetypes: [base],
      sprites: [["name": "READY", "id": 1]]).staticIntroArchetypes.isEmpty)
    XCTAssertTrue(try b.engine(archetypes: [base], sprites: [
      ["name": "#LANE", "id": 1], ["name": "READY", "id": 1]
    ]).staticIntroArchetypes.isEmpty, "Ambiguous resource IDs are not proof")
  }

  func testStaticIntroProvenanceExcludesPreparationAndDynamicSpawns() throws {
    let b = RuntimeNodeBuilder()
    let draw = b.call("Draw", [b.value(1)] + quad.map(b.value)
      + [b.value(0), b.value(1)])
    let spawn = b.call("Spawn", [b.value(0)])
    let engine = try b.engine(archetypes: [[
      "name": "Stage", "hasInput": false, "imports": [], "exports": [],
      "preprocess": ["index": b.call("Execute", [draw, spawn])],
      "updateParallel": ["index": draw]]],
      sprites: [["name": "#LANE", "id": 1]])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Stage", name: nil, data: [])]),
      options: [], aspectRatio: 2, skinSpriteIDs: [1], effectClipIDs: [],
      particleEffectIDs: [])
    XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration), [false],
      "Only the proven parallel callback may mark decoration")
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration), [true, false],
      "A dynamically spawned copy is not known to be persistent decoration")
    runtime.restart()
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration), [true, false])
  }

  @MainActor
  func testIntroVisualBoundaryKeepsStaticStageAndStopsAtVisibleChanges() {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
      .image { UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
    let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    func sprite(x: Double = 0, alpha: Double = 1,
      isStatic: Bool = true) -> EngineRenderSprite {
      EngineRenderSprite(image: image,
        points: [EnginePoint(x: x - 0.5, y: -0.5),
          EnginePoint(x: x - 0.5, y: 0.5),
          EnginePoint(x: x + 0.5, y: 0.5),
          EnginePoint(x: x + 0.5, y: -0.5)],
        matrix: identity, alpha: alpha, interpolation: false,
        isStaticIntroDecoration: isStatic)
    }
    func frame(_ sprites: [EngineRenderSprite]) -> EngineIntroVisualFrame {
      EngineIntroVisualFrame(sprites: sprites, aspect: 2)
    }
    var guardState = EngineIntroVisualGuard()
    let stage = frame([sprite()])
    XCTAssertEqual(guardState.observe(stage, hasParticles: false), .advance)
    XCTAssertEqual(guardState.observe(stage, hasParticles: false), .advance)
    XCTAssertEqual(guardState.observe(frame([sprite(), sprite(x: 10),
      sprite(alpha: 0)]), hasParticles: false), .advance,
      "Offscreen and fully transparent commands do not start an intro")
    XCTAssertEqual(guardState.observe(frame([sprite(), sprite(x: 1.9)]),
      hasParticles: false), .stop, "Preserve first entry at the screen edge")

    for changed in [frame([sprite(alpha: 0.8)]), frame([sprite(x: 0.1)]),
      frame([])] {
      var heldCountIn = EngineIntroVisualGuard()
      _ = heldCountIn.observe(stage, hasParticles: false)
      XCTAssertEqual(heldCountIn.observe(changed, hasParticles: false), .rewind,
        "Do not discard the initial held count-in when it changes or disappears")
    }
    var duplicates = EngineIntroVisualGuard()
    _ = duplicates.observe(frame([sprite(), sprite()]), hasParticles: false)
    XCTAssertEqual(duplicates.observe(stage, hasParticles: false), .rewind,
      "Removing one translucent layer changes the initial picture")
    var particles = EngineIntroVisualGuard()
    XCTAssertEqual(particles.observe(stage, hasParticles: true), .stop,
      "An already-running particle effect retains its entire lifetime")
    var held = EngineIntroVisualGuard()
    XCTAssertEqual(held.observe(frame([sprite(isStatic: false)]),
      hasParticles: false), .stop,
      "An unchanged initial READY screen is not disposable stage decoration")
    var simultaneous = EngineIntroVisualGuard()
    _ = simultaneous.observe(stage, hasParticles: false)
    XCTAssertEqual(simultaneous.observe(frame([sprite(alpha: 0.5)]),
      hasParticles: true), .rewind,
      "A particle start must not mask a change to the held opening image")
  }

  @MainActor
  func testIntroVisualBoundaryUsesTransformsBackgroundAndHUD() {
    let image = UIImage()
    let points = [EnginePoint(x: 9, y: -0.5), EnginePoint(x: 9, y: 0.5),
      EnginePoint(x: 10, y: 0.5), EnginePoint(x: 10, y: -0.5)]
    let sprite = EngineRenderSprite(image: image, points: points,
      matrix: [1,0,0,-9, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      alpha: 1, interpolation: false)
    XCTAssertEqual(EngineIntroVisualFrame(sprites: [sprite], aspect: 2)
      .sprites.count, 1, "Runtime transforms can bring offscreen commands on screen")
    for (background, ui) in [([1.0], [[0.0]]), ([0.0], [[1.0]])] {
      var guardState = EngineIntroVisualGuard()
      _ = guardState.observe(EngineIntroVisualFrame(sprites: [], aspect: 2,
        background: [0], ui: [[0]]), hasParticles: false)
      XCTAssertEqual(guardState.observe(EngineIntroVisualFrame(sprites: [],
        aspect: 2, background: background, ui: ui), hasParticles: false), .rewind)
    }
  }

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
                  key: .init(seed: seed, effect: effect, group: group, particle: index),
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
    for (start, duration, samples) in [
      (0.75, 0.5, crossing), (0.25, 0.25, straight)
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

  func testSpawnQueueStopsAtFirstWaitingEntityAndRewindsOnRestart() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Int, _ index: Int) -> Int {
      b.call("Get", [b.value(Double(block)), b.value(Double(index))])
    }
    let order = get(4001, 0)
    let spawn = b.call("Execute", [
      // Entity Input is writable in shouldSpawn; Level Memory is not.
      b.call("SetAdd", [b.value(4005), b.value(1), b.value(1)]),
      b.call("GreaterOr", [get(1001, 0), get(4001, 1)])])
    let terminate = b.call("Set", [b.value(4004), b.value(0), b.value(1)])
    let engine = try b.engine(archetypes: [[
      "name": "Note", "hasInput": true,
      "imports": [["name": "order", "index": 0],
                  ["name": "time", "index": 1]], "exports": [],
      "spawnOrder": ["index": order], "shouldSpawn": ["index": spawn],
      "initialize": ["index": terminate]]])
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[
        {"archetype":"Note","data":[
          {"name":"order","value":2},{"name":"time","value":0}]},
        {"archetype":"Note","data":[
          {"name":"order","value":0},{"name":"time","value":1}]},
        {"archetype":"Note","data":[
          {"name":"order","value":1},{"name":"time","value":3}]}]}
      """#.utf8))
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    for _ in 0..<2 {
      var resolvedCalls = 0.0
      func callCount() -> Double {
        resolvedCalls += runtime.judgments.reduce(0) { $0 + $1.accuracy }
        return resolvedCalls + (0..<3).reduce(0) { total, index in
          runtime.memory.selectEntity(key: index, index: index)
          return total + runtime.memory.value(block: 4005, index: 1)
        }
      }
      try runtime.update(at: 0)
      XCTAssertTrue(runtime.judgments.isEmpty)
      XCTAssertEqual(callCount(), 1)
      try runtime.update(at: 1)
      XCTAssertEqual(runtime.judgments.map(\.entityIndex), [1])
      XCTAssertEqual(callCount(), 3)
      try runtime.update(at: 2)
      XCTAssertTrue(runtime.judgments.isEmpty,
        "The ready third entity must not bypass the blocked queue head")
      XCTAssertEqual(callCount(), 4)
      try runtime.update(at: 3)
      XCTAssertEqual(runtime.judgments.map(\.entityIndex), [2, 0])
      XCTAssertEqual(runtime.resolvedInputCount, 3)
      XCTAssertEqual(callCount(), 6)
      try runtime.update(at: 4)
      XCTAssertTrue(runtime.judgments.isEmpty)
      XCTAssertEqual(callCount(), 6,
        "An exhausted queue must not execute shouldSpawn again")
      runtime.restart()
    }
  }

  func testLargeSpawnQueueAdvancesOneEntityPerFrame() throws {
    let b = RuntimeNodeBuilder()
    let index = b.call("Get", [b.value(4003), b.value(0)])
    let time = b.call("Get", [b.value(1001), b.value(0)])
    let spawn = b.call("GreaterOr", [time, index])
    let despawn = b.call("Set", [b.value(4004), b.value(0), b.value(1)])
    let engine = try b.engine(archetypes: [[
      "name": "Note", "hasInput": false, "imports": [], "exports": [],
      "spawnOrder": ["index": index], "shouldSpawn": ["index": spawn],
      "initialize": ["index": despawn]]])
    let count = 20_000
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: Array(repeating:
        LevelEntity(archetype: "Note", name: nil, data: []), count: count)),
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    for frame in 0..<count {
      try runtime.update(at: Double(frame))
      XCTAssertEqual(runtime.memory.value(block: 4103, index: frame * 3 + 2), 2)
      if frame + 1 < count {
        XCTAssertEqual(runtime.memory.value(block: 4103,
          index: (frame + 1) * 3 + 2), 0)
      }
    }
  }

  func testTouchPoolDoesNotCarryContactsAcrossPlaybackGenerations() {
    var pool = EngineTouchPool<Int>()
    let origin = EnginePoint(x: 0, y: 0)
    pool.beginPlayback(generation: 1)
    pool.receive(key: 10, position: origin, time: 60, started: true, ended: false)
    pool.receive(key: 20, position: origin, time: 60, started: true, ended: true)
    pool.receive(key: 20, position: origin, time: 60.01, started: true, ended: false)
    pool.beginPlayback(generation: 1)
    XCTAssertEqual(pool.touches.count, 3,
      "Ordinary frames must preserve active and not-yet-delivered ended touches")
    pool.beginPlayback(generation: 2)
    XCTAssertTrue(pool.touches.isEmpty,
      "Neither a held finger nor a queued release belongs to the retry")
    pool.receive(key: 10, position: origin, time: 0, started: false, ended: false)
    pool.receive(key: 20, position: origin, time: 0, started: false, ended: true)
    XCTAssertTrue(pool.touches.isEmpty,
      "Old UIKit contacts must begin anew before the new runtime sees them")
    pool.receive(key: 30, position: origin, time: 0.1, started: true, ended: false)
    XCTAssertEqual(pool.touches.count, 1)
    XCTAssertEqual(pool.touches.first?.id, 1)
    XCTAssertEqual(pool.touches.first?.startTime, 0.1)
    pool.nextFrame(at: 0.2)
    pool.beginPlayback(generation: 2)
    XCTAssertEqual(pool.touches.count, 1)
    XCTAssertEqual(pool.touches.first?.started, false)
  }

  @MainActor
  func testGameplayRestartReusesPreparationUntilSettingsOrViewportChange() throws {
    let b = RuntimeNodeBuilder()
    let sample = b.call("Set", [b.value(2001), b.value(0),
      b.call("Random", [b.value(0), b.value(1)])])
    let engine = try b.engine(archetypes: [[
      "name": "Setup", "hasInput": false, "imports": [], "exports": [],
      "preprocess": ["index": sample]]])
    let resource = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "restart-contract", source: nil,
      version: 1, rating: 1, title: LocalizedText("Restart"),
      artists: LocalizedText("Fixture"), author: "Fixture", tags: [],
      cover: resource, bgm: resource, data: resource)
    let server = ServerDescriptor(id: "restart-contract", name: "Fixture",
      baseURL: URL(string: "https://example.com")!)
    let model = GameplayModel()
    model.prepare(bundle: RuntimeBundle(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Setup", name: nil, data: [])]),
      bgmURL: URL(fileURLWithPath: "/nonexistent-restart-fixture.wav"),
      isOffline: true, presentation: RuntimePresentation(resources: [
        "configuration": Data(#"""
          {"options":[{"name":"#NOTE_SPEED","type":"slider",
            "def":1,"min":1,"max":12,"step":1}]}
          """#.utf8)])),
      level: level, server: server, title: "Restart")
    let originalSettings = model.settings
    defer { model.stop(); model.settings = originalSettings }
    model.settings = GameplayPreferences()
    model.start()
    let size = CGSize(width: 800, height: 400)
    model.engineFrame(size: size, touches: [])
    let first = try XCTUnwrap(model.engineRuntime)
    let prepared = first.memory.value(block: 2001, index: 0)
    first.memory.set(block: 2001, index: 0, value: -1)
    model.restart()
    model.engineFrame(size: size, touches: [])
    XCTAssertTrue(model.engineRuntime === first)
    XCTAssertEqual(first.memory.value(block: 2001, index: 0), prepared)

    model.settings.scoreDisplay = .countDown
    model.settings.judgementDisplay = .off
    model.settings.skinRenderMode = .lightweight
    model.settings.engineOptions["unused"] = 99
    model.settings.noteSpeed = 1 // Explicit default is the same effective value.
    model.restart()
    model.engineFrame(size: size, touches: [])
    XCTAssertTrue(model.engineRuntime === first,
      "Host-only preferences must not reroll engine preprocessing")
    XCTAssertEqual(first.memory.value(block: 2001, index: 0), prepared)

    model.settings.noteSpeed = (model.settings.noteSpeed ?? 1) + 1
    model.restart()
    model.engineFrame(size: size, touches: [])
    let changedSettings = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(changedSettings === first)
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    let resized = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(resized === changedSettings)
    model.settings.inputOffsetMilliseconds = -30
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    let calibrated = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(calibrated === resized)
    XCTAssertEqual(calibrated.memory.value(block: 1000, index: 3), -0.03)
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    XCTAssertTrue(model.engineRuntime === calibrated)
    model.settings.visualOffsetMilliseconds = 80
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    let visuallyCalibrated = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(visuallyCalibrated === calibrated)
    XCTAssertEqual(try visuallyCalibrated.audioOffset, 0.08)
    XCTAssertEqual(model.playAudioOffset, 0.08)
    XCTAssertEqual(model.currentTime, -0.08, accuracy: 1e-12)
    model.settings.visualOffsetMilliseconds = -80
    XCTAssertEqual(model.playAudioOffset, 0.08,
      "Changing settings must not move an active play's clock")
    model.settings.visualOffsetMilliseconds = 80
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    XCTAssertTrue(model.engineRuntime === visuallyCalibrated)
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [],
      safeAreaInsets: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0))
    XCTAssertFalse(model.engineRuntime === visuallyCalibrated)
  }

  func testAudioCalibrationHonorsEnginePreparationAndScheduledSounds() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Double, _ index: Double) -> Int {
      b.call("Get", [b.value(block), b.value(index)])
    }
    func set(_ block: Double, _ index: Double, _ value: Int) -> Int {
      b.call("Set", [b.value(block), b.value(index), value])
    }
    let preprocess = b.call("Execute", [
      set(2000, 0, get(1000, 2)),
      set(1000, 2, b.call("Add", [get(1000, 2), b.value(0.02)]))])
    let initialize = b.call("Execute", [
      b.call("Play", [b.value(8), b.value(0)]),
      b.call("PlayScheduled", [b.value(8), b.value(3), b.value(0)]),
      set(4000, 1, b.call("PlayLooped", [b.value(8)])),
      set(4000, 2, b.call("PlayLoopedScheduled", [b.value(8), b.value(4)])),
      b.call("StopLooped", [get(4000, 1)]),
      b.call("StopLoopedScheduled", [get(4000, 2), b.value(5)])])
    let engine = try b.engine(archetypes: [[
      "name": "Audio", "hasInput": false, "imports": [], "exports": [],
      "preprocess": ["index": preprocess], "initialize": ["index": initialize]]])
    let level = LevelData(bgmOffset: 0, entities: [
      LevelEntity(archetype: "Audio", name: nil, data: [])])
    for speed in [0.5, 1, 2] {
      for offset in [-0.25, 0, 0.25] {
        let runtime = try EnginePlayRuntime(engine: engine, level: level,
          options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [8],
          particleEffectIDs: [], playbackSpeed: speed, audioOffset: offset)
        let effective = offset + 0.02
        for _ in 0..<2 {
          XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), offset)
          XCTAssertEqual(try runtime.audioOffset, effective)
          try runtime.update(at: 2)
          XCTAssertEqual(runtime.host.takeAudioCommands().map(\.time),
            [2, 3 - effective])
          XCTAssertEqual(runtime.host.takeLoopCommands(), [
            .start(id: 1, clipID: 8, time: 2),
            .start(id: 2, clipID: 8, time: 4 - effective),
            .stop(id: 1, time: 2), .stop(id: 2, time: 5 - effective)])
          runtime.restart()
        }
        runtime.memory.set(block: 1000, index: 2, value: .nan)
        XCTAssertThrowsError(try runtime.audioOffset)
        XCTAssertThrowsError(try runtime.update(at: 2))
        XCTAssertThrowsError(try runtime.host.call(function: "PlayScheduled",
          arguments: [8, 3, 0]))
      }
    }
    XCTAssertThrowsError(try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [8],
      particleEffectIDs: [], audioOffset: .infinity))
  }

  func testInputCalibrationHonorsPreprocessAndKeepsFrameClockAndMotion() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Double, _ index: Double) -> Int {
      b.call("Get", [b.value(block), b.value(index)])
    }
    func set(_ block: Double, _ index: Double, _ value: Int) -> Int {
      b.call("Set", [b.value(block), b.value(index), value])
    }
    // An engine may add its own adjustment before computing its input windows.
    let preprocess = b.call("Execute", [
      set(2000, 0, get(1000, 3)),
      set(1000, 3, b.call("Add", [get(1000, 3), b.value(0.02)]))])
    let judge = b.call("JudgeSimple", [get(1002, 4), b.value(1),
      b.value(0.05), b.value(0.1), b.value(0.15)])
    let touch = set(2000, 1, judge)
    let engine = try b.engine(archetypes: [[
      "name": "Note", "hasInput": true, "imports": [], "exports": [],
      "preprocess": ["index": preprocess], "touch": ["index": touch]]])
    let level = LevelData(bgmOffset: 0, entities: [
      LevelEntity(archetype: "Note", name: nil, data: [])])
    for speed in [0.5, 1, 2] {
      for offset in [-0.25, 0, 0.25] {
        let runtime = try EnginePlayRuntime(engine: engine, level: level,
          options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
          particleEffectIDs: [], playbackSpeed: speed, inputOffset: offset)
        let effective = offset + 0.02
        XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), offset)
        for _ in 0..<2 {
          XCTAssertEqual(runtime.memory.value(block: 1000, index: 3), effective)
          try runtime.update(at: 2, touches: [EngineTouch(id: 1,
            started: true, ended: true, time: 1.1 + effective,
            startTime: 1 + effective, position: EnginePoint(x: 0.2, y: 0.4),
            startPosition: EnginePoint(x: 0, y: 0),
            delta: EnginePoint(x: 0.1, y: 0.2),
            velocity: EnginePoint(x: 3, y: 4))])
          XCTAssertEqual(runtime.memory.value(block: 1001, index: 0), 2)
          XCTAssertEqual(runtime.memory.value(block: 1002, index: 3), 1.1,
            accuracy: 1e-12)
          XCTAssertEqual(runtime.memory.value(block: 1002, index: 4), 1,
            accuracy: 1e-12)
          XCTAssertEqual(runtime.memory.value(block: 1002, index: 11), 3)
          XCTAssertEqual(runtime.memory.value(block: 1002, index: 12), 4)
          XCTAssertEqual(runtime.memory.value(block: 2000, index: 1), 1)
          runtime.restart()
        }
      }
    }
    XCTAssertThrowsError(try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [], inputOffset: .nan))
    let invalid = try b.engine(archetypes: [[
      "name": "Note", "hasInput": true, "imports": [], "exports": [],
      "preprocess": ["index": set(1000, 3,
        b.call("Divide", [b.value(0), b.value(0)]))]]])
    let runtime = try EnginePlayRuntime(engine: invalid, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    XCTAssertThrowsError(try runtime.update(at: 2))
    XCTAssertEqual(runtime.memory.value(block: 1001, index: 0), 0)
  }

  func testRestartRestoresPreparationWithoutRerollingOrLeakingPlayState() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Int, _ index: Int) -> Int {
      b.call("Get", [b.value(Double(block)), b.value(Double(index))])
    }
    func set(_ block: Int, _ index: Int, _ value: Int) -> Int {
      b.call("Set", [b.value(Double(block)), b.value(Double(index)), value])
    }
    let preprocess = b.call("Execute", [
      set(4000, 0, b.call("Random", [b.value(0), b.value(1)])),
      set(4002, 0, b.value(17)), set(2005, 6, b.value(800)),
      set(2004, 0, b.value(1))])
    let spawnOrder = set(4000, 1, get(4000, 0))
    let update = b.call("Execute", [
      set(4000, 0, b.value(-10)), set(4002, 0, b.value(-20)),
      set(4005, 0, b.value(1)), set(4005, 1, b.value(0.01)),
      set(4004, 0, b.value(1)),
      b.call("Spawn", [b.value(1), b.value(123)])])
    let dynamic = b.call("Execute", [
      set(2000, 0, get(4000, 0)), set(4004, 0, b.value(1))])
    let engine = try b.engine(archetypes: [
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "preprocess": ["index": preprocess], "spawnOrder": ["index": spawnOrder],
       "updateSequential": ["index": update]],
      ["name": "Effect", "hasInput": false, "imports": [], "exports": [],
       "updateSequential": ["index": dynamic]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Note", name: nil, data: [])]), options: [],
      aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    let preparedRandom = runtime.memory.value(block: 4000, index: 1)
    for _ in 0..<3 {
      runtime.restart()
      runtime.memory.selectEntity(key: 0, index: 0)
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 1), preparedRandom)
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 0), preparedRandom)
      XCTAssertEqual(runtime.memory.value(block: 4002, index: 0), 17)
      XCTAssertEqual(runtime.memory.value(block: 4103, index: 2), 0)
      XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 0)
      XCTAssertEqual(runtime.resolvedInputCount, 0)
      XCTAssertEqual(runtime.accuracyScore.resolvedCount, 0)
      XCTAssertEqual(runtime.arcadeScore?.snapshot.earned, 0)
      XCTAssertEqual(runtime.life.value, 800)
      XCTAssertFalse(runtime.hasActivatedInput)
      XCTAssertTrue(runtime.judgments.isEmpty)
      try runtime.update(at: 0)
      XCTAssertEqual(runtime.resolvedInputCount, 1)
      XCTAssertEqual(runtime.accuracyScore.resolvedCount, 1)
      XCTAssertEqual(runtime.memory.value(block: 1001, index: 1), 0)
      XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 0,
        "No dynamic entity from the previous play may survive restart")
      try runtime.update(at: 1)
      XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 123)
    }
  }

  func testHostRestorePointResetsHandlesQueuesAndRetainsPreparedStreams() throws {
    let host = makeHost()
    _ = try host.call(function: "StreamSet", arguments: [0, 0, 42])
    let restore = host.makeRestorePoint()
    for _ in 0..<3 {
      restore()
      XCTAssertEqual(host.time, 0)
      XCTAssertTrue(host.draws.isEmpty)
      XCTAssertTrue(host.particles.isEmpty)
      XCTAssertTrue(host.exports.isEmpty)
      XCTAssertTrue(host.takeAudioCommands().isEmpty)
      XCTAssertTrue(host.takeLoopCommands().isEmpty)
      XCTAssertTrue(host.takeSpawnCommands().isEmpty)
      XCTAssertTrue(host.takeScheduledLife(at: 100).isEmpty)
      XCTAssertEqual(try host.call(function: "StreamGetValue",
        arguments: [0, 0]), 42)
      XCTAssertEqual(try host.call(function: "StreamHas", arguments: [0, 1]), 0)
      try host.beginFrame(at: 1)
      host.selectEntity(index: 0, exportCount: 1)
      _ = try host.call(function: "ExportValue", arguments: [0, 9])
      _ = try host.call(function: "StreamSet", arguments: [0, 0, -1])
      _ = try host.call(function: "StreamSet", arguments: [0, 1, 99])
      _ = try host.call(function: "PlayScheduled", arguments: [8, 10, 0])
      XCTAssertEqual(try host.call(function: "PlayLooped", arguments: [8]), 1)
      _ = try host.call(function: "StopLoopedScheduled", arguments: [1, 20])
      _ = try host.call(function: "Spawn", arguments: [1, 3])
      _ = try host.call(function: "AddLifeScheduled", arguments: [99, 10])
      _ = try host.call(function: "Draw",
        arguments: [7, -1, -1, -1, 1, 1, 1, 1, -1, 0, 1])
      XCTAssertEqual(try host.call(function: "SpawnParticleEffect",
        arguments: [9, -1, -1, -1, 1, 1, 1, 1, -1, 100, 1]), 1)
    }
  }

  func testAllTerminateCallbacksObserveActivePeersBeforeDespawn() throws {
    let b = RuntimeNodeBuilder()
    let now = b.call("Get", [b.value(1001), b.value(0)])
    let deadline = b.call("Get", [b.value(4001), b.value(0)])
    let update = b.call("Set", [b.value(4004), b.value(0),
      b.call("GreaterOr", [now, deadline])])
    // A legal read of each peer's Info Array state. Preserve it in this
    // entity's final input payload, which is sampled after terminate.
    let peer = b.call("Get", [b.value(4001), b.value(1)])
    let stateOffset = b.call("Add", [
      b.call("Multiply", [peer, b.value(3)]), b.value(2)])
    let peerState = b.call("Get", [b.value(4103), stateOffset])
    let terminate = b.call("Execute", [
      b.call("Set", [b.value(4005), b.value(0), b.value(1)]),
      b.call("Set", [b.value(4005), b.value(1), peerState])])
    let engine = try b.engine(archetypes: [[
      "name": "linked", "hasInput": true,
      "imports": [["name": "end", "index": 0],
        ["name": "peer", "index": 1]], "exports": [],
      "updateSequential": ["index": update],
      "terminate": ["index": terminate]
    ]])
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[
        {"archetype":"linked","data":[
          {"name":"end","value":1},{"name":"peer","value":1}]},
        {"archetype":"linked","data":[
          {"name":"end","value":1},{"name":"peer","value":0}]},
        {"archetype":"linked","data":[
          {"name":"end","value":2},{"name":"peer","value":0}]}]}
      """#.utf8))
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.resolvedInputCount, 0)
    try runtime.update(at: 1)
    XCTAssertEqual(runtime.judgments.map(\.accuracy), [1, 1],
      "Both peers must see Active, regardless of callback execution order")
    XCTAssertEqual(runtime.resolvedInputCount, 2)
    XCTAssertEqual((0..<3).map {
      runtime.memory.value(block: 4103, index: $0 * 3 + 2)
    }, [2, 2, 1])
    try runtime.update(at: 2)
    XCTAssertEqual(runtime.judgments.map(\.accuracy), [2],
      "A later frame must see the earlier peers as despawned")
    XCTAssertEqual(runtime.resolvedInputCount, 3)
    try runtime.update(at: 3)
    XCTAssertTrue(runtime.judgments.isEmpty)
    XCTAssertEqual(runtime.resolvedInputCount, 3)
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
  func testHapticPlayFailureRecoversWithoutAnOSCallback() {
    let backend = MockHapticBackend()
    var time = 10.0
    let playback = EngineHapticPlayback(makeBackend: { backend }, now: { time })
    playback.start()
    backend.failsPlay = true
    playback.play(.medium)
    XCTAssertFalse(playback.isPrepared)
    playback.play(.medium)
    XCTAssertEqual(backend.starts, 2)
    for _ in 0..<100 { playback.play(.medium) }
    XCTAssertEqual(backend.starts, 2)
    time = 11
    backend.failsPlay = false
    playback.play(.medium)
    XCTAssertEqual(backend.starts, 3)
    XCTAssertTrue(playback.isPrepared)
    XCTAssertEqual(backend.played, [.medium])
  }

  @MainActor
  func testHapticRecoveryIsBoundedAndRejectsPreviousSessionCallbacks() {
    let first = MockHapticBackend()
    let second = MockHapticBackend()
    var time = 10.0
    var session = 0
    let playback = EngineHapticPlayback(makeBackend: {
      session += 1
      return session == 1 ? first : second
    }, now: { time })
    playback.start()
    let staleCallback = first.interrupted
    XCTAssertEqual(first.starts, 1)
    first.interrupted?()
    XCTAssertFalse(playback.isPrepared)
    playback.play(.none)
    XCTAssertEqual(first.starts, 1, "No work for an engine's None request")
    playback.play(.heavy)
    XCTAssertEqual(first.starts, 2)
    XCTAssertEqual(first.played, [.heavy])
    XCTAssertTrue(playback.isPrepared)
    first.interrupted?()
    first.failsStart = true
    time = 11
    for _ in 0..<100 { playback.play(.long) }
    XCTAssertEqual(first.starts, 3, "Repeated failure must not retry every frame")
    time = 12
    first.failsStart = false
    playback.play(.long)
    XCTAssertEqual(first.starts, 4)
    XCTAssertEqual(first.played, [.heavy, .long])
    playback.start()
    XCTAssertEqual(first.stops, 1)
    staleCallback?()
    XCTAssertTrue(playback.isPrepared)
    playback.play(.light)
    XCTAssertEqual(second.starts, 1)
    XCTAssertEqual(second.played, [.light])
    playback.stop()
    staleCallback?()
    playback.play(.heavy)
    XCTAssertFalse(playback.isPrepared)
    XCTAssertEqual(second.stops, 1)
    XCTAssertEqual(second.played, [.light])
  }

  func testHapticContractAndChordCoalescing() {
    XCTAssertEqual((0...4).map { EngineHaptic(runtimeValue: Double($0)) },
      [.none, .light, .medium, .heavy, .long])
    for value in [-1.0, 1.5, 5, .nan, .infinity, 1e100] {
      XCTAssertEqual(EngineHaptic(runtimeValue: value), .none)
    }
    XCTAssertEqual(EngineHaptic.combined([]), .none)
    XCTAssertEqual(EngineHaptic.combined([.light, .medium, .heavy, .none]), .heavy)
    XCTAssertEqual(EngineHaptic.combined([.long, .heavy, .long]), .long)
    XCTAssertNil(EngineHaptic.none.parameters)
    XCTAssertLessThan(EngineHaptic.light.parameters!.intensity,
      EngineHaptic.medium.parameters!.intensity)
    XCTAssertLessThan(EngineHaptic.medium.parameters!.intensity,
      EngineHaptic.heavy.parameters!.intensity)
    XCTAssertEqual(EngineHaptic.heavy.parameters!.duration, 0)
    XCTAssertGreaterThan(EngineHaptic.long.parameters!.duration, 0)
  }

  @MainActor
  func testUnavailableHapticHardwareIsSafeAcrossRestart() {
    let playback = EngineHapticPlayback(hardwareAvailable: false)
    for _ in 0..<3 {
      playback.start()
      XCTAssertFalse(playback.isPrepared)
      for type in EngineHaptic.allCases { playback.play(type) }
      playback.stop()
      XCTAssertFalse(playback.isPrepared)
    }
  }

  func testFinalHapticAndAccuracyAreConsumedAfterTerminateOnce() throws {
    let builder = RuntimeNodeBuilder()
    func set(_ field: Int, _ value: Double) -> Int {
      builder.call("Set", [builder.value(4005), builder.value(Double(field)),
        builder.value(value)])
    }
    let despawn = builder.call("Set", [builder.value(4004), builder.value(0),
      builder.value(1)])
    let update = builder.call("Execute", [set(4, 1), set(1, -0.2), despawn])
    let terminate = builder.call("Execute", [set(4, 4), set(1, 0.025)])
    let engine = try builder.engine(archetypes: [
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "updateParallel": ["index": update], "terminate": ["index": terminate]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Note", name: nil, data: [])
      ]), options: [], aspectRatio: 1, skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [])
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.judgments.map(\.haptic), [.long])
    XCTAssertEqual(runtime.judgments.first?.accuracy, 0.025)
    XCTAssertEqual(runtime.accuracyScore.snapshot(noteCount: 1)?.earned, 975_000)
    try runtime.update(at: 1)
    XCTAssertTrue(runtime.judgments.isEmpty)
  }

  func testAccuracyUsesAbsoluteEngineErrorsAndBothScoreDirections() throws {
    var score = EngineAccuracyScore()
    XCTAssertNil(score.snapshot(noteCount: 0))
    XCTAssertEqual(score.snapshot(noteCount: 4),
      EngineScoreSnapshot(earned: 0, remaining: 1_000_000))
    score.record(accuracy: -0.02)
    XCTAssertEqual(score.snapshot(noteCount: 4),
      EngineScoreSnapshot(earned: 245_000, remaining: 995_000))
    score.record(accuracy: 0.02)
    score.record(accuracy: 0.12) // Engine-assigned miss error still counts.
    score.record(accuracy: 0) // Automatic ticks remain part of engine scoring.
    XCTAssertEqual(score.snapshot(noteCount: 4),
      EngineScoreSnapshot(earned: 960_000, remaining: 960_000))
    XCTAssertEqual(score.resolvedCount, 4)
    var extreme = EngineAccuracyScore()
    extreme.record(accuracy: .greatestFiniteMagnitude)
    extreme.record(accuracy: -.greatestFiniteMagnitude)
    XCTAssertEqual(extreme.snapshot(noteCount: 2),
      EngineScoreSnapshot(earned: 0, remaining: 0))
  }

  func testRuntimeAccuracyConsumesMissAtDespawnExactlyOnce() throws {
    let builder = RuntimeNodeBuilder()
    let accuracy = builder.call("Set", [builder.value(4005), builder.value(1),
      builder.value(-0.125)])
    let despawn = builder.call("Set", [builder.value(4004), builder.value(0),
      builder.value(1)])
    let callback = builder.call("Execute", [accuracy, despawn])
    let engine = try builder.engine(archetypes: [
      ["name": "Miss", "hasInput": true, "imports": [], "exports": [],
       "updateParallel": ["index": callback]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Miss", name: nil, data: [])
      ]), options: [], aspectRatio: 1, skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [])
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.judgments.first?.grade, 0)
    XCTAssertEqual(runtime.accuracyScore.snapshot(noteCount: runtime.inputCount),
      EngineScoreSnapshot(earned: 875_000, remaining: 875_000))
    try runtime.update(at: 1)
    XCTAssertEqual(runtime.accuracyScore.resolvedCount, 1)
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
      context: context, size: CGSize(width: 40, height: 40), pixelBudget: 10000))
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
      XCTAssertThrowsError(try host.call(function: function, arguments: base + [1025] + controls))
    }
    try host.beginFrame(at: 0)
    for _ in 0..<16 {
      _ = try host.call(function: "DrawCurvedB", arguments: base + [1024, 0, 0])
    }
    XCTAssertThrowsError(try host.call(function: "Draw", arguments: base))
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
    for edge in [EngineCurve.Edge.leftRight, .bottomTop] {
      let patches = EngineGeometry.curvedPatches(quad, curve: EngineCurve(
        edge: edge, segments: 8, controls: [EnginePoint(x: 0, y: 0),
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
  func testStartupDetectsInputEvenWhenItDespawnsInTheActivationFrame() throws {
    let builder = RuntimeNodeBuilder()
    let now = builder.call("Get", [builder.value(1001), builder.value(0)])
    let spawn = builder.call("GreaterOr", [now, builder.value(-2)])
    let despawn = builder.call("Set", [builder.value(4004), builder.value(0),
      builder.value(1)])
    let engine = try builder.engine(archetypes: [
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "shouldSpawn": ["index": spawn], "initialize": ["index": despawn]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 9, entities: [
        LevelEntity(archetype: "Note", name: nil, data: [])]),
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    try runtime.update(at: -3)
    XCTAssertFalse(runtime.hasActivatedInput)
    try runtime.update(at: -2)
    XCTAssertTrue(runtime.hasActivatedInput)
    XCTAssertEqual(runtime.resolvedInputCount, 1)
    try runtime.update(at: -1)
    XCTAssertTrue(runtime.hasActivatedInput)
  }

  func testStartupAudioBoundaryDoesNotConsumeScheduledOrLoopCommands() throws {
    let host = makeHost()
    try host.beginFrame(at: -9)
    _ = try host.call(function: "PlayScheduled", arguments: [8, -1, 0])
    _ = try host.call(function: "PlayLoopedScheduled", arguments: [8, -2])
    XCTAssertEqual(host.nextAudioStartTime, -2)
    try host.beginFrame(at: -2)
    XCTAssertEqual(host.nextAudioStartTime, -2)
    XCTAssertEqual(host.takeAudioCommands().count, 1)
    XCTAssertEqual(host.takeLoopCommands().count, 1)
    XCTAssertNil(host.nextAudioStartTime)
  }

  func testDynamicSpawnsDoNotInventAnInputBoundaryDuringSilentIntro() throws {
    let builder = RuntimeNodeBuilder()
    let spawn = builder.call("Spawn", [builder.value(1)])
    let engine = try builder.engine(archetypes: [
      ["name": "Init", "hasInput": false, "imports": [], "exports": [],
       "initialize": ["index": spawn]],
      ["name": "Dynamic", "hasInput": true, "imports": [], "exports": []]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Init", name: nil, data: [])]), options: [],
      aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    try runtime.update(at: -3)
    try runtime.update(at: -2)
    XCTAssertEqual(runtime.inputCount, 0)
    XCTAssertFalse(runtime.hasActivatedInput,
      "Spawn has no input, even when its archetype declares hasInput")
  }
  func testCompatibilityChecksLazyAndSpawnablePathsButNotOrphanedNodes() throws {
    let builder = RuntimeNodeBuilder()
    let unknown = builder.call("UnimplementedHitEffect", [])
    _ = builder.call("OrphanedCompilerFunction", [])
    let branch = builder.call("If", [builder.value(0), unknown, builder.value(1)])
    let engine = try builder.engine(archetypes: [
      ["name": "Spawnable", "hasInput": false, "imports": [], "exports": [],
       "touch": ["index": branch]]
    ])
    XCTAssertEqual(try engine.unsupportedFunctions(), ["UnimplementedHitEffect"])
    XCTAssertThrowsError(try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: []), options: [], aspectRatio: 1,
      skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: []))
    let invalid = try builder.engine(archetypes: [
      ["name": "Note", "hasInput": false, "imports": [], "exports": [],
       "touch": ["index": -1]]
    ])
    XCTAssertThrowsError(try invalid.unsupportedFunctions())
  }

  func testRuntimeSeedsEngineVisibilitySafeAreaAndLifeBeforePreprocess() throws {
    let builder = RuntimeNodeBuilder()
    let readLife = builder.call("Get", [builder.value(2005), builder.value(6)])
    let capture = builder.call("Set", [builder.value(2000), builder.value(0), readLife])
    let engine = try builder.engine(archetypes: [
      ["name": "Init", "hasInput": false, "imports": [], "exports": [],
       "preprocess": ["index": capture]]
    ])
    let ui = [1.0, 0, 2, 0.3, 0.7, 0.5, 1, 0.8, 2, 0.1]
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Init", name: nil, data: [])]),
      options: [], aspectRatio: 2, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [], uiConfiguration: ui, safeArea: [-1.8, 1.9, -0.9, 1])
    XCTAssertEqual((0..<10).map { runtime.memory.value(block: 1007, index: $0) }, ui)
    XCTAssertEqual((5..<9).map { runtime.memory.value(block: 1000, index: $0) },
      [-1.8, 1.9, -0.9, 1])
    XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), 1000)
    XCTAssertEqual(runtime.life.value, 1000)
  }

  func testEngineLifeCombinesArchetypeEntityAndScheduledChangesAtDespawn() throws {
    let builder = RuntimeNodeBuilder()
    func set(_ block: Double, _ index: Double, _ value: Double) -> Int {
      builder.call("Set", [builder.value(block), builder.value(index), builder.value(value)])
    }
    let schedule = builder.call("AddLifeScheduled", [builder.value(30), builder.value(2)])
    let preprocess = builder.call("Execute", [set(2005, 6, 100),
      set(2005, 7, 200), set(5000, 1, -10), set(4007, 1, -5), schedule])
    let update = builder.call("Execute", [set(4005, 0, 2), set(4004, 0, 1)])
    let engine = try builder.engine(archetypes: [
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "preprocess": ["index": preprocess], "updateParallel": ["index": update]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Note", name: nil, data: [])]), options: [],
      aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    XCTAssertEqual(runtime.life.value, 100)
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.life.value, 85)
    try runtime.update(at: 2)
    XCTAssertEqual(runtime.life.value, 115)
    try runtime.update(at: 3)
    XCTAssertEqual(runtime.life.value, 115)
  }

  func testLifeStreaksCapsScheduledOrderAndPermanentFailure() throws {
    var life = EngineLife(configuration: [10, 2, 0, 0, 0, 0, 100, 110])
    life.record(grade: 1, increment: -5)
    XCTAssertEqual(life.value, 95)
    life.record(grade: 1, increment: -5)
    XCTAssertEqual(life.value, 100)
    life.record(grade: 2, increment: -5)
    life.record(grade: 1, increment: -5)
    XCTAssertEqual(life.value, 90)
    life.add(100)
    XCTAssertEqual(life.value, 110)
    life.add(-200)
    life.add(1000)
    XCTAssertEqual(life.value, 0)
    XCTAssertTrue(life.failed)
    let host = makeHost()
    _ = try host.call(function: "AddLifeScheduled", arguments: [20, 4])
    _ = try host.call(function: "AddLifeScheduled", arguments: [-10, 2])
    XCTAssertEqual(host.takeScheduledLife(at: 3), [-10])
    XCTAssertEqual(host.takeScheduledLife(at: 5), [20])
    XCTAssertTrue(host.takeScheduledLife(at: 5).isEmpty)
  }

  func testJudgeSimpleAndBeatSegmentFunctions() throws {
    let host = makeHost()
    for (error, grade) in [(0.0, 1.0), (0.05, 1), (-0.1, 2), (0.15, 3), (0.2, 0)] {
      XCTAssertEqual(try host.call(function: "JudgeSimple",
        arguments: [error, 0, 0.05, 0.1, 0.15]), grade)
    }
    XCTAssertEqual(try host.call(function: "BeatToStartingBeat", arguments: [1]), 0)
    XCTAssertEqual(try host.call(function: "BeatToStartingTime", arguments: [1]), 0)
  }

  func testTimeScaleIntegratesTempoPausesReversalsAndNegativeLeadIn() throws {
    func scale(_ beat: Double, _ value: Double) -> LevelEntity {
      LevelEntity(archetype: "#TIMESCALE_CHANGE", name: nil, data: [
        LevelEntityData(name: "#BEAT", value: beat, ref: nil),
        LevelEntityData(name: "#TIMESCALE", value: value, ref: nil)])
    }
    let level = LevelData(bgmOffset: 9, entities: [
      bpm(beat: -4, value: 120), bpm(beat: 4, value: 60),
      scale(-2, 2), scale(2, 0), scale(4, -1), scale(6, 1)])
    let tempo = BPMTimeline(level: level)
    XCTAssertEqual(tempo.time(at: 0), 0)
    XCTAssertEqual(tempo.time(at: -4), -2)
    XCTAssertEqual(tempo.time(at: 6), 4)
    let engine = try RuntimeNodeBuilder().engine(archetypes: [])
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    for (time, expected) in [(-2.0, -4.0), (0, 0), (1, 2), (1.5, 2),
      (2, 2), (3, 1), (4, 0), (5, 1)] {
      XCTAssertEqual(try runtime.host.call(function: "TimeToScaledTime",
        arguments: [time]), expected)
      try runtime.update(at: time)
      XCTAssertEqual(runtime.memory.value(block: 1001, index: 2), expected)
      XCTAssertEqual(runtime.memory.value(block: 1001, index: 0), time)
    }
    XCTAssertEqual(try runtime.host.call(function: "TimeToStartingTime", arguments: [3]), 2)
    XCTAssertEqual(try runtime.host.call(function: "TimeToStartingScaledTime", arguments: [3]), 2)
    XCTAssertEqual(try runtime.host.call(function: "TimeToTimeScale", arguments: [3]), -1)
    XCTAssertEqual(try runtime.host.call(function: "BeatToStartingBeat", arguments: [6]), 4)
    XCTAssertEqual(try runtime.host.call(function: "BeatToStartingTime", arguments: [6]), 2)
  }

  func testRuntimeReadsArcadeWeightsAfterPreprocessAndScoresAtDespawn() throws {
    let builder = RuntimeNodeBuilder()
    func set(_ block: Int, _ index: Int, _ value: Double) -> Int {
      builder.call("Set", [builder.value(Double(block)),
        builder.value(Double(index)), builder.value(value)])
    }
    let preprocess = builder.call("Execute", [set(2004, 0, 1),
      set(2004, 1, 0.7), set(2004, 2, 0.5), set(5001, 0, 10), set(4006, 0, 20)])
    let update = builder.call("Execute", [set(4005, 0, 2), set(4004, 0, 1)])
    let engine = try builder.engine(archetypes: [
      ["name": "Note", "hasInput": true, "imports": [], "exports": [],
       "preprocess": ["index": preprocess], "updateParallel": ["index": update]]
    ])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Note", name: nil, data: [])]),
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    XCTAssertEqual(runtime.arcadeScore?.snapshot.earned, 0)
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.arcadeScore?.snapshot.earned, 700_000)
    XCTAssertEqual(runtime.arcadeScore?.snapshot.remaining, 700_000)
  }

  func testArcadeScoreUsesEngineWeightsGradeMultipliersAndStreaks() throws {
    // Bonus after every two GREAT-or-better inputs, capped at four.
    let config = [1.0, 0.7, 0.5, 0, 0, 0, 0.1, 2, 4, 0, 0, 0]
    let weights = [0: 10.0, 1: 20, 2: 1, 3: 10, 4: 30]
    var score = try XCTUnwrap(EngineArcadeScore(configuration: config,
      weights: weights))
    XCTAssertEqual(score.snapshot.remaining, 1_000_000)
    let maximum = 71.6 // All-perfect base 71 + bonuses 0,.1,.1,.2,.2.
    score.record(entity: 0, grade: 1)
    score.record(entity: 1, grade: 2)
    XCTAssertEqual(score.snapshot.earned,
      Int(((10 + 20.1 * 0.7) / maximum * 1_000_000).rounded()))
    score.record(entity: 2, grade: 3) // GOOD resets the GREAT-or-better streak.
    score.record(entity: 3, grade: 1)
    score.record(entity: 4, grade: 0)
    let final = score.snapshot
    XCTAssertEqual(final.earned, final.remaining)
    XCTAssertEqual(final.earned,
      Int(((10 + 20.1 * 0.7 + 0.5 + 10) / maximum * 1_000_000).rounded()))
    score.record(entity: 0, grade: 1)
    XCTAssertEqual(score.snapshot, final, "Duplicate entity resolutions do not score twice")
    var flawless = try XCTUnwrap(EngineArcadeScore(configuration: config,
      weights: weights))
    for index in 0..<5 { flawless.record(entity: index, grade: 1) }
    XCTAssertEqual(flawless.snapshot.earned, 1_000_000)
    XCTAssertEqual(flawless.snapshot.remaining, 1_000_000)
    XCTAssertNil(EngineArcadeScore(configuration: Array(repeating: 0, count: 12),
      weights: weights), "Unconfigured engines use the fallback scoring policy")
  }

  func testFlatArcadeScoreUsesThreeTwoOneAndIndependentNoteWeights() throws {
    let config = [3.0, 2, 1] + Array(repeating: 0.0, count: 9)
    var weighted = try XCTUnwrap(EngineArcadeScore(configuration: config,
      weights: [0: 10, 1: 20]))
    weighted.record(entity: 0, grade: 2)
    weighted.record(entity: 1, grade: 3)
    XCTAssertEqual(weighted.snapshot.earned, 444_444)
    var unweighted = try XCTUnwrap(EngineArcadeScore(configuration: config,
      weights: [0: 10, 1: 10]))
    unweighted.record(entity: 0, grade: 2)
    unweighted.record(entity: 1, grade: 3)
    XCTAssertEqual(unweighted.snapshot.earned, 500_000)
  }

  func testTouchPoolKeepsTenCoincidentContactsAndReusedIdentities() throws {
    var pool = EngineTouchPool<Int>()
    let point = EnginePoint(x: 0, y: -0.75)
    for key in 0..<10 {
      pool.receive(key: key, position: point, time: 1,
        started: true, ended: false)
    }
    XCTAssertEqual(pool.touches.count, 10)
    XCTAssertEqual(Set(pool.touches.map(\.id)).count, 10)
    pool.receive(key: 0, position: point, time: 1.01,
      started: false, ended: true)
    pool.receive(key: 0, position: point, time: 1.02,
      started: true, ended: false)
    XCTAssertEqual(pool.touches.count, 11)
    XCTAssertTrue(pool.touches[0].started && pool.touches[0].ended)
    XCTAssertEqual(pool.touches.last?.startTime, 1.02)
    let engine = try RuntimeNodeBuilder().engine(archetypes: [])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: []), options: [],
      aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [])
    try runtime.update(at: 1.03, touches: pool.touches)
    XCTAssertEqual(runtime.memory.value(block: 1001, index: 3), 11)
    for index in 0..<11 {
      XCTAssertEqual(runtime.memory.value(block: 1002, index: index * 15),
        Double(index + 1))
    }
    pool.nextFrame(at: 1.03)
    XCTAssertEqual(pool.touches.count, 10)
    XCTAssertFalse(pool.touches.contains { $0.started || $0.ended })
  }

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
    let missingBlock = EngineInterpreter(nodes: [
      EngineDataNode(value: .infinity), EngineDataNode(value: 0),
      EngineDataNode(function: "Get", arguments: [0, 1])
    ])
    XCTAssertEqual(try missingBlock.execute(nodeAt: 2), 0)
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
       "updateSequential": ["index": dynamicUpdate]],
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
  var pauseCount = 0
  var resumeCount = 0

  func pause() { pauseCount += 1 }
  func resume() { resumeCount += 1 }

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

@MainActor
private final class MockHapticBackend: EngineHapticBackend {
  var interrupted: (() -> Void)?
  var starts = 0
  var stops = 0
  var played = [EngineHaptic]()
  var failsStart = false
  var failsPlay = false

  func start() throws {
    starts += 1
    if failsStart { throw EngineInterpreterError.operationLimitExceeded }
  }
  func play(_ type: EngineHaptic) throws {
    if failsPlay { throw EngineInterpreterError.operationLimitExceeded }
    played.append(type)
  }
  func stop() { stops += 1 }
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

  func engine(archetypes: [[String: Any]], sprites: [[String: Any]] = [],
    buckets: [[String: Any]] = [])
    throws -> EnginePlayData {
    let data = try JSONSerialization.data(withJSONObject: [
      "skin": ["sprites": sprites], "effect": ["clips": []],
      "particle": ["effects": []], "buckets": buckets,
      "nodes": nodes, "archetypes": archetypes
    ])
    return try JSONDecoder().decode(EnginePlayData.self, from: data)
  }
}
