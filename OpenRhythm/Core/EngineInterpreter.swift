import Foundation

enum EngineInterpreterError: LocalizedError {
  case invalidNode(Int)
  case invalidArguments(String)
  case unsupportedFunction(String)
  case operationLimitExceeded

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
  private var rom = [Double]()
  private var blocks = [Int: [Int: Double]]()
  private var entityBlocks = [Int: [Int: [Int: Double]]]()
  private var entityKey: Int?
  private var entityIndex: Int?

  func loadROM(_ data: Data?) throws {
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
    guard index >= 0 else { return 0 }
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
    guard index >= 0, block != 3000 else { return value }
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
  let memory: EngineMemory

  private let nodes: [EngineDataNode]
  private let host: any EngineRuntimeHost
  private let operationLimit: Int
  private var operationCount = 0
  private var depth = 0

  init(
    nodes: [EngineDataNode],
    memory: EngineMemory = EngineMemory(),
    host: any EngineRuntimeHost = EmptyEngineRuntimeHost(),
    operationLimit: Int = 1_000_000
  ) {
    self.nodes = nodes
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
    return try evaluate(function, arguments: node.arguments)
  }

  private func evaluate(
    _ function: String,
    arguments: [Int]
  ) throws -> Double {
    switch function {
    case "Abs": return try unary(arguments, abs)
    case "Add": return try values(arguments).reduce(0, +)
    case "And":
      var result = 0.0
      for argument in arguments {
        result = try evaluate(argument)
        if result == 0 { return 0 }
      }
      return result
    case "Arctan": return try unary(arguments, atan)
    case "Arctan2": return try binary(arguments, atan2)
    case "Block":
      try require(arguments, count: 1, function: function)
      do {
        return try evaluate(arguments[0])
      } catch let signal as EngineBreak {
        if signal.count <= 1 { return signal.value }
        throw EngineBreak(count: signal.count - 1, value: signal.value)
      }
    case "Break":
      try require(arguments, count: 2, function: function)
      let count = try integer(evaluate(arguments[0]), function: function)
      let value = try evaluate(arguments[1])
      throw EngineBreak(count: count, value: value)
    case "Ceil": return try unary(arguments, ceil)
    case "Clamp":
      try require(arguments, count: 3, function: function)
      let v = try values(arguments)
      return v[0] < v[1] ? v[1] : (v[0] > v[2] ? v[2] : v[0])
    case "Cos": return try unary(arguments, cos)
    case "Divide": return try binary(arguments, /)
    case "Equal": return try comparison(arguments, ==)
    case "EaseInQuad", "EaseOutQuad", "EaseInOutQuad", "EaseOutInQuad",
      "EaseInCubic", "EaseOutCubic":
      let suffix = String(function.dropFirst(4))
      let name = suffix.prefix(1).lowercased() + suffix.dropFirst()
      return try unary(arguments) { EngineEasing.value(name, $0, clamped: false) }
    case "Execute":
      var result = 0.0
      for argument in arguments {
        result = try evaluate(argument)
      }
      return result
    case "Floor": return try unary(arguments, floor)
    case "Get":
      let address = try memoryAddress(arguments, function: function)
      return memory.value(block: address.block, index: address.index)
    case "GetShifted":
      try require(arguments, count: 4, function: function)
      let values = try values(arguments)
      return memory.value(
        block: try integer(values[0], function: function),
        index: try integer(values[1] + values[2] * values[3], function: function)
      )
    case "Greater": return try comparison(arguments, >)
    case "GreaterOr": return try comparison(arguments, >=)
    case "IncrementPost", "DecrementPost", "IncrementPre", "DecrementPre":
      let address = try memoryAddress(arguments, function: function)
      let before = memory.value(block: address.block, index: address.index)
      let after = before + (function.hasPrefix("Increment") ? 1 : -1)
      memory.set(block: address.block, index: address.index, value: after)
      // Sonolus names refer to which value is returned, not C-style operators.
      return function.hasSuffix("Post") ? after : before
    case "If":
      try require(arguments, count: 3, function: function)
      return try evaluate(
        try evaluate(arguments[0]) != 0 ? arguments[1] : arguments[2]
      )
    case "JumpLoop":
      var branch = 0
      while arguments.indices.contains(branch) {
        let result = try evaluate(arguments[branch])
        if branch == arguments.count - 1 { return result }
        branch = try integer(result, function: function)
      }
      return 0
    case "Lerp", "LerpClamped":
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      let fraction = function == "LerpClamped"
        ? min(1, max(0, values[2])) : values[2]
      return values[0] + (values[1] - values[0]) * fraction
    case "Less": return try comparison(arguments, <)
    case "LessOr": return try comparison(arguments, <=)
    case "Log": return try unary(arguments, log)
    case "Max": return try values(arguments).max() ?? 0
    case "Min": return try values(arguments).min() ?? 0
    case "Mod":
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
    case "Multiply": return try values(arguments).reduce(1, *)
    case "Negate": return try unary(arguments, -)
    case "Not": return try unary(arguments) { $0 == 0 ? 1 : 0 }
    case "NotEqual": return try comparison(arguments, !=)
    case "Or":
      for argument in arguments {
        let value = try evaluate(argument)
        if value != 0 { return value }
      }
      return 0
    case "Power": return try binary(arguments, pow)
    case "Remap", "RemapClamped":
      try require(arguments, count: 5, function: function)
      let v = try values(arguments)
      let fraction = (v[4] - v[0]) / (v[1] - v[0])
      let t = function == "RemapClamped" ? min(1, max(0, fraction)) : fraction
      return v[2] + (v[3] - v[2]) * t
    case "Round": return try unary(arguments) { $0.rounded() }
    case "SetShifted":
      try require(arguments, count: 5, function: function)
      let v = try values(arguments)
      return memory.set(block: try integer(v[0], function: function),
        index: try integer(v[1] + v[2] * v[3], function: function), value: v[4])
    case "Set", "SetAdd", "SetMultiply", "SetSubtract", "SetDivide", "SetPower":
      try require(arguments, count: 3, function: function)
      let address = try memoryAddress(
        Array(arguments.prefix(2)),
        function: function
      )
      let current = memory.value(block: address.block, index: address.index)
      let operand = try evaluate(arguments[2])
      let result = switch function {
      case "SetAdd": current + operand
      case "SetMultiply": current * operand
      case "SetSubtract": current - operand
      case "SetDivide": current / operand
      case "SetPower": pow(current, operand)
      default: operand
      }
      return memory.set(
        block: address.block,
        index: address.index,
        value: result
      )
    case "Sin": return try unary(arguments, sin)
    case "Subtract":
      guard let first = arguments.first else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      var result = try evaluate(first)
      for argument in arguments.dropFirst() {
        result -= try evaluate(argument)
      }
      return result
    case "Switch", "SwitchWithDefault":
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
    case "SwitchInteger", "SwitchIntegerWithDefault":
      return try switchInteger(
        arguments,
        hasDefault: function == "SwitchIntegerWithDefault",
        function: function
      )
    case "Trunc": return try unary(arguments, trunc)
    case "Unlerp", "UnlerpClamped":
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      let fraction = (values[2] - values[0]) / (values[1] - values[0])
      return function == "UnlerpClamped" ? min(1, max(0, fraction)) : fraction
    case "While":
      try require(arguments, count: 2, function: function)
      var result = 0.0
      while try evaluate(arguments[0]) != 0 {
        result = try evaluate(arguments[1])
      }
      return result
    default:
      return try host.call(
        function: function,
        arguments: values(arguments)
      )
    }
  }

  private func values(_ arguments: [Int]) throws -> [Double] {
    try arguments.map(evaluate)
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

    let discriminant = try integer(evaluate(arguments[0]), function: function)
    let branchCount = arguments.count - (hasDefault ? 2 : 1)
    if discriminant >= 0, discriminant < branchCount {
      return try evaluate(arguments[discriminant + 1])
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
