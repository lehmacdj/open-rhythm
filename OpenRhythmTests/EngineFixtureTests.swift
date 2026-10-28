import XCTest
import UIKit
import zlib
@testable import OpenRhythm

/// Engine-level regression tests against real, MIT-licensed Sonolus engines.
/// The built engine data lives in git submodules (forks pinned to each npm
/// release, plus its build output) under Fixtures/Engines. Skins, effects,
/// particles and backgrounds are generated placeholders; levels are small
/// hand-written charts using each engine's own archetypes and data fields.
@MainActor
final class EngineFixtureTests: XCTestCase {
  // MARK: Project Sekai

  func testPJSekaiDeclaresSupportedVersionAndFunctions() throws {
    try checkPreflight(try Fixture.load(.pjsekai))
  }

  func testPJSekaiPlaceholderPresentationLoadsThroughProductionLoaders()
    throws {
    try checkPresentation(try Fixture.load(.pjsekai))
  }

  func testPJSekaiNoTouchRunResolvesEveryInput() throws {
    // Seven notes plus two hidden slide ticks, which are also judged.
    try checkNoTouchRun(try Fixture.load(.pjsekai), expectedInputs: 9)
  }

  func testPJSekaiOutputIsDeterministicAcrossRestartAndRuns() throws {
    try checkDeterminism(try Fixture.load(.pjsekai))
  }

  // MARK: BanG Dream!

  func testBandoriDeclaresSupportedVersionAndFunctions() throws {
    try checkPreflight(try Fixture.load(.bandori))
  }

  func testBandoriPlaceholderPresentationLoadsThroughProductionLoaders()
    throws {
    try checkPresentation(try Fixture.load(.bandori))
  }

  func testBandoriNoTouchRunResolvesEveryInput() throws {
    try checkNoTouchRun(try Fixture.load(.bandori), expectedInputs: 8)
  }

  func testBandoriOutputIsDeterministicAcrossRestartAndRuns() throws {
    try checkDeterminism(try Fixture.load(.bandori))
  }

  // MARK: Checks

  private func checkPreflight(_ fixture: Fixture) throws {
    // RuntimeBundleLoader accepts only engine version 13.
    XCTAssertEqual(fixture.version, 13, fixture.name)
    XCTAssertEqual(try fixture.engine.unsupportedFunctions(), [],
      "\(fixture.name) uses functions the interpreter does not implement")
  }

