import XCTest
import UIKit
@testable import OpenRhythm

/// Builds preview data from nodes, as the compiler emits it.
private final class PreviewNodeBuilder {
  private var nodes = [[String: Any]]()

  func value(_ value: Double) -> Int {
    nodes.append(["value": value])
    return nodes.count - 1
  }

  func call(_ function: String, _ arguments: [Int]) -> Int {
    nodes.append(["func": function, "args": arguments])
    return nodes.count - 1
  }

  func call(_ function: String, values: [Double]) -> Int {
    call(function, values.map { value($0) })
  }

  func set(_ block: Int, _ index: Int, _ value: Int) -> Int {
    call("Set", [self.value(Double(block)), self.value(Double(index)), value])
  }

  func get(_ block: Int, _ index: Int) -> Int {
    call("Get", [value(Double(block)), value(Double(index))])
  }

  func engine(archetypes: [[String: Any]],
    sprites: [[String: Any]] = [["name": "#NOTE", "id": 7]],
    fields: [String: Any] = [:]) throws -> EnginePreviewData {
    let data = try JSONSerialization.data(withJSONObject: fields.merging([
      "skin": ["sprites": sprites], "nodes": nodes, "archetypes": archetypes
    ]) { _, required in required })
    return try JSONDecoder().decode(EnginePreviewData.self, from: data)
  }
}

private func entity(_ archetype: String, name: String? = nil,
  _ values: [String: Double] = [:], refs: [String: String] = [:])
  -> LevelEntity {
  LevelEntity(archetype: archetype, name: name, data:
    values.sorted { $0.key < $1.key }.map {
      LevelEntityData(name: $0.key, value: $0.value, ref: nil)
    } + refs.sorted { $0.key < $1.key }.map {
      LevelEntityData(name: $0.key, value: nil, ref: $0.value)
    })
}

private typealias Block = EnginePreviewBlock

final class EnginePreviewTests: XCTestCase {
  // MARK: Canvas and scrolling

  func testCanvasStartsAtTheScrollDirectionsEdgeAndExtendsBySize() {
    let aspect = 1.5
    // Left to right: x from the left edge to left + size; start at the left.
    let ltr = EnginePreviewCanvas(scroll: .leftToRight, size: 10,
      aspectRatio: aspect)
    XCTAssertTrue(ltr.isHorizontal)
    XCTAssertEqual(ltr.visibleLength, 3)
    XCTAssertEqual(ltr.scrollLength, 7)
    XCTAssertEqual(ltr.visibleBounds(at: 0),
      CGRect(x: -1.5, y: -1, width: 3, height: 2))
    XCTAssertEqual(ltr.visibleBounds(at: 7).maxX, -1.5 + 10)
    XCTAssertEqual(ltr.offset(at: 2), EnginePoint(x: -2, y: 0))
    // Right to left mirrors it: the canvas ends at the right edge.
    let rtl = EnginePreviewCanvas(scroll: .rightToLeft, size: 10,
      aspectRatio: aspect)
    XCTAssertEqual(rtl.visibleBounds(at: 7).minX, 1.5 - 10)
    XCTAssertEqual(rtl.offset(at: 2), EnginePoint(x: 2, y: 0))
    // Vertical canvases scroll by screen heights (2 units).
    let ttb = EnginePreviewCanvas(scroll: .topToBottom, size: 10,
      aspectRatio: aspect)
    XCTAssertFalse(ttb.isHorizontal)
    XCTAssertEqual(ttb.scrollLength, 8)
    XCTAssertEqual(ttb.visibleBounds(at: 8).minY, 1 - 10)
    let btt = EnginePreviewCanvas(scroll: .bottomToTop, size: 10,
      aspectRatio: aspect)
    XCTAssertEqual(btt.visibleBounds(at: 8).maxY, -1 + 10)
    XCTAssertEqual(btt.offset(at: 3), EnginePoint(x: 0, y: -3))
  }

  func testCanvasShorterThanTheScreenDoesNotScroll() {
    for size in [0.0, 1, 3] {
      let canvas = EnginePreviewCanvas(scroll: .leftToRight, size: size,
        aspectRatio: 1.5)
      XCTAssertEqual(canvas.scrollLength, 0)
      XCTAssertEqual(canvas.offset(at: 5), EnginePoint(x: -0.0, y: 0))
      XCTAssertEqual(canvas.progress(at: 5), 0)
      XCTAssertEqual(canvas.contentLength(pointsPerUnit: 100), 300)
    }
  }

