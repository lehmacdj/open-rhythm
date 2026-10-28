import XCTest
import UIKit
@testable import OpenRhythm

final class EngineInputTests: EngineHostTestCase {
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

  func testTouchPoolEndsContactWhoseReleaseWasMissed() {
    var pool = EngineTouchPool<Int>()
    pool.beginPlayback(generation: 1)
    pool.receive(key: 10, position: EnginePoint(x: 0, y: 0), time: 1,
      started: true, ended: false)
    pool.nextFrame(at: 1)
    pool.receive(key: 10, position: EnginePoint(x: 1, y: 0), time: 2,
      started: true, ended: false)
    XCTAssertEqual(pool.touches.map(\.id), [1, 2])
    XCTAssertEqual(pool.touches.map(\.ended), [true, false],
      "The replaced contact must report its end to the engine")
    XCTAssertEqual(pool.touches.first?.position, EnginePoint(x: 0, y: 0))
    pool.nextFrame(at: 2)
    XCTAssertEqual(pool.touches.map(\.id), [2])
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

  func testStationaryHoldBeginningBeforeInputWindowStillResolves() throws {
    let builder = RuntimeNodeBuilder()
    let now = builder.call("Get", [builder.value(1001), builder.value(0)])
    let inWindow = builder.call("GreaterOr", [now, builder.value(1.05)])
    let hasTouch = builder.call("Get", [builder.value(1001), builder.value(3)])
    let judge = builder.call("Set", [builder.value(4005), builder.value(0),
      builder.value(1)])
    let despawn = builder.call("Set", [builder.value(4004), builder.value(0),
      builder.value(1)])
    let hit = builder.call("Execute", [judge, despawn])
    let touch = builder.call("If", [builder.call("And", [inWindow, hasTouch]),
      hit, builder.value(0)])
    let engine = try builder.engine(archetypes: [["name": "HoldTick",
      "hasInput": true, "imports": [], "exports": [],
      "touch": ["index": touch]]])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "HoldTick", name: nil, data: [])]),
      options: [], aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    var pool = EngineTouchPool<Int>()
    pool.receive(key: 0, position: EnginePoint(x: 0, y: -0.75),
      time: 1, started: true, ended: false)
    try runtime.update(at: 1, touches: pool.touches)
    XCTAssertEqual(runtime.resolvedInputCount, 0)
    pool.nextFrame(at: 1)
    try runtime.update(at: 1.02, touches: pool.touches)
    XCTAssertEqual(runtime.resolvedInputCount, 0)
    pool.nextFrame(at: 1.02)
    XCTAssertFalse(try XCTUnwrap(pool.touches.first).started)
    XCTAssertEqual(pool.touches.first?.time, 1)
    try runtime.update(at: 1.06, touches: pool.touches)
    XCTAssertEqual(runtime.resolvedInputCount, 1,
      "A held finger remains valid input when the note's window opens")
    XCTAssertEqual(runtime.judgments.first?.grade, 1)
  }

  func testStationaryContactsContinueCallbacksWithoutFabricatingPresses() throws {
    let builder = RuntimeNodeBuilder()
    let memory = builder.value(4000)
    let increment = builder.call("IncrementPost", [memory, builder.value(0)])
    let contactCount = builder.call("Get", [builder.value(1001), builder.value(3)])
    let rememberCount = builder.call("Set", [memory, builder.value(1), contactCount])
    let engine = try builder.engine(archetypes: [["name": "InputProbe",
      "hasInput": false, "imports": [], "exports": [],
      "touch": ["index": increment],
      "updateParallel": ["index": rememberCount]]])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "InputProbe", name: nil, data: [])]),
      options: [], aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [])
    var pool = EngineTouchPool<Int>()
    let point = EnginePoint(x: 0, y: -0.75)
    func frame(_ time: Double, calls: Double, contacts: Double) throws {
      try runtime.update(at: time, touches: pool.touches)
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 0), calls)
      XCTAssertEqual(runtime.memory.value(block: 4000, index: 1), contacts)
      pool.nextFrame(at: time)
    }
    pool.receive(key: 0, position: point, time: 1, started: true, ended: false)
    try frame(1, calls: 1, contacts: 1)
    XCTAssertFalse(try XCTUnwrap(pool.touches.first).started)
    XCTAssertEqual(pool.touches.first?.time, 1)
    try frame(1.01, calls: 2, contacts: 1)
    // A delivered event can have unchanged coordinates and timestamp.
    // It must not become a new press or stop continuous hold evaluation.
    pool.receive(key: 0, position: point, time: 1, started: false, ended: false)
    try frame(1.02, calls: 3, contacts: 1)
    pool.receive(key: 0, position: EnginePoint(x: 0.2, y: -0.75),
      time: 1.025, started: false, ended: false)
    try frame(1.03, calls: 4, contacts: 1)
    try frame(1.04, calls: 5, contacts: 1)
    pool.receive(key: 1, position: point, time: 1.041, started: true, ended: false)
    try frame(1.042, calls: 6, contacts: 2)
    try frame(1.044, calls: 7, contacts: 2)
    pool.receive(key: 0, position: point, time: 1.045, started: false, ended: true)
    try frame(1.05, calls: 8, contacts: 2)
    try frame(1.06, calls: 9, contacts: 1)
    pool.receive(key: 1, position: point, time: 1.065, started: false, ended: true)
    try frame(1.07, calls: 10, contacts: 1)
    try frame(1.08, calls: 10, contacts: 0)
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

  func testTouchVelocityDoesNotDependOnDisplayFramePhase() throws {
    let p = EnginePoint(x: 0, y: 0)
    let start = EngineTouch(id: 1, started: true, ended: false,
      time: 1, startTime: 1, position: p, startPosition: p, delta: p)
    for frameTime in [1, 1.005, 1.008, 1.02, 4] {
      let moved = start.nextFrame(at: frameTime).moved(
        to: EnginePoint(x: 0, y: 0.1), at: 1.01, ended: false)
      XCTAssertEqual(moved.velocity?.y ?? 0, 10, accuracy: 1e-9,
        "Display time \(frameTime) must not rewrite an OS sampling interval")
      XCTAssertEqual(moved.time, 1.01)
      XCTAssertEqual(moved.delta, EnginePoint(x: 0, y: 0.1))
    }
    let shortInterval = start.moved(to: EnginePoint(x: 0, y: 0.1),
      at: 1.001, ended: false)
    XCTAssertEqual(shortInterval.velocity?.y ?? 0, 100, accuracy: 1e-8,
      "Use measured intervals rather than assuming a maximum sampling rate")
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
    // A display tick cannot establish a stationary sample at time 3. Supply
    // a real timestamped sample instead of fabricating one from rendering.
    let stationary = held.moved(to: p, at: 3, ended: false)
    let flick = stationary.moved(to: EnginePoint(x: 0, y: 0.2),
      at: 3.01, ended: false)
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

  func testCoalescedFlickUsesRecentPhysicalSamplesAfterAStationaryHold() throws {
    // Chart time may be clamped at startup or frozen during a player stall.
    // Velocity still uses the physical interval, with no calibration added.
    for chartTime in [1.0, 3.0, 10.0] {
      var pool = EngineTouchPool<Int>()
      pool.receive(key: 0, samples: [EngineTouchSample(
        position: EnginePoint(x: 0, y: 0), time: 1, timestamp: 100)],
        started: true, ended: false)
      pool.nextFrame(at: 3.1)
      pool.receive(key: 0, samples: [
        EngineTouchSample(position: EnginePoint(x: 0, y: 0.1),
          time: chartTime, timestamp: 102.005),
        EngineTouchSample(position: EnginePoint(x: 0, y: 0.2),
          time: chartTime, timestamp: 102.010)
      ], started: false, ended: false)
      let flick = try XCTUnwrap(pool.touches.first)
      XCTAssertEqual(pool.touches.count, 1)
      XCTAssertEqual(flick.id, 1)
      XCTAssertFalse(flick.started)
      XCTAssertEqual(flick.time, chartTime)
      XCTAssertEqual(flick.startTime, 1)
      XCTAssertEqual(flick.delta, EnginePoint(x: 0, y: 0.2))
      XCTAssertEqual(flick.velocity?.y ?? 0, 20, accuracy: 1e-8)
      pool.receive(key: 0, samples: [EngineTouchSample(
        position: flick.position, time: chartTime, timestamp: 102.011)],
        started: false, ended: true)
      XCTAssertEqual(pool.touches.first?.velocity?.y ?? 0, 20, accuracy: 1e-8)
      XCTAssertTrue(try XCTUnwrap(pool.touches.first).ended)
      pool.nextFrame(at: 3.2)
      XCTAssertTrue(pool.touches.isEmpty)
    }
  }

  func testCoalescedContactsPreserveLifecycleAndOnlyMeasuredVelocity() throws {
    var pool = EngineTouchPool<Int>()
    func sample(_ x: Double, _ timestamp: Double) -> EngineTouchSample {
      EngineTouchSample(position: EnginePoint(x: x, y: 0),
        time: timestamp - 100, timestamp: timestamp)
    }
    pool.receive(key: 7, samples: [sample(0, 100), sample(0.1, 100.01)],
      started: true, ended: false)
    pool.receive(key: 7, samples: [sample(0.2, 100.02), sample(0.2, 100.03)],
      started: false, ended: true)
    let ended = try XCTUnwrap(pool.touches.first)
    XCTAssertTrue(ended.started && ended.ended)
    XCTAssertEqual(ended.startTime, 0)
    XCTAssertEqual(ended.time, 0.03, accuracy: 1e-10)
    XCTAssertEqual(ended.delta.x, 0.2, accuracy: 1e-10)
    XCTAssertEqual(ended.velocity?.x ?? 0, 10, accuracy: 1e-8)
    pool.receive(key: 7, samples: [sample(0, 101), sample(0.1, 101.01)],
      started: true, ended: false)
    XCTAssertEqual(pool.touches.map(\.id), [1, 2],
      "Auxiliary copies must not create extra contacts or reuse the ended ID")
    pool.nextFrame(at: 101.02)
    XCTAssertEqual(pool.touches.map(\.id), [2])
    XCTAssertEqual(pool.touches.first?.velocity?.x, 0)
    // Without intermediate samples, only the long-interval average is known.
    // A frame must not turn that uncertainty into an invented fast flick.
    pool.receive(key: 7, samples: [sample(0.2, 103.01)],
      started: false, ended: false)
    XCTAssertEqual(pool.touches.first?.velocity?.x ?? 0, 0.05, accuracy: 1e-8)
    pool.receive(key: 7, samples: [sample(0.3, 103.01)],
      started: false, ended: true)
    XCTAssertEqual(pool.touches.first?.velocity?.x, 0,
      "An equal timestamp does not define a nonzero velocity")
    XCTAssertTrue(try XCTUnwrap(pool.touches.first).ended)
  }
}
