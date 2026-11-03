import CoreGraphics
import Foundation

/// Preview-mode block IDs, named as in the public engine specs:
/// https://wiki.sonolus.com/engine-specs/preview-blocks/overview
/// Several IDs coincide with play blocks of a different meaning.
enum EnginePreviewBlock {
  static let runtimeEnvironment = 1000
  static let runtimeCanvas = 1001
  static let runtimeSkinTransform = 1002
  static let runtimeUI = 1003
  static let runtimeUIConfiguration = 1004
  static let previewData = 2000
  static let previewOption = 2001
  static let engineROM = 3000
  static let entityData = 4000
  static let entitySharedMemory = 4001
  static let entityInfo = 4002
  static let entityDataArray = 4100
  static let entitySharedMemoryArray = 4101
  static let entityInfoArray = 4102
  static let temporaryMemory = 10000
}

enum EnginePreviewError: LocalizedError {
  case noPreviewData

  var errorDescription: String? {
    switch self {
    case .noPreviewData:
      "This chart’s engine doesn’t provide a preview."
    }
  }
}

struct EnginePreviewArchetype: Decodable, Sendable {
  let name: String
  let preprocess: EngineCallback?
  let render: EngineCallback?
  let imports: [EngineArchetypeImport]
}

/// The engine's `previewData` resource. Its skin sprite IDs are independent
/// of play data's, so availability is computed from this definition.
struct EnginePreviewData: Decodable, Sendable {
  let skin: EngineSkinDefinition
  let archetypes: [EnginePreviewArchetype]
  let nodes: [EngineDataNode]
  let entityLayout: EngineEntityLayout

  private enum CodingKeys: String, CodingKey {
    case skin, archetypes, nodes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    skin = try container.decode(EngineSkinDefinition.self, forKey: .skin)
    archetypes = try container.decode([EnginePreviewArchetype].self,
      forKey: .archetypes)
    nodes = try container.decode([EngineDataNode].self, forKey: .nodes)
    // The optional length fields apply to every mode's data; Entity Memory's
    // length is unused because preview has no Entity Memory.
    entityLayout = try EngineEntityLayout(from: decoder)
  }

  /// Reachable functions this host cannot run in preview, scanning both
  /// sides of lazy branches like the play preflight.
  func unsupportedFunctions() throws -> [String] {
    let supported = EngineInterpreter.supportedFunctions
      .union(CommandEngineRuntimeHost.previewSupportedFunctions)
    var pending = archetypes.flatMap {
      [$0.preprocess, $0.render].compactMap { $0?.index }
    }
    var visited = Set<Int>()
    var missing = Set<String>()
    while let index = pending.popLast() {
      guard nodes.indices.contains(index) else {
        throw EngineInterpreterError.invalidNode(index)
      }
      guard visited.insert(index).inserted else { continue }
      let node = nodes[index]
      if let function = node.function, !supported.contains(function) {
        missing.insert(function)
      }
      pending.append(contentsOf: node.arguments)
    }
    return missing.sorted()
  }
}

/// Runtime Canvas: the engine draws one picture longer than the screen along
/// the scroll axis, and the host scrolls a screen-sized window across it.
/// https://wiki.sonolus.com/engine-specs/preview-blocks/runtime-canvas
///
/// The canvas starts at the screen edge named by the scroll direction and
/// extends `size` screen units from it, as in the official preview guides
/// (left to right: x from the screen's left edge to left + size). Positions
/// are measured from that start, so 0 is the initial view for every
/// direction.
struct EnginePreviewCanvas: Equatable, Sendable {
  enum Scroll: Int, Sendable {
    case leftToRight = 0, topToBottom, rightToLeft, bottomToTop
  }

  /// Host safety limit in screen units (screen heights / 2), not a protocol
  /// bound. It keeps scroll content within Core Animation's precision.
  static let maximumSize = 65_536.0

  let scroll: Scroll
  let size: Double
  let aspectRatio: Double

  init(scroll: Scroll, size: Double, aspectRatio: Double) {
    self.scroll = scroll
    self.size = size
    self.aspectRatio = aspectRatio
  }

  /// Validates the engine's Runtime Canvas values.
  init(scrollValue: Double, size: Double, aspectRatio: Double) throws {
    guard let raw = Int(exactly: scrollValue),
      let scroll = Scroll(rawValue: raw) else {
      throw RuntimeBundleError.unsupportedPresentationValue(
        field: "preview scroll direction", value: String(scrollValue))
    }
    guard size.isFinite, size >= 0 else {
      throw EngineInterpreterError.invalidArguments("Runtime Canvas size")
    }
    guard size <= Self.maximumSize else {
      throw EngineInterpreterError.resourceLimitExceeded("preview canvas size")
    }
    self.init(scroll: scroll, size: size, aspectRatio: aspectRatio)
  }

