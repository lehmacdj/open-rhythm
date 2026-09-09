import XCTest
@testable import OpenRhythm

final class ResultStoreTests: XCTestCase {
  func testStoresAndFiltersResultsByLevel() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let store = ResultStore(rootURL: rootURL)
    let first = result(levelID: "first", perfect: 10)
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
