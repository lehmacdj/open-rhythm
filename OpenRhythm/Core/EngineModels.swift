import Foundation

struct EngineNamedID: Decodable, Sendable {
  let name: String
  let id: Int
}

struct EngineSkinDefinition: Decodable, Sendable {
  let renderMode: String?
  let sprites: [EngineNamedID]

  var forcedRenderMode: EngineSkinRenderMode? {
    get throws {
      switch renderMode {
      case nil, "default": return nil
      case "standard": return .standard
      case "lightweight": return .lightweight
      default: throw EngineInterpreterError.invalidArguments("skin render mode: \(renderMode!)")
      }
    }
  }
}

enum EngineSkinRenderMode: String, Codable, CaseIterable, Sendable {
  case standard, lightweight
  var title: String { self == .standard ? "Standard" : "Lightweight" }
}

struct EngineEffectDefinition: Decodable, Sendable {
  let clips: [EngineNamedID]
}

struct EngineParticleDefinition: Decodable, Sendable {
  let effects: [EngineNamedID]
}

struct EngineCallback: Decodable, Sendable {
  let index: Int
  let order: Double?
}

struct EngineArchetypeImport: Decodable, Sendable {
  let name: String
  let index: Int
  let def: Double?
}

struct EngineArchetype: Decodable, Sendable {
  let name: String
  let hasInput: Bool
  let preprocess: EngineCallback?
  let spawnOrder: EngineCallback?
  let shouldSpawn: EngineCallback?
  let initialize: EngineCallback?
  let updateSequential: EngineCallback?
  let touch: EngineCallback?
  let updateParallel: EngineCallback?
  let terminate: EngineCallback?
  let imports: [EngineArchetypeImport]
  let exports: [String]
}

struct EngineDataNode: Decodable, Sendable {
  let value: Double?
  let function: String?
  let arguments: [Int]

  private enum CodingKeys: String, CodingKey {
    case value
    case function = "func"
    case arguments = "args"
  }

  init(value: Double) {
    self.value = value
    function = nil
    arguments = []
  }

  init(function: String, arguments: [Int]) {
    value = nil
    self.function = function
    self.arguments = arguments
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = try container.decodeIfPresent(Double.self, forKey: .value)
    function = try container.decodeIfPresent(String.self, forKey: .function)
    arguments = try container.decodeIfPresent(
      [Int].self,
      forKey: .arguments
    ) ?? []

    guard (value == nil) != (function == nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: .value,
        in: container,
        debugDescription: "A node must contain exactly one value or function."
      )
    }
  }
}

struct EngineBucketSprite: Decodable, Sendable {
  let id: Int
  let x: Double
  let y: Double
  let w: Double
  let h: Double
  let rotation: Double
}

struct EngineBucket: Decodable, Sendable {
  let sprites: [EngineBucketSprite]
  let unit: String?
}

struct EnginePlayData: Decodable, Sendable {
  let skin: EngineSkinDefinition
  let effect: EngineEffectDefinition
  let particle: EngineParticleDefinition
  let archetypes: [EngineArchetype]
  let nodes: [EngineDataNode]
  let buckets: [EngineBucket]

