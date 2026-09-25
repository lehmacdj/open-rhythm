import Foundation

enum EngineInterpreterError: LocalizedError {
  case invalidNode(Int)
  case invalidArguments(String)
  case unsupportedFunction(String)
  case operationLimitExceeded
  case invalidMemoryAccess(block: Int, callback: String, write: Bool)
  case invalidFunctionCallback(function: String, callback: String)

  var errorDescription: String? {
    switch self {
    case .invalidNode(let index):
      "The engine referenced invalid node \(index)."
    case .invalidArguments(let function):
      "The engine supplied invalid arguments to \(function)."
    case .unsupportedFunction(let function):
      "The engine function \(function) is not implemented."
    case .operationLimitExceeded:
      "The engine exceeded the operation limit for one callback."
    case .invalidMemoryAccess(let block, let callback, let write):
      "The engine cannot \(write ? "write" : "read") memory block \(block) "
        + "during \(callback)."
    case .invalidFunctionCallback(let function, let callback):
      "The engine cannot call \(function) during \(callback)."
    }
  }
}

protocol EngineRuntimeHost {
  func call(function: String, arguments: [Double]) throws -> Double
}

struct EmptyEngineRuntimeHost: EngineRuntimeHost {
  func call(function: String, arguments: [Double]) throws -> Double {
    throw EngineInterpreterError.unsupportedFunction(function)
  }
}

final class EngineMemory {
  enum Callback: String, CaseIterable {
    case preprocess, spawnOrder, shouldSpawn, initialize
    case updateSequential, touch, updateParallel, terminate
  }

  // Nil is reserved for host bookkeeping and standalone interpreter tests.
  // Engine callbacks must always establish a context before evaluation.
  var callback: Callback?
  private var rom = [Double]()
  private var blocks = [Int: [Int: Double]]()
  private var entityBlocks = [Int: [Int: [Int: Double]]]()
  private var entityKey: Int?
  private var entityIndex: Int?
  // Indexed by public block ID: ~80 KB, shared by preparation snapshots.
  // Avoid another hash lookup in every interpreted memory read/write.
  private var lengths: [Int]?

  /// Install the play-mode layout after loading ROM and before preprocessing.
  /// Standalone memory tests can omit a layout; production runtimes cannot.
  func configurePlayBlocks(entityCount: Int, optionCount: Int,
    bucketCount: Int, archetypeCount: Int) throws {
    guard [entityCount, optionCount, bucketCount, archetypeCount].allSatisfy({
      $0 >= 0 && $0 <= Int.max / 32
    }) else { throw EngineInterpreterError.invalidArguments("memory layout") }
    let declared = [
      1000: 9, 1001: 5, 1002: 0, 1003: 16, 1004: 16, 1005: 8,
      1006: 80, 1007: 10, 2000: 4096, 2001: 4096,
      2002: optionCount, 2003: bucketCount * 6, 2004: 12, 2005: 8,
      3000: rom.count, 4000: 64, 4001: 32, 4002: 32, 4003: 3,
      4004: 1, 4005: 5, 4006: 1, 4007: 4,
      4101: entityCount * 32, 4102: entityCount * 32,
      4103: entityCount * 3, 4106: entityCount, 4107: entityCount * 4,
      5000: archetypeCount * 4, 5001: archetypeCount, 10000: 4096
    ]
    var table = [Int](repeating: 0, count: 10001)
    for (block, count) in declared { table[block] = count }
    lengths = table
  }

  func setTouchCount(_ count: Int) throws {
    guard count >= 0, count <= Int.max / 15 else {
      throw EngineInterpreterError.invalidArguments("touch count")
    }
    if lengths != nil { lengths?[1002] = count * 15 }
    set(block: 1001, index: 3, value: Double(count))
  }

  private func contains(block: Int, index: Int) -> Bool {
    guard index >= 0 else { return false }
    guard let lengths else { return true }
    return lengths.indices.contains(block) && index < lengths[block]
  }