  func testContentOffsetsMoveThePictureWithTheFingerInEveryDirection() {
    for scroll in [EnginePreviewCanvas.Scroll.leftToRight, .topToBottom,
      .rightToLeft, .bottomToTop] {
      let canvas = EnginePreviewCanvas(scroll: scroll, size: 12,
        aspectRatio: 2)
      let unit = 50.0
      XCTAssertEqual(canvas.contentLength(pointsPerUnit: unit),
        (canvas.visibleLength + canvas.scrollLength) * unit)
      let start = canvas.contentOffset(at: 0, pointsPerUnit: unit)
      let end = canvas.contentOffset(at: canvas.scrollLength,
        pointsPerUnit: unit)
      // Content offsets run rightward/downward; reversed directions begin
      // at the far end of the content.
      let reversed = scroll == .rightToLeft || scroll == .bottomToTop
      XCTAssertEqual(start, reversed ? canvas.scrollLength * unit : 0)
      XCTAssertEqual(end, reversed ? 0 : canvas.scrollLength * unit)
      for position in stride(from: 0.0, through: canvas.scrollLength,
        by: 0.75) {
        let offset = canvas.contentOffset(at: position, pointsPerUnit: unit)
        XCTAssertEqual(canvas.position(atContentOffset: offset,
          pointsPerUnit: unit), position, accuracy: 1e-9, "\(scroll)")
        XCTAssertEqual(canvas.position(atProgress:
          canvas.progress(at: position)), position, accuracy: 1e-9)
      }
      // Bounces past either end clamp to the canvas.
      XCTAssertEqual(canvas.position(atContentOffset: -500,
        pointsPerUnit: unit), reversed ? canvas.scrollLength : 0)
      XCTAssertEqual(canvas.position(atContentOffset: 1e6,
        pointsPerUnit: unit), reversed ? 0 : canvas.scrollLength)
      XCTAssertEqual(canvas.position(atContentOffset: .nan,
        pointsPerUnit: unit), 0)
    }
  }

  func testRuntimeCanvasValuesAreValidated() throws {
    XCTAssertEqual(try EnginePreviewCanvas(scrollValue: 3, size: 4,
      aspectRatio: 1).scroll, .bottomToTop)
    for scroll in [-1.0, 4, 0.5, .nan] {
      XCTAssertThrowsError(try EnginePreviewCanvas(scrollValue: scroll,
        size: 4, aspectRatio: 1)) { error in
        guard case RuntimeBundleError.unsupportedPresentationValue = error
        else { return XCTFail("\(error)") }
      }
    }
    for size in [-1.0, .nan, .infinity] {
      XCTAssertThrowsError(try EnginePreviewCanvas(scrollValue: 0,
        size: size, aspectRatio: 1))
    }
    XCTAssertThrowsError(try EnginePreviewCanvas(scrollValue: 0,
      size: EnginePreviewCanvas.maximumSize + 1, aspectRatio: 1)) { error in
      guard case EngineInterpreterError.resourceLimitExceeded = error
      else { return XCTFail("\(error)") }
    }
  }

  func testUIElementFrameUsesAnchorPivotAndSize() {
    // Anchor at the top-right corner, pivot top-right, 0.2 × 0.1 units.
    let element = EnginePreviewUIElement(values: [2, 1, 1, 1, 0.2, 0.1, 0,
      1, 1])
    XCTAssertTrue(element.isVisible)
    let size = CGSize(width: 400, height: 200)
    XCTAssertEqual(element.frame(in: size),
      CGRect(x: 380, y: 0, width: 20, height: 10))
    XCTAssertFalse(EnginePreviewUIElement(values: Array(repeating: 0,
      count: 9)).isVisible)
  }

  // MARK: Print

  func testPrintFormatsValues() {
    func text(_ value: Double, _ format: Double, _ places: Double) -> String {
      EnginePrintCommand(value: value, format: format, decimalPlaces: places,
        anchor: EnginePoint(x: 0, y: 0), pivot: EnginePoint(x: 0, y: 0),
        size: EnginePoint(x: 1, y: 1), rotation: 0, color: 0, alpha: 1,
        horizontalAlign: 0, background: false)
        .text(locale: Locale(identifier: "en_US"))
    }
    XCTAssertEqual(text(1.25, 0, -1), "1.25")
    XCTAssertEqual(text(1.23456, 0, -1), "1.235")
    XCTAssertEqual(text(2, 0, 2), "2.00")
    XCTAssertEqual(text(0.5, 1, 0), "50%")
    XCTAssertEqual(text(1, 10, 0), "0:01")
    XCTAssertEqual(text(65.25, 10, 2), "1:05.25")
    XCTAssertEqual(text(59.96, 10, 1), "1:00.0")
    XCTAssertEqual(text(-3, 10, 0), "-0:03")
    XCTAssertEqual(text(1234567, 11, 0), "1,234,567")
    XCTAssertEqual(text(128.5, 20, -1), "128.5 BPM")
    XCTAssertEqual(text(1.5, 21, -1), "×1.5")
    XCTAssertEqual(text(32, 30, 0), "32")
    XCTAssertEqual(text(9, 31, 0), "9")
    XCTAssertEqual(text(4, 32, 0), "4")
    // An unknown format prints the plain number instead of failing.
    XCTAssertEqual(text(7, 99, 0), "7")
  }

