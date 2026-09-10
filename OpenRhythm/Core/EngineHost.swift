import Foundation

struct EnginePoint: Equatable, Sendable {
  let x: Double
  let y: Double
}

struct EngineDrawCommand: Equatable, Sendable {
  let spriteID: Int
  // Bottom-left, top-left, top-right, bottom-right, in engine coordinates.
  let points: [EnginePoint]
  let zValues: [Double]
  var z: Double { zValues[0] }
  let alpha: Double
  let transform: [Double]
}

struct EngineAudioCommand: Equatable, Sendable {
  let clipID: Int
  let time: TimeInterval
  let minimumDistance: TimeInterval
}

struct EngineSpawnCommand: Equatable, Sendable {
  let archetypeID: Int
  let memory: [Double]
}

struct EngineParticleInstance: Equatable, Sendable {
  let id: Int
  let effectID: Int
  var points: [EnginePoint]
  let startTime: TimeInterval
  let duration: TimeInterval
  let isLooped: Bool
  var transform: [Double]
}

private struct EngineStream {
  var entries = [(key: Double, value: Double)]()

  func lowerBound(_ key: Double) -> Int {
    var lower = 0
    var upper = entries.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if entries[middle].key < key { lower = middle + 1 }
      else { upper = middle }
    }
    return lower
  }
}

/// Runtime side effects are retained until consumed by the presentation and
/// lifecycle systems. No unavailable resource is reported as available merely
/// because its name appears in EnginePlayData.
final class CommandEngineRuntimeHost: EngineRuntimeHost {
  let memory: EngineMemory
  let timeline: BPMTimeline
  let skinSpriteIDs: Set<Int>
  let effectClipIDs: Set<Int>
  let particleEffectIDs: Set<Int>
  let archetypeCount: Int

  private(set) var time: TimeInterval = 0
  private(set) var draws = [EngineDrawCommand]()
  private(set) var particles = [Int: EngineParticleInstance]()
  private(set) var exports = [Int: [Int: Double]]()
  private var audio = [EngineAudioCommand]()
  private var spawns = [EngineSpawnCommand]()
  private var streams = [Int: EngineStream]()
  private var streamEntryCount = 0
  private let streamEntryLimit: Int
  private var nextParticleID = 1
  private var entityIndex: Int?
  private var exportCount = 0
  private let commandLimit = 16_384

  init(
    memory: EngineMemory,
    level: LevelData,
    skinSpriteIDs: Set<Int>,
    effectClipIDs: Set<Int>,
    particleEffectIDs: Set<Int>,
    archetypeCount: Int,
    streamEntryLimit: Int = 262_144
  ) {
    self.memory = memory
    timeline = BPMTimeline(level: level)
    self.skinSpriteIDs = skinSpriteIDs
    self.effectClipIDs = effectClipIDs
    self.particleEffectIDs = particleEffectIDs
    self.archetypeCount = archetypeCount
    self.streamEntryLimit = max(0, streamEntryLimit)
    for block in [1003, 1004] {
      for index in 0..<16 {
        memory.set(block: block, index: index, value: index % 5 == 0 ? 1 : 0)
      }
    }
  }

  func beginFrame(at time: TimeInterval) throws {
    guard time.isFinite else {
      throw EngineInterpreterError.invalidArguments("frame time")
    }
    self.time = time
    draws.removeAll(keepingCapacity: true)
    particles = particles.filter {
      $0.value.isLooped || time < $0.value.startTime + $0.value.duration
    }
  }

  func selectEntity(index: Int?, exportCount: Int) {
    entityIndex = index
    self.exportCount = exportCount
  }

  func takeAudioCommands() -> [EngineAudioCommand] {
    defer { audio.removeAll(keepingCapacity: true) }
    return audio
  }

  /// Drain before executing this frame's callbacks: Spawn is deferred until
  /// the next update, and its data belongs in Entity Memory, not Entity Data.
  func takeSpawnCommands() -> [EngineSpawnCommand] {
    defer { spawns.removeAll(keepingCapacity: true) }
    return spawns
  }