  var isHorizontal: Bool {
    scroll == .leftToRight || scroll == .rightToLeft
  }

  /// The screen's extent along the scroll axis.
  var visibleLength: Double { isHorizontal ? 2 * aspectRatio : 2 }

  /// How far the view can travel from its starting position.
  var scrollLength: Double { max(0, size - visibleLength) }

  func clamped(_ position: Double) -> Double {
    position.isFinite ? min(scrollLength, max(0, position)) : 0
  }

  /// The translation from canvas to screen coordinates at `position`.
  func offset(at position: Double) -> EnginePoint {
    let p = clamped(position)
    switch scroll {
    case .leftToRight: return EnginePoint(x: -p, y: 0)
    case .rightToLeft: return EnginePoint(x: p, y: 0)
    case .topToBottom: return EnginePoint(x: 0, y: p)
    case .bottomToTop: return EnginePoint(x: 0, y: -p)
    }
  }

  /// The part of the canvas on screen at `position`, in canvas coordinates.
  func visibleBounds(at position: Double) -> CGRect {
    let offset = offset(at: position)
    return CGRect(x: -aspectRatio - offset.x, y: -1 - offset.y,
      width: 2 * aspectRatio, height: 2)
  }

  /// Scroll view content length along the axis, in points.
  func contentLength(pointsPerUnit: Double) -> Double {
    (visibleLength + scrollLength) * pointsPerUnit
  }

  /// UIKit content offsets grow rightward and downward. Right-to-left and
  /// bottom-to-top canvases start at the far end of the content, so dragging
  /// always moves the picture with the finger.
  func contentOffset(at position: Double, pointsPerUnit: Double) -> Double {
    let p = clamped(position)
    switch scroll {
    case .leftToRight, .topToBottom: return p * pointsPerUnit
    case .rightToLeft, .bottomToTop: return (scrollLength - p) * pointsPerUnit
    }
  }

  func position(atContentOffset offset: Double, pointsPerUnit: Double)
    -> Double {
    guard pointsPerUnit > 0 else { return 0 }
    let distance = offset / pointsPerUnit
    switch scroll {
    case .leftToRight, .topToBottom: return clamped(distance)
    case .rightToLeft, .bottomToTop: return clamped(scrollLength - distance)
    }
  }

  /// Fraction of the scroll range, 0 at the start; 0 when nothing scrolls.
  func progress(at position: Double) -> Double {
    scrollLength > 0 ? clamped(position) / scrollLength : 0
  }

  func position(atProgress progress: Double) -> Double {
    clamped(progress * scrollLength)
  }
}

/// One Runtime UI layout (menu or progress): anchor, pivot, size, rotation,
/// alpha and background, in that order.
struct EnginePreviewUIElement: Equatable, Sendable {
  let values: [Double]

  var isVisible: Bool {
    values.count == 9 && values.allSatisfy(\.isFinite)
      && values[4] > 0 && values[5] > 0 && values[7] > 0
  }

  /// The element's frame in view points (top-left origin), ignoring rotation.
  func frame(in size: CGSize) -> CGRect {
    let unit = size.height / 2
    let width = values[4] * unit, height = values[5] * unit
    let anchorX = size.width / 2 + values[0] * unit
    let anchorY = size.height / 2 - values[1] * unit
    return CGRect(x: anchorX - values[2] * width,
      y: anchorY - (1 - values[3]) * height, width: width, height: height)
  }
}

/// The values a preview produces once: a static picture plus labels.
struct EnginePreviewFrame: Sendable {
  let canvas: EnginePreviewCanvas
  /// In emission order; renderers sort by z as for play frames.
  let draws: [EngineDrawCommand]
  let prints: [EnginePrintCommand]
  let menu: EnginePreviewUIElement
  let progress: EnginePreviewUIElement
}

/// Runs preview preparation and rendering. Preview has no time: `render`
/// callbacks draw the whole chart into the canvas, so the host renders once
/// per screen size and scrolls the result.
/// https://wiki.sonolus.com/engine-specs/preview-lifecycle/overview
final class EnginePreviewRuntime {
  private typealias Block = EnginePreviewBlock

  /// Host safety limits for one whole-chart rendering, not protocol limits.
  static let drawSegmentLimit = 1 << 20
  static let printLimit = 65_536

  let host: CommandEngineRuntimeHost
  let memory: EngineMemory
  private let engine: EnginePreviewData
  private let interpreter: EngineInterpreter
  private let aspectRatio: Double
  /// Level-backed entities: (entity index, archetype index).
  private var entities = [(index: Int, archetype: Int)]()

