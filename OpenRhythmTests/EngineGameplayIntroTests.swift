import XCTest
import UIKit
import AVFoundation
@testable import OpenRhythm

final class EngineGameplayIntroTests: EngineHostTestCase {
  @MainActor
  func testGameplayIntroStopsForVisualEffectBeforeMusic() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "OpeningEffect")
  }

  @MainActor
  func testGameplayIntroSkipsUnchangedInitialScenery() async throws {
    try await checkGameplayIntro(appearanceTime: 0, spriteName: "#LANE")
  }

  @MainActor
  func testGameplayIntroPreservesInitiallyVisibleInputAndChangingOpening() async throws {
    try await checkGameplayIntro(appearanceTime: 0, spriteName: "InitialNote",
      earlyInput: true)
    try await checkGameplayIntro(appearanceTime: 0, spriteName: "CountIn",
      stageMovesAt: 0.5)
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
  func testGameplayIntroPassesStagePreparedFromFixedData() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
      earlyInput: true, preparedStage: true)
  }

  @MainActor
  func testGameplayIntroPassesShiftedFixedStageAndPreservesChanges() async throws {
    let moveTimes: [Double?] = [nil, 0.25]
    for movesAt in moveTimes {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
        shiftedStageRead: true)
    }
  }

  @MainActor
  func testGameplayIntroPassesResourceSelectedStageAndPreservesChanges() async throws {
    for function in ["HasSkinSprite", "HasEffectClip", "HasParticleEffect"] {
      let moveTimes: [Double?] = [nil, 0.25]
      for movesAt in moveTimes {
        try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
          earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
          stageResourceQuery: function)
      }
    }
  }

  @MainActor
  func testGameplayIntroPassesReadOnlyLocalStageAndPreservesChanges() async throws {
    for shifted in [false, true] {
      let moveTimes: [Double?] = [nil, 0.25]
      for movesAt in moveTimes {
        try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
          earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
          shiftedStageRead: shifted, stageMemoryBlock: 4000)
      }
    }
  }

  @MainActor
  func testGameplayIntroPassesInitializedScratchStageAndPreservesChanges() async throws {
    for movesAt: Double? in [nil, 0.25] {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
        stageMemoryBlock: 10000, computedStageSprite: true)
    }
  }

  @MainActor
  func testGameplayIntroPassesComputedStageIDAndPreservesChanges() async throws {
    let moveTimes: [Double?] = [nil, 0.25]
    for movesAt in moveTimes {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
        computedStageSprite: true)
    }
  }

  @MainActor
  func testGameplayIntroPassesFixedBranchSelectedStage() async throws {
    for branch in ["If", "Switch", "SwitchWithDefault", "SwitchInteger",
      "SwitchIntegerWithDefault"] {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, preparedBranch: branch)
    }
  }

  @MainActor
  func testGameplayIntroPassesPureLifecycleStageAndPreservesChanges() async throws {
    let moveTimes: [Double?] = [nil, 0.25]
    for movesAt in moveTimes {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, stageMovesAt: movesAt,
        stagePureCallbacks: true)
    }
  }

  @MainActor
  func testGameplayIntroFixedBranchStageStillPreservesVisibleChanges() async throws {
    for branch in ["If", "Switch", "SwitchWithDefault", "SwitchInteger",
      "SwitchIntegerWithDefault"] {
      try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
        earlyInput: true, preparedStage: true, stageMovesAt: 0.25,
        preparedBranch: branch)
    }
  }

  @MainActor
  func testGameplayIntroRewindsWhenAnotherEntityMovesPreparedStage() async throws {
    try await checkGameplayIntro(appearanceTime: 0.5, spriteName: "#LANE",
      earlyInput: true, preparedStage: true, stageMovesAt: 0.25)
  }

  @MainActor
  private func checkGameplayIntro(appearanceTime: Double, spriteName: String,
    rewind: Bool = false, earlyInput: Bool = false,
    resolveAt: Double? = nil, debugAtResolution: Bool = false,
    resolvesFutureInput: Bool = true, lifeChangeAt: Double? = nil,
    preparedStage: Bool = false, stageMovesAt: Double? = nil,
    preparedBranch: String? = nil,
    stagePureCallbacks: Bool = false,
    shiftedStageRead: Bool = false,
    stageResourceQuery: String? = nil,
    stageMemoryBlock: Int = 2001,
    computedStageSprite: Bool = false) async throws {
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
    if preparedStage {
      let coordinates = quad.indices.map {
        shiftedStageRead
          ? b.call("GetShifted", [b.value(Double(stageMemoryBlock)), b.value(0),
            b.value(Double($0)), b.value(1)])
          : b.call("Get", [b.value(Double(stageMemoryBlock)), b.value(Double($0))])
      }
      var writes = quad.enumerated().map { index, value in
        b.call("Set", [b.value(Double(stageMemoryBlock)), b.value(Double(index)),
          b.value(value)])
      }
      let stageID: Int
      if computedStageSprite {
        writes.append(b.call("Set", [b.value(Double(stageMemoryBlock)),
          b.value(8), b.value(1)]))
        stageID = b.call("Get", [b.value(Double(stageMemoryBlock)), b.value(8)])
      } else { stageID = b.value(1) }
      var stage = b.call("Draw", [stageID]
        + coordinates + [b.value(-1), b.value(1)])
      if let stageResourceQuery {
        // Skin is present, while effect/particle resources are absent. Both
        // branches still draw a stage, exercising true and fallback layouts.
        let fallback = b.call("Draw", [b.value(1)] + coordinates
          + [b.value(-1), b.value(0.75)])
        stage = b.call("If", [b.call(stageResourceQuery, [b.value(1)]),
          stage, fallback])
      }
      let selected = b.call("GreaterOr", [coordinates[0], b.value(-2)])
      switch preparedBranch {
      case "If": stage = b.call("If", [selected, stage, b.value(0)])
      case "Switch": stage = b.call("Switch", [selected, b.value(1), stage])
      case "SwitchWithDefault":
        stage = b.call("SwitchWithDefault", [selected, b.value(0), b.value(0), stage])
      case "SwitchInteger":
        stage = b.call("SwitchInteger", [selected, b.value(0), stage])
      case "SwitchIntegerWithDefault":
        stage = b.call("SwitchIntegerWithDefault", [selected, b.value(0), stage])
      default: break
      }
      archetypes.append(["name": "Stage", "hasInput": false,
        "imports": [], "exports": [],
        "preprocess": ["index": b.call("Execute0", writes)],
        "updateParallel": ["index": stageMemoryBlock == 10000
          ? b.call("Execute0", writes + [stage]) : stage]])
      if stagePureCallbacks {
        for callback in ["shouldSpawn", "initialize", "updateSequential",
          "touch", "terminate"] {
          archetypes[archetypes.count - 1][callback] = ["index": selected]
        }
      }
      entities.append(LevelEntity(archetype: "Stage", name: nil, data: []))
    }
    if let stageMovesAt {
      let move = b.call("Set", [b.value(1003), b.value(3), b.value(0.25)])
      archetypes.append(["name": "Mover", "hasInput": false,
        "imports": [], "exports": [], "updateSequential": ["index":
          b.call("If", [b.call("GreaterOr", [now, b.value(stageMovesAt)]),
            move, b.value(0)])]])
      entities.append(LevelEntity(archetype: "Mover", name: nil, data: []))
    }
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
    XCTAssertFalse(model.isStartingPlayback, model.startupDiagnostics)
    XCTAssertEqual(model.skippedIntroDuration,
      rewind || resolveAt != nil || lifeChangeAt != nil || stageMovesAt != nil
        ? 0 : appearanceTime == 0 && !earlyInput ? 1.95
          : min(appearanceTime, 1.95),
      accuracy: 1.0 / 60 + 1e-9,
      "Stop at visible content or 50 ms before the 2s audio onset")
    XCTAssertEqual(model.engineRuntime?.host.draws.count, preparedStage ? 2 : 1)
    if let stageResourceQuery {
      let stageDraws = try XCTUnwrap(model.engineRuntime).host.draws
        .filter(\.isStaticIntroDecoration)
      XCTAssertEqual(stageDraws.map(\.alpha),
        [stageResourceQuery == "HasSkinSprite" ? 1 : 0.75],
        "The present-resource or fallback branch must actually render")
    }
    if earlyInput {
      let runtime = try XCTUnwrap(model.engineRuntime)
      XCTAssertTrue(runtime.hasActivatedInput)
      XCTAssertEqual(runtime.resolvedInputCount, 0)
      XCTAssertTrue(runtime.judgments.isEmpty)
      XCTAssertEqual(model.judgements.values.reduce(0, +), 0)
      XCTAssertGreaterThanOrEqual(model.startupSteps,
        appearanceTime == 0 ? 1
          : resolveAt == nil && lifeChangeAt == nil && stageMovesAt == nil ? 31 : 16,
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
      if let stageMovesAt {
        XCTAssertEqual(runtime.memory.value(block: 1003, index: 3), 0)
        try runtime.update(at: stageMovesAt)
        XCTAssertEqual(runtime.memory.value(block: 1003, index: 3), 0.25,
          "The transform change must remain pending after rewind")
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

  func testStaticIntroScratchProofTracksInitializationAndLazyBranches() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1), scratch = b.value(10000)
    let read = b.call("Get", [scratch, zero])
    let write = b.call("Set", [scratch, zero, one])
    let add = b.call("SetAdd", [scratch, zero, one])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, read])
    let choice = b.call("Get", [b.value(2002), zero])
    let sequence: ([Int]) -> Int = { b.call("Execute0", $0) }
    let valid = [sequence([write, draw]), sequence([write, add, draw]),
      sequence([b.call("If", [choice, write, write]), draw]),
      sequence([write, b.call("If", [choice, add, zero]), draw]),
      b.call("If", [choice, sequence([write, draw]), zero])]
    let invalid = [draw, sequence([draw, write]), sequence([add, draw]),
      sequence([b.call("If", [choice, write, zero]), draw]),
      sequence([b.call("And", [zero, write]), draw]),
      sequence([b.call("Or", [one, write]), draw]),
      sequence([b.call("SwitchInteger", [choice, write]), draw]),
      sequence([b.call("Switch", [choice, zero, read, write, zero]), draw]),
      sequence([b.call("Set", [scratch, zero,
        b.call("Get", [b.value(1001), zero])]), draw]),
      sequence([b.call("Set", [scratch, zero,
        b.call("Random", [zero, one])]), draw]),
      sequence([write, b.call("Set", [b.value(4000), zero, read]), draw])]
    let archetypes: [[String: Any]] = (valid + invalid).map {
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": $0]]
    }
    let engine = try b.engine(archetypes: archetypes,
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, Set(valid.indices))
    let reversed = try b.engine(archetypes: Array(archetypes.reversed()),
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(reversed.staticIntroArchetypes,
      Set(valid.indices.map { archetypes.count - 1 - $0 }),
      "A shared read proof must not inherit another callback's initialization")
    let crossCallback = try b.engine(archetypes: [[
      "name": "Stage", "hasInput": false, "imports": [], "exports": [],
      "initialize": ["index": write], "updateParallel": ["index": draw]]],
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertTrue(crossCallback.staticIntroArchetypes.isEmpty,
      "Scratch initialization never carries across callbacks")
  }

  func testStaticIntroScratchReadModifyWriteRequiresOldValue() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1), scratch = b.value(10000)
    let write = b.call("Set", [scratch, zero, one])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    let binary = ["SetAdd", "SetSubtract", "SetMultiply", "SetDivide",
      "SetPower", "SetMod", "SetRem"]
    let unary = ["IncrementPre", "IncrementPost", "DecrementPre", "DecrementPost"]
    var callbacks = [Int]()
    var accepted = Set<Int>()
    for function in binary + unary {
      // Reading the old value precedes evaluation of even a same-slot Set.
      let operand = binary.contains(function) ? [write] : []
      let operation = b.call(function, [scratch, zero] + operand)
      callbacks.append(b.call("Execute0", [operation, draw]))
      accepted.insert(callbacks.count)
      callbacks.append(b.call("Execute0", [write, operation, draw]))
    }
    let engine = try b.engine(archetypes: callbacks.map {
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": $0]]
    }, sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, accepted)
  }

  func testStaticIntroScratchAddressesAndSummaryBudget() throws {
    func makeEngine(slotCount: Int) throws -> EnginePlayData {
      let b = RuntimeNodeBuilder()
      let zero = b.value(0), one = b.value(1), scratch = b.value(10000)
      var callback = zero
      for slot in 0..<slotCount {
        callback = b.call("Execute0", [callback,
          b.call("Set", [scratch, b.value(Double(slot)), one])])
      }
      callback = b.call("Execute0", [callback,
        b.call("Draw", [one] + quad.map(b.value) + [zero, one])])
      return try b.engine(archetypes: [["name": "Stage", "hasInput": false,
        "imports": [], "exports": [], "updateParallel": ["index": callback]]],
        sprites: [["name": "#LANE", "id": 1]])
    }
    XCTAssertEqual(try makeEngine(slotCount: 8).staticIntroArchetypes, [0])
    XCTAssertTrue(try makeEngine(slotCount: 512).staticIntroArchetypes.isEmpty,
      "Small graphs with growing dependency sets must still have bounded work")

    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1), scratch = b.value(10000)
    let addresses = [-0.5, 0.9, -1, 4096, Double.greatestFiniteMagnitude]
      .map(b.value) + [b.call("Add", [zero, zero])]
    let callbacks = addresses.map { address in
      b.call("Execute0", [b.call("Set", [scratch, zero, one]),
        b.call("Draw", [one] + quad.map(b.value)
          + [zero, b.call("Get", [scratch, address])])])
    }
    let engine = try b.engine(archetypes: callbacks.map {
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": $0]]
    }, sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0, 1],
      "Direct addresses truncate toward zero; computed scratch stays unproven")
  }

  func testStaticIntroProofAcceptsPreparedExpressionsAndSharedDraws() throws {
    let b = RuntimeNodeBuilder()
    let one = b.value(1)
    let index = b.call("Add", [b.value(0), b.value(0)])
    let fixed = [2001, 2002, 3000, 4001].map {
      b.call("Get", [b.value(Double($0)), index])
    }
    let width = b.call("If", [one,
      b.call("Max", [one, b.call("Add", fixed)]), one])
    let left = b.call("Negate", [width])
    let alpha = b.call("EaseInSine", [one])
    let draw = b.call("Draw", [one, left, left, left, width,
      width, width, width, left, b.value(0), alpha])
    let curved = b.call("DrawCurvedLR", [one, left, left, left, width,
      width, width, width, left, b.value(0), one, b.value(2),
      left, b.value(0), width, b.value(0)])
    let callback = b.call("Execute0", [draw, curved, draw])
    let prepare = b.call("Execute0", [
      b.call("Set", [b.value(2001), b.value(0),
        b.call("Random", [one, b.value(2)])]),
      b.call("Set", [b.value(4101), b.value(0), b.value(0.25)])])
    let engine = try b.engine(archetypes: [["name": "Stage", "hasInput": false,
      "imports": [], "exports": [], "preprocess": ["index": prepare],
      "updateParallel": ["index": callback]]],
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Stage", name: nil, data: [])]),
      options: [1], aspectRatio: 2, skinSpriteIDs: [1], effectClipIDs: [],
      particleEffectIDs: [])
    var preparedDraws: [EngineDrawCommand]?
    for time in [0.0, 0.25, 0.5] {
      try runtime.update(at: time)
      XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration),
        [true, true, true])
      if let preparedDraws { XCTAssertEqual(runtime.host.draws, preparedDraws) }
      else { preparedDraws = runtime.host.draws }
    }
    runtime.restart()
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.host.draws, preparedDraws,
      "Prepared random values remain fixed across restart")
  }

  func testStaticIntroProofAcceptsOnlyImmutableShiftedReads() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let fixedBlock = b.value(2001)
    let fixedIndex = b.call("Get", [b.value(2002), zero])
    let valid = [2001, 2002, 3000, 4001].map {
      b.call("GetShifted", [b.value(Double($0)), zero, fixedIndex, one])
    }
    let mutable = b.call("Get", [b.value(1001), zero])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    var invalid = [1001, 1002, 1003, 2000, 4002, 4003, 4004,
      4005, 4101, 4102, 4103, 10000].map {
      b.call("GetShifted", [b.value(Double($0)), zero, zero, one])
    }
    for index in 1...3 {
      for unsafe in [mutable, draw, b.call("Random", [zero, one]),
        b.call("Set", [b.value(4000), zero, one])] {
        var args = [fixedBlock, zero, zero, one]
        args[index] = unsafe
        invalid.append(b.call("GetShifted", args))
      }
    }
    // Fixed pointer storage does not prove its target block is immutable.
    invalid += [b.call("GetPointed", [fixedBlock, zero, zero]),
      b.call("GetShifted", [fixedBlock, zero, zero]),
      b.call("GetShifted", [fixedBlock, zero, zero, one, zero])]
    let engine = try b.engine(archetypes: (valid + invalid).map { read in
      let callback = b.call("Draw", [one] + quad.map(b.value) + [zero, read])
      return ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": callback]]
    }, sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, Set(valid.indices))
  }

  func testStaticIntroProofResourceQueriesRequireFixedPureIDs() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let fixed = b.call("GetShifted", [b.value(2002), zero, zero, one])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    let mutable = b.call("Get", [b.value(1001), zero])
    let unsafe = [mutable, draw, b.call("Random", [zero, one]),
      b.call("Set", [b.value(4000), zero, one])]
    var valid = [Int](), invalid = [Int]()
    for function in ["HasSkinSprite", "HasEffectClip", "HasParticleEffect"] {
      for id in [one, fixed] {
        valid.append(b.call(function, [id]))
      }
      invalid += unsafe.map { b.call(function, [$0]) }
      invalid += [b.call(function, []), b.call(function, [one, zero])]
    }
    let engine = try b.engine(archetypes: (valid + invalid).map { query in
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "shouldSpawn": ["index": query],
        "updateParallel": ["index": b.call("If", [query, draw, zero])]]
    }, sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, Set(valid.indices))
  }

  func testStaticIntroProofLocalReadsRequireReadOnlyLifecycle() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1), local = b.value(4000)
    let read = b.call("Get", [local, zero])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, read])
    let callbacks = ["shouldSpawn", "initialize", "updateSequential", "touch",
      "updateParallel", "terminate"]
    let base: [String: Any] = ["name": "Stage", "hasInput": false,
      "imports": [], "exports": [], "updateParallel": ["index": draw]]
    var archetypes = [base]
    let mutations = [
      b.call("Set", [local, zero, one]),
      b.call("SetShifted", [local, zero, zero, one, one]),
      b.call("SetPointed", [local, zero, zero, one]),
      b.call("IncrementPost", [local, zero]),
      b.call("Copy", [local, zero, local, one, one])]
    for callback in callbacks {
      for mutation in mutations {
        var candidate = base
        // Even an unselected writing branch disqualifies the whole entity.
        candidate[callback] = ["index": b.call("If", [one,
          callback == "updateParallel" ? draw : read, mutation])]
        archetypes.append(candidate)
      }
    }
    let engine = try b.engine(archetypes: archetypes,
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0])
    XCTAssertEqual(try b.engine(archetypes: Array(archetypes.reversed()),
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes,
      [archetypes.count - 1], "Shared memoized reads cannot hide a writer")
  }

  func testStaticIntroLocalMemoryKeepsEntityIsolationSpawnAndRestart() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1), local = b.value(4000)
    let read = b.call("Get", [local, zero])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, read])
    let now = b.call("Get", [b.value(1001), zero])
    let other = b.call("Execute0", [
      b.call("Set", [local, zero, now]),
      b.call("If", [b.call("Equal", [now, zero]),
        b.call("Spawn", [zero, b.value(0.9)]), zero])])
    let engine = try b.engine(archetypes: [
      ["name": "Stage", "hasInput": false,
        "imports": [["name": "alpha", "index": 0]], "exports": [],
        "preprocess": ["index": b.call("Set", [local, zero,
          b.call("Get", [b.value(4001), zero])])],
        "spawnOrder": ["index": b.call("Set", [local, one, b.value(7)])],
        "shouldSpawn": ["index": b.call("Get", [local, one])],
        "initialize": ["index": read], "touch": ["index": read],
        "updateSequential": ["index": read], "terminate": ["index": read],
        "updateParallel": ["index": draw]],
      ["name": "Other", "hasInput": false, "imports": [], "exports": [],
        "updateSequential": ["index": other]]],
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [
        LevelEntity(archetype: "Stage", name: nil,
          data: [LevelEntityData(name: "alpha", value: 0.25, ref: nil)]),
        LevelEntity(archetype: "Stage", name: nil,
          data: [LevelEntityData(name: "alpha", value: 0.75, ref: nil)]),
        LevelEntity(archetype: "Other", name: nil, data: [])]),
      options: [], aspectRatio: 2, skinSpriteIDs: [1], effectClipIDs: [],
      particleEffectIDs: [])
    for _ in 0..<2 {
      try runtime.update(at: 0)
      XCTAssertEqual(runtime.host.draws.map(\.alpha), [0.25, 0.75])
      XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration), [true, true])
      try runtime.update(at: 0.25)
      XCTAssertEqual(runtime.host.draws.map(\.alpha), [0.25, 0.75, 0.9])
      XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration),
        [true, true, false], "Dynamically spawned copies are not initial decoration")
      runtime.restart()
    }
  }

  func testComputedIntroStageIDsRetainResolvedSpriteClassification() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let id = b.call("Get", [b.value(4001), zero])
    let draw = b.call("Draw", [id] + quad.map(b.value) + [zero, one])
    let engine = try b.engine(archetypes: [[
      "name": "Stage", "hasInput": false,
      "imports": [["name": "sprite", "index": 0]], "exports": [],
      "updateParallel": ["index": draw]]], sprites: [
        ["name": "#LANE", "id": 1], ["name": "READY", "id": 2],
        ["name": "#LANE", "id": 3], ["name": "READY", "id": 3],
        ["name": "#STAGE_MIDDLE", "id": 4]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0],
      "A fixed computed ID is a candidate, not proof of its sprite name")
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: (1...4).map {
        LevelEntity(archetype: "Stage", name: nil,
          data: [LevelEntityData(name: "sprite", value: Double($0), ref: nil)])
      }), options: [], aspectRatio: 2, skinSpriteIDs: [1, 2, 3],
      effectClipIDs: [], particleEffectIDs: [])
    for _ in 0..<2 {
      try runtime.update(at: 0)
      XCTAssertEqual(runtime.host.draws.map(\.spriteID), [1, 2, 3],
        "Missing sprites remain unavailable, regardless of metadata")
      XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration),
        [true, false, false], "Custom and ambiguous IDs must remain visible effects")
      runtime.restart()
    }
    let unsafeIDs = [b.call("Get", [b.value(1001), zero]),
      b.call("Random", [one, b.value(2)]), draw,
      b.call("Set", [b.value(4000), zero, one])]
    let unsafe = try b.engine(archetypes: unsafeIDs.map { id in
      ["name": "Dynamic", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": b.call("Draw",
          [id] + quad.map(b.value) + [zero, one])]]
    }, sprites: [["name": "#LANE", "id": 1]])
    XCTAssertTrue(unsafe.staticIntroArchetypes.isEmpty)
  }

  func testIntroBranchValidatesOnlyResolvedDrawIdentities() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    let custom = b.call("Draw", [b.value(2)] + quad.map(b.value) + [zero, one])
    let choice = b.call("Get", [b.value(4001), zero])
    let engine = try b.engine(archetypes: [["name": "Choice", "hasInput": false,
      "imports": [["name": "choice", "index": 0]], "exports": [],
      "updateParallel": ["index": b.call("If", [choice, draw, custom])]]],
      sprites: [["name": "#LANE", "id": 1], ["name": "READY", "id": 2]])
    XCTAssertEqual(engine.staticIntroArchetypes, [0])
    let runtime = try EnginePlayRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [1.0, 0].map {
        LevelEntity(archetype: "Choice", name: nil,
          data: [LevelEntityData(name: "choice", value: $0, ref: nil)])
      }), options: [], aspectRatio: 2, skinSpriteIDs: [1, 2], effectClipIDs: [],
      particleEffectIDs: [])
    try runtime.update(at: 0)
    XCTAssertEqual(runtime.host.draws.map(\.spriteID), [1, 2])
    XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration), [true, false],
      "An unselected custom branch is not visible; a selected one is an effect")
  }

  func testStaticIntroProofClassifiesFixedSelectionBranches() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let fixed = b.call("Get", [b.value(2002), zero])
    let mutable = b.call("Get", [b.value(1001), zero])
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    let custom = b.call("Draw", [b.value(2)] + quad.map(b.value) + [zero, one])
    func branches(_ selector: Int, _ value: Int) -> [Int] {
      [b.call("If", [selector, value, zero]),
       b.call("Switch", [selector, one, value]),
       b.call("SwitchWithDefault", [selector, zero, zero, value]),
       b.call("SwitchInteger", [selector, zero, value]),
       b.call("SwitchIntegerWithDefault", [selector, zero, value])]
    }
    var valid = branches(fixed, draw)
    let nested = b.call("If", [fixed, valid[1], zero])
    valid.append(nested)
    valid += branches(fixed, custom)
      + [b.call("SwitchInteger", [zero, draw, custom])]
    let random = b.call("Random", [zero, one])
    let write = b.call("Set", [b.value(4000), zero, one])
    let invalid = branches(mutable, draw) + branches(draw, draw)
      + branches(fixed, mutable)
      + branches(fixed, random) + branches(fixed, write) + [
        b.call("If", [nested, draw, zero]),
        b.call("Draw", [one] + quad.map(b.value) + [zero, nested]),
        b.call("Get", [b.value(2001), nested]),
        b.call("If", [one, draw, random]),
        b.call("SwitchWithDefault", [one, one, draw, write]),
        b.call("Switch", [fixed, draw, draw]),
        b.call("SwitchWithDefault", [fixed, draw, draw, zero]),
        b.call("If", [fixed, draw]), b.call("Switch", [fixed, draw]),
        b.call("SwitchWithDefault", [fixed]),
        b.call("SwitchInteger", []), b.call("SwitchIntegerWithDefault", [fixed])]
    let engine = try b.engine(archetypes: (valid + invalid).map {
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": $0]]
    }, sprites: [["name": "#LANE", "id": 1], ["name": "READY", "id": 2]])
    XCTAssertEqual(engine.staticIntroArchetypes, Set(valid.indices))
  }

  func testStaticIntroProofAcceptsOnlyPureLifecycleCallbacks() throws {
    let b = RuntimeNodeBuilder()
    let zero = b.value(0), one = b.value(1)
    let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
    let fixed = b.call("Get", [b.value(2002), zero])
    let pure = b.call("If", [fixed, b.call("Add", [one, zero]), zero])
    let unsafe = [draw,
      b.call("Get", [b.value(1001), zero]),
      b.call("Set", [b.value(4004), zero, one]),
      b.call("Random", [zero, one]), b.call("Spawn", [zero]),
      b.call("Play", [one, zero]),
      b.call("If", [one, pure, draw])]
    let callbacks = ["shouldSpawn", "initialize", "updateSequential",
      "touch", "terminate"]
    let base: [String: Any] = ["name": "Stage", "hasInput": false,
      "imports": [], "exports": [], "updateParallel": ["index": draw]]
    var archetypes = [[String: Any]]()
    for callback in callbacks {
      var candidate = base
      candidate[callback] = ["index": pure]
      archetypes.append(candidate)
    }
    var combined = base
    for callback in callbacks { combined[callback] = ["index": pure] }
    archetypes.append(combined)
    let accepted = Set(archetypes.indices)
    for callback in callbacks {
      for expression in unsafe {
        var candidate = combined
        candidate[callback] = ["index": expression]
        archetypes.append(candidate)
      }
    }
    let engine = try b.engine(archetypes: archetypes,
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(engine.staticIntroArchetypes, accepted,
      "Non-drawing callbacks require pure proof, not merely safe stage draws")
    let reversed = try b.engine(archetypes: Array(archetypes.reversed()),
      sprites: [["name": "#LANE", "id": 1]])
    XCTAssertEqual(reversed.staticIntroArchetypes,
      Set(accepted.map { archetypes.count - 1 - $0 }),
      "Memoized draw proofs must stay distinct in either traversal order")
  }

  func testPureIntroCallbacksKeepSpawnAndDespawnSemantics() throws {
    for shouldSpawn in [0.0, 1.0] {
      for despawn in [0.0, 1.0] {
        let b = RuntimeNodeBuilder()
        let one = b.value(1), zero = b.value(0)
        let draw = b.call("Draw", [one] + quad.map(b.value) + [zero, one])
        let engine = try b.engine(archetypes: [[
          "name": "Stage", "hasInput": false, "imports": [], "exports": [],
          "preprocess": ["index": b.call("Set",
            [b.value(4004), zero, b.value(despawn)])],
          "shouldSpawn": ["index": b.value(shouldSpawn)],
          "initialize": ["index": one], "updateSequential": ["index": one],
          "touch": ["index": one], "terminate": ["index": one],
          "updateParallel": ["index": draw]]],
          sprites: [["name": "#LANE", "id": 1]])
        XCTAssertEqual(engine.staticIntroArchetypes, [0])
        let runtime = try EnginePlayRuntime(engine: engine,
          level: LevelData(bgmOffset: 0, entities: [
            LevelEntity(archetype: "Stage", name: nil, data: [])]),
          options: [], aspectRatio: 2, skinSpriteIDs: [1], effectClipIDs: [],
          particleEffectIDs: [])
        let origin = EnginePoint(x: 0, y: 0)
        let touch = EngineTouch(id: 1, started: true, ended: false,
          time: 0, startTime: 0, position: origin, startPosition: origin,
          delta: origin)
        try runtime.update(at: 0, touches: [touch])
        XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration),
          shouldSpawn == 0 ? [] : [despawn == 0])
        try runtime.update(at: 0.5)
        XCTAssertEqual(runtime.host.draws.map(\.isStaticIntroDecoration),
          shouldSpawn == 0 || despawn != 0 ? [] : [true],
          "Only the despawn block retires the stage, not pure callback returns")
      }
    }
  }

  func testStaticIntroProofRejectsMutableArgumentExpressionsAndCycles() throws {
    let b = RuntimeNodeBuilder()
    let one = b.value(1)
    let mutable = [1001, 1002, 1003, 2000, 4002, 4003, 4004,
      4005, 4102, 4103, 10000].map {
      b.call("Get", [b.value(Double($0)), b.value(0)])
    }
    let random = b.call("Random", [b.value(0), one])
    let stream = b.call("StreamGetValue", [b.value(0), b.value(0)])
    let write = b.call("Set", [b.value(4000), b.value(0), one])
    let indirectBlock = b.call("Get", [
      b.call("Get", [b.value(2002), b.value(0)]), b.value(0)])
    let archetypes: [[String: Any]] = (mutable + [random, stream, write,
      indirectBlock]).map { expression in
      let alpha = b.call("Add", [one, expression])
      let draw = b.call("Draw", [one] + quad.map(b.value) + [b.value(0), alpha])
      return ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": draw]]
    }
    XCTAssertTrue(try b.engine(archetypes: archetypes,
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes.isEmpty)
    let cycle = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[{"id":1,"name":"#LANE"}]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[{"name":"Cycle","hasInput":false,"imports":[],
         "exports":[],"updateParallel":{"index":0}}],
       "nodes":[{"func":"Execute","args":[0]}]}
      """#.utf8))
    XCTAssertTrue(cycle.staticIntroArchetypes.isEmpty)
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
      candidate[callback] = ["index": now]
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
      sprites: [["name": "READY", "id": 1]]).introStageSpriteIDs.isEmpty)
    XCTAssertTrue(try b.engine(archetypes: [base], sprites: [
      ["name": "#LANE", "id": 1], ["name": "READY", "id": 1]
    ]).introStageSpriteIDs.isEmpty, "Ambiguous resource IDs are not proof")
  }

  func testStaticIntroProofSeparatesDrawEffectsAndBoundsGraphWork() throws {
    let b = RuntimeNodeBuilder()
    let one = b.value(1)
    let draw = b.call("Draw", [one] + quad.map(b.value) + [b.value(0), one])
    let contaminated = b.call("Add", [draw, one])
    let nested = b.call("Draw", [one] + quad.map(b.value)
      + [b.value(0), contaminated])
    let conditional = b.call("If", [draw, draw, draw])
    let roots = [b.call("Execute", [draw, contaminated]),
      b.call("Execute", [contaminated, draw]), nested, conditional]
    func archetype(_ root: Int) -> [String: Any] {
      ["name": "Stage", "hasInput": false, "imports": [], "exports": [],
        "updateParallel": ["index": root]]
    }
    XCTAssertTrue(try b.engine(archetypes: roots.map(archetype),
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes.isEmpty,
      "A cached drawing proof must not become a pure-expression proof")
    var deep = draw
    for _ in 0..<12_000 { deep = b.call("Execute0", [deep]) }
    XCTAssertEqual(try b.engine(archetypes: [archetype(deep)],
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes, [0],
      "Analysis uses an explicit stack, independent of Swift call-stack depth")
    let tooWide = b.call("Execute0", Array(repeating: draw, count: 100_000))
    XCTAssertTrue(try b.engine(archetypes: [archetype(tooWide)],
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes.isEmpty,
      "Excessive proof work preserves the intro rather than trusting the graph")
    let invalid = b.call("Execute0", [-1])
    XCTAssertTrue(try b.engine(archetypes: [archetype(invalid)],
      sprites: [["name": "#LANE", "id": 1]]).staticIntroArchetypes.isEmpty)
    let indirectCycle = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[{"name":"Cycle","hasInput":false,"imports":[],
         "exports":[],"updateParallel":{"index":0}}],
       "nodes":[{"func":"Execute","args":[1]},
         {"func":"Execute0","args":[0]}]}
      """#.utf8))
    XCTAssertTrue(indirectCycle.staticIntroArchetypes.isEmpty)
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
      isStatic: Bool = true, isInput: Bool = false) -> EngineRenderSprite {
      EngineRenderSprite(image: image,
        points: [EnginePoint(x: x - 0.5, y: -0.5),
          EnginePoint(x: x - 0.5, y: 0.5),
          EnginePoint(x: x + 0.5, y: 0.5),
          EnginePoint(x: x + 0.5, y: -0.5)],
        matrix: identity, alpha: alpha, interpolation: false,
        isStaticIntroDecoration: isStatic, isInputVisual: isInput)
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
      hasParticles: false), .advance,
      "Approved policy treats unchanged initial non-input graphics as scenery")
    XCTAssertEqual(held.observe(frame([sprite(alpha: 0.5, isStatic: false)]),
      hasParticles: false), .rewind, "A held count-in still retains its beginning")
    var input = EngineIntroVisualGuard()
    XCTAssertEqual(input.observe(frame([sprite(isStatic: false, isInput: true)]),
      hasParticles: false), .stop, "An initial visible note is not scenery")
    var deferred = EngineIntroVisualGuard()
    XCTAssertEqual(deferred.observe(frame([]), hasParticles: false), .advance)
    let customStage = frame([sprite(isStatic: false)])
    XCTAssertEqual(deferred.observe(customStage, hasParticles: false), .advance)
    XCTAssertEqual(deferred.observe(customStage, hasParticles: false), .advance)
    XCTAssertEqual(deferred.observe(frame([sprite(isStatic: false),
      sprite(x: 1, isStatic: false)]), hasParticles: false), .stop,
      "Only the first deferred cycle may add initial scenery, not later effects")
    var deferredInput = EngineIntroVisualGuard()
    _ = deferredInput.observe(frame([]), hasParticles: false)
    XCTAssertEqual(deferredInput.observe(frame([sprite(isInput: true)]),
      hasParticles: false), .stop)
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
}