  private func checkPresentation(_ fixture: Fixture) throws {
    let engine = fixture.engine
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: fixture.presentation)
    XCTAssertEqual(Set(assets.skin.keys), Set(engine.skin.sprites.map(\.id)))
    XCTAssertEqual(Set(assets.particles.keys),
      Set(engine.particle.effects.map(\.id)))
    XCTAssertNotNil(assets.background)
    XCTAssertFalse(assets.configuration.options.isEmpty,
      "The real engine configuration declares options")
    let audio = try EngineAudioPlayback(engine: engine,
      presentation: fixture.presentation)
    XCTAssertEqual(audio.clipIDs, Set(engine.effect.clips.map(\.id)))
  }

  private func checkNoTouchRun(_ fixture: Fixture, expectedInputs: Int) throws {
    let (runtime, assets) = try fixture.makeRuntime()
    XCTAssertEqual(runtime.inputCount, expectedInputs, fixture.name)
    var seen = Set<Int>()
    var drewSprites = false
    for frame in 0..<Fixture.frameCount {
      try runtime.update(at: fixture.time(frame: frame))
      if !EngineRenderer.sprites(host: runtime.host, assets: assets).isEmpty {
        drewSprites = true
      }
      for judgment in runtime.judgments {
        XCTAssertTrue(seen.insert(judgment.entityIndex).inserted,
          "\(fixture.name): input \(judgment.entityIndex) resolved twice")
        XCTAssertEqual(judgment.grade, 0,
          "\(fixture.name): input \(judgment.entityIndex) hit without touches")
      }
      if runtime.resolvedInputCount == runtime.inputCount { break }
    }
    XCTAssertEqual(runtime.resolvedInputCount, runtime.inputCount, fixture.name)
    XCTAssertEqual(seen.count, runtime.inputCount, fixture.name)
    XCTAssertTrue(drewSprites, "\(fixture.name) drew no placeholder sprites")
  }

  private func checkDeterminism(_ fixture: Fixture) throws {
    let (runtime, _) = try fixture.makeRuntime()
    let first = try record(runtime, fixture)
    runtime.restart()
    let restarted = try record(runtime, fixture)
    let (fresh, _) = try fixture.makeRuntime()
    let second = try record(fresh, fixture)
    XCTAssertEqual(first.count, Fixture.frameCount)
    XCTAssertTrue(first.contains { !$0.draws.isEmpty }, fixture.name)
    // The comparison must cover hits, hit effects and sound, not only misses.
    XCTAssertTrue(first.contains { $0.judgments.contains { $0[1] > 0 } },
      "\(fixture.name): the tap pattern hit nothing")
    XCTAssertTrue(first.contains { !$0.particles.isEmpty }, fixture.name)
    XCTAssertTrue(first.contains { !$0.audio.isEmpty }, fixture.name)
    for (name, other) in [("restart", restarted), ("second runtime", second)] {
      XCTAssertEqual(other.count, first.count, "\(fixture.name) \(name)")
      // Report the first divergent frame rather than thousands of draws.
      if let frame = zip(first, other).enumerated()
        .first(where: { $0.element.0 != $0.element.1 })?.offset {
        XCTFail("\(fixture.name) \(name) diverges at frame \(frame)")
      }
    }
  }

  private struct Snapshot: Equatable {
    let draws: [EngineDrawCommand]
    let particles: [Int: EngineParticleInstance]
    let audio: [EngineAudioCommand]
    let loops: [EngineLoopCommand]
    // Entity index, grade and accuracy bits (keep NaN/-0 distinct).
    let judgments: [[UInt64]]
    let resolved: Int
  }

  /// Taps across the stage at each chart beat, so judgments, hit effects and
  /// particles also participate. Only repeatability matters, not accuracy.
  private func record(_ runtime: EnginePlayRuntime, _ fixture: Fixture) throws
    -> [Snapshot] {
    var pool = EngineTouchPool<Int>()
    var snapshots = [Snapshot]()
    for frame in 0..<Fixture.frameCount {
      let time = fixture.time(frame: frame)
      let phase = fixture.contactPhase(frame: frame)
      if phase == 0 || phase == 5 {
        for lane in 0..<8 {
          pool.receive(key: lane,
            position: EnginePoint(x: -1.05 + Double(lane) * 0.3, y: -0.75),
            time: time, started: phase == 0, ended: phase == 5)
        }
      }
      try runtime.update(at: time, touches: pool.touches)
      snapshots.append(Snapshot(draws: runtime.host.draws,
        particles: runtime.host.particles,
        audio: runtime.host.takeAudioCommands(),
        loops: runtime.host.takeLoopCommands(),
        judgments: runtime.judgments.map {
          [UInt64($0.entityIndex), UInt64($0.grade), $0.accuracy.bitPattern]
        },
        resolved: runtime.resolvedInputCount))
      pool.nextFrame(at: time)
    }
    return snapshots
  }
}

// MARK: - Fixtures

@MainActor
private struct Fixture {
  enum Engine: String {
    case pjsekai, bandori
  }

  /// 120 BPM throughout: beat b is at b / 2 seconds. Every chart ends by
  /// beat 11 (5.5 s); run 9 s so misses and despawns complete.
  static let frameCount = 9 * 60
  static let beatsPerSecond = 2.0

  let name: String
  let version: Int
  let engine: EnginePlayData
  let level: LevelData
  let presentation: RuntimePresentation

