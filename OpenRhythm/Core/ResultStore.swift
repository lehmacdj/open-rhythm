import Foundation

/// Detailed payloads stay outside the history index. Decode the old bare sample
/// array as well as the extensible object used for engine result metadata.
struct ResultDetails: Codable, Equatable, Sendable {
  let samples: [NoteTiming]
  let engineBuckets: [EngineResultBucket]?

  init(samples: [NoteTiming], engineBuckets: [EngineResultBucket]? = nil) {
    self.samples = samples
    self.engineBuckets = engineBuckets
  }

  private enum CodingKeys: String, CodingKey { case samples, engineBuckets }

  init(from decoder: any Decoder) throws {
    if let _ = try? decoder.unkeyedContainer() {
      samples = try [NoteTiming](from: decoder)
      engineBuckets = nil
    } else {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      samples = try values.decode([NoteTiming].self, forKey: .samples)
      engineBuckets = try values.decodeIfPresent(
        [EngineResultBucket].self, forKey: .engineBuckets)
    }
  }
}

struct EngineOptionOverride: Codable, Equatable, Sendable {
  let name: String
  let value: String
}

struct PlayResult: Codable, Identifiable, Sendable {
  let id: UUID
  let levelID: String
  let title: String
  let difficulty: Difficulty
  let rating: Double
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
  var level: SonolusLevelItem? = nil
  var server: ServerDescriptor? = nil
  var engineScore: Int? = nil
  var scoreMode: String? = nil
  var finalLife: Double? = nil
  var maximumLife: Double? = nil
  var failed: Bool? = nil
  var modifiedOptions: [EngineOptionOverride]? = nil
  // Older records omit engine miss accuracy. Do not reconstruct this score
  // from their plot samples, which deliberately exclude miss timing values.
  var accuracyScore: Int? = nil
  var playbackTiming: PlaybackTimingReport? = nil
  var engineBuckets: [EngineResultBucket]? = nil

  /// Engine scores depend on note weights and judgement order, so retain the
  /// actual result. Legacy plays lack that information; preserve their prior
  /// flat-count scoring rather than inventing a retrospective engine score.
  var score: Int {
    if let engineScore { return engineScore }
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
    var summary = result
    let payload = try result.noteTimings.map {
      try JSONEncoder().encode(ResultDetails(samples: $0,
        engineBuckets: result.engineBuckets))
    }
    if payload != nil {
      summary.noteTimings = nil
      summary.engineBuckets = nil
      summary.hasTimingData = true
      summary.timingID = UUID()
    }
    let removed = values.filter { $0.id == result.id }
    values.removeAll { $0.id == result.id }
    values.insert(summary, at: 0)
    // New plays must not evict historical results or their timing payloads.
    // Only a replacement of the same result ID supersedes an old payload.
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
    try details(for: result)?.samples
  }

  func details(for result: PlayResult) throws -> ResultDetails? {
    if let embedded = result.noteTimings {
      return ResultDetails(samples: embedded, engineBuckets: result.engineBuckets)
    }
    guard result.hasTimingData == true else { return nil }
    return try JSONDecoder().decode(ResultDetails.self,
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

  func allResults() throws -> [PlayResult] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
    return try JSONDecoder().decode(
      [PlayResult].self,
      from: Data(contentsOf: fileURL)
    ).sorted {
      $0.playedAt == $1.playedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.playedAt > $1.playedAt
    }
  }

  func playedSongs() throws -> [CatalogSong] {
    var seen = Set<String>()
    var byServer = [URL: (server: ServerDescriptor, levels: [SonolusLevelItem])]()
    for result in try allResults() {
      guard let level = result.level, let server = result.server,
        seen.insert(level.resultKey(server: server)).inserted else { continue }
      // Names and user-assigned IDs may change. One server origin must not
      // yield duplicate song rows when its older plays use the old name.
      if byServer[server.baseURL] == nil {
        byServer[server.baseURL] = (server, [])
      }
      byServer[server.baseURL]?.levels.append(level)
    }
    return byServer.values.flatMap { entry in
      CatalogBuilder.group(levels: entry.levels, server: entry.server)
    }
  }
}
