import XCTest
import UIKit
@testable import OpenRhythm

final class EngineRuntimeLifecycleTests: EngineHostTestCase {
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

  func testNaNSpawnOrderQueuesLast() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Int, _ index: Int) -> Int {
      b.call("Get", [b.value(Double(block)), b.value(Double(index))])
    }
    // 0 / 0 gives the first entity a NaN spawn order.
    let order = b.call("Divide", [get(4001, 0), get(4001, 1)])
    let spawn = b.call("GreaterOr", [get(1001, 0), get(4001, 2)])
    let despawn = b.call("Set", [b.value(4004), b.value(0), b.value(1)])
    let engine = try b.engine(archetypes: [[
      "name": "Note", "hasInput": false,
      "imports": [["name": "a", "index": 0], ["name": "b", "index": 1],
                  ["name": "time", "index": 2]], "exports": [],
      "spawnOrder": ["index": order], "shouldSpawn": ["index": spawn],
      "initialize": ["index": despawn]]])
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[
        {"archetype":"Note","data":[{"name":"a","value":0},
          {"name":"b","value":0},{"name":"time","value":0}]},
        {"archetype":"Note","data":[{"name":"a","value":1},
          {"name":"b","value":1},{"name":"time","value":2}]},
        {"archetype":"Note","data":[{"name":"a","value":0},
          {"name":"b","value":1},{"name":"time","value":1}]}]}
      """#.utf8))
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    func spawned() -> [Bool] {
      (0..<3).map { runtime.memory.value(block: 4103, index: $0 * 3 + 2) != 0 }
    }
    try runtime.update(at: 0)
    XCTAssertEqual(spawned(), [false, false, false],
      "The NaN entity must wait behind the blocked queue head")
    try runtime.update(at: 1)
    XCTAssertEqual(spawned(), [false, false, true])
    try runtime.update(at: 2)
    XCTAssertEqual(spawned(), [true, true, true])
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
    let originalTiming = model.timing
    defer {
      model.stop()
      model.settings = originalSettings
      model.timing = originalTiming
    }
    model.settings = GameplayPreferences()
    model.timing = TimingCalibration()
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
    model.timing.inputOffsetMilliseconds = -30
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    let calibrated = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(calibrated === resized)
    XCTAssertEqual(try calibrated.inputOffset, -0.03, accuracy: 1e-12)
    XCTAssertEqual(calibrated.memory.value(block: 1000, index: 3),
      -0.03 + GameplayModel.displayLead, accuracy: 1e-12,
      "Engines wait out the display lead before closing judgment windows")
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    XCTAssertTrue(model.engineRuntime === calibrated)
    model.timing.visualOffsetMilliseconds = 80
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    let visuallyCalibrated = try XCTUnwrap(model.engineRuntime)
    XCTAssertFalse(visuallyCalibrated === calibrated)
    XCTAssertEqual(try visuallyCalibrated.audioOffset, 0.08)
    XCTAssertEqual(model.playAudioOffset, 0.08)
    XCTAssertEqual(model.currentTime, -0.08, accuracy: 1e-12)
    model.timing.visualOffsetMilliseconds = -80
    XCTAssertEqual(model.playAudioOffset, 0.08,
      "Changing settings must not move an active play's clock")
    model.timing.visualOffsetMilliseconds = 80
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [])
    XCTAssertTrue(model.engineRuntime === visuallyCalibrated)
    model.restart()
    model.engineFrame(size: CGSize(width: 900, height: 400), touches: [],
      safeAreaInsets: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0))
    XCTAssertFalse(model.engineRuntime === visuallyCalibrated)
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
}