  static func load(_ engine: Engine) throws -> Fixture {
    let dist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Engines/\(engine.rawValue)/dist")
    guard FileManager.default.fileExists(
      atPath: dist.appendingPathComponent("EnginePlayData").path) else {
      throw XCTSkip("The \(engine.rawValue) engine fixture submodule is not "
        + "checked out. Run `git submodule update --init`.")
    }
    struct Item: Decodable { let version: Int }
    let item = try JSONDecoder().decode(Item.self,
      from: Data(contentsOf: dist.appendingPathComponent("EngineItem.json")))
    let data = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: dist.appendingPathComponent("EnginePlayData")))
    let configuration = try Data(contentsOf:
      dist.appendingPathComponent("EngineConfiguration"))
    return Fixture(name: engine.rawValue, version: item.version, engine: data,
      level: engine == .pjsekai ? pjsekaiLevel : bandoriLevel,
      presentation: try PlaceholderPresentation.make(engine: data,
        configuration: configuration))
  }

  func makeRuntime() throws -> (EnginePlayRuntime, EnginePresentationAssets) {
    let missing = try engine.unsupportedFunctions()
    guard missing.isEmpty else {
      throw XCTSkip("\(name) needs unsupported functions: "
        + missing.joined(separator: ", "))
    }
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine,
      presentation: presentation)
    let runtime = try EnginePlayRuntime(engine: engine, level: level,
      options: assets.configuration.options.map(\.def), aspectRatio: 1.8,
      skinSpriteIDs: Set(assets.skin.keys), effectClipIDs: audio.clipIDs,
      particleEffectIDs: Set(assets.particles.keys))
    return (runtime, assets)
  }

  func time(frame: Int) -> Double {
    BGMClockMapping(offset: level.bgmOffset).initialChartTime
      + Double(frame) / 60
  }

  /// Frames since the most recent whole beat, or nil before the first note.
  func contactPhase(frame: Int) -> Int? {
    let beat = time(frame: frame) * Self.beatsPerSecond
    guard beat >= 4 else { return nil }
    return Int(((beat - beat.rounded(.down)) / Self.beatsPerSecond * 60)
      .rounded())
  }

  // Data field names and refs follow each engine's own chart converter
  // (uscToLevelData / bestdoriToLevelData) output for an equivalent chart.

  static let pjsekaiLevel = LevelData(bgmOffset: 0, entities: [
    entity("Initialization"),
    entity("Stage"),
    entity("#BPM_CHANGE", ["#BEAT": 0, "#BPM": 120]),
    entity("#TIMESCALE_CHANGE", ["#BEAT": 0, "#TIMESCALE": 1]),
    entity("NormalTapNote", ["#BEAT": 4, "lane": -3, "size": 1.5]),
    entity("CriticalTapNote", ["#BEAT": 5, "lane": 3, "size": 1.5]),
    entity("NormalFlickNote",
      ["#BEAT": 6, "lane": 0, "size": 1.5, "direction": 0]),
    entity("NormalTraceNote", ["#BEAT": 7, "lane": 0, "size": 1.5]),
    entity("NormalSlideStartNote", name: "start",
      ["#BEAT": 8, "lane": -2, "size": 1.5]),
    entity("HiddenSlideTickNote", ["#BEAT": 8.5], refs: ["attach": "first"]),
    entity("NormalSlideTickNote", name: "tick",
      ["#BEAT": 9, "lane": 0, "size": 1.5]),
    entity("HiddenSlideTickNote", ["#BEAT": 9.5], refs: ["attach": "second"]),
    // Direction -1 is left.
    entity("NormalSlideEndFlickNote", name: "end",
      ["#BEAT": 10, "lane": 2, "size": 1.5, "direction": -1],
      refs: ["slide": "second"]),
    entity("NormalActiveSlideConnector", name: "first", ["ease": 0],
      refs: ["start": "start", "end": "end", "head": "start", "tail": "tick"]),
    entity("NormalActiveSlideConnector", name: "second", ["ease": 0],
      refs: ["start": "start", "end": "end", "head": "tick", "tail": "end"]),
  ])

  static let bandoriLevel = LevelData(bgmOffset: 0, entities: [
    entity("Initialization"),
    entity("Stage"),
    entity("#BPM_CHANGE", ["#BEAT": 0, "#BPM": 120]),
    entity("TapNote", ["#BEAT": 4, "lane": -2]),
    entity("FlickNote", ["#BEAT": 5, "lane": 2]),
    entity("DirectionalFlickNote",
      ["#BEAT": 6, "lane": 0, "direction": -1, "size": 2]),
    // A slide with a tick and a flick end.
    entity("SlideStartNote", name: "a0", ["#BEAT": 7, "lane": -1],
      refs: ["last": "a2"]),
    entity("SlideTickNote", name: "a1", ["#BEAT": 8, "lane": 1],
      refs: ["first": "a0", "prev": "a0"]),
    entity("SlideEndFlickNote", name: "a2", ["#BEAT": 9, "lane": 3, "long": 0],
      refs: ["first": "a0", "prev": "a1"]),
    entity("StraightSlideConnector", refs: ["first": "a0", "start": "a0",
      "head": "a0", "tail": "a1", "end": "a1"]),
    entity("StraightSlideConnector", refs: ["first": "a0", "start": "a1",
      "head": "a1", "tail": "a2", "end": "a2"]),
    // A hold in one lane.
    entity("SlideStartNote", name: "b0", ["#BEAT": 10, "lane": -3],
      refs: ["last": "b1"]),
    entity("SlideEndNote", name: "b1", ["#BEAT": 11, "lane": -3],
      refs: ["first": "b0", "prev": "b0"]),
    entity("StraightSlideConnector", refs: ["first": "b0", "start": "b0",
      "head": "b0", "tail": "b1", "end": "b1"]),
  ])

  private static func entity(_ archetype: String, name: String? = nil,
    _ values: [String: Double] = [:], refs: [String: String] = [:])
    -> LevelEntity {
    LevelEntity(archetype: archetype, name: name, data:
      values.sorted { $0.key < $1.key }.map {
        LevelEntityData(name: $0.key, value: $0.value, ref: nil)
      } + refs.sorted { $0.key < $1.key }.map {
        LevelEntityData(name: $0.key, value: nil, ref: $0.value)
      })
  }
}

