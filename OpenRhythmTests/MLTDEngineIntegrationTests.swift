import XCTest
@testable import OpenRhythm

/// Opt-in integration tests for the rhythm-lab MLTD engine
/// (THE IDOLM@STER Million Live! Theater Days). They read the optional
/// `mltd` folder of the cached `OpenRhythmIntegrationFixtures` root, written
/// by the engine repository's `scripts/fixtures.ts`, and skip without it.
/// Converted charts never enter this repository.
@MainActor
final class MLTDEngineIntegrationTests: XCTestCase {
  /// The synthetic chart bundled with the engine build: every note kind.
  func testMLTDDemoNoTouchAndPerfectInput() throws {
    try checkMLTDChart("demo.gz")
  }

  /// 虹色letters MILLION MIX: holds, slides with waypoints, hold-end flicks.
  func testMLTDNijiiroLettersMillionMix() throws {
    try checkMLTDChart("mltd-nijile-mm.gz")
  }

  /// Brand New Theater! MILLION MIX.
  func testMLTDBrandNewTheaterMillionMix() throws {
    try checkMLTDChart("mltd-bnthtr-mm.gz")
  }

  /// 虹色letters 6M (six lanes, easier windows of play).
  func testMLTDNijiiroLetters6M() throws {
    try checkMLTDChart("mltd-nijile-6m.gz")
  }

  /// わたしは花、あなたは太陽 4M: four lanes, many slides.
  func testMLTDWatashiwaHana4M() throws {
    try checkMLTDChart("mltd-wataha-4m.gz")
  }

  private struct Fixture {
    let engine: EnginePlayData
    let level: LevelData
    let options: [Double]
    let skin: Set<EngineResourceID>
    let clips: Set<EngineResourceID>
    let particles: Set<EngineResourceID>

    func runtime() throws -> EnginePlayRuntime {
      try EnginePlayRuntime(engine: engine, level: level, options: options,
        aspectRatio: MLTDEngineIntegrationTests.aspectRatio,
        skinSpriteIDs: skin, effectClipIDs: clips,
        particleEffectIDs: particles)
    }
  }

  private static let aspectRatio = 1.8
  private static let frameRate = 60.0

