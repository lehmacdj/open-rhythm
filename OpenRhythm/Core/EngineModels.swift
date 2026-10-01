import Foundation

// Named resource identities are engine numbers, not array indices.
typealias EngineResourceID = Double

struct EngineNamedID: Decodable, Sendable {
  let name: String
  let id: EngineResourceID
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

struct EngineBucketSprite: Codable, Equatable, Sendable {
  let id: EngineResourceID
  var fallbackId: EngineResourceID? = nil
  let x: Double
  let y: Double
  let w: Double
  let h: Double
  let rotation: Double
}

struct EngineBucket: Codable, Equatable, Sendable {
  let sprites: [EngineBucketSprite]
  let unit: String?
}

struct EngineResultBucket: Codable, Equatable, Sendable {
  let definition: EngineBucket
  // LevelBucket order: min/max Perfect, min/max Great, min/max Good.
  // Invalid values stay unavailable, never guessed or used to rejudge input.
  let windows: [Double?]
  var imagePNG: Data? = nil
  var imageError: String? = nil
}

struct EnginePlayData: Decodable, Sendable {
  let skin: EngineSkinDefinition
  let effect: EngineEffectDefinition
  let particle: EngineParticleDefinition
  let archetypes: [EngineArchetype]
  let nodes: [EngineDataNode]
  let buckets: [EngineBucket]

  /// Ambiguous aliases must not turn a custom effect into stage decoration.
  var introStageSpriteIDs: Set<EngineResourceID> {
    let stageNames: Set<String> = ["#STAGE_MIDDLE", "#STAGE_COVER", "#LANE",
      "#LANE_SEAMLESS", "#LANE_ALTERNATIVE", "#LANE_ALTERNATIVE_SEAMLESS",
      "#JUDGMENT_LINE", "#NOTE_SLOT", "#STAGE_LEFT_BORDER",
      "#STAGE_RIGHT_BORDER", "#STAGE_TOP_BORDER", "#STAGE_BOTTOM_BORDER",
      "#STAGE_LEFT_BORDER_SEAMLESS", "#STAGE_RIGHT_BORDER_SEAMLESS",
      "#STAGE_TOP_BORDER_SEAMLESS", "#STAGE_BOTTOM_BORDER_SEAMLESS",
      "#STAGE_TOP_LEFT_CORNER", "#STAGE_TOP_RIGHT_CORNER",
      "#STAGE_BOTTOM_LEFT_CORNER", "#STAGE_BOTTOM_RIGHT_CORNER"]
    let grouped = Dictionary(grouping: skin.sprites, by: \.id)
    return Set(grouped.compactMap { id, sprites in
      sprites.allSatisfy { stageNames.contains($0.name) } ? id : nil
    })
  }

