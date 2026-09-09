import XCTest
@testable import OpenRhythm

final class RuntimeDecodingTests: XCTestCase {
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

    model.update(mediaTime: 1.05)
    model.press(lane: 0)
    model.press(lane: 0)
    XCTAssertEqual(model.score, 200_000)
    model.release(lane: 0)

    model.update(mediaTime: 2.05)
    model.slide(lane: 1)
    XCTAssertEqual(model.score, 400_000)
    model.release(lane: 1)

    model.update(mediaTime: 3.05)
    model.slide(lane: 2)
    XCTAssertEqual(model.score, 400_000, "Sliding cannot hit a tap note")
    model.release(lane: 2)
    model.press(lane: 2)
    model.release(lane: 2)

    model.update(mediaTime: 4.05)
    model.press(lane: 3)
    XCTAssertEqual(model.activeHoldIDs.count, 1)
    model.update(mediaTime: 5.05)
    model.release(lane: 3)
    model.release(lane: 3)

    XCTAssertEqual(model.score, NoteJudgement.maximumScore)
    XCTAssertEqual(model.maxCombo, 5)
    XCTAssertEqual(model.judgements[.perfect], 5)
    XCTAssertEqual(model.judgements[.miss], 0)
  }

  @MainActor
  func testGameplayCompletesAndSavesAfterAudioEnds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let model = try gameplayModel(resultStore: store)
    model.start()
    model.update(mediaTime: 1.05)
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
    model.advanceAfterAudioEnd(uptime: 200)
    XCTAssertEqual(model.judgements[.miss], 4)
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
    XCTAssertEqual(model.playbackTime, -0.05)
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
    resultStore: ResultStore = ResultStore()
  ) throws -> GameplayModel {
    let engine = try JSONDecoder().decode(
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
        isOffline: true
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
