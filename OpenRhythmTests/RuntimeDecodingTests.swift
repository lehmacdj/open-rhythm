import XCTest
import UIKit
@testable import OpenRhythm

final class RuntimeDecodingTests: XCTestCase {
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
    XCTAssertThrowsError(try interpreter.execute(nodeAt: 8))
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

  @MainActor
  func testGameplayCompletesAndSavesAfterAudioEnds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let model = try gameplayModel(resultStore: store)
    model.start()
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