  private func validate(block: Int, write: Bool) throws -> Bool {
    guard let callback else { return true }
    let writable: Bool
    switch block {
    case 1000, 1006, 1007, 2001, 2003...2005, 4001, 4006, 4007,
      4101, 4106, 4107, 5000, 5001:
      writable = callback == .preprocess
    case 1003...1005, 2000, 4002, 4102:
      writable = callback == .preprocess || callback == .updateSequential
        || callback == .touch
    case 4000, 4004, 4005, 10000:
      writable = true
    case 1001, 1002, 2002, 3000, 4003, 4103:
      writable = false
    default:
      // Get explicitly returns zero for a nonexistent block. Keep invalid
      // writes separate from that defined read behavior.
      if !write { return false }
      throw EngineInterpreterError.invalidMemoryAccess(
        block: block, callback: callback.rawValue, write: write)
    }
    // Spawn explicitly excludes these four level-backed blocks. Do not
    // infer additional restrictions from a spawned entity's lack of input.
    let unavailable = entityIndex == nil
      && ((4001...4003).contains(block) || block == 4005)
    if unavailable && !write { return false }
    guard !unavailable, !write || writable else {
      throw EngineInterpreterError.invalidMemoryAccess(
        block: block, callback: callback.rawValue, write: write)
    }
    return true
  }

  func read(block: Int, index: Int) throws -> Double {
    guard try validate(block: block, write: false) else { return 0 }
    return value(block: block, index: index)
  }

  @discardableResult
  func write(block: Int, index: Int, value: Double) throws -> Double {
    _ = try validate(block: block, write: true)
    return set(block: block, index: index, value: value)
  }

  /// A copy-on-write snapshot of preparation, including engine-owned data.
  /// The returned closure belongs to the runtime, not to this memory object.
  func makeRestorePoint() -> () -> Void {
    { [rom, blocks, entityBlocks, entityKey, entityIndex, lengths] in
      self.rom = rom
      self.blocks = blocks
      self.entityBlocks = entityBlocks
      self.entityKey = entityKey
      self.entityIndex = entityIndex
      self.lengths = lengths
    }
  }