  private func loadFixture(_ chart: String) throws -> Fixture {
    let root = try XCTUnwrap(FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent("OpenRhythmIntegrationFixtures/mltd")
    let chartURL = root.appendingPathComponent(chart)
    guard FileManager.default.fileExists(atPath: chartURL.path) else {
      throw XCTSkip("Optional cached MLTD fixture \(chart) is not installed.")
    }
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: Data(contentsOf: root.appendingPathComponent("engine.gz")))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: Data(contentsOf: chartURL))
    var resources = [String: Data]()
    for key in ["configuration", "skinData", "skinTexture", "particleData",
      "particleTexture", "effectData", "effectAudio"] {
      resources[key] = try Data(contentsOf: root.appendingPathComponent(key))
    }
    let presentation = RuntimePresentation(resources: resources)
    let assets = try EnginePresentationAssets(engine: engine,
      presentation: presentation)
    let audio = try EngineAudioPlayback(engine: engine,
      presentation: presentation)
    return Fixture(engine: engine, level: level,
      options: assets.configuration.options.map(\.def),
      skin: Set(assets.skin.keys), clips: audio.clipIDs,
      particles: Set(assets.particles.keys))
  }

  private func checkMLTDChart(_ chart: String) throws {
    let fixture = try loadFixture(chart)
    let level = fixture.level
    let runtime = try fixture.runtime()
    XCTAssertGreaterThan(runtime.inputCount, 0)

    // No touches: every note must resolve exactly once (as a miss), and a
    // restart must reproduce the same results.
    let first = try run(runtime, level: level, touches: { _, _ in [] },
      chart: chart)
    XCTAssertEqual(first.count, runtime.inputCount, chart)
    XCTAssertTrue(first.values.allSatisfy { $0 == 0 },
      "\(chart): a no-touch run must miss every note")
    runtime.restart()
    let second = try run(runtime, level: level, touches: { _, _ in [] },
      chart: chart)
    XCTAssertEqual(first, second, "\(chart): restart must replay identically")

    // Simulated perfect play: press, flick and release every note on time.
    let perfectRuntime = try fixture.runtime()
    let script = try perfectScript(level: level, runtime: perfectRuntime)
    var pool = EngineTouchPool<Int>()
    var lastFrame = -1
    let grades = try run(perfectRuntime, level: level, touches: { frame, time in
      if frame != lastFrame {
        if lastFrame >= 0 { pool.nextFrame(at: time - 1 / Self.frameRate) }
        lastFrame = frame
      }
      for event in script[frame] ?? [] {
        pool.receive(key: event.key, samples: [EngineTouchSample(
          position: event.position, time: time,
          timestamp: 100 + time)], started: event.started, ended: event.ended)
      }
      return pool.touches
    }, chart: chart)
    XCTAssertEqual(grades.count, perfectRuntime.inputCount, chart)
    var byGrade = [Int: Int]()
    var failures = [String]()
    for (index, grade) in grades {
      byGrade[grade, default: 0] += 1
      if grade != 1 {
        failures.append("\(level.entities[index].archetype)#\(index)=\(grade)")
      }
    }
    print("MLTD \(chart): \(runtime.inputCount) inputs, perfect-play grades "
      + "\(byGrade.sorted { $0.key < $1.key })")
    XCTAssertTrue(failures.isEmpty,
      "\(chart): not Perfect: \(failures.prefix(20).joined(separator: ", "))")
  }

  /// Runs to the last input, returning each judged entity's grade (Sonolus:
  /// 0 miss, 1 perfect, 2 great, 3 good) and failing on duplicates.
  private func run(_ runtime: EnginePlayRuntime, level: LevelData,
    touches: (Int, Double) -> [EngineTouch], chart: String) throws
    -> [Int: Int] {
    let start = BGMClockMapping(offset: level.bgmOffset).initialChartTime
    var grades = [Int: Int]()
    // Bounded: 600 s of chart time at 60 fps.
    for frame in 0..<36_000 {
      let time = start + Double(frame) / Self.frameRate
      try runtime.update(at: time, touches: touches(frame, time))
      for judgment in runtime.judgments {
        XCTAssertNil(grades[judgment.entityIndex],
          "\(chart): entity \(judgment.entityIndex) judged twice")
        grades[judgment.entityIndex] = judgment.grade
      }
      if runtime.resolvedInputCount == runtime.inputCount { break }
    }
    XCTAssertEqual(runtime.resolvedInputCount, runtime.inputCount,
      "\(chart): not every note resolved")
    return grades
  }

  private struct TouchEvent {
    let key: Int
    let position: EnginePoint
    let started: Bool
    let ended: Bool
  }

  /// Touch events per frame that hit every note of the chart on time. Lane
  /// positions mirror the engine's layout (layout.ts) for this aspect ratio.
  private func perfectScript(level: LevelData, runtime: EnginePlayRuntime)
    throws -> [Int: [TouchEvent]] {
    let lanes = level.entities.first { $0.archetype == "Initialization" }?
      .data.first { $0.name == "lanes" }?.value ?? 6
    let screenW = 2 * Self.aspectRatio
    let laneW = min(screenW * 0.92 / lanes,
      lanes >= 6 ? 0.42 : lanes >= 4 ? 0.56 : 0.8)
    let y = -0.8
    func x(_ lane: Double) -> Double { (lane - (lanes - 1) / 2) * laneW }
    func value(_ entity: LevelEntity, _ name: String) -> Double? {
      entity.data.first { $0.name == name }?.value
    }
    func frame(_ entity: LevelEntity) throws -> Int {
      let beat = try XCTUnwrap(value(entity, "#BEAT"))
      let time = try runtime.host.call(function: "BeatToTime",
        arguments: [beat])
      return Int(ceil(time * Self.frameRate - 1e-9))
    }
    let names = Dictionary(level.entities.enumerated().compactMap {
      index, entity in entity.name.map { ($0, index) }
    }, uniquingKeysWith: { first, _ in first })

    var script = [Int: [TouchEvent]]()
    func add(_ frame: Int, _ event: TouchEvent) {
      script[frame, default: []].append(event)
    }
    func flickOffset(_ direction: Double) -> EnginePoint {
      direction == 0 ? EnginePoint(x: 0, y: 0.15)
        : EnginePoint(x: 0.15 * direction, y: 0)
    }

    for (index, entity) in level.entities.enumerated() {
      switch entity.archetype {
      case "TapNote", "SpecialNote", "FlickNote":
        let f = try frame(entity)
        let lane = entity.archetype == "SpecialNote" ? (lanes - 1) / 2
          : value(entity, "lane") ?? 0
        let p = EnginePoint(x: x(lane), y: y)
        add(f, TouchEvent(key: index, position: p, started: true, ended: false))
        var last = p
        if entity.archetype == "FlickNote" {
          let d = flickOffset(value(entity, "direction") ?? 0)
          last = EnginePoint(x: p.x + d.x, y: p.y + d.y)
          add(f + 1, TouchEvent(key: index, position: last, started: false,
            ended: false))
        }
        add(f + 2, TouchEvent(key: index, position: last, started: false,
          ended: true))
      case "HoldEndNote", "HoldEndFlickNote":
        let headName = try XCTUnwrap(entity.data.first { $0.name == "first" }?.ref)
        let headIndex = try XCTUnwrap(names[headName])
        let head = level.entities[headIndex]
        let p = EnginePoint(x: x(value(head, "lane") ?? 0), y: y)
        add(try frame(head), TouchEvent(key: headIndex, position: p,
          started: true, ended: false))
        let end = try frame(entity)
        var last = p
        if entity.archetype == "HoldEndFlickNote" {
          let d = flickOffset(value(entity, "direction") ?? 0)
          last = EnginePoint(x: p.x + d.x, y: p.y + d.y)
          add(end, TouchEvent(key: headIndex, position: last, started: false,
            ended: false))
        }
        add(end + 1, TouchEvent(key: headIndex, position: last, started: false,
          ended: true))
      default:
        break
      }
    }
    return script
  }
}