  func call(function: String, arguments a: [Double]) throws -> Double {
    switch function {
    case "BeatToTime":
      try validate(a, count: 1, function: function)
      return timeline.time(at: a[0])
    case "BeatToBPM":
      try validate(a, count: 1, function: function)
      return timeline.bpm(at: a[0])
    case "Judge":
      try validate(a, count: 8, function: function)
      let distance = a[0] - a[1]
      for judgment in 1...3 {
        let index = judgment * 2
        if a[index] <= distance && distance <= a[index + 1] {
          return Double(judgment)
        }
      }
      return 0
    case "HasSkinSprite", "HasParticleEffect", "HasEffectClip":
      try validate(a, count: 1, function: function)
      let id = try identifier(a[0], function: function)
      let available = switch function {
      case "HasSkinSprite": skinSpriteIDs
      case "HasParticleEffect": particleEffectIDs
      default: effectClipIDs
      }
      return available.contains(id) ? 1 : 0
    case "Draw":
      guard (11...14).contains(a.count), a.allSatisfy(\.isFinite) else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      let id = try identifier(a[0], function: function)
      guard skinSpriteIDs.contains(id) else { return 0 }
      try checkLimit(draws.count)
      draws.append(EngineDrawCommand(
        spriteID: id, points: points(a),
        zValues: [a[9]] + Array(a.dropFirst(11))
          + Array(repeating: 0, count: 14 - a.count),
        alpha: min(1, max(0, a[10])), transform: transform(block: 1003)
      ))
      return 0
    case "Play", "PlayScheduled":
      try validate(
        a, count: function == "Play" ? 2 : 3, function: function
      )
      let id = try identifier(a[0], function: function)
      guard effectClipIDs.contains(id) else { return 0 }
      try checkLimit(audio.count)
      audio.append(EngineAudioCommand(
        clipID: id, time: function == "Play" ? time : a[1],
        minimumDistance: max(0, a.last!)
      ))
      return 0
    case "SpawnParticleEffect":
      try validate(a, count: 11, function: function)
      let effectID = try identifier(a[0], function: function)
      guard particleEffectIDs.contains(effectID), a[9] > 0 else { return 0 }
      try checkLimit(particles.count)
      // Keep handles exactly representable in engine doubles.
      guard nextParticleID < 9_007_199_254_740_991 else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      let id = nextParticleID
      nextParticleID += 1
      particles[id] = EngineParticleInstance(
        id: id, effectID: effectID, points: points(a), startTime: time,
        duration: a[9], isLooped: a[10] != 0,
        transform: transform(block: 1004)
      )
      return Double(id)
    case "DestroyParticleEffect":
      try validate(a, count: 1, function: function)
      particles.removeValue(forKey: try identifier(a[0], function: function))
      return 0
    case "MoveParticleEffect":
      try validate(a, count: 9, function: function)
      let id = try identifier(a[0], function: function)
      guard particles[id] != nil else { return 0 }
      particles[id]?.points = points(a)
      particles[id]?.transform = transform(block: 1004)
      return 0
    case "StreamSet", "StreamHas", "StreamGetValue",
      "StreamGetNextKey", "StreamGetPreviousKey":
      try validate(a, count: function == "StreamSet" ? 3 : 2,
        function: function)
      let id = try identifier(a[0], function: function)
      guard id >= 0 else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      let key = a[1]
      // Do not copy the stream across a mutation: writes typically append
      // samples and should not copy an ever-growing buffer each frame.
      let index = streams[id]?.lowerBound(key) ?? 0
      let count = streams[id]?.entries.count ?? 0
      let found = index < count && streams[id]?.entries[index].key == key
      if function == "StreamSet" {
        if found { streams[id]?.entries[index].value = a[2] }
        else {
          guard streamEntryCount < streamEntryLimit else {
            throw EngineInterpreterError.operationLimitExceeded
          }
          streams[id, default: EngineStream()].entries.insert((key, a[2]),
            at: index)
          streamEntryCount += 1
        }
        return 0
      }
      if function == "StreamHas" { return found ? 1 : 0 }
      if function == "StreamGetNextKey" {
        let next = index + (found ? 1 : 0)
        return next < count ? streams[id]!.entries[next].key : key
      }
      if function == "StreamGetPreviousKey" {
        return index > 0 ? streams[id]!.entries[index - 1].key : key
      }
      guard let stream = streams[id], !stream.entries.isEmpty else { return 0 }
      if index == 0 { return stream.entries[0].value }
      if index == count { return stream.entries[count - 1].value }
      if found { return stream.entries[index].value }
      let before = stream.entries[index - 1]
      let after = stream.entries[index]
      let span = after.key - before.key
      let fraction = span.isFinite ? (key - before.key) / span
        : (key / 2 - before.key / 2) / (after.key / 2 - before.key / 2)
      return before.value * (1 - fraction) + after.value * fraction
    case "Spawn":
      guard (1...65).contains(a.count), a.allSatisfy(\.isFinite) else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      let id = try identifier(a[0], function: function)
      guard (0..<archetypeCount).contains(id) else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      try checkLimit(spawns.count)
      spawns.append(EngineSpawnCommand(
        archetypeID: id, memory: Array(a.dropFirst())
      ))
      return 0
    case "ExportValue":
      try validate(a, count: 2, function: function)
      let index = try identifier(a[0], function: function)
      guard let entityIndex, (0..<exportCount).contains(index) else {
        throw EngineInterpreterError.invalidArguments(function)
      }
      exports[entityIndex, default: [:]][index] = a[1]
      return 0
    default:
      throw EngineInterpreterError.unsupportedFunction(function)
    }
  }

