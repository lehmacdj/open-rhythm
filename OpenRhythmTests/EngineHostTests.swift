import XCTest
@testable import OpenRhythm

final class EngineHostTests: XCTestCase {
  private let quad: [Double] = [-1, -1, -1, 1, 1, 1, 1, -1]

  func testInterpreterDispatchesHostFunctions() throws {
    let host = makeHost()
    let nodes = [
      EngineDataNode(value: 7),
      EngineDataNode(function: "HasSkinSprite", arguments: [0]),
      EngineDataNode(value: 123),
      EngineDataNode(function: "HasSkinSprite", arguments: [2])
    ]
    let interpreter = EngineInterpreter(nodes: nodes, host: host)
    XCTAssertEqual(try interpreter.execute(nodeAt: 1), 1)
    XCTAssertEqual(try interpreter.execute(nodeAt: 3), 0)
    XCTAssertEqual(try host.call(function: "HasParticleEffect", arguments: [9]), 1)
    XCTAssertEqual(try host.call(function: "HasParticleEffect", arguments: [7]), 0)
  }

  func testDrawRetainsGeometryAlphaDepthAndTransformForOneFrame() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    host.memory.set(block: 1003, index: 0, value: 0.5)
    XCTAssertEqual(try host.call(
      function: "Draw", arguments: [7] + quad + [42, 0.75]
    ), 0)
    host.memory.set(block: 1003, index: 0, value: 1)
    let draw = try XCTUnwrap(host.draws.first)
    XCTAssertEqual(draw.points, [
      EnginePoint(x: -1, y: -1), EnginePoint(x: -1, y: 1),
      EnginePoint(x: 1, y: 1), EnginePoint(x: 1, y: -1)
    ])
    XCTAssertEqual(draw.spriteID, 7)
    XCTAssertEqual(draw.z, 42)
    XCTAssertEqual(draw.alpha, 0.75)
    XCTAssertEqual(draw.transform[0], 0.5)
    _ = try host.call(function: "Draw", arguments: [88] + quad + [0, 1])
    XCTAssertEqual(host.draws.count, 1, "Missing sprites must not be drawn")
    try host.beginFrame(at: 3)
    XCTAssertTrue(host.draws.isEmpty)
  }

  func testJudgeUsesSignedInclusiveWindowsAndBestMatchingGrade() throws {
    let host = makeHost()
    let windows = [-0.02, 0.03, -0.05, 0.06, -0.10, 0.12]
    for (distance, expected) in [
      (-0.101, 0), (-0.1, 3), (-0.05, 2), (-0.02, 1),
      (0, 1), (0.03, 1), (0.06, 2), (0.12, 3), (0.121, 0)
    ] {
      XCTAssertEqual(try host.call(
        function: "Judge", arguments: [distance, 0] + windows
      ), Double(expected))
    }
    XCTAssertEqual(try host.call(
      function: "Judge", arguments: [10, 10] + windows
    ), 1)
  }

  func testBeatToTimeIntegratesChangesWithoutBGMOffset() throws {
    let host = makeHost(level: LevelData(bgmOffset: 0.25, entities: [
      bpm(beat: 0, value: 120), bpm(beat: 4, value: 60)
    ]))
    for (beat, time) in [(-2.0, -1.0), (0, 0), (2, 1), (4, 2), (6, 4)] {
      XCTAssertEqual(try host.call(
        function: "BeatToTime", arguments: [beat]
      ), time)
    }
  }

  func testAudioSeparationUsesPlaybackOrderAndClipIdentity() throws {
    let host = makeHost()
    try host.beginFrame(at: 1)
    _ = try host.call(function: "PlayScheduled", arguments: [8, 2, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [10, 0.1])
    _ = try host.call(function: "Play", arguments: [999, 0.1])
    var scheduler = EngineAudioScheduler()
    scheduler.enqueue(host.takeAudioCommands())
    XCTAssertTrue(host.takeAudioCommands().isEmpty)
    XCTAssertEqual(scheduler.due(at: 1).map(\.clipID), [8, 10])
    XCTAssertTrue(scheduler.due(at: 1.5).isEmpty)
    XCTAssertEqual(scheduler.due(at: 2).map(\.clipID), [8])
    XCTAssertTrue(scheduler.due(at: 3).isEmpty)
  }

  func testParticlesHaveUniqueHandlesExpireAndCanBeDestroyed() throws {
    let host = makeHost()
    try host.beginFrame(at: 1)
    let first = try host.call(
      function: "SpawnParticleEffect", arguments: [9] + quad + [0.5, 0]
    )
    let loop = try host.call(
      function: "SpawnParticleEffect", arguments: [9] + quad + [0.5, 1]
    )
    XCTAssertNotEqual(first, loop)
    XCTAssertEqual(host.particles.count, 2)
    try host.beginFrame(at: 1.5)
    XCTAssertNil(host.particles[Int(first)])
    XCTAssertNotNil(host.particles[Int(loop)])
    _ = try host.call(function: "DestroyParticleEffect", arguments: [loop])
    _ = try host.call(function: "DestroyParticleEffect", arguments: [loop])
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertEqual(try host.call(
      function: "SpawnParticleEffect", arguments: [999] + quad + [1, 1]
    ), 0)
  }

  func testSpawnsAreDeferredAndExportsAreEntityScoped() throws {
    let host = makeHost()
    _ = try host.call(function: "Spawn", arguments: [1, 20, 30])
    XCTAssertEqual(host.takeSpawnCommands(), [
      EngineSpawnCommand(archetypeID: 1, memory: [20, 30])
    ])
    XCTAssertTrue(host.takeSpawnCommands().isEmpty)
    host.selectEntity(index: 12, exportCount: 2)
    _ = try host.call(function: "ExportValue", arguments: [0, 5])
    _ = try host.call(function: "ExportValue", arguments: [0, 6])
    host.selectEntity(index: 13, exportCount: 1)
    _ = try host.call(function: "ExportValue", arguments: [0, 7])
    XCTAssertEqual(host.exports[12], [0: 6])
    XCTAssertEqual(host.exports[13], [0: 7])
    XCTAssertThrowsError(try host.call(
      function: "ExportValue", arguments: [1, 8]
    ))
    host.selectEntity(index: nil, exportCount: 0)
    XCTAssertThrowsError(try host.call(
      function: "ExportValue", arguments: [0, 8]
    ))
  }

  func testMalformedCommandsThrowInsteadOfCrashingOrGrowingState() throws {
    let host = makeHost()
    for (function, arguments) in [
      ("Draw", [7.0]), ("BeatToTime", [Double.nan]),
      ("Spawn", [Double.infinity]), ("Spawn", [-1]), ("Spawn", [2]),
      ("HasSkinSprite", [Double.greatestFiniteMagnitude]),
      ("DestroyParticleEffect", [0.5]), ("Judge", []),
      ("UnknownFunction", [])
    ] {
      XCTAssertThrowsError(try host.call(
        function: function, arguments: arguments
      ), function)
    }
    XCTAssertTrue(host.draws.isEmpty)
    XCTAssertTrue(host.particles.isEmpty)
    XCTAssertTrue(host.takeSpawnCommands().isEmpty)
  }

  private func makeHost(
    level: LevelData = LevelData(bgmOffset: 0, entities: [])
  ) -> CommandEngineRuntimeHost {
    CommandEngineRuntimeHost(
      memory: EngineMemory(), level: level, skinSpriteIDs: [7],
      effectClipIDs: [8, 10], particleEffectIDs: [9], archetypeCount: 2
    )
  }

  private func bpm(beat: Double, value: Double) -> LevelEntity {
    LevelEntity(archetype: "#BPM_CHANGE", name: nil, data: [
      LevelEntityData(name: "#BEAT", value: beat, ref: nil),
      LevelEntityData(name: "#BPM", value: value, ref: nil)
    ])
  }
}
