import Foundation

struct EngineTouch: Sendable {
  let id: Int
  let started: Bool
  let ended: Bool
  let time: TimeInterval
  let startTime: TimeInterval
  let position: EnginePoint
  let startPosition: EnginePoint
  let delta: EnginePoint
}

struct EngineJudgment: Sendable {
  let entityIndex: Int
  let grade: Int
  let accuracy: Double
}

/// Executes the play lifecycle serially. "Parallel" callbacks have independent
/// entity memory, but need not run on parallel threads to preserve semantics.
final class EnginePlayRuntime {
  private struct Entity {
    let key: Int
    let index: Int?
    let archetype: Int
  }

  let host: CommandEngineRuntimeHost
  let memory: EngineMemory
  let inputCount: Int
  private(set) var judgments = [EngineJudgment]()
  private(set) var resolvedInputCount = 0
  private let engine: EnginePlayData
  private let interpreter: EngineInterpreter
  private var entities = [Entity]()
  private var waiting = [Entity]()
  private var active = [Entity]()
  private var nextKey: Int
  private var previousTime = 0.0
  private let entityLimit = 100_000

  init(
    engine: EnginePlayData, level: LevelData,
    options: [Double], aspectRatio: Double,
    skinSpriteIDs: Set<Int>, effectClipIDs: Set<Int>,
    particleEffectIDs: Set<Int>
  ) throws {
    guard aspectRatio.isFinite, aspectRatio > 0,
      level.entities.count <= 100_000 else {
      throw EngineInterpreterError.invalidArguments("runtime environment")
    }
    self.engine = engine
    memory = EngineMemory()
    host = CommandEngineRuntimeHost(
      memory: memory, level: level, skinSpriteIDs: skinSpriteIDs,
      effectClipIDs: effectClipIDs, particleEffectIDs: particleEffectIDs,
      archetypeCount: engine.archetypes.count
    )
    interpreter = EngineInterpreter(
      nodes: engine.nodes, memory: memory, host: host
    )
    nextKey = level.entities.count
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
    inputCount = level.entities.filter {
      archetypes[$0.archetype].map { engine.archetypes[$0].hasInput } ?? false
    }.count
    memory.set(block: 1000, index: 1, value: aspectRatio)
    for (index, value) in options.enumerated() {
      memory.set(block: 2002, index: index, value: value)
    }
    for index in 0..<10 {
      memory.set(block: 1007, index: index, value: 1)
    }
    for index in engine.archetypes.indices {
      memory.set(block: 5001, index: index, value: 1)
    }
    for (index, source) in level.entities.enumerated() {
      // Preserve original indices, including built-in timing entities.
      guard let archetypeID = archetypes[source.archetype] else {
        // Unimplemented chart archetypes are metadata, not startup errors.
        memory.set(block: 4103, index: index * 3, value: Double(index))
        memory.set(block: 4103, index: index * 3 + 1, value: -1)
        memory.set(block: 4103, index: index * 3 + 2, value: 2)
        continue
      }
      let entity = Entity(key: index, index: index, archetype: archetypeID)
      entities.append(entity)
      select(entity)
      memory.set(block: 4005, index: 2, value: -1)
      memory.set(block: 4103, index: index * 3, value: Double(index))
      memory.set(
        block: 4103, index: index * 3 + 1, value: Double(archetypeID)
      )
      for field in engine.archetypes[archetypeID].imports {
        guard (0..<32).contains(field.index) else {
          throw EngineInterpreterError.invalidArguments("entity import index")
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
        memory.set(block: 4001, index: field.index, value: value)
      }
    }
    for entity in ordered(entities, by: \.preprocess) {
      _ = try execute(entity, callback: \.preprocess)
    }
    var orders = [Int: Double]()
    for entity in ordered(entities, by: \.spawnOrder) {
      orders[entity.key] = try execute(entity, callback: \.spawnOrder)
    }
    waiting = entities.sorted {
      let lhs = orders[$0.key, default: 0]
      let rhs = orders[$1.key, default: 0]
      return lhs == rhs ? $0.key < $1.key : lhs < rhs
    }
  }

  func update(at time: TimeInterval, touches: [EngineTouch] = []) throws {
    let spawned = host.takeSpawnCommands()
    try host.beginFrame(at: time)
    judgments.removeAll(keepingCapacity: true)
    let delta = max(0, time - previousTime)
    previousTime = time
    for (index, value) in [time, delta, time, Double(touches.count)]
      .enumerated() {
      memory.set(block: 1001, index: index, value: value)
    }
    for (index, touch) in touches.enumerated() {
      let values: [Double] = [
        Double(touch.id), touch.started ? 1 : 0, touch.ended ? 1 : 0,
        touch.time, touch.startTime, touch.position.x, touch.position.y,
        touch.startPosition.x, touch.startPosition.y,
        touch.delta.x, touch.delta.y,
        delta > 0 ? touch.delta.x / delta : 0,
        delta > 0 ? touch.delta.y / delta : 0, 0, 0
      ]
      for (offset, value) in values.enumerated() {
        memory.set(block: 1002, index: index * 15 + offset, value: value)
      }
    }
    var newlyActive = [Entity]()
    var spawnCount = 0
    for entity in waiting {
      guard try execute(entity, callback: \.shouldSpawn, default: 1) != 0 else {
        break
      }
      setState(entity, value: 1)
      newlyActive.append(entity)
      spawnCount += 1
    }
    waiting.removeFirst(spawnCount)
    guard active.count + newlyActive.count + spawned.count <= entityLimit else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    for command in spawned {
      let entity = Entity(key: nextKey, index: nil, archetype: command.archetypeID)
      nextKey += 1
      select(entity)
      for (index, value) in command.memory.enumerated() {
        memory.set(block: 4000, index: index, value: value)
      }
      newlyActive.append(entity)
    }
    active.append(contentsOf: newlyActive)
    for entity in newlyActive {
      _ = try execute(entity, callback: \.initialize)
    }
    for entity in ordered(active, by: \.updateSequential) {
      _ = try execute(entity, callback: \.updateSequential)
    }
    if !touches.isEmpty {
      for entity in ordered(active, by: \.touch) {
        _ = try execute(entity, callback: \.touch)
      }
    }
    for entity in active {
      _ = try execute(entity, callback: \.updateParallel)
    }
    var despawned = Set<Int>()
    for entity in active {
      select(entity)
      guard memory.value(block: 4004, index: 0) != 0 else { continue }
      _ = try execute(entity, callback: \.terminate)
      if let index = entity.index, engine.archetypes[entity.archetype].hasInput {
        let grade = memory.value(block: 4005, index: 0)
        judgments.append(EngineJudgment(
          entityIndex: index, grade: Int(exactly: grade) ?? 0,
          accuracy: memory.value(block: 4005, index: 1)
        ))
        resolvedInputCount += 1
      }
      setState(entity, value: 2)
      despawned.insert(entity.key)
      memory.removeEntity(key: entity.key)
    }
    active.removeAll { despawned.contains($0.key) }
  }

  private func select(_ entity: Entity) {
    memory.selectEntity(key: entity.key, index: entity.index)
    host.selectEntity(
      index: entity.index,
      exportCount: engine.archetypes[entity.archetype].exports.count
    )
  }

  private func setState(_ entity: Entity, value: Double) {
    guard let index = entity.index else { return }
    memory.set(block: 4103, index: index * 3 + 2, value: value)
  }

  private func execute(
    _ entity: Entity, callback: KeyPath<EngineArchetype, EngineCallback?>,
    default defaultValue: Double = 0
  ) throws -> Double {
    guard let callback = engine.archetypes[entity.archetype][keyPath: callback]
    else { return defaultValue }
    select(entity)
    return try interpreter.execute(nodeAt: callback.index)
  }

  private func ordered(
    _ entities: [Entity], by callback: KeyPath<EngineArchetype, EngineCallback?>
  ) -> [Entity] {
    entities.sorted {
      let lhs = engine.archetypes[$0.archetype][keyPath: callback]?.order ?? 0
      let rhs = engine.archetypes[$1.archetype][keyPath: callback]?.order ?? 0
      return lhs == rhs ? $0.key < $1.key : lhs < rhs
    }
  }
}
