import XCTest
@testable import OpenRhythm

final class ResultStoreTests: XCTestCase {
  func testStoresAndFiltersResultsByLevel() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let store = ResultStore(rootURL: rootURL)
    let first = result(levelID: "first", score: 12_000)
    let second = result(levelID: "second", score: 8_000)

    try await store.record(first)
    try await store.record(second)

    let values = try await store.results(for: "first")
    XCTAssertEqual(values.map(\.id), [first.id])
    XCTAssertEqual(values[0].score, 12_000)
  }

  private func result(levelID: String, score: Int) -> PlayResult {
    PlayResult(
      id: UUID(),
      levelID: levelID,
      title: "Song",
      difficulty: .easy,
      rating: 1,
      playedAt: Date(),
      score: score,
      maxCombo: 10,
      perfect: 10,
      great: 0,
      good: 0,
      miss: 0
    )
  }
}
