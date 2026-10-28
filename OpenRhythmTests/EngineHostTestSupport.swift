import XCTest
@testable import OpenRhythm

/// Shared fixtures for the engine host test classes, which subclass this
/// to reuse its helpers. It declares no tests of its own.
class EngineHostTestCase: XCTestCase {
  let quad: [Double] = [-1, -1, -1, 1, 1, 1, 1, -1]

  func makeHost(
    level: LevelData = LevelData(bgmOffset: 0, entities: [])
  ) -> CommandEngineRuntimeHost {
    CommandEngineRuntimeHost(
      memory: EngineMemory(), level: level, skinSpriteIDs: [7],
      effectClipIDs: [8, 10], particleEffectIDs: [9], archetypeCount: 2
    )
  }
}

@MainActor
final class MockEffectVoice: EngineEffectVoice {
  var isPlaying = false
  var delays = [Double]()
  var looping = [Bool]()
  var stopDelays = [Double]()
  var stopCount = 0
  var pauseCount = 0
  var resumeCount = 0
  var events = [String]()
  var onPlay: (() -> Void)?
  var onResume: (() -> Void)?

  func pause() { pauseCount += 1 }
  func resume() {
    resumeCount += 1
    events.append("resume")
    onResume?()
  }

  func play(after delay: Double, looped: Bool) {
    delays.append(delay)
    looping.append(looped)
    isPlaying = true
    onPlay?()
  }

  func stop(after delay: Double) {
    events.append("scheduledStop")
    stopDelays.append(delay)
    if delay <= 0 { stop() }
  }

  func stop() {
    stopCount += 1
    isPlaying = false
  }
}

final class RuntimeNodeBuilder {
  private var nodes = [[String: Any]]()

  func value(_ value: Double) -> Int {
    nodes.append(["value": value])
    return nodes.count - 1
  }

  func call(_ function: String, _ arguments: [Int]) -> Int {
    nodes.append(["func": function, "args": arguments])
    return nodes.count - 1
  }

  func engine(archetypes: [[String: Any]], sprites: [[String: Any]] = [],
    buckets: [[String: Any]] = [])
    throws -> EnginePlayData {
    let data = try JSONSerialization.data(withJSONObject: [
      "skin": ["sprites": sprites], "effect": ["clips": []],
      "particle": ["effects": []], "buckets": buckets,
      "nodes": nodes, "archetypes": archetypes
    ])
    return try JSONDecoder().decode(EnginePlayData.self, from: data)
  }
}