  func loadROM(_ data: Data?) throws {
    defer { if lengths != nil { lengths?[3000] = rom.count } }
    guard let data else { rom = []; return }
    let decoded = try data.starts(with: [0x1f, 0x8b])
      ? GzipDecoder.decompress(data, maximumSize: 16 * 1024 * 1024) : data
    guard decoded.count.isMultiple(of: 4), decoded.count <= 16 * 1024 * 1024 else {
      throw EngineInterpreterError.invalidArguments("engine ROM size")
    }
    rom = decoded.withUnsafeBytes { bytes in
      stride(from: 0, to: bytes.count, by: 4).map { offset in
        let bits = UInt32(littleEndian:
          bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        return Double(Float(bitPattern: bits))
      }
    }
  }

  func selectEntity(key: Int, index: Int?) {
    entityKey = key
    entityIndex = index
    blocks[10000] = nil
  }

  func removeEntity(key: Int) {
    entityBlocks[key] = nil
  }

  private func arrayAddress(block: Int, index: Int) -> (Int, Int)? {
    guard let entityIndex else { return nil }
    let size: Int
    switch block {
    case 4001, 4002: size = 32
    case 4003: size = 3
    case 4006: size = 1
    case 4007: size = 4
    default: return nil
    }
    guard index < size else { return nil }
    return (block + 100, entityIndex * size + index)
  }

  func value(block: Int, index: Int) -> Double {
    guard contains(block: block, index: index) else { return 0 }
    if block == 3000 { return rom.indices.contains(index) ? rom[index] : 0 }
    if let (array, offset) = arrayAddress(block: block, index: index) {
      return blocks[array]?[offset] ?? 0
    }
    if (4000...4007).contains(block), let entityKey {
      return entityBlocks[entityKey]?[block]?[index] ?? 0
    }
    return blocks[block]?[index] ?? 0
  }

  @discardableResult
  func set(block: Int, index: Int, value: Double) -> Double {
    guard contains(block: block, index: index), block != 3000 else { return value }
    if let (array, offset) = arrayAddress(block: block, index: index) {
      blocks[array, default: [:]][offset] = value
      return value
    }
    if (4000...4007).contains(block), let entityKey {
      entityBlocks[entityKey, default: [:]][block, default: [:]][index] = value
      return value
    }
    blocks[block, default: [:]][index] = value
    return value
  }
}

private struct EngineBreak: Error {
  let count: Int
  let value: Double
}

final class EngineInterpreter {
  // Decode dispatch once; node evaluation is the dominant frame-time cost.
  private enum Operation: String, CaseIterable {
    case `abs` = "Abs"
    case `add` = "Add"
    case `and` = "And"
    case `arctan` = "Arctan"
    case `arctan2` = "Arctan2"
    case arccos = "Arccos", arcsin = "Arcsin", cosh = "Cosh"
    case sinh = "Sinh", tan = "Tan", tanh = "Tanh"
    case degree = "Degree", radian = "Radian", frac = "Frac", sign = "Sign"
    case rem = "Rem", random = "Random", randomInteger = "RandomInteger"
    case copy = "Copy", doWhile = "DoWhile"
    case extendedMemory, easing
    case `block` = "Block"
    case `break` = "Break"
    case `ceil` = "Ceil"
    case `clamp` = "Clamp"
    case `cos` = "Cos"
    case `divide` = "Divide"
    case `equal` = "Equal"
    case `easeInQuad` = "EaseInQuad"
    case `easeOutQuad` = "EaseOutQuad"
    case `easeInOutQuad` = "EaseInOutQuad"
    case `easeOutInQuad` = "EaseOutInQuad"
    case `easeInCubic` = "EaseInCubic"
    case `easeOutCubic` = "EaseOutCubic"
    case `execute` = "Execute"
    case execute0 = "Execute0"
    case `floor` = "Floor"
    case `get` = "Get"
    case `getShifted` = "GetShifted"
    case `greater` = "Greater"
    case `greaterOr` = "GreaterOr"
    case `incrementPost` = "IncrementPost"
    case `decrementPost` = "DecrementPost"
    case `incrementPre` = "IncrementPre"
    case `decrementPre` = "DecrementPre"
    case `if` = "If"
    case `jumpLoop` = "JumpLoop"
    case `lerp` = "Lerp"
    case `lerpClamped` = "LerpClamped"
    case `less` = "Less"
    case `lessOr` = "LessOr"
    case `log` = "Log"
    case `max` = "Max"
    case `min` = "Min"
    case `mod` = "Mod"
    case `multiply` = "Multiply"
    case `negate` = "Negate"
    case `not` = "Not"
    case `notEqual` = "NotEqual"
    case `or` = "Or"
    case `power` = "Power"
    case `remap` = "Remap"
    case `remapClamped` = "RemapClamped"
    case `round` = "Round"
    case `setShifted` = "SetShifted"
    case `set` = "Set"
    case `setAdd` = "SetAdd"
    case `setMultiply` = "SetMultiply"
    case `setSubtract` = "SetSubtract"
    case `setDivide` = "SetDivide"
    case `setPower` = "SetPower"
    case `sin` = "Sin"
    case `subtract` = "Subtract"
    case `switch` = "Switch"
    case `switchWithDefault` = "SwitchWithDefault"
    case `switchInteger` = "SwitchInteger"
    case `switchIntegerWithDefault` = "SwitchIntegerWithDefault"
    case `trunc` = "Trunc"
    case `unlerp` = "Unlerp"
    case `unlerpClamped` = "UnlerpClamped"
    case `while` = "While"
    case host
  }
  let memory: EngineMemory

  static let memoryFunctions = Set(
    ["Get", "Set", "SetAdd", "SetSubtract", "SetMultiply", "SetDivide",
      "SetPower", "SetMod", "SetRem", "IncrementPre", "IncrementPost",
      "DecrementPre", "DecrementPost"].flatMap { base in
      [base, base + "Pointed", base + "Shifted"]
    })
  static let easingFunctions = Set(
    ["In", "Out", "InOut", "OutIn"].flatMap { mode in
      ["Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Back",
        "Elastic"].map { "Ease" + mode + $0 }
    })
  static var supportedFunctions: Set<String> {
    Set(Operation.allCases.filter {
      $0 != .host && $0 != .extendedMemory && $0 != .easing
    }.map(\.rawValue)).union(memoryFunctions).union(easingFunctions)
  }

  private let nodes: [EngineDataNode]
  private let operations: [Operation]
  private struct LiteralAddress {
    let block: Int
    let index: Int
  }
  private let literalAddresses: [LiteralAddress?]
  private let host: any EngineRuntimeHost
  private let operationLimit: Int
  private var operationCount = 0
  private var depth = 0

