import Foundation

struct LevelEntityData: Decodable, Sendable {
  let name: String
  let value: Double?
  let ref: String?
}

struct LevelEntity: Decodable, Sendable {
  let archetype: String
  let name: String?
  let data: [LevelEntityData]
}

struct LevelData: Decodable, Sendable {
  let bgmOffset: Double
  let entities: [LevelEntity]
}
