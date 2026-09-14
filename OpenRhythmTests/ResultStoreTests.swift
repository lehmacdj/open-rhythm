import XCTest
@testable import OpenRhythm

final class ResultStoreTests: XCTestCase {
  func testHeatmapKeepsZeroCenteredAndMirrorsSignedInputs() {
    var early = EngineErrorHeatmap()
    var late = EngineErrorHeatmap()
    for index in 0..<100 {
      let offset = Double(index % 7) / 1000
      early.record(NoteTiming(id: index, songTime: Double(index), noteType: "Tap",
        judgement: .perfect, accuracy: -offset))
      late.record(NoteTiming(id: index, songTime: Double(index), noteType: "Tap",
        judgement: .perfect, accuracy: offset))
    }
    XCTAssertEqual(early.snapshot.count, 100)
    XCTAssertEqual(early.snapshot.meanMS!, -late.snapshot.meanMS!, accuracy: 1e-10)
    for (left, right) in zip(early.snapshot.cells, late.snapshot.cells.reversed()) {
      XCTAssertEqual(left.total, right.total, accuracy: 1e-10)
    }
    var exact = EngineErrorHeatmap()
    exact.record(NoteTiming(id: 1, songTime: 0, noteType: "Tap",
      judgement: .perfect, accuracy: 0))
    let snapshot = exact.snapshot
    XCTAssertEqual(snapshot.cells.count, 129)
    XCTAssertEqual(snapshot.cells[64].total, snapshot.peak)
    XCTAssertEqual(snapshot.meanMS, 0)
    XCTAssertEqual(snapshot.text, "+0.0 ms")
    XCTAssertNil(EngineErrorHeatmap().snapshot.meanMS)
  }

  func testHeatmapExcludesAutomaticTicksAndMissesWithoutBinningInputs() {
    var map = EngineErrorHeatmap()
    let excluded: [(String, NoteJudgement, Double?)] = [
      ("NormalTickNote", .perfect, 0), ("SlideTickNote", .perfect, 0),
      ("Tap", .miss, 0), ("Tap", .perfect, nil),
      ("Tap", .good, .infinity), ("Tap", .great, .nan), ("Tap", .good, 3601)
    ]
    for (type, grade, error) in excluded {
      XCTAssertFalse(map.record(NoteTiming(id: 0, songTime: 0,
        noteType: type, judgement: grade, accuracy: error)))
    }
    XCTAssertEqual(map.snapshot.count, 0)
    XCTAssertEqual(map.snapshot.peak, 0)
    var neighbor = EngineErrorHeatmap()
    map.record(NoteTiming(id: 1, songTime: 0, noteType: "Hold End",
      judgement: .great, accuracy: 0.0001))
    neighbor.record(NoteTiming(id: 1, songTime: 0, noteType: "Hold End",
      judgement: .great, accuracy: 0.0002))
    XCTAssertNotEqual(map.snapshot.cells, neighbor.snapshot.cells,
      "Nearby inputs must not be rounded into a shared bin")
    XCTAssertEqual(map.snapshot.cells.map(\.perfect).max(), 0)
    XCTAssertGreaterThan(map.snapshot.cells[64].great, 0)
  }

  func testHeatmapRangeGrowthRetainsEveryEarlierInputWithBoundedStorage() {
    var map = EngineErrorHeatmap()
    for index in 0..<10_000 {
      map.record(NoteTiming(id: index, songTime: Double(index), noteType: "Tap",
        judgement: .perfect, accuracy: 0))
    }
    map.record(NoteTiming(id: 10_000, songTime: 10_000, noteType: "Flick",
      judgement: .good, accuracy: 0.2))
    let snapshot = map.snapshot
    XCTAssertEqual(snapshot.count, 10_001)
    XCTAssertEqual(snapshot.limitMS, 400)
    XCTAssertEqual(snapshot.cells.count, 129)
    XCTAssertEqual(snapshot.cells[64].perfect,
      10_000 * 0.75 / (snapshot.limitMS / 32), accuracy: 1e-6)
    XCTAssertGreaterThan(snapshot.cells.map(\.good).max() ?? 0, 0)
    map.record(NoteTiming(id: 10_001, songTime: 10_001, noteType: "Tap",
      judgement: .great, accuracy: -3600))
    XCTAssertGreaterThan(map.snapshot.limitMS, 3_600_000)
    XCTAssertEqual(map.snapshot.cells.count, 129)
    XCTAssertTrue(map.snapshot.cells.allSatisfy { $0.total.isFinite })
  }