  init(
    nodes: [EngineDataNode],
    memory: EngineMemory = EngineMemory(),
    host: any EngineRuntimeHost = EmptyEngineRuntimeHost(),
    operationLimit: Int = 1_000_000,
    optimizeLiteralAddresses: Bool = true
  ) {
    self.nodes = nodes
    operations = nodes.map {
      guard let name = $0.function else { return .host }
      return Operation(rawValue: name)
        ?? (Self.memoryFunctions.contains(name) ? .extendedMemory
          : Self.easingFunctions.contains(name) ? .easing : .host)
    }
    literalAddresses = nodes.map { node in
      guard optimizeLiteralAddresses, let function = node.function else { return nil }
      let count: Int
      switch function {
      case "Get", "IncrementPre", "IncrementPost", "DecrementPre", "DecrementPost":
        count = 2
      case "Set", "SetAdd", "SetSubtract", "SetMultiply", "SetDivide", "SetPower":
        count = 3
      default: return nil
      }
      guard node.arguments.count == count,
        nodes.indices.contains(node.arguments[0]),
        nodes.indices.contains(node.arguments[1]),
        let block = nodes[node.arguments[0]].value,
        let index = nodes[node.arguments[1]].value,
        let block = Int(exactly: block.rounded(.towardZero)),
        let index = Int(exactly: index.rounded(.towardZero)) else { return nil }
      return LiteralAddress(block: block, index: index)
    }
    self.memory = memory
    self.host = host
    self.operationLimit = operationLimit
  }

  func execute(nodeAt index: Int) throws -> Double {
    operationCount = 0
    do {
      return try evaluate(index)
    } catch let signal as EngineBreak {
      throw EngineInterpreterError.invalidArguments(
        "Break(count: \(signal.count))"
      )
    }
  }

  private func evaluate(_ index: Int) throws -> Double {
    operationCount += 1
    depth += 1
    defer { depth -= 1 }
    guard operationCount <= operationLimit, depth <= 256 else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    guard nodes.indices.contains(index) else {
      throw EngineInterpreterError.invalidNode(index)
    }

    let node = nodes[index]
    if let value = node.value {
      return value
    }
    guard let function = node.function else {
      throw EngineInterpreterError.invalidNode(index)
    }
    if let address = literalAddresses[index] {
      return try evaluateLiteralAddress(address, operation: operations[index],
        arguments: node.arguments)
    }
    return try evaluate(function, operation: operations[index],
      arguments: node.arguments)
  }

  @inline(never)
  private func evaluateLiteralAddress(_ address: LiteralAddress,
    operation: Operation, arguments: [Int]) throws -> Double {
    // Literal operands have no side effects, but still consume their original
    // operation/depth budget. Never cache the memory value or entity binding.
    guard depth < 256, operationLimit - operationCount >= 2 else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    operationCount += 2
    let before = try memory.read(block: address.block, index: address.index)
    let result: Double
    switch operation {
    case .get: return before
    case .incrementPre, .incrementPost, .decrementPre, .decrementPost:
      let increment = operation == .incrementPre || operation == .incrementPost
      result = before + (increment ? 1 : -1)
      try memory.write(block: address.block, index: address.index, value: result)
      let post = operation == .incrementPost || operation == .decrementPost
      return post ? result : before
    default:
      // Read-modify-write reads before evaluating the operand, which may
      // itself mutate the same address. Keep the unoptimized evaluation order.
      let operand = try evaluate(arguments[2])
      switch operation {
      case .setAdd: result = before + operand
      case .setSubtract: result = before - operand
      case .setMultiply: result = before * operand
      case .setDivide: result = before / operand
      case .setPower: result = pow(before, operand)
      default: result = operand
      }
    }
    return try memory.write(block: address.block, index: address.index, value: result)
  }

