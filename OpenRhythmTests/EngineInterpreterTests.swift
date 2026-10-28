import XCTest
import UIKit
@testable import OpenRhythm

final class EngineInterpreterTests: EngineHostTestCase {
  @MainActor
  func testNumericResourceIDsSurviveHostCommandsAndAudioPools() throws {
    let ids: Set<EngineResourceID> = [0.5, 0.75, -9999.5, 1e100]
    let host = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: ids,
      effectClipIDs: ids, particleEffectIDs: ids, archetypeCount: 1)
    var voices = [EngineResourceID: [MockEffectVoice]]()
    let audio = try EngineAudioPlayback(clips:
      Dictionary(uniqueKeysWithValues: ids.map { ($0, Data()) }),
      makeVoice: { id, _ in
        let voice = MockEffectVoice()
        voices[id, default: []].append(voice)
        return voice
      })
    defer { audio.stop() }
    var loopHandles = [Double](), particleHandles = [Double]()
    for id in ids.sorted() {
      for function in ["HasSkinSprite", "HasEffectClip", "HasParticleEffect"] {
        XCTAssertEqual(try host.call(function: function, arguments: [id]), 1)
        XCTAssertEqual(try host.call(function: function, arguments: [0.6]), 0)
        XCTAssertThrowsError(try host.call(function: function, arguments: [.nan]))
      }
      for suffix in ["", "CurvedB", "CurvedT", "CurvedL", "CurvedR",
        "CurvedBT", "CurvedLR"] {
        let controls: [Double] = suffix.isEmpty ? []
          : suffix.count == 8 ? [1, 0, 0, 0, 0] : [1, 0, 0]
        _ = try host.call(function: "Draw" + suffix,
          arguments: [id] + quad + [0, 1] + controls)
        XCTAssertEqual(host.draws.last?.spriteID, id)
      }
      _ = try host.call(function: "Play", arguments: [id, 1])
      loopHandles.append(try host.call(function: "PlayLooped", arguments: [id]))
      particleHandles.append(try host.call(function: "SpawnParticleEffect",
        arguments: [id] + quad + [1, 0]))
    }
    XCTAssertEqual(Set(host.particles.values.map(\.effectID)), ids)
    let commands = host.takeAudioCommands()
    XCTAssertEqual(Set(commands.map(\.clipID)), ids)
    try audio.update(commands, at: 0, loopCommands: host.takeLoopCommands())
    for id in ids {
      XCTAssertEqual(voices[id]?.flatMap(\.looping).sorted { !$0 && $1 },
        [false, true], "Both one-shot and loop pools preserve the clip ID")
      _ = try host.call(function: "PlayScheduled", arguments: [id, 2, 0])
      _ = try host.call(function: "PlayLoopedScheduled", arguments: [id, 2])
    }
    XCTAssertEqual(Set(host.takeAudioCommands().map(\.clipID)), ids)
    for command in host.takeLoopCommands() {
      guard case .start(_, let clipID, let time) = command else {
        return XCTFail("Expected a scheduled loop start")
      }
      XCTAssertTrue(ids.contains(clipID))
      XCTAssertEqual(time, 2)
    }
    for handle in loopHandles {
      _ = try host.call(function: "StopLooped", arguments: [handle])
    }
    for handle in particleHandles {
      _ = try host.call(function: "DestroyParticleEffect", arguments: [handle])
    }
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertThrowsError(try host.call(function: "Spawn", arguments: [0.5]))
    XCTAssertThrowsError(try host.call(function: "ExportValue", arguments: [0.5, 1]))
    XCTAssertThrowsError(try host.call(function: "DrawCurvedB",
      arguments: [0.5] + quad + [0, 1, 1.5, 0, 0]))
  }

  @MainActor
  func testResourceLimitErrorsIdentifyTheFailingSubsystem() throws {
    func check(_ context: String, _ action: () throws -> Void) {
      XCTAssertThrowsError(try action()) { error in
        XCTAssertTrue(error.localizedDescription.contains(context),
          "Expected \(context) context, got \(error.localizedDescription)")
        XCTAssertFalse(error.localizedDescription.contains("callback"),
          "A resource failure must not blame callback instruction execution")
      }
    }
    let host = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [7],
      effectClipIDs: [8], particleEffectIDs: [], archetypeCount: 0,
      streamEntryLimit: 0)
    check("stream entries") {
      _ = try host.call(function: "StreamSet", arguments: [0, 0, 1])
    }
    check("draw segments per frame") {
      _ = try host.call(function: "DrawCurvedB",
        arguments: [7] + quad + [0, 1, 16_385, 0, 0])
    }
    for _ in 0..<256 {
      _ = try host.call(function: "PlayLooped", arguments: [8])
    }
    check("active audio loops") {
      _ = try host.call(function: "PlayLooped", arguments: [8])
    }
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      MockEffectVoice()
    }
    check("queued audio commands") {
      try audio.update(Array(repeating: EngineAudioCommand(
        clipID: 8, time: 100, minimumDistance: 0), count: 16_385), at: 0)
    }
    check("effect audio clips") {
      _ = try EngineAudioPlayback(clips: Dictionary(uniqueKeysWithValues:
        (0..<257).map { (Double($0), Data()) }), makeVoice: { _, _ in
          XCTFail("Clip-count rejection must precede voice allocation")
          return MockEffectVoice()
        })
    }
    check("software render size") {
      _ = try EngineSoftwareRenderer.render([], size: CGSize(width: 0, height: 1))
    }
    let interpreter = EngineInterpreter(nodes: [EngineDataNode(value: 1)],
      operationLimit: 0)
    XCTAssertThrowsError(try interpreter.execute(nodeAt: 0)) { error in
      XCTAssertTrue(error.localizedDescription.contains("callback"))
    }
  }

  func testPublicFunctionInventoryMatchesDispatchAndPreflight() throws {
    // Independent name inventory from Sonolus/runtime-metadata, revision
    // 8da7fab2580701fdff82e10224f428db05add4bc, Runtime/Functions.json.
    // Keep unresolved functions explicit. This is dispatch coverage, not a
    // substitute for each function's behavioral conformance tests.
    let names = """
      Abs Add AddLifeScheduled And Arccos Arcsin Arctan Arctan2 BeatToBPM
      BeatToStartingBeat BeatToStartingTime BeatToTime Block Break Ceil Clamp
      Copy Cos Cosh DebugLog DebugPause DecrementPost DecrementPostPointed
      DecrementPostShifted DecrementPre DecrementPrePointed DecrementPreShifted
      Degree DestroyParticleEffect Divide DoWhile Draw DrawCurvedB DrawCurvedBT
      DrawCurvedL DrawCurvedLR DrawCurvedR DrawCurvedT EaseInBack EaseInCirc
      EaseInCubic EaseInElastic EaseInExpo EaseInOutBack EaseInOutCirc
      EaseInOutCubic EaseInOutElastic EaseInOutExpo EaseInOutQuad EaseInOutQuart
      EaseInOutQuint EaseInOutSine EaseInQuad EaseInQuart EaseInQuint EaseInSine
      EaseOutBack EaseOutCirc EaseOutCubic EaseOutElastic EaseOutExpo
      EaseOutInBack EaseOutInCirc EaseOutInCubic EaseOutInElastic EaseOutInExpo
      EaseOutInQuad EaseOutInQuart EaseOutInQuint EaseOutInSine EaseOutQuad
      EaseOutQuart EaseOutQuint EaseOutSine Equal Execute Execute0 ExportValue
      Floor Frac Get GetPointed GetShifted Greater GreaterOr HasEffectClip
      HasParticleEffect HasSkinSprite If IncrementPost IncrementPostPointed
      IncrementPostShifted IncrementPre IncrementPrePointed IncrementPreShifted
      Judge JudgeSimple JumpLoop Lerp LerpClamped Less LessOr Log Max Min Mod
      MoveParticleEffect Multiply Negate Not NotEqual Or Paint Play PlayLooped
      PlayLoopedScheduled PlayScheduled Power Print Radian Random RandomInteger
      Rem Remap RemapClamped Round Set SetAdd SetAddPointed SetAddShifted
      SetDivide SetDividePointed SetDivideShifted SetMod SetModPointed
      SetModShifted SetMultiply SetMultiplyPointed SetMultiplyShifted SetPointed
      SetPower SetPowerPointed SetPowerShifted SetRem SetRemPointed SetRemShifted
      SetShifted SetSubtract SetSubtractPointed SetSubtractShifted Sign Sin Sinh
      Spawn SpawnParticleEffect StackEnter StackGet StackGetFrame
      StackGetFramePointer StackGetPointer StackGrow StackInit StackLeave
      StackPop StackPush StackSet StackSetFrame StackSetFramePointer
      StackSetPointer StopLooped StopLoopedScheduled StreamGetNextKey
      StreamGetPreviousKey StreamGetValue StreamHas StreamSet Subtract Switch
      SwitchInteger SwitchIntegerWithDefault SwitchWithDefault Tan Tanh
      TimeToScaledTime TimeToStartingScaledTime TimeToStartingTime TimeToTimeScale
      Trunc Unlerp UnlerpClamped While
      """.split(whereSeparator: \.isWhitespace).map(String.init)
    let inventory = Set(names)
    XCTAssertEqual(names.count, 191)
    XCTAssertEqual(inventory.count, names.count, "No duplicated inventory names")
    let stack: Set<String> = ["StackEnter", "StackGet", "StackGetFrame",
      "StackGetFramePointer", "StackGetPointer", "StackGrow", "StackInit",
      "StackLeave", "StackPop", "StackPush", "StackSet", "StackSetFrame",
      "StackSetFramePointer", "StackSetPointer"]
    let nonPlay: Set<String> = ["Paint", "Print"]
    let unavailable = stack.union(nonPlay)
    let supported = EngineInterpreter.supportedFunctions
      .union(CommandEngineRuntimeHost.supportedFunctions)
    XCTAssertEqual(supported, inventory.subtracting(unavailable),
      "A registration change requires reconciling the public API audit")
    XCTAssertEqual(supported.count, 175)
    // Declared parameter counts from the same independent metadata, including
    // optional draw depths and repeated judgment windows. Variadics use their
    // minimum count. Names not listed here take one argument.
    let arityGroups: [Int: String] = [
      0: "DebugPause StackGetFramePointer StackGetPointer StackInit StackLeave StackPop",
      2: """
        AddLifeScheduled Arctan2 Break DecrementPost DecrementPre DoWhile Equal
        ExportValue Get Greater GreaterOr IncrementPost IncrementPre Less
        LessOr Max Min NotEqual Play PlayLoopedScheduled Random RandomInteger
        StackSet StackSetFrame StopLoopedScheduled StreamGetNextKey
        StreamGetPreviousKey StreamGetValue StreamHas SwitchIntegerWithDefault
        SwitchWithDefault While
        """,
      3: """
        Clamp DecrementPostPointed DecrementPrePointed GetPointed If
        IncrementPostPointed IncrementPrePointed Lerp LerpClamped PlayScheduled
        Set SetAdd SetDivide SetMod SetMultiply SetPower SetRem SetSubtract
        StreamSet Unlerp UnlerpClamped
        """,
      4: """
        DecrementPostShifted DecrementPreShifted GetShifted IncrementPostShifted
        IncrementPreShifted SetAddPointed SetDividePointed SetModPointed
        SetMultiplyPointed SetPointed SetPowerPointed SetRemPointed
        SetSubtractPointed
        """,
      5: """
        Copy JudgeSimple Remap RemapClamped SetAddShifted SetDivideShifted
        SetModShifted SetMultiplyShifted SetPowerShifted SetRemShifted SetShifted
        SetSubtractShifted
        """,
      7: "Paint", 8: "Judge", 9: "MoveParticleEffect",
      11: "SpawnParticleEffect", 14: "Draw Print",
      17: "DrawCurvedB DrawCurvedL DrawCurvedR DrawCurvedT",
      19: "DrawCurvedBT DrawCurvedLR"
    ]
    var arities: [String: Int] = [:]
    for (count, group) in arityGroups {
      for name in group.split(whereSeparator: \.isWhitespace).map(String.init) {
        XCTAssertTrue(inventory.contains(name), name)
        XCTAssertNil(arities.updateValue(count, forKey: name), name)
      }
    }
    for name in names {
      let builder = RuntimeNodeBuilder()
      let host = makeHost()
      host.selectEntity(index: 0, exportCount: 1)
      host.memory.set(block: 2000, index: 0, value: 2000)
      host.memory.set(block: 2000, index: 1, value: 8)
      host.memory.set(block: 2000, index: 8, value: 2)
      var arguments = Array(repeating: 0.0, count: arities[name] ?? 1)
      if name.hasPrefix("Get") || name.hasPrefix("Set")
        || name.hasPrefix("Increment") || name.hasPrefix("Decrement") {
        arguments[0] = 2000
        arguments[1] = name.hasSuffix("Pointed") ? 0 : 8
        if name.hasPrefix("Set") { arguments[arguments.count - 1] = 1 }
      } else if name.hasPrefix("Draw") {
        arguments[0] = 7
        arguments.replaceSubrange(1...8, with: quad)
        arguments[10] = 1
        if name != "Draw" { arguments[11] = 1 }
      } else if name.hasPrefix("Play") {
        arguments[0] = 8
      } else {
        switch name {
        case "Break": arguments = [1, 42]
        case "Copy": arguments = [2000, 8, 2000, 9, 1]
        case "Random", "RandomInteger": arguments = [0, 1]
        case "Unlerp", "UnlerpClamped": arguments = [0, 1, 0.5]
        case "Remap", "RemapClamped": arguments = [0, 1, 0, 1, 0.5]
        case "HasSkinSprite": arguments = [7]
        case "HasEffectClip": arguments = [8]
        case "HasParticleEffect": arguments = [9]
        case "SpawnParticleEffect": arguments = [9] + quad + [1, 0]
        case "MoveParticleEffect", "DestroyParticleEffect":
          arguments[0] = try host.call(function: "SpawnParticleEffect",
            arguments: [9] + quad + [1, 0])
          if name == "MoveParticleEffect" {
            arguments.replaceSubrange(1...8, with: quad)
          }
        case "StopLooped", "StopLoopedScheduled":
          arguments[0] = try host.call(function: "PlayLooped", arguments: [8])
        default: break
        }
      }
      let call = builder.call(name, arguments.map { builder.value($0) })
      let root = name == "Break" ? builder.call("Block", [call]) : call
      let engine = try builder.engine(archetypes: [["name": "Probe",
        "hasInput": true, "imports": [], "exports": [],
        "touch": ["index": root]]])
      XCTAssertEqual(try engine.unsupportedFunctions(),
        unavailable.contains(name) ? [name] : [], name)
      // The touch root checks reachability, not callback legality. Standalone
      // execution intentionally has no callback context (e.g. life scheduling
      // is preprocessing-only). Callback rules have dedicated runtime tests.
      let interpreter = EngineInterpreter(nodes: engine.nodes,
        memory: host.memory, host: host)
      do {
        _ = try interpreter.execute(nodeAt: root)
        XCTAssertFalse(unavailable.contains(name), name)
      } catch EngineInterpreterError.unsupportedFunction(let missing) {
        XCTAssertTrue(unavailable.contains(name), "Registered but missing: \(name)")
        XCTAssertEqual(missing, name)
      } catch { XCTFail("Unexpected dispatch error for \(name): \(error)") }
    }
  }

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
    _ = try call("StreamSet", [2, -Double.greatestFiniteMagnitude, -100])
    _ = try call("StreamSet", [2, Double.greatestFiniteMagnitude, 100])
    XCTAssertEqual(try call("StreamGetValue", [2, 0]), 0)
  }

  func testStreamIDsPreserveSignedFractionalAndLargeNumbers() throws {
    let host = makeHost()
    let ids: [Double] = [-9999, -1, -0.5, 0, 0.5, 1,
      Double(Int.max), Double.greatestFiniteMagnitude]
    for (index, id) in ids.enumerated() {
      _ = try host.call(function: "StreamSet", arguments: [id, -2, Double(index)])
      _ = try host.call(function: "StreamSet", arguments: [id, 2, Double(index + 4)])
    }
    let restore = host.makeRestorePoint()
    for (index, id) in ids.enumerated() {
      XCTAssertEqual(try host.call(function: "StreamHas", arguments: [id, -2]), 1)
      XCTAssertEqual(try host.call(function: "StreamHas", arguments: [id, 0]), 0)
      XCTAssertEqual(try host.call(function: "StreamGetValue", arguments: [id, 0]),
        Double(index + 2), "Stream IDs must not be truncated or aliased")
      XCTAssertEqual(try host.call(function: "StreamGetNextKey", arguments: [id, 0]), 2)
      XCTAssertEqual(try host.call(function: "StreamGetPreviousKey", arguments: [id, 0]), -2)
      _ = try host.call(function: "StreamSet", arguments: [id, -2, 99])
    }
    restore()
    for (index, id) in ids.enumerated() {
      XCTAssertEqual(try host.call(function: "StreamGetValue", arguments: [id, -2]),
        Double(index))
    }
    XCTAssertEqual(try host.call(function: "StreamGetValue", arguments: [-0.0, -2]), 3)
    for function in ["StreamSet", "StreamHas", "StreamGetValue",
      "StreamGetNextKey", "StreamGetPreviousKey"] {
      for invalid in [Double.nan, .infinity, -.infinity] {
        let arguments = [invalid, 0] + (function == "StreamSet" ? [1] : [])
        XCTAssertThrowsError(try host.call(function: function, arguments: arguments))
      }
    }
  }

  func testStreamBudgetCountsAllStreamsButAllowsReplacement() throws {
    let host = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0,
      streamEntryLimit: 2)
    _ = try host.call(function: "StreamSet", arguments: [-9999, 0, 1])
    _ = try host.call(function: "StreamSet", arguments: [0.5, 0, 2])
    _ = try host.call(function: "StreamSet", arguments: [-9999, 0, 3])
    XCTAssertThrowsError(try host.call(function: "StreamSet", arguments: [2, 0, 4]))
    XCTAssertEqual(try host.call(function: "StreamGetValue", arguments: [-9999, 0]), 3)
    XCTAssertEqual(try host.call(function: "StreamHas", arguments: [2, 0]), 0)
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

  func testMalformedCommandsThrowInsteadOfCrashingOrGrowingState() throws {
    let host = makeHost()
    for (function, arguments) in [
      ("Draw", [7.0]), ("BeatToTime", [Double.nan]),
      ("Spawn", [Double.infinity]), ("Spawn", [-1]), ("Spawn", [2]),
      ("HasSkinSprite", [Double.infinity]),
      ("DestroyParticleEffect", [0.5]), ("Judge", []),
      ("UnknownFunction", [])
    ] {
      XCTAssertThrowsError(try host.call(
        function: function, arguments: arguments
      ), function)
    }
    XCTAssertEqual(try host.call(function: "HasSkinSprite",
      arguments: [Double.greatestFiniteMagnitude]), 0,
      "An absent finite resource identity is not a malformed index")
    XCTAssertTrue(host.draws.isEmpty)
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertTrue(host.takeSpawnCommands().isEmpty)
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
}