  func testPrintRecordsItsBoxOnlyInPreview() throws {
    let memory = EngineMemory()
    try memory.configurePreviewBlocks(entityCount: 0, optionCount: 0)
    let host = CommandEngineRuntimeHost(memory: memory,
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0,
      mode: .preview)
    let arguments: [Double] = [3, 10, 0, 0.5, 0.25, 1, 0.5, 0.2, 0.1, 0.3,
      5, 2, -1, 1]
    XCTAssertEqual(try host.call(function: "Print", arguments: arguments), 0)
    XCTAssertEqual(host.prints, [EnginePrintCommand(value: 3, format: 10,
      decimalPlaces: 0, anchor: EnginePoint(x: 0.5, y: 0.25),
      pivot: EnginePoint(x: 1, y: 0.5), size: EnginePoint(x: 0.2, y: 0.1),
      rotation: 0.3, color: 5, alpha: 1, horizontalAlign: -1,
      background: true)])
    // Non-finite values print nothing, like Draw; wrong counts are errors.
    var nonFinite = arguments
    nonFinite[3] = .nan
    XCTAssertEqual(try host.call(function: "Print", arguments: nonFinite), 0)
    XCTAssertThrowsError(try host.call(function: "Print",
      arguments: Array(arguments.dropLast())))
    XCTAssertEqual(host.takePrintCommands().count, 1)
    XCTAssertTrue(host.prints.isEmpty)
    let play = CommandEngineRuntimeHost(memory: EngineMemory(),
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [],
      effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0)
    XCTAssertThrowsError(try play.call(function: "Print",
      arguments: arguments)) { error in
      guard case EngineInterpreterError.unsupportedFunction("Print") = error
      else { return XCTFail("\(error)") }
    }
  }