  // Keep recursive dispatch frames small enough for iOS's main-thread stack.
  // One monolithic switch overflowed it before the 256-node guard could fire.
  private func evaluate(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`abs`, .`arctan`, .arccos, .arcsin, .cosh, .sinh, .tan, .tanh,
      .degree, .radian, .frac, .sign, .`ceil`, .`cos`, .`floor`, .`log`,
      .`negate`, .`not`, .`round`, .`sin`, .`trunc`:
      return try evaluateUnaryMath(function, operation: operation,
        arguments: arguments)
    case .`arctan2`, .`clamp`, .`equal`, .`greater`, .`greaterOr`, .`lerp`,
      .`lerpClamped`, .`less`, .`lessOr`, .`notEqual`, .`remap`,
      .`remapClamped`, .`unlerp`, .`unlerpClamped`:
      return try evaluateBinaryMath(function, operation: operation,
        arguments: arguments)
    case .`add`, .`divide`, .`easeInQuad`, .`easeOutQuad`, .`easeInOutQuad`,
      .`easeOutInQuad`, .`easeInCubic`, .`easeOutCubic`, .easing, .`max`,
      .`min`, .`mod`, .`multiply`, .`power`, .rem, .`subtract`:
      return try evaluateArithmetic(function, operation: operation,
        arguments: arguments)
    case .random, .randomInteger:
      return try evaluateRandom(function, operation: operation,
        arguments: arguments)
    case .copy:
      return try evaluateCopy(function, operation: operation,
        arguments: arguments)
    case .extendedMemory:
      return try extendedMemory(function, arguments)
    case .`get`, .`getShifted`, .`incrementPost`,
      .`decrementPost`, .`incrementPre`, .`decrementPre`:
      return try evaluateMemoryRead(function, operation: operation,
        arguments: arguments)
    case .`setShifted`, .`set`, .`setAdd`, .`setMultiply`, .`setSubtract`,
      .`setDivide`, .`setPower`:
      return try evaluateMemoryWrite(function, operation: operation,
        arguments: arguments)
    case .`and`, .`execute`, .execute0, .`or`:
      return try evaluateLazySequence(function, operation: operation,
        arguments: arguments)
    case .doWhile, .`block`, .`break`, .`while`:
      return try evaluateLoopAndBlock(function, operation: operation,
        arguments: arguments)
    case .`if`, .`jumpLoop`, .`switch`, .`switchWithDefault`, .`switchInteger`,
      .`switchIntegerWithDefault`:
      return try evaluateBranch(function, operation: operation,
        arguments: arguments)
    default:
      return try host.call(
        function: function,
        arguments: values(arguments)
      )
    }
  }