  /// Persistent non-input candidates with fixed draws and no persistent writes.
  /// Callback-local scratch calculations require initialization before use.
  /// Each actual draw must also resolve to an unambiguous stage sprite ID in
  /// the host. Neither a fixed expression nor a stage name alone is sufficient.
  var staticIntroArchetypes: Set<Int> {
    // Do not infer purity from supportedFunctions: streams and random values
    // can change even when their arguments are fixed. Drawing is a separate
    // proof result and must never qualify as a fixed scalar argument.
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
    // The host captures these availability sets once for the entire runtime.
    // Unlike streams or random values, fixed IDs always yield fixed answers.
    let resourceQueries: Set<String> = ["HasSkinSprite", "HasEffectClip",
      "HasParticleEffect"]
    // These blocks cannot change after preprocessing, including writes via
    // Entity Data's array alias. Only level-backed entities receive the flag.
    let fixedBlocks: Set<Double> = [2001, 2002, 3000, 4001]
    // Entity Memory (4000) has no cross-entity alias. It is also stable once
    // preparation finishes IF subsequent callbacks never write it. The
    // whole-archetype checks below establish that condition: any possible
    // write disqualifies the entity, even when a shared read node was memoized.
    // Spawned copies never receive this flag; their memory is initialized at
    // spawn rather than at level preparation.
    struct Proof {
      enum Kind { case constant, drawing, unsafe }
      var kind: Kind
      // A summary is independent of the caller's scratch state, so it can be
      // memoized even when a shared node is read before and after a write.
      var required = Set<Int>()
      var written = Set<Int>()
      static let constant = Proof(kind: .constant)
      static let unsafe = Proof(kind: .unsafe)
    }
    var proofs = [Int: Proof]()
    var remainingWork = 100_000
    func scratchAccess(_ node: EngineDataNode)
      -> (slot: Int, reads: Bool, writes: Bool)? {
      let function = node.function ?? ""
      let count: Int
      switch function {
      case "Get", "IncrementPre", "IncrementPost", "DecrementPre", "DecrementPost":
        count = 2
      case "Set", "SetAdd", "SetSubtract", "SetMultiply", "SetDivide",
        "SetPower", "SetMod", "SetRem": count = 3
      default: return nil
      }
      guard node.arguments.count == count,
        nodes.indices.contains(node.arguments[0]),
        nodes.indices.contains(node.arguments[1]),
        nodes[node.arguments[0]].value == 10000,
        let index = nodes[node.arguments[1]].value,
        let slot = Int(exactly: index.rounded(.towardZero)),
        (0..<4096).contains(slot) else { return nil }
      return (slot, function != "Set", function != "Get")
    }
    func sequence(_ children: [Proof], kind: Proof.Kind) -> Proof {
      var result = Proof(kind: kind)
      for child in children {
        result.required.formUnion(child.required.subtracting(result.written))
        result.written.formUnion(child.written)
      }
      return result
    }
    // Only the first expression is guaranteed to run in lazy choices. Require
    // later paths to be safe independently; do not borrow writes from a branch
    // or short-circuited operand that may never execute.
    func choice(_ children: [Proof], kind: Proof.Kind) -> Proof {
      guard let first = children.first else { return Proof(kind: kind) }
      var result = first
      result.kind = kind
      for child in children.dropFirst() {
        result.required.formUnion(child.required.subtracting(first.written))
      }
      return result
    }
    func proof(_ root: Int) -> Proof {
      var pending = [(index: root, expanded: false)]
      var active = Set<Int>()
      while let (index, expanded) = pending.popLast() {
        if proofs[index] != nil { continue }
        guard nodes.indices.contains(index), remainingWork > 0 else {
          return .unsafe
        }
        let node = nodes[index]
        let function = node.function ?? ""
        if expanded {
          active.remove(index)
          let arguments = node.arguments.map { proofs[$0] ?? .unsafe }
          // Bound data-flow set work as well as graph traversal. Large shared
          // DAGs must not multiply the cost of copying dependency summaries.
          let setWork = arguments.reduce(0) {
            $0 + $1.required.count + $1.written.count
          }
          guard setWork < remainingWork else { return .unsafe }
          remainingWork -= setWork
          let combined: Proof.Kind = arguments.contains { $0.kind == .unsafe }
            ? .unsafe : arguments.contains { $0.kind == .drawing }
              ? .drawing : .constant
          switch function {
          case "Execute", "Execute0":
            proofs[index] = sequence(arguments, kind: combined)
          case "If":
            guard arguments.count == 3, arguments[0].kind == .constant else {
              proofs[index] = .unsafe
              continue
            }
            var result = choice(arguments, kind: combined)
            result.written.formUnion(
              arguments[1].written.intersection(arguments[2].written))
            proofs[index] = result
          case "Switch", "SwitchWithDefault":
            let end = arguments.count - (function == "SwitchWithDefault" ? 1 : 0)
            let fixedSelection = end >= 1 && (end - 1).isMultiple(of: 2)
              && arguments[0].kind == .constant
              && stride(from: 1, to: end, by: 2).allSatisfy {
                arguments[$0].kind == .constant
              }
            proofs[index] = fixedSelection
              ? choice(arguments, kind: combined) : .unsafe
          case "SwitchInteger", "SwitchIntegerWithDefault":
            let minimum = function == "SwitchIntegerWithDefault" ? 2 : 1
            proofs[index] = arguments.count >= minimum
              && arguments[0].kind == .constant
              ? choice(arguments, kind: combined) : .unsafe
          case "And", "Or":
            proofs[index] = combined == .constant
              ? choice(arguments, kind: combined) : .unsafe
          default:
            guard combined == .constant else {
              proofs[index] = .unsafe
              continue
            }
            var result = sequence(arguments,
              kind: drawing.contains(function) ? .drawing : .constant)
            if let access = scratchAccess(node) {
              // RMW operations read the old value before evaluating their
              // operand. An operand's write cannot initialize that old read.
              if access.reads { result.required.insert(access.slot) }
              if access.writes { result.written.insert(access.slot) }
            }
            proofs[index] = result
          }
          continue
        }
        // Charge edges before allocating their traversal frames. Reuse results
        // across archetypes and shared DAGs, but reject gray (cyclic) nodes.
        guard node.arguments.count < remainingWork else { return .unsafe }
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
        // Shifted addresses stay within the named block. All address
        // expressions still require constant proof below. GetPointed is not
        // equivalent: even fixed pointer storage can name a mutable block.
        let readArity = function == "Get" ? 2
          : function == "GetShifted" ? 4 : nil
        let fixedRead = readArity == node.arguments.count
          && first.map { fixedBlocks.contains($0) || $0 == 4000 } == true
        // Identity is checked per emitted draw by the host, including literal
        // IDs. An unselected custom draw must not taint a selected stage draw.
        // Draw arguments must be fixed, with no external/persistent effects.
        let fixedDraw = drawing.contains(function) && !node.arguments.isEmpty
        let fixedResourceQuery = resourceQueries.contains(function)
          && node.arguments.count == 1
        guard pure.contains(function) || branching.contains(function)
          || fixedRead || fixedDraw || fixedResourceQuery
          || scratchAccess(node) != nil
          || function == "Execute" || function == "Execute0" else {
          proofs[index] = .unsafe
          active.remove(index)
          continue
        }
        pending.append((index, true))
        pending.append(contentsOf: node.arguments.map { ($0, false) })
      }
      return proofs[root] ?? .unsafe
    }
    return Set(archetypes.indices.filter { index in
      let a = archetypes[index]
      guard !a.hasInput,
        let update = a.updateParallel else { return false }
      // Compiler-generated callbacks may calculate through local scratch.
      // Results must be fixed with no external/persistent effects, not merely
      // safe stage drawings. Only shouldSpawn consumes their returned value;
      // a fixed false result never introduces a later visual change.
      let lifecycle = [a.shouldSpawn, a.initialize, a.updateSequential,
        a.touch, a.terminate].compactMap { $0 }
      guard lifecycle.allSatisfy({
        let result = proof($0.index)
        return result.kind == .constant && result.required.isEmpty
      }) else {
        return false
      }
      let result = proof(update.index)
      return result.kind != .unsafe && result.required.isEmpty
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