  /// Only persistent non-input entities with proven fixed stage draws
  /// are exempt from the initial visual boundary. A sprite's name alone cannot
  /// establish that it is static: engines can animate ordinary stage sprites.
  var staticIntroArchetypes: Set<Int> {
    let stageNames: Set<String> = ["#STAGE_MIDDLE", "#STAGE_COVER", "#LANE",
      "#LANE_SEAMLESS", "#LANE_ALTERNATIVE", "#LANE_ALTERNATIVE_SEAMLESS",
      "#JUDGMENT_LINE", "#NOTE_SLOT", "#STAGE_LEFT_BORDER",
      "#STAGE_RIGHT_BORDER", "#STAGE_TOP_BORDER", "#STAGE_BOTTOM_BORDER",
      "#STAGE_LEFT_BORDER_SEAMLESS", "#STAGE_RIGHT_BORDER_SEAMLESS",
      "#STAGE_TOP_BORDER_SEAMLESS", "#STAGE_BOTTOM_BORDER_SEAMLESS",
      "#STAGE_TOP_LEFT_CORNER", "#STAGE_TOP_RIGHT_CORNER",
      "#STAGE_BOTTOM_LEFT_CORNER", "#STAGE_BOTTOM_RIGHT_CORNER"]
    let grouped = Dictionary(grouping: skin.sprites, by: \.id)
    let stageIDs = Set(grouped.compactMap { id, sprites in
      sprites.allSatisfy { stageNames.contains($0.name) } ? id : nil
    })
    // Do not infer purity from supportedFunctions: streams and random values
    // can change even when their arguments are fixed. Drawing is a separate
    // proof result and must never qualify as a side-effect-free argument.
    let pure: Set<String> = Set([
      "Abs", "Add", "And", "Arccos", "Arcsin", "Arctan", "Arctan2",
      "Ceil", "Clamp", "Cos", "Cosh", "Degree", "Divide", "Equal",
      "Floor", "Frac", "Greater", "GreaterOr", "Lerp", "LerpClamped",
      "Less", "LessOr", "Log", "Max", "Min", "Mod", "Multiply", "Negate",
      "Not", "NotEqual", "Or", "Power", "Radian", "Rem", "Remap",
      "RemapClamped", "Round", "Sign", "Sin", "Sinh", "Subtract", "Tan",
      "Tanh", "Trunc", "Unlerp", "UnlerpClamped"
    ]).union(EngineInterpreter.easingFunctions)
    let drawing: Set<String> = ["Draw", "DrawCurvedB", "DrawCurvedT",
      "DrawCurvedL", "DrawCurvedR", "DrawCurvedBT", "DrawCurvedLR"]
    let branching: Set<String> = ["If", "Switch", "SwitchWithDefault",
      "SwitchInteger", "SwitchIntegerWithDefault"]
    // These blocks cannot change after preprocessing, including writes via
    // Entity Data's array alias. Only level-backed entities receive the flag.
    let fixedBlocks: Set<Double> = [2001, 2002, 3000, 4001]
    enum Proof { case constant, drawing, unsafe }
    var proofs = [Int: Proof]()
    var remainingWork = 100_000
    func isStaticDrawing(_ root: Int) -> Bool {
      var pending = [(index: root, expanded: false)]
      var active = Set<Int>()
      while let (index, expanded) = pending.popLast() {
        if proofs[index] != nil { continue }
        guard nodes.indices.contains(index), remainingWork > 0 else {
          return false
        }
        let node = nodes[index]
        let function = node.function ?? ""
        if expanded {
          active.remove(index)
          let arguments = node.arguments.map { proofs[$0] ?? .unsafe }
          let combined: Proof = arguments.contains(.unsafe) ? .unsafe
              : arguments.contains(.drawing) ? .drawing : .constant
          switch function {
          case "Execute", "Execute0": proofs[index] = combined
          case "If":
            proofs[index] = arguments.count == 3 && arguments[0] == .constant
              ? combined : .unsafe
          case "Switch", "SwitchWithDefault":
            let end = arguments.count - (function == "SwitchWithDefault" ? 1 : 0)
            let fixedSelection = end >= 1 && (end - 1).isMultiple(of: 2)
              && arguments[0] == .constant
              && stride(from: 1, to: end, by: 2).allSatisfy {
                arguments[$0] == .constant
              }
            proofs[index] = fixedSelection ? combined : .unsafe
          case "SwitchInteger", "SwitchIntegerWithDefault":
            let minimum = function == "SwitchIntegerWithDefault" ? 2 : 1
            proofs[index] = arguments.count >= minimum && arguments[0] == .constant
              ? combined : .unsafe
          default:
            proofs[index] = arguments.allSatisfy { $0 == .constant }
              ? (drawing.contains(function) ? .drawing : .constant) : .unsafe
          }
          continue
        }
        // Charge edges before allocating their traversal frames. Reuse results
        // across archetypes and shared DAGs, but reject gray (cyclic) nodes.
        guard node.arguments.count < remainingWork else { return false }
        remainingWork -= node.arguments.count + 1
        guard active.insert(index).inserted else {
          proofs[index] = .unsafe
          continue
        }
        if node.value != nil {
          proofs[index] = .constant
          active.remove(index)
          continue
        }
        let first = node.arguments.first.flatMap {
          nodes.indices.contains($0) ? nodes[$0].value : nil
        }
        let fixedRead = function == "Get" && node.arguments.count == 2
          && first.map(fixedBlocks.contains) == true
        let stageDraw = drawing.contains(function)
          && first.flatMap(Int.init(exactly:)).map(stageIDs.contains) == true
        guard pure.contains(function) || branching.contains(function)
          || fixedRead || stageDraw
          || function == "Execute" || function == "Execute0" else {
          proofs[index] = .unsafe
          active.remove(index)
          continue
        }
        pending.append((index, true))
        pending.append(contentsOf: node.arguments.map { ($0, false) })
      }
      return proofs[root].map { $0 != .unsafe } ?? false
    }
    return Set(archetypes.indices.filter { index in
      let a = archetypes[index]
      guard !a.hasInput, a.shouldSpawn == nil, a.initialize == nil,
        a.updateSequential == nil, a.touch == nil, a.terminate == nil,
        let update = a.updateParallel else { return false }
      return isStaticDrawing(update.index)
    })
  }

  /// Include callbacks of spawnable archetypes, but not orphaned compiler
  /// nodes. Inspect both sides of lazy branches: a missed tap must not be the
  /// first time we discover that its successful-hit path is unsupported.
  func unsupportedFunctions() throws -> [String] {
    let supported = EngineInterpreter.supportedFunctions
      .union(CommandEngineRuntimeHost.supportedFunctions)
    var pending = archetypes.flatMap {
      [$0.preprocess, $0.spawnOrder, $0.shouldSpawn, $0.initialize,
       $0.updateSequential, $0.touch, $0.updateParallel, $0.terminate]
        .compactMap { $0?.index }
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