  @inline(never)
  private func evaluateUnaryMath(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`abs`: return try unary(arguments, abs)
    case .`arctan`: return try unary(arguments, atan)
    case .arccos: return try unary(arguments, acos)
    case .arcsin: return try unary(arguments, asin)
    case .cosh: return try unary(arguments, cosh)
    case .sinh: return try unary(arguments, sinh)
    case .tan: return try unary(arguments, tan)
    case .tanh: return try unary(arguments, tanh)
    case .degree: return try unary(arguments) { $0 * 180 / .pi }
    case .radian: return try unary(arguments) { $0 * .pi / 180 }
    case .frac: return try unary(arguments) { $0 - floor($0) }
    case .sign: return try unary(arguments) { $0 == 0 ? 0 : ($0 < 0 ? -1 : 1) }
    case .`ceil`: return try unary(arguments, ceil)
    case .`cos`: return try unary(arguments, cos)
    case .`floor`: return try unary(arguments, floor)
    case .`log`: return try unary(arguments, log)
    case .`negate`: return try unary(arguments, -)
    case .`not`: return try unary(arguments) { $0 == 0 ? 1 : 0 }
    case .`round`: return try unary(arguments) { $0.rounded() }
    case .`sin`: return try unary(arguments, sin)
    case .`trunc`: return try unary(arguments, trunc)
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateBinaryMath(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`arctan2`: return try binary(arguments, atan2)
    case .`clamp`:
      try require(arguments, count: 3, function: function)
      let v = try values(arguments)
      return v[0] < v[1] ? v[1] : (v[0] > v[2] ? v[2] : v[0])
    case .`equal`: return try comparison(arguments, ==)
    case .`greater`: return try comparison(arguments, >)
    case .`greaterOr`: return try comparison(arguments, >=)
    case .`lerp`, .`lerpClamped`:
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      let fraction = function == "LerpClamped"
        ? min(1, max(0, values[2])) : values[2]
      return values[0] + (values[1] - values[0]) * fraction
    case .`less`: return try comparison(arguments, <)
    case .`lessOr`: return try comparison(arguments, <=)
    case .`notEqual`: return try comparison(arguments, !=)
    case .`remap`, .`remapClamped`:
      try require(arguments, count: 5, function: function)
      let v = try values(arguments)
      let fraction = (v[4] - v[0]) / (v[1] - v[0])
      let t = function == "RemapClamped" ? min(1, max(0, fraction)) : fraction
      return v[2] + (v[3] - v[2]) * t
    case .`unlerp`, .`unlerpClamped`:
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      let fraction = (values[2] - values[0]) / (values[1] - values[0])
      return function == "UnlerpClamped" ? min(1, max(0, fraction)) : fraction
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateArithmetic(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`add`:
      var result = 0.0
      for argument in arguments { result += try evaluate(argument) }
      return result
    case .`divide`: return try fold(arguments, function: function, /)
    case .`easeInQuad`, .`easeOutQuad`, .`easeInOutQuad`, .`easeOutInQuad`,
      .`easeInCubic`, .`easeOutCubic`, .easing:
      let suffix = String(function.dropFirst(4))
      let name = suffix.prefix(1).lowercased() + suffix.dropFirst()
      return try unary(arguments) { EngineEasing.value(name, $0, clamped: false) }
    case .`max`: return try values(arguments).max() ?? 0
    case .`min`: return try values(arguments).min() ?? 0
    case .`mod`:
      guard let first = arguments.first else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      var result = try evaluate(first)
      for argument in arguments.dropFirst() {
        let divisor = try evaluate(argument)
        let remainder = result.truncatingRemainder(dividingBy: divisor)
        result = remainder != 0 && (remainder < 0) != (divisor < 0)
          ? remainder + divisor : remainder
      }
      return result
    case .`multiply`:
      var result = 1.0
      for argument in arguments { result *= try evaluate(argument) }
      return result
    case .`power`: return try fold(arguments, function: function, pow)
    case .rem:
      return try fold(arguments, function: function) { $0.truncatingRemainder(dividingBy: $1) }
    case .`subtract`:
      guard let first = arguments.first else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      var result = try evaluate(first)
      for argument in arguments.dropFirst() {
        result -= try evaluate(argument)
      }
      return result
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateRandom(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .random, .randomInteger:
      try require(arguments, count: 2, function: function)
      let a = try values(arguments)
      guard a.allSatisfy(\.isFinite), a[0] <= a[1] else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      if operation == .random {
        let fraction = Double.random(in: 0...1)
        return fraction * a[1] + (1 - fraction) * a[0]
      }
      let lower = try integer(ceil(a[0]), function: function)
      let upper = try integer(ceil(a[1]), function: function)
      guard lower < upper else { throw EngineInterpreterError.invalidArguments(function) }
      return Double(Int.random(in: lower..<upper))
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateCopy(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .copy:
      try require(arguments, count: 5, function: function)
      let a = try values(arguments).map { try integer($0, function: function) }
      let count = a[4]
      guard count >= 0, count <= operationLimit - operationCount,
        a[1] >= 0, a[3] >= 0, a[1] <= Int.max - count,
        a[3] <= Int.max - count else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      operationCount += count
      let copied = try (0..<count).map {
        try memory.read(block: a[0], index: a[1] + $0)
      }
      for (offset, value) in copied.enumerated() {
        try memory.write(block: a[2], index: a[3] + offset, value: value)
      }
      return 0
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateMemoryRead(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`get`:
      try require(arguments, count: 2, function: function)
      let block = try evaluate(arguments[0])
      let index = try evaluate(arguments[1])
      return try readMemory(block: block, index: index)
    case .`getShifted`:
      try require(arguments, count: 4, function: function)
      let values = try values(arguments)
      return try readMemory(block: values[0],
        index: values[1] + values[2] * values[3])
    case .`incrementPost`, .`decrementPost`, .`incrementPre`, .`decrementPre`:
      let address = try memoryAddress(arguments, function: function)
      let before = try memory.read(block: address.block, index: address.index)
      let after = before + (function.hasPrefix("Increment") ? 1 : -1)
      try memory.write(block: address.block, index: address.index, value: after)
      // Sonolus names refer to which value is returned, not C-style operators.
      return function.hasSuffix("Post") ? after : before
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateMemoryWrite(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`setShifted`:
      try require(arguments, count: 5, function: function)
      let v = try values(arguments)
      return try memory.write(block: try integer(v[0], function: function),
        index: try integer(v[1] + v[2] * v[3], function: function), value: v[4])
    case .`set`, .`setAdd`, .`setMultiply`, .`setSubtract`, .`setDivide`, .`setPower`:
      try require(arguments, count: 3, function: function)
      let block = try integer(evaluate(arguments[0]), function: function)
      let index = try integer(evaluate(arguments[1]), function: function)
      let address = (block: block, index: index)
      let current = try memory.read(block: address.block, index: address.index)
      let operand = try evaluate(arguments[2])
      let result = switch function {
      case "SetAdd": current + operand
      case "SetMultiply": current * operand
      case "SetSubtract": current - operand
      case "SetDivide": current / operand
      case "SetPower": pow(current, operand)
      default: operand
      }
      return try memory.write(
        block: address.block,
        index: address.index,
        value: result
      )
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateLazySequence(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`and`:
      var result = 0.0
      for argument in arguments {
        result = try evaluate(argument)
        if result == 0 { return 0 }
      }
      return result
    case .`execute`:
      var result = 0.0
      for argument in arguments {
        result = try evaluate(argument)
      }
      return result
    case .execute0:
      for argument in arguments { _ = try evaluate(argument) }
      return 0
    case .`or`:
      for argument in arguments {
        let value = try evaluate(argument)
        if value != 0 { return value }
      }
      return 0
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateLoopAndBlock(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .doWhile:
      try require(arguments, count: 2, function: function)
      repeat { _ = try evaluate(arguments[0]) } while try evaluate(arguments[1]) != 0
      return 0
    case .`block`:
      try require(arguments, count: 1, function: function)
      do {
        return try evaluate(arguments[0])
      } catch let signal as EngineBreak {
        if signal.count <= 1 { return signal.value }
        throw EngineBreak(count: signal.count - 1, value: signal.value)
      }
    case .`break`:
      try require(arguments, count: 2, function: function)
      let count = try integer(evaluate(arguments[0]), function: function)
      let value = try evaluate(arguments[1])
      throw EngineBreak(count: count, value: value)
    case .`while`:
      try require(arguments, count: 2, function: function)
      while try evaluate(arguments[0]) != 0 {
        _ = try evaluate(arguments[1])
      }
      return 0
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  @inline(never)
  private func evaluateBranch(
    _ function: String, operation: Operation,
    arguments: [Int]
  ) throws -> Double {
    switch operation {
    case .`if`:
      try require(arguments, count: 3, function: function)
      return try evaluate(
        try evaluate(arguments[0]) != 0 ? arguments[1] : arguments[2]
      )
    case .`jumpLoop`:
      var branch = 0
      while arguments.indices.contains(branch) {
        let result = try evaluate(arguments[branch])
        if branch == arguments.count - 1 { return result }
        guard let next = Int(exactly: result), arguments.indices.contains(next)
        else { return 0 }
        branch = next
      }
      return 0
    case .`switch`, .`switchWithDefault`:
      let hasDefault = function == "SwitchWithDefault"
      let end = arguments.count - (hasDefault ? 1 : 0)
      guard end >= 1, (end - 1).isMultiple(of: 2) else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      let discriminant = try evaluate(arguments[0])
      for index in stride(from: 1, to: end, by: 2) {
        if try evaluate(arguments[index]) == discriminant {
          return try evaluate(arguments[index + 1])
        }
      }
      return hasDefault ? try evaluate(arguments[end]) : 0
    case .`switchInteger`, .`switchIntegerWithDefault`:
      return try switchInteger(
        arguments,
        hasDefault: function == "SwitchIntegerWithDefault",
        function: function
      )
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }
  private func values(_ arguments: [Int]) throws -> [Double] {
    var result = [Double]()
    result.reserveCapacity(arguments.count)
    for argument in arguments { result.append(try evaluate(argument)) }
    return result
  }

  private func fold(_ arguments: [Int], function: String,
    _ operation: (Double, Double) -> Double) throws -> Double {
    guard let first = arguments.first else {
      throw EngineInterpreterError.invalidArguments(function)
    }
    var result = try evaluate(first)
    for argument in arguments.dropFirst() { result = operation(result, try evaluate(argument)) }
    return result
  }

  private func extendedMemory(_ function: String, _ arguments: [Int]) throws -> Double {
    let suffix = function.hasSuffix("Pointed") ? "Pointed"
      : function.hasSuffix("Shifted") ? "Shifted" : ""
    let base = String(function.dropLast(suffix.count))
    let addressCount = suffix == "Pointed" ? 3 : suffix == "Shifted" ? 4 : 2
    let writes = base.hasPrefix("Set")
    try require(arguments, count: addressCount + (writes ? 1 : 0), function: function)
    // Pointed addressing dereferences the pointer before evaluating offset;
    // offset expressions may themselves mutate the pointer's storage.
    let a = try values(Array(arguments.prefix(suffix == "Pointed" ? 2 : addressCount)))
    if base == "Get", suffix == "Pointed" {
      let targetBlock = try readMemory(block: a[0], index: a[1])
      let pointerIndex = try readMemory(block: a[0], index: a[1] + 1)
      let offset = try evaluate(arguments[2])
      return try readMemory(block: targetBlock, index: pointerIndex + offset)
    }
    var block = try integer(a[0], function: function)
    var index = try integer(a[1], function: function)
    if suffix == "Shifted" {
      index = try integer(a[1] + a[2] * a[3], function: function)
    } else if suffix == "Pointed" {
      guard index < Int.max else { throw EngineInterpreterError.invalidArguments(function) }
      let targetBlock = try memory.read(block: block, index: index)
      let pointerIndex = try memory.read(block: block, index: index + 1)
      let targetIndex = pointerIndex + (try evaluate(arguments[2]))
      block = try integer(targetBlock, function: function)
      index = try integer(targetIndex, function: function)
    }
    let old = try memory.read(block: block, index: index)
    if base == "Get" { return old }
    if !writes {
      let value = old + (base.hasPrefix("Increment") ? 1 : -1)
      try memory.write(block: block, index: index, value: value)
      return base.hasSuffix("Post") ? value : old
    }
    let operand = try evaluate(arguments[addressCount])
    let value: Double
    switch base {
    case "Set": value = operand
    case "SetAdd": value = old + operand
    case "SetSubtract": value = old - operand
    case "SetMultiply": value = old * operand
    case "SetDivide": value = old / operand
    case "SetPower": value = pow(old, operand)
    case "SetRem": value = old.truncatingRemainder(dividingBy: operand)
    case "SetMod":
      let remainder = old.truncatingRemainder(dividingBy: operand)
      value = remainder != 0 && (remainder < 0) != (operand < 0)
        ? remainder + operand : remainder
    default: throw EngineInterpreterError.unsupportedFunction(function)
    }
    return try memory.write(block: block, index: index, value: value)
  }

  private func readMemory(block: Double, index: Double) throws -> Double {
    // Get has a defined zero result outside memory, even when an address
    // cannot be represented by a machine Int. Evaluate operands before this
    // check so their side effects are not lost.
    guard let block = Int(exactly: block.rounded(.towardZero)),
      let index = Int(exactly: index.rounded(.towardZero)) else { return 0 }
    return try memory.read(block: block, index: index)
  }

  private func unary(
    _ arguments: [Int],
    _ operation: (Double) -> Double
  ) throws -> Double {
    try require(arguments, count: 1, function: "unary function")
    return operation(try evaluate(arguments[0]))
  }

  private func binary(
    _ arguments: [Int],
    _ operation: (Double, Double) -> Double
  ) throws -> Double {
    try require(arguments, count: 2, function: "binary function")
    return operation(try evaluate(arguments[0]), try evaluate(arguments[1]))
  }

  private func comparison(
    _ arguments: [Int],
    _ operation: (Double, Double) -> Bool
  ) throws -> Double {
    try binary(arguments) { operation($0, $1) ? 1 : 0 }
  }

  private func memoryAddress(
    _ arguments: [Int],
    function: String
  ) throws -> (block: Int, index: Int) {
    try require(arguments, count: 2, function: function)
    return (
      block: try integer(evaluate(arguments[0]), function: function),
      index: try integer(evaluate(arguments[1]), function: function)
    )
  }

  private func switchInteger(
    _ arguments: [Int],
    hasDefault: Bool,
    function: String
  ) throws -> Double {
    let minimumCount = hasDefault ? 2 : 1
    guard arguments.count >= minimumCount else {
      throw EngineInterpreterError.invalidArguments(function)
    }

    let discriminant = try evaluate(arguments[0])
    let branchCount = arguments.count - (hasDefault ? 2 : 1)
    // Branch labels are exact integers, not truncated addresses. Fractional
    // and nonfinite results match no label and must not execute its effects.
    if let branch = Int(exactly: discriminant), branch >= 0, branch < branchCount {
      return try evaluate(arguments[branch + 1])
    }
    return hasDefault ? try evaluate(arguments.last!) : 0
  }

  private func require(
    _ arguments: [Int],
    count: Int,
    function: String
  ) throws {
    guard arguments.count == count else {
      throw EngineInterpreterError.invalidArguments(function)
    }
  }

  private func integer(_ value: Double, function: String) throws -> Int {
    guard let result = Int(exactly: value.rounded(.towardZero)) else {
      throw EngineInterpreterError.invalidArguments(function)
    }
    return result
  }
}
