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
  private var blocks = [Int: [Int: Double]]()

  func value(block: Int, index: Int) -> Double {
    guard index >= 0 else { return 0 }
    return blocks[block]?[index] ?? 0
  }

  @discardableResult
  func set(block: Int, index: Int, value: Double) -> Double {
    guard index >= 0 else { return value }
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
    guard operationCount <= operationLimit else {
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
      let count = Int(try evaluate(arguments[0]))
      let value = try evaluate(arguments[1])
      throw EngineBreak(count: count, value: value)
    case "Cos": return try unary(arguments, cos)
    case "Divide": return try binary(arguments, /)
    case "Equal": return try comparison(arguments, ==)
    case "Execute":
      var result = 0.0
      for argument in arguments {
        result = try evaluate(argument)
      }
      return result
    case "Get":
      let address = try memoryAddress(arguments, function: function)
      return memory.value(block: address.block, index: address.index)
    case "GetShifted":
      try require(arguments, count: 4, function: function)
      let values = try values(arguments)
      return memory.value(
        block: Int(values[0]),
        index: Int(values[1] + values[2] * values[3])
      )
    case "Greater": return try comparison(arguments, >)
    case "GreaterOr": return try comparison(arguments, >=)
    case "If":
      try require(arguments, count: 3, function: function)
      return try evaluate(
        try evaluate(arguments[0]) != 0 ? arguments[1] : arguments[2]
      )
    case "Lerp":
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      return values[0] + (values[1] - values[0]) * values[2]
    case "Less": return try comparison(arguments, <)
    case "LessOr": return try comparison(arguments, <=)
    case "Max": return try values(arguments).max() ?? 0
    case "Min": return try values(arguments).min() ?? 0
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
    case "Set", "SetAdd", "SetMultiply":
      try require(arguments, count: 3, function: function)
      let address = try memoryAddress(
        Array(arguments.prefix(2)),
        function: function
      )
      let operand = try evaluate(arguments[2])
      let current = memory.value(block: address.block, index: address.index)
      let result = switch function {
      case "SetAdd": current + operand
      case "SetMultiply": current * operand
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
    case "SwitchInteger", "SwitchIntegerWithDefault":
      return try switchInteger(
        arguments,
        hasDefault: function == "SwitchIntegerWithDefault",
        function: function
      )
    case "Unlerp":
      try require(arguments, count: 3, function: function)
      let values = try values(arguments)
      return (values[2] - values[0]) / (values[1] - values[0])
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
      block: Int(try evaluate(arguments[0])),
      index: Int(try evaluate(arguments[1]))
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

    let discriminant = Int(try evaluate(arguments[0]))
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
}