  func testPreviewDrawsUsePreviewSkinTransformBlock() throws {
    let memory = EngineMemory()
    try memory.configurePreviewBlocks(entityCount: 0, optionCount: 0)
    let host = CommandEngineRuntimeHost(memory: memory,
      level: LevelData(bgmOffset: 0, entities: []), skinSpriteIDs: [7],
      effectClipIDs: [], particleEffectIDs: [], archetypeCount: 0,
      mode: .preview)
    // Preview's transform is block 1002 and starts as the identity; 1003
    // and 1004 are Runtime UI blocks and stay zero.
    XCTAssertEqual((0..<16).map {
      memory.value(block: Block.runtimeSkinTransform, index: $0)
    }, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    XCTAssertEqual((0..<18).map {
      memory.value(block: Block.runtimeUI, index: $0)
    }, Array(repeating: 0, count: 18))
    memory.set(block: Block.runtimeSkinTransform, index: 0, value: 3)
    _ = try host.call(function: "Draw",
      arguments: [7, -1, -1, -1, 1, 1, 1, 1, -1, 0, 1])
    XCTAssertEqual(host.draws.first?.transform[0], 3)
    XCTAssertEqual(host.takeDrawCommands().count, 1)
    XCTAssertTrue(host.draws.isEmpty)
    // Preview has no effects or particles to report.
    XCTAssertEqual(try host.call(function: "HasEffectClip", arguments: [1]), 0)
  }

  // MARK: Memory access

  func testPreviewBlockAccessFollowsThePreviewTables() throws {
    let memory = EngineMemory()
    try memory.configurePreviewBlocks(entityCount: 2, optionCount: 1)
    memory.selectEntity(key: 1, index: 1)
    let preprocessWritable = [Block.runtimeEnvironment, Block.runtimeCanvas,
      Block.runtimeSkinTransform, Block.runtimeUI,
      Block.runtimeUIConfiguration, Block.previewData, Block.entityData,
      Block.entitySharedMemory, Block.entityDataArray,
      Block.entitySharedMemoryArray, Block.temporaryMemory]
    let readOnly = [Block.previewOption, Block.engineROM, Block.entityInfo,
      Block.entityInfoArray]
    for callback in [EngineMemory.Callback.preprocess, .render] {
      memory.callback = callback
      for block in preprocessWritable + readOnly {
        XCTAssertNoThrow(try memory.read(block: block, index: 0))
        let writable = block == Block.temporaryMemory
          || (callback == .preprocess && preprocessWritable.contains(block))
        if writable {
          XCTAssertNoThrow(try memory.write(block: block, index: 0, value: 1),
            "\(block) during \(callback)")
        } else {
          XCTAssertThrowsError(try memory.write(block: block, index: 0,
            value: 1), "\(block) during \(callback)") { error in
            guard case EngineInterpreterError.invalidMemoryAccess(
              block, callback.rawValue, true) = error
            else { return XCTFail("\(error)") }
          }
        }
      }
      // Play-only blocks do not exist in preview: reads are zero and
      // writes are errors.
      XCTAssertEqual(try memory.read(block: EnginePlayBlock.levelScore,
        index: 0), 0)
      XCTAssertThrowsError(try memory.write(block: EnginePlayBlock.levelScore,
        index: 0, value: 1))
    }
    memory.callback = nil
  }

  func testPreviewEntityViewsAliasTheirArrays() throws {
    let memory = EngineMemory()
    try memory.configurePreviewBlocks(entityCount: 3, optionCount: 0,
      entityLayout: EngineEntityLayout(memory: 0, data: 4, sharedMemory: 2))
    memory.selectEntity(key: 2, index: 2)
    memory.set(block: Block.entityData, index: 3, value: 5)
    memory.set(block: Block.entitySharedMemory, index: 1, value: 6)
    XCTAssertEqual(memory.value(block: Block.entityDataArray, index: 11), 5)
    XCTAssertEqual(memory.value(block: Block.entitySharedMemoryArray,
      index: 5), 6)
    memory.set(block: Block.entityInfoArray, index: 4, value: 2)
    memory.set(block: Block.entityInfoArray, index: 5, value: 9)
    XCTAssertEqual(memory.value(block: Block.entityInfo, index: 0), 2)
    XCTAssertEqual(memory.value(block: Block.entityInfo, index: 1), 9)
    // Past the declared lengths, reads are zero.
    XCTAssertEqual(memory.value(block: Block.entityData, index: 4), 0)
    XCTAssertEqual(memory.value(block: Block.entityInfo, index: 2), 0)
  }

  // MARK: Runtime lifecycle

  /// Initialization sets a scrolling canvas and a skin transform; each Note
  /// copies its beat to shared memory in preprocess, then draws and prints.
  private func makeEngine(renderWritesEntityData: Bool = false,
    extraRenderFunction: String? = nil) throws -> EnginePreviewData {
    let b = PreviewNodeBuilder()
    let initialization = b.call("Execute", [
      b.set(Block.runtimeCanvas, 0, b.value(1)),
      b.set(Block.runtimeCanvas, 1, b.call("Multiply", [
        b.get(Block.runtimeEnvironment, 1), b.value(4)])),
      b.set(Block.runtimeSkinTransform, 0, b.value(0.5)),
      b.set(Block.runtimeUI, 9 + 4, b.value(1)),
      b.set(Block.previewData, 0, b.call("Add", [
        b.get(Block.previewData, 0), b.value(1)])),
    ])
    let notePreprocess = b.call("Execute", [
      b.set(Block.entitySharedMemory, 0, b.call("Multiply", [
        b.get(Block.entityData, 0), b.value(2)])),
      b.set(Block.previewData, 1, b.get(Block.entityData, 1)),
    ])
    let beat = b.get(Block.entityData, 0)
    var render = [
      b.call("Draw", [b.value(7), beat, b.value(-1), beat, b.value(1),
        b.call("Add", [beat, b.value(1)]), b.value(1),
        b.call("Add", [beat, b.value(1)]), b.value(-1),
        b.get(Block.entitySharedMemory, 0), b.value(1)]),
      b.call("Print", [b.get(Block.entityInfo, 0), b.value(32), b.value(0),
        beat, b.value(0), b.value(0.5), b.value(0.5), b.value(0.2),
        b.value(0.1), b.value(0), b.value(-1), b.value(1), b.value(0),
        b.value(0)]),
      // Render may use Temporary Memory.
      b.set(Block.temporaryMemory, 0, b.value(1)),
    ]
    if renderWritesEntityData {
      render.append(b.set(Block.entityData, 0, b.value(1)))
    }
    if let extraRenderFunction {
      render.append(b.call(extraRenderFunction, values: [1, 1]))
    }
    let noteRender = b.call("Execute", render)
    return try b.engine(archetypes: [
      ["name": "Note", "preprocess": ["index": notePreprocess],
       "render": ["index": noteRender],
       "imports": [["name": "#BEAT", "index": 0],
         ["name": "next", "index": 1]]],
      // Preprocessed after the notes because of its order.
      ["name": "Initialization",
       "preprocess": ["index": initialization, "order": 1], "imports": []],
    ])
  }

  private let level = LevelData(bgmOffset: 0, entities: [
    entity("Note", name: "a", ["#BEAT": 2], refs: ["next": "b"]),
    entity("Editor metadata"),
    entity("Note", name: "b", ["#BEAT": 5]),
    entity("Initialization"),
  ])

  func testPreviewPreprocessesThenRendersEveryEntityOnce() throws {
    let runtime = try EnginePreviewRuntime(engine: makeEngine(), level: level,
      options: [], aspectRatio: 2, skinSpriteIDs: [7])
    // Preprocessing ran once per entity, Initialization last.
    XCTAssertEqual(runtime.memory.value(block: Block.previewData, index: 0), 1)
    // Imports, including references (entity "b" is index 2).
    XCTAssertEqual(runtime.memory.value(block: Block.entityDataArray,
      index: 1), 2)
    XCTAssertEqual(runtime.memory.value(block: Block.entitySharedMemoryArray,
      index: 64), 10)
    // Entity Info: index and archetype; -1 without a preview archetype.
    XCTAssertEqual((0..<8).map {
      runtime.memory.value(block: Block.entityInfoArray, index: $0)
    }, [0, 0, 1, -1, 2, 0, 3, 1])
    let frame = try runtime.render()
    XCTAssertEqual(frame.canvas, EnginePreviewCanvas(scroll: .topToBottom,
      size: 8, aspectRatio: 2))
    XCTAssertEqual(frame.draws.map(\.points.first?.x), [2, 5])
    XCTAssertEqual(frame.draws.map(\.z), [4, 10])
    XCTAssertEqual(frame.draws.map { $0.transform[0] }, [0.5, 0.5])
    XCTAssertEqual(frame.prints.map(\.value), [0, 2])
    XCTAssertEqual(frame.prints.map(\.anchor.x), [2, 5])
    XCTAssertEqual(frame.progress.values[4], 1)
    XCTAssertFalse(frame.menu.isVisible)
    // Render is repeatable: it neither writes persistent memory nor keeps
    // draws between renders.
    let again = try runtime.render()
    XCTAssertEqual(again.draws, frame.draws)
    XCTAssertEqual(again.prints, frame.prints)
  }

  func testPreviewEnvironmentAndOptionsAreSupplied() throws {
    let b = PreviewNodeBuilder()
    let copy = b.call("Execute", (0..<6).map {
      b.set(Block.previewData, $0, b.get(Block.runtimeEnvironment, $0))
    } + [
      b.set(Block.previewData, 6, b.get(Block.previewOption, 1)),
      b.set(Block.previewData, 7, b.get(Block.runtimeUIConfiguration, 3)),
      b.set(Block.previewData, 8, b.get(Block.engineROM, 0)),
    ])
    let engine = try b.engine(archetypes: [["name": "Stage",
      "preprocess": ["index": copy], "imports": []]])
    var rom = Data()
    withUnsafeBytes(of: Float(2.5).bitPattern.littleEndian) {
      rom.append(contentsOf: $0)
    }
    let runtime = try EnginePreviewRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [entity("Stage")]),
      options: [3, 4], aspectRatio: 1.5, skinSpriteIDs: [], rom: rom,
      safeArea: [-1.4, 1.4, -0.9, 0.9], uiConfiguration: [1, 0.5, 2, 0.75],
      debugMode: true)
    XCTAssertEqual((0..<9).map {
      runtime.memory.value(block: Block.previewData, index: $0)
    }, [1, 1.5, -1.4, 1.4, -0.9, 0.9, 4, 0.75, 2.5])
    // Without preprocessing changes the canvas is zero: left to right, no
    // scrolling.
    XCTAssertEqual(try runtime.render().canvas.scrollLength, 0)
  }

  func testRenderCannotWriteEntityData() throws {
    let runtime = try EnginePreviewRuntime(
      engine: makeEngine(renderWritesEntityData: true), level: level,
      options: [], aspectRatio: 2, skinSpriteIDs: [7])
    XCTAssertThrowsError(try runtime.render()) { error in
      guard case EngineInterpreterError.invalidMemoryAccess(
        Block.entityData, "render", true) = error
      else { return XCTFail("\(error)") }
    }
  }

  func testPreviewRejectsPlayOnlyFunctionsBeforeRunning() throws {
    for function in ["Play", "Spawn", "SpawnParticleEffect", "ExportValue",
      "StreamSet", "AddLifeScheduled", "Paint"] {
      let engine = try makeEngine(extraRenderFunction: function)
      XCTAssertEqual(try engine.unsupportedFunctions(), [function])
      XCTAssertThrowsError(try EnginePreviewRuntime(engine: engine,
        level: level, options: [], aspectRatio: 2, skinSpriteIDs: [7])) {
        error in
        guard case EngineInterpreterError.unsupportedFunction(function) = error
        else { return XCTFail("\(error)") }
      }
    }
    // Print belongs to preview; play's preflight still rejects it.
    let b = RuntimeNodeBuilder()
    let print = b.call("Print", (0..<14).map { _ in b.value(0) })
    let play = try b.engine(archetypes: [["name": "Stage", "hasInput": false,
      "updateParallel": ["index": print], "imports": [], "exports": []]])
    XCTAssertEqual(try play.unsupportedFunctions(), ["Print"])
  }

  func testInvalidCanvasFailsRendering() throws {
    let b = PreviewNodeBuilder()
    let set = b.set(Block.runtimeCanvas, 0, b.value(7))
    let engine = try b.engine(archetypes: [["name": "Stage",
      "preprocess": ["index": set], "imports": []]])
    let runtime = try EnginePreviewRuntime(engine: engine,
      level: LevelData(bgmOffset: 0, entities: [entity("Stage")]),
      options: [], aspectRatio: 1, skinSpriteIDs: [])
    XCTAssertThrowsError(try runtime.render())
  }

  func testPreviewDataDecodesOptionalEntityLengths() throws {
    let engine = try PreviewNodeBuilder().engine(archetypes: [],
      fields: ["entityDataLength": 48, "entitySharedMemoryLength": 8])
    XCTAssertEqual(engine.entityLayout.data, 48)
    XCTAssertEqual(engine.entityLayout.sharedMemory, 8)
  }

  // MARK: Scene

  @MainActor
  func testSceneProjectsOnceThenTranslatesAndCullsPerPosition() throws {
    let runtime = try EnginePreviewRuntime(engine: makeEngine(), level: level,
      options: [], aspectRatio: 0.9, skinSpriteIDs: [7])
    let assets = try PreviewPresentation.assets(for: runtime)
    let frame = try runtime.render()
    let scene = EnginePreviewScene(frame: frame, assets: assets)
    XCTAssertEqual(scene.spriteCount, 2)
    // The skin transform halves x: the notes span x 1...1.5 and 2.5...3 and
    // y -1...1. A 0.9-wide screen shows neither, and this vertical canvas
    // never pans sideways.
    XCTAssertTrue(scene.sprites(at: 0).isEmpty)
    let wide = EnginePreviewScene(frame: try EnginePreviewRuntime(
      engine: makeEngine(), level: level, options: [], aspectRatio: 3.2,
      skinSpriteIDs: [7]).render(), assets: assets)
    let visible = wide.sprites(at: 0)
    XCTAssertEqual(visible.count, 2)
    XCTAssertEqual(visible.first?.points.map(\.x), [1, 1, 1.5, 1.5])
    // Scrolling down 1.5 units moves drawings up by 1.5.
    let scrolled = wide.sprites(at: 1.5)
    XCTAssertEqual(scrolled.first?.matrix[7], 1.5)
    XCTAssertEqual(EngineGeometry.screenPoint(scrolled[0].points[0],
      matrix: scrolled[0].matrix, size: CGSize(width: 320, height: 100)).y,
      50 - (-1 + 1.5) * 50)
    // y spans -1...1, so past position 2 + margin they leave the screen.
    XCTAssertTrue(wide.sprites(at: 3.1).isEmpty)
    // Print anchors are canvas coordinates, outside the skin transform:
    // x 2 is on a 3.2-wide screen, x 5 is not.
    XCTAssertEqual(wide.prints(at: 0).map(\.anchor.x), [2])
  }
}

