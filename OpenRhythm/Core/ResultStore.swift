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
  var level: SonolusLevelItem? = nil
  var server: ServerDescriptor? = nil
  var engineScore: Int? = nil
  var scoreMode: String? = nil

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