  private func points(_ arguments: [Double]) -> [EnginePoint] {
    stride(from: 1, through: 7, by: 2).map {
      EnginePoint(x: arguments[$0], y: arguments[$0 + 1])
    }
  }

  private func transform(block: Int) -> [Double] {
    (0..<16).map { memory.value(block: block, index: $0) }
  }

  private func validate(
    _ arguments: [Double], count: Int, function: String
  ) throws {
    guard arguments.count == count, arguments.allSatisfy(\.isFinite) else {
      throw EngineInterpreterError.invalidArguments(function)
    }
  }

  private func identifier(_ value: Double, function: String) throws -> Int {
    guard let result = Int(exactly: value) else {
      throw EngineInterpreterError.invalidArguments(function)
    }
    return result
  }

  private func checkLimit(_ count: Int) throws {
    guard count < commandLimit else {
      throw EngineInterpreterError.operationLimitExceeded
    }
  }
}

/// Resolves clip separation in playback-time order, not callback order. Future
/// scheduled clips must not suppress an immediate hit sound in an earlier frame.
struct EngineAudioScheduler {
  private var pending = [EngineAudioCommand]()
  private var lastPlayed = [Int: TimeInterval]()

  mutating func enqueue(_ commands: [EngineAudioCommand]) throws {
    guard commands.count <= 16_384 - pending.count else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    pending.append(contentsOf: commands)
    pending = pending.enumerated().sorted {
      if $0.element.time == $1.element.time { return $0.offset < $1.offset }
      return $0.element.time < $1.element.time
    }.map(\.element)
  }

  mutating func due(at time: TimeInterval) -> [EngineAudioCommand] {
    var result = [EngineAudioCommand]()
    let count = pending.prefix { $0.time <= time }.count
    for command in pending.prefix(count) {
      if let last = lastPlayed[command.clipID],
         command.time - last < command.minimumDistance {
        continue
      }
      lastPlayed[command.clipID] = command.time
      result.append(command)
    }
    pending.removeFirst(count)
    return result
  }
}