/// Generated placeholder skin: one colored 4×4 cell per declared sprite.
@MainActor
private enum PreviewPresentation {
  static func assets(for runtime: EnginePreviewRuntime) throws
    -> EnginePresentationAssets {
    try assets(sprites: [EngineNamedID(name: "#NOTE", id: 7)])
  }

  static func assets(sprites: [EngineNamedID],
    configuration: Data = Data(#"{"options":[]}"#.utf8)) throws
    -> EnginePresentationAssets {
    try EnginePresentationAssets(skinDefinition: EngineSkinDefinition(
      renderMode: nil, sprites: sprites),
      particleDefinition: EngineParticleDefinition(effects: []),
      presentation: presentation(names: sprites.map(\.name),
        configuration: configuration))
  }

  static func presentation(names: [String], configuration: Data) throws
    -> RuntimePresentation {
    let unique = Array(Set(names)).sorted()
    let columns = 16, cell = 4
    let rows = max(1, (unique.count + columns - 1) / columns)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let texture = UIGraphicsImageRenderer(size: CGSize(width: columns * cell,
      height: rows * cell), format: format).pngData { _ in
      for index in unique.indices {
        UIColor(hue: Double(index) / Double(max(1, unique.count)),
          saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
        UIRectFill(CGRect(x: index % columns * cell,
          y: index / columns * cell, width: cell, height: cell))
      }
    }
    let identity = Dictionary(uniqueKeysWithValues: (1...4)
      .flatMap { ["x\($0)", "y\($0)"] }.map { ($0, [$0: 1]) })
    let sprites: [[String: Any]] = unique.enumerated().map { index, name in
      ["name": name, "x": index % columns * cell, "y": index / columns * cell,
       "w": cell, "h": cell, "transform": identity]
    }
    return RuntimePresentation(resources: [
      "configuration": configuration, "skinTexture": texture,
      "skinData": try JSONSerialization.data(withJSONObject: [
        "width": columns * cell, "height": rows * cell,
        "interpolation": false, "sprites": sprites])])
  }
}

// MARK: - Real engines

/// Whole-chart preview checks: the frame renders, every drawing can be
/// scrolled on screen, and a sweep across the full canvas in both directions
/// produces the same visible sets.
@MainActor
private enum PreviewSweep {
  struct Result {
    let frame: EnginePreviewFrame
    let scene: EnginePreviewScene
    let positions: Int
  }

  static func run(engine: EnginePreviewData, level: LevelData,
    assets: EnginePresentationAssets, rom: Data? = nil,
    aspectRatio: Double, name: String,
    file: StaticString = #filePath, line: UInt = #line) throws -> Result {
    XCTAssertEqual(try engine.unsupportedFunctions(), [], name,
      file: file, line: line)
    let runtime = try EnginePreviewRuntime(engine: engine, level: level,
      options: assets.configuration.options.map(\.def),
      aspectRatio: aspectRatio, skinSpriteIDs: Set(assets.skin.keys),
      rom: rom)
    let frame = try runtime.render()
    XCTAssertFalse(frame.draws.isEmpty, "\(name) drew nothing",
      file: file, line: line)
    let scene = EnginePreviewScene(frame: frame, assets: assets)
    XCTAssertGreaterThan(scene.spriteCount, 0, name, file: file, line: line)
    let canvas = frame.canvas
    XCTAssertGreaterThan(canvas.scrollLength, 0,
      "\(name)'s chart is longer than one screen", file: file, line: line)
    // Half-screen steps forward, then back: each drawing must reach the
    // screen at some position, and both passes must agree.
    let step = canvas.visibleLength / 2
    let count = Int((canvas.scrollLength / step).rounded(.up)) + 1
    let positions = (0..<count).map { min(Double($0) * step,
      canvas.scrollLength) }
    var forward = [Int]()
    var seen = 0
    for position in positions {
      let sprites = scene.sprites(at: position)
      forward.append(sprites.count)
      _ = scene.prints(at: position)
      seen = max(seen, sprites.count)
    }
    let backward = positions.reversed().map { scene.sprites(at: $0).count }
    XCTAssertEqual(forward, Array(backward.reversed()), name,
      file: file, line: line)
    XCTAssertGreaterThan(seen, 0, name, file: file, line: line)
    return Result(frame: frame, scene: scene, positions: positions.count)
  }

  /// Drawings that no scroll position brings on screen.
  static func unreachable(_ result: Result) -> Int {
    let canvas = result.frame.canvas
    let reachable = canvas.visibleBounds(at: 0)
      .union(canvas.visibleBounds(at: canvas.scrollLength))
    return result.scene.spriteBounds.filter { !$0.intersects(reachable) }
      .count
  }

  /// A software rendering at one position, for inspection.
  static func image(_ scene: EnginePreviewScene, at position: Double,
    size: CGSize) throws -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    var failure: Error?
    let image = UIGraphicsImageRenderer(size: size, format: format).image {
      context in
      UIColor.black.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      do {
        try EngineRenderer.draw(scene.sprites(at: position),
          context: context.cgContext, size: size)
      } catch { failure = error }
    }
    if let failure { throw failure }
    return image
  }
}

/// The two open-source fixture engines, in the default suite.
@MainActor
final class EnginePreviewFixtureTests: XCTestCase {
  func testPJSekaiPreviewRendersAndScrollsTheWholeChart() throws {
    try check(.pjsekai, level: Fixture.pjsekaiLevel)
  }

  func testBandoriPreviewRendersAndScrollsTheWholeChart() throws {
    try check(.bandori, level: Fixture.bandoriLevel)
  }

  private func check(_ engine: Fixture.Engine, level: LevelData) throws {
    let dist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Engines/\(engine.rawValue)/dist")
    let url = dist.appendingPathComponent("EnginePreviewData")
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw XCTSkip("The \(engine.rawValue) engine fixture submodule is not "
        + "checked out. Run `git submodule update --init`.")
    }
    let preview = try CompressedJSONDecoder.decode(EnginePreviewData.self,
      from: Data(contentsOf: url))
    let assets = try PreviewPresentation.assets(
      sprites: preview.skin.sprites, configuration: Data(contentsOf:
        dist.appendingPathComponent("EngineConfiguration")))
    XCTAssertEqual(Set(assets.skin.keys), Set(preview.skin.sprites.map(\.id)))
    // A 120 BPM, 5.5-second chart is two panels at most; stretch it so the
    // canvas is wider than the screen, as any real song's is.
    let long = LevelData(bgmOffset: 0, entities: level.entities
      + (12..<160).map { beat in
        LevelEntity(archetype: level.entities[4].archetype, name: nil,
          data: level.entities[4].data.map {
            $0.name == "#BEAT" ? LevelEntityData(name: "#BEAT",
              value: Double(beat), ref: nil) : $0
          })
      })
    for aspect in [16.0 / 9, 19.5 / 9, 4.0 / 3] {
      let result = try PreviewSweep.run(engine: preview, level: long,
        assets: assets, aspectRatio: aspect, name: engine.rawValue)
      XCTAssertEqual(result.frame.canvas.scroll, .leftToRight)
      // Times, measures and the BPM are printed.
      XCTAssertTrue(Set(result.frame.prints.map(\.format))
        .isSuperset(of: [10, 31, 20]), engine.rawValue)
      XCTAssertEqual(PreviewSweep.unreachable(result), 0, engine.rawValue)
    }
  }
}

/// Opt-in: real charts and engines in the test host's caches, under
/// `OpenRhythmIntegrationFixtures/preview/<engine>`: preview.gz, level.gz,
/// configuration, skinData, skinTexture and, if the engine has one, rom.bin.
/// Downloaded assets never enter the repository. No network access is used.
@MainActor
final class CachedEnginePreviewTests: XCTestCase {
  func testLLSIFPreview() throws { try check("llsif") }
  func testSekaiPreview() throws { try check("sekai") }
  func testCGSSPreview() throws { try check("cgss") }
  // The rhythm-lab `sfp` engine (sonolus-sfp-engine scripts/openrhythm-fixture.ts).
  func testSFPPreview() throws { try check("sfp") }
  // The rhythm-lab `mltd` engine (sonolus-mltd-engine scripts/fixtures.ts).
  func testMLTDPreview() throws { try check("mltd") }