/// Generated stand-ins for the skin, effect, particle and background items a
/// server would pair with the engine. Every resource the engine names exists.
@MainActor
private enum PlaceholderPresentation {
  static func make(engine: EnginePlayData, configuration: Data) throws
    -> RuntimePresentation {
    try RuntimePresentation(resources: [
      "configuration": configuration,
      "backgroundData": json(["fit": "cover", "color": "#000000"]),
      "backgroundConfiguration": json(["blur": 0, "mask": "#00000080"]),
      "backgroundImage": png(width: 16, height: 9) { _ in
        UIColor.darkGray.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 9))
      },
    ].merging(skin(engine)) { $1 }
      .merging(particles(engine)) { $1 }
      .merging(effects(engine)) { $1 })
  }

  private static let cell = 4
  private static let identity: [String: [String: Double]] = Dictionary(
    uniqueKeysWithValues: (1...4).flatMap { ["x\($0)", "y\($0)"] }
      .map { ($0, [$0: 1]) })

  /// One distinctly colored cell per sprite in a 16-column atlas.
  private static func skin(_ engine: EnginePlayData) throws -> [String: Data] {
    let names = engine.skin.sprites.map(\.name)
    let columns = 16
    let rows = max(1, (names.count + columns - 1) / columns)
    let texture = try png(width: columns * cell, height: rows * cell) { _ in
      for index in names.indices {
        UIColor(hue: Double(index) / Double(max(1, names.count)),
          saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
        UIRectFill(CGRect(x: index % columns * cell, y: index / columns * cell,
          width: cell, height: cell))
      }
    }
    let sprites: [[String: Any]] = names.enumerated().map { index, name in
      ["name": name, "x": index % columns * cell, "y": index / columns * cell,
       "w": cell, "h": cell, "transform": identity]
    }
    return try ["skinTexture": texture, "skinData": json(["width": columns * cell,
      "height": rows * cell, "interpolation": false, "sprites": sprites])]
  }

  /// One fading particle per effect, using a single white sprite.
  private static func particles(_ engine: EnginePlayData) throws
    -> [String: Data] {
    func property(_ from: Double, _ to: Double) -> [String: Any] {
      ["from": ["c": from], "to": ["c": to], "ease": "linear"]
    }
    let particle: [String: Any] = ["sprite": 0, "color": "#ffffff",
      "start": 0, "duration": 1, "x": property(0, 0), "y": property(0, 0),
      "w": property(1, 2), "h": property(1, 2), "r": property(0, 0),
      "a": property(1, 0)]
    let effects: [[String: Any]] = engine.particle.effects.map {
      ["name": $0.name, "transform": identity,
       "groups": [["count": 1, "particles": [particle]]]]
    }
    let texture = try png(width: cell, height: cell) { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: cell, height: cell))
    }
    return try ["particleTexture": texture, "particleData": json([
      "width": cell, "height": cell, "interpolation": false,
      "sprites": [["x": 0, "y": 0, "w": cell, "h": cell]],
      "effects": effects])]
  }

  /// A short silent WAV per clip, stored in a ZIP as effect audio is served.
  private static func effects(_ engine: EnginePlayData) throws
    -> [String: Data] {
    let clips = engine.effect.clips.enumerated().map { index, clip in
      (name: clip.name, filename: "clip\(index).wav")
    }
    return try ["effectData": json(["clips": clips.map {
        ["name": $0.name, "filename": $0.filename]
      }]),
      "effectAudio": storedZIP(clips.map { ($0.filename, silentWAV()) })]
  }

  private static func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  private static func png(width: Int, height: Int,
    draw: (UIGraphicsImageRendererContext) -> Void) throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
      format: format).pngData(actions: draw)
  }

  /// 50 ms of 16-bit mono PCM silence at 8 kHz.
  private static func silentWAV() -> Data {
    let samples = 400
    var data = Data("RIFF".utf8)
    data.appendLE(UInt32(36 + samples * 2), 4)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    for (value, size) in [(16, 4), (1, 2), (1, 2), (8000, 4), (16000, 4),
      (2, 2), (16, 2)] {
      data.appendLE(UInt32(value), size)
    }
    data.append(contentsOf: Array("data".utf8))
    data.appendLE(UInt32(samples * 2), 4)
    data.append(Data(count: samples * 2))
    return data
  }

  /// A minimal uncompressed (method 0) ZIP archive.
  private static func storedZIP(_ files: [(name: String, data: Data)]) -> Data {
    var archive = Data()
    var directory = Data()
    for file in files {
      let name = Data(file.name.utf8)
      let crc = file.data.withUnsafeBytes {
        crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
      }
      let offset = archive.count
      // Version, flags, method, time, date; CRC and sizes; name/extra lengths.
      func common(_ data: inout Data) {
        for (value, size) in [(20, 2), (0, 2), (0, 2), (0, 2), (0, 2)] {
          data.appendLE(UInt32(value), size)
        }
        data.appendLE(UInt32(crc), 4)
        data.appendLE(UInt32(file.data.count), 4)
        data.appendLE(UInt32(file.data.count), 4)
        data.appendLE(UInt32(name.count), 2)
        data.appendLE(0, 2)
      }
      archive.appendLE(0x0403_4b50, 4)
      common(&archive)
      archive.append(name)
      archive.append(file.data)
      directory.appendLE(0x0201_4b50, 4)
      directory.appendLE(20, 2)
      common(&directory)
      // Comment length, disk, internal/external attributes, local offset.
      for (value, size) in [(0, 2), (0, 2), (0, 2), (0, 4), (offset, 4)] {
        directory.appendLE(UInt32(value), size)
      }
      directory.append(name)
    }
    let directoryOffset = archive.count
    archive.append(directory)
    archive.appendLE(0x0605_4b50, 4)
    for (value, size) in [(0, 2), (0, 2), (files.count, 2), (files.count, 2),
      (directory.count, 4), (directoryOffset, 4), (0, 2)] {
      archive.appendLE(UInt32(value), size)
    }
    return archive
  }
}

private extension Data {
  mutating func appendLE(_ value: UInt32, _ size: Int) {
    for byte in 0..<size { append(UInt8(truncatingIfNeeded: value >> (8 * byte))) }
  }
}
