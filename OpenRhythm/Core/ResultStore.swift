import Foundation

struct PlayResult: Codable, Identifiable, Sendable {
  let id: UUID
  let levelID: String
  let title: String
  let difficulty: Difficulty
  let rating: Int
  let playedAt: Date
  let score: Int
  let maxCombo: Int
  let perfect: Int
  let great: Int
  let good: Int
  let miss: Int
}

actor ResultStore {
  static let shared = ResultStore()

  private let fileManager: FileManager
  private let fileURL: URL

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    if let rootURL {
      fileURL = rootURL.appendingPathComponent("Results.json")
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      fileURL = applicationSupport
        .appendingPathComponent("OpenRhythm", isDirectory: true)
        .appendingPathComponent("Results.json")
    }
  }

  func record(_ result: PlayResult) throws {
    var values = try allResults()
    values.insert(result, at: 0)
    if values.count > 500 {
      values.removeLast(values.count - 500)
    }
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(values).write(to: fileURL, options: [.atomic])
  }

  func results(for levelID: String) throws -> [PlayResult] {
    try results(forAnyLevelID: [levelID])
  }

  func results(forAnyLevelID levelIDs: Set<String>) throws -> [PlayResult] {
    try allResults()
      .filter { levelIDs.contains($0.levelID) }
      .sorted { $0.playedAt > $1.playedAt }
  }

  private func allResults() throws -> [PlayResult] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
    return try JSONDecoder().decode(
      [PlayResult].self,
      from: Data(contentsOf: fileURL)
    )
  }
}
