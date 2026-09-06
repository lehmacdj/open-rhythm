import Foundation

struct EngineNamedID: Decodable, Sendable {
  let name: String
  let id: Int
}

struct EngineSkinDefinition: Decodable, Sendable {
  let renderMode: String?
  let sprites: [EngineNamedID]
}

struct EngineEffectDefinition: Decodable, Sendable {
  let clips: [EngineNamedID]
}

struct EngineParticleDefinition: Decodable, Sendable {
  let effects: [EngineNamedID]
}

struct EngineCallback: Decodable, Sendable {
  let index: Int
  let order: Int?
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
  let unit: String
}

struct EnginePlayData: Decodable, Sendable {
  let skin: EngineSkinDefinition
  let effect: EngineEffectDefinition
  let particle: EngineParticleDefinition
  let archetypes: [EngineArchetype]
  let nodes: [EngineDataNode]
  let buckets: [EngineBucket]
}
