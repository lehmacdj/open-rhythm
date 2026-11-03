import XCTest
import UIKit
import AVFoundation
@testable import OpenRhythm

final class EngineScoringTests: EngineHostTestCase {
  func testScheduledLifeRejectsEveryNonPreprocessingCallback() throws {
    // Play callbacks; render belongs to preview.
    for callback in EngineMemory.Callback.allCases where callback != .render {
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
    XCTAssertEqual(runtime.judgments.first?.bucketIndex, -1)
    XCTAssertEqual(runtime.judgments.first?.bucketValue, 0)
    XCTAssertEqual(runtime.accuracyScore.snapshot(noteCount: 1)?.earned, 975_000)
    try runtime.update(at: 1)
    XCTAssertTrue(runtime.judgments.isEmpty)
  }

  func testFinalBucketInputIsRetainedSeparatelyFromAccuracy() throws {
    let builder = RuntimeNodeBuilder()
    func set(_ field: Int, _ value: Double) -> Int {
      builder.call("Set", [builder.value(4005), builder.value(Double(field)),
        builder.value(value)])
    }
    let despawn = builder.call("Set", [builder.value(4004), builder.value(0),
      builder.value(1)])
    let update = builder.call("Execute", [set(2, 3), set(3, 123), despawn])
    let terminate = builder.call("Execute", [set(0, 2), set(1, -0.025),
      set(2, 0), set(3, -72.5)])
    let windows: [Double] = [-1, 2, -3, 4, -5, 6]
    let preprocess = builder.call("Execute", windows.enumerated().map { i, v in
      builder.call("Set", [builder.value(2003), builder.value(Double(i)),
        builder.value(v)])
    })
    let engine = try builder.engine(archetypes: [
      ["name": "CustomInput", "hasInput": true, "imports": [], "exports": [],
       "preprocess": ["index": preprocess],
       "updateParallel": ["index": update], "terminate": ["index": terminate]]
    ], buckets: [["sprites": [], "unit": "custom units"]])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "CustomInput", name: nil, data: [])
      ]), options: [], aspectRatio: 1, skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [])
    for _ in 0..<2 {
      try runtime.update(at: 0)
      let judgment = try XCTUnwrap(runtime.judgments.first)
      XCTAssertEqual(judgment.bucketIndex, 0)
      XCTAssertEqual(judgment.bucketValue, -72.5)
      XCTAssertEqual(judgment.accuracy, -0.025)
      XCTAssertEqual(runtime.resultBuckets.first?.definition.unit, "custom units")
      XCTAssertEqual(runtime.resultBuckets.first?.windows, windows.map(Optional.some))
      XCTAssertEqual(runtime.accuracyScore.snapshot(noteCount: 1)?.earned, 975_000)
      try runtime.update(at: 1)
      XCTAssertTrue(runtime.judgments.isEmpty)
      runtime.restart()
    }
  }

  @MainActor
  func testGameplayPersistsEngineBucketInputAndDefinitions() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("silent.caf")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000,
      channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
    buffer.frameLength = 8000
    buffer.floatChannelData![0].initialize(repeating: 0, count: 8000)
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }
    let b = RuntimeNodeBuilder()
    func set(_ block: Int, _ index: Int, _ value: Double) -> Int {
      b.call("Set", [b.value(Double(block)), b.value(Double(index)), b.value(value)])
    }
    let initialize = b.call("Execute", [set(4005, 0, 2), set(4005, 1, -0.025),
      set(4005, 2, 0), set(4005, 3, 72.5), set(4004, 0, 1)])
    let engine = try b.engine(archetypes: [[
      "name": "CustomInput", "hasInput": true, "imports": [], "exports": [],
      "initialize": ["index": initialize]]],
      buckets: [["sprites": [], "unit": "degrees"]])
    let locator = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "bucket-result", source: nil,
      version: 1, rating: 1, title: LocalizedText("Bucket Result"),
      artists: LocalizedText("Fixture"), author: "Fixture", tags: [],
      cover: locator, bgm: locator, data: locator)
    let store = ResultStore(rootURL: root)
    let model = GameplayModel(resultStore: store)
    model.prepare(bundle: RuntimeBundle(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "CustomInput", name: nil, data: [])]),
      bgmURL: url, isOffline: true, presentation: RuntimePresentation(resources: [
        "configuration": Data(#"{"options":[]}"#.utf8)])), level: level,
      server: ServerDescriptor(id: "bucket-result", name: "Fixture",
        baseURL: URL(string: "https://fixture.example")!), title: "Bucket Result")
    let previousSettings = model.settings
    defer { model.stop(); model.settings = previousSettings }
    model.settings = GameplayPreferences()
    model.start()
    for _ in 0..<1000 {
      model.engineFrame(size: CGSize(width: 800, height: 400), touches: [])
      if !model.noteTimings.isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let sample = try XCTUnwrap(model.noteTimings.first)
    XCTAssertEqual(sample.bucketIndex, 0)
    XCTAssertEqual(sample.bucketValue, 72.5)
    XCTAssertEqual(sample.accuracy, -0.025)
    // Signal the normal completion boundary; this is not an audio-duration test.
    model.playbackEnded()
    await model.resultSaveTask?.value
    XCTAssertEqual(model.phase, .finished)
    XCTAssertNil(model.resultSaveError)
    let results = try await store.allResults()
    let result = try XCTUnwrap(results.first)
    let loaded = try await store.details(for: result)
    XCTAssertEqual(loaded?.samples, [sample])
    XCTAssertEqual(loaded?.engineBuckets?.first?.definition.unit, "degrees")
    XCTAssertEqual(result.great, 1)
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

  private func bpm(beat: Double, value: Double) -> LevelEntity {
    LevelEntity(archetype: "#BPM_CHANGE", name: nil, data: [
      LevelEntityData(name: "#BEAT", value: beat, ref: nil),
      LevelEntityData(name: "#BPM", value: value, ref: nil)
    ])
  }
}