  init(
    engine: EnginePreviewData, level: LevelData, options: [Double],
    aspectRatio: Double, skinSpriteIDs: Set<EngineResourceID>,
    rom: Data? = nil, safeArea: [Double]? = nil,
    uiConfiguration: [Double] = [1, 1, 1, 1], debugMode: Bool = false
  ) throws {
    guard aspectRatio.isFinite, aspectRatio > 0,
      level.entities.count <= 100_000,
      uiConfiguration.count == 4, uiConfiguration.allSatisfy(\.isFinite),
      safeArea == nil || (safeArea?.count == 4
        && safeArea?.allSatisfy(\.isFinite) == true) else {
      throw EngineInterpreterError.invalidArguments("runtime environment")
    }
    let missing = try engine.unsupportedFunctions()
    guard missing.isEmpty else {
      throw EngineInterpreterError.unsupportedFunction(
        missing.joined(separator: ", "))
    }
    self.engine = engine
    self.aspectRatio = aspectRatio
    memory = EngineMemory()
    try memory.loadROM(rom)
    try memory.configurePreviewBlocks(entityCount: level.entities.count,
      optionCount: options.count, entityLayout: engine.entityLayout)
    // Preview has no effects or particles: their availability queries
    // report nothing, and timelines use the chart's own tempo (speed 1).
    host = CommandEngineRuntimeHost(memory: memory, level: level,
      skinSpriteIDs: skinSpriteIDs, effectClipIDs: [], particleEffectIDs: [],
      archetypeCount: engine.archetypes.count, mode: .preview)
    interpreter = EngineInterpreter(nodes: engine.nodes, memory: memory,
      host: host)
    var archetypes = [String: Int]()
    for (index, archetype) in engine.archetypes.enumerated() {
      guard archetypes.updateValue(index, forKey: archetype.name) == nil else {
        throw EngineInterpreterError.invalidArguments("duplicate archetype")
      }
    }
    var names = [String: Int]()
    for (index, entity) in level.entities.enumerated() {
      if let name = entity.name,
        names.updateValue(index, forKey: name) != nil {
        throw EngineInterpreterError.invalidArguments("duplicate entity name")
      }
    }
    memory.set(block: Block.runtimeEnvironment, index: 0,
      value: debugMode ? 1 : 0)
    memory.set(block: Block.runtimeEnvironment, index: 1, value: aspectRatio)
    for (index, value) in (safeArea ?? [-aspectRatio, aspectRatio, -1, 1])
      .enumerated() {
      memory.set(block: Block.runtimeEnvironment, index: 2 + index,
        value: value)
    }
    for (index, value) in options.enumerated() {
      memory.set(block: Block.previewOption, index: index, value: value)
    }
    for (index, value) in uiConfiguration.enumerated() {
      memory.set(block: Block.runtimeUIConfiguration, index: index,
        value: value)
    }
    for (index, source) in level.entities.enumerated() {
      memory.set(block: Block.entityInfoArray, index: index * 2,
        value: Double(index))
      // Entities without a preview archetype (such as editor metadata) keep
      // their indices but run no callbacks.
      guard let archetypeID = archetypes[source.archetype] else {
        memory.set(block: Block.entityInfoArray, index: index * 2 + 1,
          value: -1)
        continue
      }
      memory.set(block: Block.entityInfoArray, index: index * 2 + 1,
        value: Double(archetypeID))
      entities.append((index, archetypeID))
      memory.selectEntity(key: index, index: index)
      for field in engine.archetypes[archetypeID].imports {
        guard (0..<engine.entityLayout.data).contains(field.index) else {
          throw EngineInterpreterError.invalidArguments(
            "entity import index \(field.index) (Entity Data length "
              + "\(engine.entityLayout.data))")
        }
        let datum = source.data.first { $0.name == field.name }
        let value: Double
        if let reference = datum?.ref {
          guard let index = names[reference] else {
            throw EngineInterpreterError.invalidArguments("entity reference")
          }
          value = Double(index)
        } else {
          value = datum?.value ?? field.def ?? 0
        }
        memory.set(block: Block.entityData, index: field.index, value: value)
      }
    }
    for entity in ordered(by: \.preprocess) {
      _ = try execute(entity, callback: \.preprocess)
    }
  }

  /// The canvas as preprocessing left it.
  var canvas: EnginePreviewCanvas {
    get throws {
      try EnginePreviewCanvas(
        scrollValue: memory.value(block: Block.runtimeCanvas, index: 0),
        size: memory.value(block: Block.runtimeCanvas, index: 1),
        aspectRatio: aspectRatio)
    }
  }

