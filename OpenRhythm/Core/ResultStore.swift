import Foundation

struct PlayResult: Codable, Identifiable, Sendable {
  let id: UUID
  let levelID: String
  let title: String
  let difficulty: Difficulty
  let rating: Int
  let playedAt: Date
  let maxCombo: Int
  let perfect: Int
  let great: Int
  let good: Int
  let miss: Int
  var noteTimings: [NoteTiming]? = nil
  var duration: Double? = nil
  var hasTimingData: Bool? = nil
  var timingID: UUID? = nil

  /// Derived, never stored: every note earns exactly one judgement, so the
  /// counts carry the note total too. Results written before scoring was
  /// normalized read back on today's scale, and a change to the weights
  /// rescales history rather than stranding it.
  var score: Int {
    let counts: [NoteJudgement: Int] = [
      .perfect: perfect, .great: great, .good: good, .miss: miss
    ]
    return NoteJudgement.score(
      for: counts, noteCount: counts.values.reduce(0, +)
    )
  }
}

actor ResultStore {
  static let shared = ResultStore()

  private let fileManager: FileManager
  private let fileURL: URL
  private let maximumResults: Int

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    maximumResults: Int = 500
  ) {
    self.fileManager = fileManager
    self.maximumResults = max(1, maximumResults)
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
    var summary = result
    let payload = try result.noteTimings.map { try JSONEncoder().encode($0) }
    if payload != nil {
      summary.noteTimings = nil
      summary.hasTimingData = true
      summary.timingID = UUID()
    }
    var removed = values.filter { $0.id == result.id }
    values.removeAll { $0.id == result.id }
    values.insert(summary, at: 0)
    removed.append(contentsOf: values.dropFirst(maximumResults))
    values = Array(values.prefix(maximumResults))
    let indexData = try JSONEncoder().encode(values)
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // Immutable payload versions keep an old result intact if its replacement
    // index fails. The atomic index write is the transaction's commit point.
    let newURL = payload.flatMap { _ in summary.timingID.map(timingURL) }
    if let payload, let newURL {
      try fileManager.createDirectory(at: newURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try payload.write(to: newURL, options: [.atomic])
    }
    do {
      try indexData.write(to: fileURL, options: [.atomic])
    } catch {
      if let newURL { try? fileManager.removeItem(at: newURL) }
      throw error
    }
    // Remove payloads only after the replacement index is safely persisted.
    let retained = Set(values.filter { $0.hasTimingData == true }
      .map { $0.timingID ?? $0.id })
    for old in removed where old.hasTimingData == true {
      let id = old.timingID ?? old.id
      if !retained.contains(id) {
        try? fileManager.removeItem(at: timingURL(for: id))
      }
    }
  }

  func noteTimings(for result: PlayResult) throws -> [NoteTiming]? {
    if let embedded = result.noteTimings { return embedded }
    guard result.hasTimingData == true else { return nil }
    return try JSONDecoder().decode([NoteTiming].self,
      from: Data(contentsOf: timingURL(for: result.timingID ?? result.id)))
  }

  private func timingURL(for id: UUID) -> URL {
    fileURL.deletingLastPathComponent()
      .appendingPathComponent("ResultTimings", isDirectory: true)
      .appendingPathComponent(id.uuidString + ".json")
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