  func testAccuracyScoreSurvivesHistoryWithoutInventingLegacyValues() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var play = result(levelID: "chart", perfect: 3)
    play.accuracyScore = 975_000
    try await ResultStore(rootURL: root).record(play)
    let reopened = try await ResultStore(rootURL: root).allResults()
    XCTAssertEqual(reopened.first?.accuracyScore, 975_000)
    let data = try JSONEncoder().encode(result(levelID: "legacy", perfect: 1))
    XCTAssertNil(try JSONDecoder().decode(PlayResult.self, from: data).accuracyScore)
  }

  func testModifiedEngineOptionsSurviveHistoryPersistence() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var play = result(levelID: "chart", perfect: 3)
    play.modifiedOptions = [EngineOptionOverride(name: "Mirror", value: "On"),
      EngineOptionOverride(name: "Speed", value: "150%")]
    try await ResultStore(rootURL: root).record(play)
    let reopened = try await ResultStore(rootURL: root).allResults()
    XCTAssertEqual(reopened.first?.modifiedOptions, play.modifiedOptions)
    XCTAssertNil(result(levelID: "legacy", perfect: 1).modifiedOptions)
  }
  func testContinuousDensityCentersZeroAndExcludesOnlyHoldTicks() throws {
    let samples = (0..<100).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "TransientHiddenTickNote",
        judgement: .perfect, accuracy: 0)
    } + [NoteTiming(id: 100, songTime: 101, noteType: "TapNote",
      judgement: .perfect, accuracy: 0)]
    let stats = PlayStatistics(samples: samples)
    XCTAssertEqual(stats.distributionCount, 1)
    XCTAssertEqual(stats.excludedHoldTicks, 100)
    XCTAssertEqual(stats.samples.count, 101, "Scatterplot and score keep hold ticks")
    let peak = try XCTUnwrap(stats.density.max { $0.density < $1.density })
    XCTAssertEqual(peak.timingMS, 0)
    for index in 0..<stats.density.count {
      XCTAssertEqual(stats.density[index].density,
        stats.density[stats.density.count - 1 - index].density, accuracy: 1e-10)
    }
    XCTAssertTrue(PlayStatistics(samples: samples,
      noteType: "TransientHiddenTickNote").density.isEmpty)
    let flick = NoteTiming(id: 1, songTime: 1, noteType: "SlideEndFlickNote",
      judgement: .perfect, accuracy: 0)
    XCTAssertEqual(PlayStatistics(samples: [flick]).distributionCount, 1)
  }

  func testDensityRetainsJudgementMassAndTranslationWithoutBins() {
    let samples = (0..<40).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "TapNote",
        judgement: $0 < 30 ? .perfect : .great, accuracy: Double($0 - 20) * 0.001)
    }
    let stats = PlayStatistics(samples: samples)
    for (grade, expected) in [(NoteJudgement.perfect, 30.0), (.great, 10)] {
      let curve = stats.density.filter { $0.judgement == grade }
      let integral = zip(curve, curve.dropFirst()).reduce(0.0) {
        $0 + ($1.0.density + $1.1.density) / 2 * ($1.1.timingMS - $1.0.timingMS)
      }
      XCTAssertEqual(integral, expected, accuracy: 0.03)
    }
  }

  func testDensityDoesNotLoseNarrowOutlierPeaks() {
    let samples = (0..<100).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "TapNote",
        judgement: .perfect, accuracy: $0.isMultiple(of: 2) ? -0.0001 : 0.0001)
    } + [NoteTiming(id: 100, songTime: 100, noteType: "TapNote",
      judgement: .great, accuracy: 1)]
    let curve = PlayStatistics(samples: samples).density.filter { $0.judgement == .great }
    XCTAssertGreaterThan(curve.first { $0.timingMS == 1000 }?.density ?? 0, 0)
    let integral = zip(curve, curve.dropFirst()).reduce(0.0) {
      $0 + ($1.0.density + $1.1.density) / 2 * ($1.1.timingMS - $1.0.timingMS)
    }
    XCTAssertEqual(integral, 1, accuracy: 0.03)
  }

  func testDensityPreservesInteriorSupportZerosAndBoundedRenderingWork() {
    let samples = (0..<100).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "TapNote",
        judgement: .perfect, accuracy: $0.isMultiple(of: 2) ? -0.0001 : 0.0001)
    } + [NoteTiming(id: 100, songTime: 100, noteType: "TapNote",
      judgement: .great, accuracy: 0.03034),
      NoteTiming(id: 101, songTime: 101, noteType: "TapNote",
        judgement: .good, accuracy: 1)]
    let curve = PlayStatistics(samples: samples).density.filter { $0.judgement == .great }
    let integral = zip(curve, curve.dropFirst()).reduce(0.0) {
      $0 + ($1.0.density + $1.1.density) / 2 * ($1.1.timingMS - $1.0.timingMS)
    }
    XCTAssertEqual(integral, 1, accuracy: 0.03)
    let many = (0..<10000).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "TapNote",
        judgement: .perfect, accuracy: Double($0) / 50000)
    }
    XCTAssertLessThan(PlayStatistics(samples: many).density.count, 1024)
  }
  func testEngineLifeAndFailureSurviveHistoryRoundTrip() throws {
    var play = result(levelID: "life", perfect: 9)
    play.finalLife = 0
    play.maximumLife = 2000
    play.failed = true
    let decoded = try JSONDecoder().decode(PlayResult.self,
      from: JSONEncoder().encode(play))
    XCTAssertEqual(decoded.finalLife, 0)
    XCTAssertEqual(decoded.maximumLife, 2000)
    XCTAssertEqual(decoded.failed, true)
    let legacy = try JSONDecoder().decode(PlayResult.self,
      from: JSONEncoder().encode(result(levelID: "legacy", perfect: 1)))
    XCTAssertNil(legacy.failed)
    XCTAssertNil(legacy.finalLife)
  }
  func testEngineScoreIsPreservedInsteadOfRederivedFromFlatCounts() throws {
    var play = result(levelID: "weighted", perfect: 9)
    play.engineScore = 812_345
    play.scoreMode = "Weighted Combo (Sekai Standard)"
    let decoded = try JSONDecoder().decode(PlayResult.self,
      from: JSONEncoder().encode(play))
    XCTAssertEqual(decoded.score, 812_345)
    XCTAssertEqual(decoded.scoreMode, play.scoreMode)
    XCTAssertEqual(decoded.perfect, 9)
  }
  func testGlobalHistoryAndPlayedSongsPreserveOriginsAndDeduplicate() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    let level = SonolusLevelItem(name: "chart", source: nil, version: 1,
      rating: 18, title: LocalizedText("Song"), artists: LocalizedText("Cast"),
      author: "Fixture", tags: [SonolusTag(title: "#HARD")],
      cover: ResourceLocator(hash: nil, url: nil),
      bgm: ResourceLocator(hash: nil, url: "music"),
      data: ResourceLocator(hash: nil, url: "notes"))
    for server in [ServerDescriptor.defaults[0], .suggested[0]] {
      for _ in 0..<2 {
        var play = result(levelID: level.resultKey(server: server), perfect: 10)
        play.level = level
        play.server = server
        try await store.record(play)
      }
    }
    try await store.record(result(levelID: "legacy", perfect: 5))
    let plays = try await store.allResults()
    XCTAssertEqual(plays.count, 5)
    XCTAssertEqual(plays.map(\.playedAt), plays.map(\.playedAt).sorted(by: >))
    let songs = try await store.playedSongs()
    XCTAssertEqual(songs.count, 2)
    XCTAssertTrue(songs.allSatisfy { $0.variants.count == 1 })
    XCTAssertEqual(Set(songs.map(\.server.baseURL)),
      [ServerDescriptor.defaults[0].baseURL, ServerDescriptor.suggested[0].baseURL])
  }

  func testTimingStatisticsFilterAndHistogramPreserveJudgements() {
    let samples = [
      NoteTiming(id: 0, songTime: 1, noteType: "Tap", judgement: .perfect,
        accuracy: -0.01),
      NoteTiming(id: 1, songTime: 2, noteType: "Tap", judgement: .great,
        accuracy: 0.05),
      NoteTiming(id: 2, songTime: 3, noteType: "Flick", judgement: .good,
        accuracy: -0.1),
      NoteTiming(id: 3, songTime: 4, noteType: "Tap", judgement: .miss,
        accuracy: nil)
    ]
    let all = PlayStatistics(samples: samples)
    XCTAssertEqual(all.early, 2)
    XCTAssertEqual(all.late, 1)
    XCTAssertEqual(all.misses, 1)
    XCTAssertEqual(all.meanMS ?? 0, -20, accuracy: 0.001)
    XCTAssertEqual(all.medianMS, -10)
    XCTAssertEqual(all.meanAbsoluteMS ?? 0, 160.0 / 3, accuracy: 0.001)
    XCTAssertEqual(all.standardDeviationMS ?? 0, sqrt(3800), accuracy: 0.001)
    XCTAssertEqual(all.bins.reduce(0) { $0 + $1.count }, 3)
    XCTAssertFalse(all.bins.contains { $0.judgement == .miss })
    let taps = PlayStatistics(samples: samples, noteType: "Tap")
    XCTAssertEqual(taps.samples.count, 3)
    XCTAssertEqual(taps.meanMS, 20)
    XCTAssertEqual(taps.hitRate ?? 0, 2.0 / 3, accuracy: 0.001)
    XCTAssertEqual(taps.bins.map(\.judgement), [.perfect, .great])
    let empty = PlayStatistics(samples: samples, noteType: "Unknown")
    XCTAssertNil(empty.meanMS)
    XCTAssertNil(empty.hitRate)
    XCTAssertTrue(empty.bins.isEmpty)
    XCTAssertGreaterThan(empty.timingLimitMS, 0)
  }

  func testTimingStatisticsExcludeInvalidErrorsWithoutInventingMissTimings() {
    let stats = PlayStatistics(samples: [
      NoteTiming(id: 0, songTime: 1, noteType: "Tap", judgement: .miss,
        accuracy: 0.2),
      NoteTiming(id: 1, songTime: 2, noteType: "Tap", judgement: .perfect,
        accuracy: .nan),
      NoteTiming(id: 2, songTime: 3, noteType: "Tap", judgement: .great,
        accuracy: .greatestFiniteMagnitude)
    ])
    XCTAssertEqual(stats.samples.count, 3)
    XCTAssertTrue(stats.timingsMS.isEmpty)
    XCTAssertTrue(stats.bins.isEmpty)
    XCTAssertEqual(stats.misses, 1)
    XCTAssertNil(stats.standardDeviationMS)
  }

  func testStoresAndFiltersResultsByLevel() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let store = ResultStore(rootURL: rootURL)
    var first = result(levelID: "first", perfect: 10)
    first.noteTimings = (0..<10).map {
      NoteTiming(id: $0, songTime: Double($0), noteType: "Tap",
        judgement: .perfect, accuracy: -0.005)
    }
    first.duration = 12
    let second = result(levelID: "second", perfect: 8)

    try await store.record(first)
    try await store.record(second)

    let values = try await store.results(for: "first")
    XCTAssertEqual(values.map(\.id), [first.id])
    XCTAssertEqual(values[0].score, NoteJudgement.maximumScore)
    XCTAssertEqual(values[0].maxCombo, first.maxCombo)
    XCTAssertEqual(values[0].perfect, first.perfect)
    XCTAssertEqual(values[0].great, first.great)
    XCTAssertEqual(values[0].good, first.good)
    XCTAssertEqual(values[0].miss, first.miss)
    XCTAssertEqual(values[0].title, first.title)
    XCTAssertEqual(values[0].difficulty, first.difficulty)
    XCTAssertEqual(values[0].rating, first.rating)
    XCTAssertNil(values[0].noteTimings, "History queries load only summaries")
    XCTAssertEqual(values[0].hasTimingData, true)
    let timings = try await store.noteTimings(for: values[0])
    XCTAssertEqual(timings, first.noteTimings)
    XCTAssertEqual(values[0].duration, 12)
  }

  func testTimingPayloadRetentionAndMissingDataDoNotBreakHistory() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root, maximumResults: 1)
    var first = result(levelID: "first", perfect: 10)
    first.noteTimings = []
    try await store.record(first)
    let firstHistory = try await store.results(for: "first")
    let firstSummary = try XCTUnwrap(firstHistory.first)
    var second = result(levelID: "second", perfect: 10)
    second.noteTimings = []
    try await store.record(second)
    do {
      _ = try await store.noteTimings(for: firstSummary)
      XCTFail("Evicted result payloads should be removed")
    } catch { }
    let history = try await store.results(for: "second")
    XCTAssertEqual(history.count, 1)
    let url = root.appendingPathComponent("ResultTimings")
      .appendingPathComponent(try XCTUnwrap(history[0].timingID).uuidString + ".json")
    try Data("damaged timing payload".utf8).write(to: url)
    let stillReadable = try await store.results(for: "second")
    XCTAssertEqual(stillReadable.count, 1)
    XCTAssertEqual(stillReadable[0].score, second.score)
  }

  func testFailedReplacementKeepsOriginalSummaryAndTimings() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResultStore(rootURL: root)
    var original = result(levelID: "song", perfect: 10)
    original.duration = 10
    original.noteTimings = [NoteTiming(id: 0, songTime: 1, noteType: "Tap",
      judgement: .perfect, accuracy: 0.001)]
    try await store.record(original)
    var replacement = original
    replacement.duration = .nan
    replacement.noteTimings = []
    do {
      try await store.record(replacement)
      XCTFail("An unencodable replacement must fail")
    } catch { }
    let history = try await store.results(for: "song")
    XCTAssertEqual(history.count, 1)
    XCTAssertEqual(history[0].duration, 10)
    let timings = try await store.noteTimings(for: history[0])
    XCTAssertEqual(timings, original.noteTimings)
    replacement.duration = 11
    try await store.record(replacement)
    let replaced = try await store.results(for: "song")
    XCTAssertEqual(replaced.count, 1)
    XCTAssertEqual(replaced[0].duration, 11)
    XCTAssertNotEqual(replaced[0].timingID, history[0].timingID)
    let newTimings = try await store.noteTimings(for: replaced[0])
    XCTAssertEqual(newTimings, [])
  }

  func testFiltersCurrentAndLegacyLevelIdentities() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let store = ResultStore(rootURL: rootURL)
    let current = result(levelID: "server\u{0}level", perfect: 10)
    let legacy = result(levelID: "level", perfect: 8)
    let unrelated = result(levelID: "other", perfect: 4)

    try await store.record(legacy)
    try await store.record(unrelated)
    try await store.record(current)

    let values = try await store.results(
      forAnyLevelID: ["server\u{0}level", "level"]
    )
    XCTAssertEqual(Set(values.map(\.id)), [current.id, legacy.id])
  }

  func testLegacyStoredScoresAreRederivedFromJudgements() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    try FileManager.default.createDirectory(
      at: rootURL, withIntermediateDirectories: true
    )
    // Written when scores were stored as raw points, before normalization.
    try Data(#"""
      [{"id":"5E2E2E2E-0000-0000-0000-000000000001","levelID":"legacy",
        "title":"Song","difficulty":"easy","rating":1,
        "playedAt":0,"score":3700,"maxCombo":4,
        "perfect":3,"great":1,"good":0,"miss":1}]
      """#.utf8).write(to: rootURL.appendingPathComponent("Results.json"))

    let store = ResultStore(rootURL: rootURL)
    let values = try await store.results(for: "legacy")

    XCTAssertEqual(values.count, 1)
    XCTAssertEqual(values[0].perfect, 3)
    XCTAssertEqual(values[0].score, 740_000, "3.7 of 5 notes' worth")
    XCTAssertNil(values[0].noteTimings)
    XCTAssertNil(values[0].duration)
  }

  private func result(levelID: String, perfect: Int) -> PlayResult {
    PlayResult(
      id: UUID(),
      levelID: levelID,
      title: "Song",
      difficulty: .easy,
      rating: 1,
      playedAt: Date(),
      maxCombo: 10,
      perfect: perfect,
      great: 0,
      good: 0,
      miss: 10 - perfect
    )
  }
}