  /// Runs every entity's `render` callback once.
  func render() throws -> EnginePreviewFrame {
    let canvas = try canvas
    var draws = [EngineDrawCommand]()
    var prints = [EnginePrintCommand]()
    var segments = 0
    for entity in ordered(by: \.render) {
      _ = try execute(entity, callback: \.render)
      let entityDraws = host.takeDrawCommands()
      segments += entityDraws.reduce(0) { $0 + ($1.curve?.segments ?? 1) }
      guard segments <= Self.drawSegmentLimit else {
        throw EngineInterpreterError.resourceLimitExceeded(
          "preview draw segments")
      }
      draws.append(contentsOf: entityDraws)
      prints.append(contentsOf: host.takePrintCommands())
      guard prints.count <= Self.printLimit else {
        throw EngineInterpreterError.resourceLimitExceeded(
          "preview printed values")
      }
    }
    func element(_ index: Int) -> EnginePreviewUIElement {
      EnginePreviewUIElement(values: (0..<9).map {
        memory.value(block: Block.runtimeUI, index: index * 9 + $0)
      })
    }
    return EnginePreviewFrame(canvas: canvas, draws: draws, prints: prints,
      menu: element(0), progress: element(1))
  }

  private func execute(_ entity: (index: Int, archetype: Int),
    callback: KeyPath<EnginePreviewArchetype, EngineCallback?>) throws {
    guard let definition = engine.archetypes[entity.archetype][
      keyPath: callback] else { return }
    memory.selectEntity(key: entity.index, index: entity.index)
    host.selectEntity(index: entity.index, exportCount: 0)
    memory.callback = callback == \EnginePreviewArchetype.preprocess
      ? .preprocess : .render
    defer { memory.callback = nil }
    _ = try interpreter.execute(nodeAt: definition.index)
  }

  private func ordered(
    by callback: KeyPath<EnginePreviewArchetype, EngineCallback?>
  ) -> [(index: Int, archetype: Int)] {
    entities.sorted {
      let lhs = engine.archetypes[$0.archetype][keyPath: callback]?.order ?? 0
      let rhs = engine.archetypes[$1.archetype][keyPath: callback]?.order ?? 0
      return lhs == rhs ? $0.index < $1.index : lhs < rhs
    }
  }
}

/// Text for `Print`'s formats. The function page names the formats but not
/// their rendering, so the wording here is host policy.
enum EnginePrintFormat: Int, Sendable {
  case number = 0, percentage = 1, time = 10, score = 11, bpm = 20
  case timeScale = 21, beatCount = 30, measureCount = 31, entityCount = 32
}

extension EnginePrintCommand {
  /// Unknown formats print the plain number rather than ending the preview.
  func text(locale: Locale = .current) -> String {
    let places = Int(exactly: decimalPlaces).flatMap {
      (0...10).contains($0) ? $0 : nil
    }
    func number(_ value: Double, grouping: Bool = false) -> String {
      let style = FloatingPointFormatStyle<Double>.number.locale(locale)
        .grouping(grouping ? .automatic : .never)
      return places.map {
        value.formatted(style.precision(.fractionLength($0)))
      } ?? value.formatted(style.precision(.fractionLength(0...3)))
    }
    switch Int(exactly: format).flatMap(EnginePrintFormat.init(rawValue:)) {
    case .percentage: return number(value * 100) + "%"
    case .time: return Self.time(value, places: places, locale: locale)
    case .score: return number(value, grouping: true)
    case .bpm: return number(value) + " BPM"
    case .timeScale: return "×" + number(value)
    case .number, .beatCount, .measureCount, .entityCount, nil:
      return number(value)
    }
  }

  /// Minutes and seconds, such as 1:05 or 1:05.25.
  private static func time(_ value: Double, places: Int?, locale: Locale)
    -> String {
    // Round first so 59.96 seconds at one place reads 1:00.0, not 0:60.0.
    let digits = places ?? 3
    let scale = pow(10, Double(digits))
    let total = (abs(value) * scale).rounded() / scale
    let minutes = (total / 60).rounded(.down)
    let seconds = total - minutes * 60
    let style = FloatingPointFormatStyle<Double>.number.locale(locale)
      .grouping(.never)
      .precision(places.map {
        .integerAndFractionLength(integerLimits: 2..., fractionLimits: $0...$0)
      } ?? .integerAndFractionLength(integerLimits: 2...,
        fractionLimits: 0...3))
    let sign = value < 0 && total > 0 ? "-" : ""
    return sign + Int(minutes).formatted(.number.locale(locale)
      .grouping(.never)) + ":" + seconds.formatted(style)
  }
}