  private func check(_ name: String) throws {
    let root = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures/preview/\(name)")
    guard FileManager.default.fileExists(atPath: root.path) else {
      throw XCTSkip("Optional cached \(name) preview fixtures are not "
        + "installed.")
    }
    func data(_ file: String) throws -> Data {
      try Data(contentsOf: root.appendingPathComponent(file))
    }
    let engine = try CompressedJSONDecoder.decode(EnginePreviewData.self,
      from: data("preview.gz"))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: data("level.gz"))
    let rom = FileManager.default.fileExists(atPath:
      root.appendingPathComponent("rom.bin").path) ? try data("rom.bin") : nil
    let assets = try EnginePresentationAssets(skinDefinition: engine.skin,
      particleDefinition: EngineParticleDefinition(effects: []),
      presentation: RuntimePresentation(resources: [
        "configuration": data("configuration"),
        "skinData": data("skinData"), "skinTexture": data("skinTexture")]))
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("preview-\(name)")
    try FileManager.default.createDirectory(at: output,
      withIntermediateDirectories: true)
    for (label, aspect) in [("16x9", 16.0 / 9), ("19.5x9", 19.5 / 9),
      ("portrait", 9.0 / 19.5)] {
      let started = ProcessInfo.processInfo.systemUptime
      let result = try PreviewSweep.run(engine: engine, level: level,
        assets: assets, rom: rom, aspectRatio: aspect, name: name)
      let elapsed = ProcessInfo.processInfo.systemUptime - started
      XCTAssertFalse(result.frame.prints.isEmpty, "\(name) printed nothing")
      let unreachable = PreviewSweep.unreachable(result)
      XCTAssertEqual(unreachable, 0, "\(name) drew off the canvas")
      print("\(name) \(label): \(result.frame.draws.count) draws, "
        + "\(result.scene.spriteCount) sprites, "
        + "\(result.frame.prints.count) prints, canvas "
        + "\(result.frame.canvas.size) (\(result.frame.canvas.scroll)), "
        + "\(result.positions) positions, \(unreachable) unreachable, "
        + String(format: "%.2f s", elapsed))
      // Software renderings at the start, middle and end, for inspection.
      let height = 390.0
      let size = CGSize(width: (height * aspect).rounded(), height: height)
      for (index, fraction) in [0, 0.5, 1].enumerated() {
        let image = try PreviewSweep.image(result.scene,
          at: result.frame.canvas.position(atProgress: fraction), size: size)
        try image.pngData()?.write(to: output.appendingPathComponent(
          "\(label)-\(index).png"))
      }
    }
    print("\(name) preview renderings: \(output.path)")
  }
}
