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

/// Saved plays, newest first. Index entries this version can't decode are
/// counted instead of hiding the rest of the history.
struct PlayHistory: Sendable {
  var results: [PlayResult]
  var unreadableCount: Int
}

actor ResultStore {
  static let shared = ResultStore()

  /// Every entry keeps its exact JSON, and only an added or replaced entry is
  /// encoded afresh. Rewriting the index thus never discards entries, or
  /// fields of entries, that a newer or repaired version could read.
  private struct IndexEntry {
    let raw: Data
    /// Nil when this version can't decode the entry.
    let result: PlayResult?
    let levelID: String?
  }

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
    var entries = try indexEntries()
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
    let removed = entries.compactMap(\.result).filter { $0.id == result.id }
    entries.removeAll { $0.result?.id == result.id }
    entries.insert(IndexEntry(raw: try JSONEncoder().encode(summary),
      result: summary, levelID: summary.levelID), at: 0)
    // New plays must not evict historical results or their timing payloads.
    // Only a replacement of the same result ID supersedes an old payload.
    let indexData = Self.encodeIndex(entries)
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
    let retained = Set(entries.compactMap(\.result)
      .filter { $0.hasTimingData == true }
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
    try history(forAnyLevelID: levelIDs).results
  }

  func allResults() throws -> [PlayResult] {
    try history().results
  }

  /// Without level IDs, returns every play. An unreadable entry counts toward
  /// the given levels unless it names a different one: it might be theirs.
  func history(forAnyLevelID levelIDs: Set<String>? = nil) throws
    -> PlayHistory {
    var results = [PlayResult]()
    var unreadableCount = 0
    for entry in try indexEntries() {
      if let result = entry.result {
        if levelIDs?.contains(result.levelID) ?? true {
          results.append(result)
        }
      } else {
        if let levelIDs, let levelID = entry.levelID,
          !levelIDs.contains(levelID) { continue }
        unreadableCount += 1
      }
    }
    results.sort {
      $0.playedAt == $1.playedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.playedAt > $1.playedAt
    }
    return PlayHistory(results: results, unreadableCount: unreadableCount)
  }

  private func indexEntries() throws -> [IndexEntry] {
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    // Only a JSON array can be split into entries; rewriting anything else
    // would discard it. UTF-16 and UTF-32 JSON always contain zero bytes.
    guard !data.contains(0),
      try JSONSerialization.jsonObject(with: data) is [Any] else {
      throw CocoaError(.fileReadCorruptFile,
        userInfo: [NSURLErrorKey: fileURL])
    }
    let decoder = JSONDecoder()
    return Self.arrayElements(of: data).map { element in
      if let result = try? decoder.decode(PlayResult.self, from: element) {
        return IndexEntry(raw: element, result: result,
          levelID: result.levelID)
      }
      let object = try? JSONSerialization.jsonObject(with: element,
        options: .fragmentsAllowed)
      return IndexEntry(raw: element, result: nil,
        levelID: (object as? [String: Any])?["levelID"] as? String)
    }
  }

  /// The exact bytes of each element of a valid UTF-8 JSON array.
  private static func arrayElements(of data: Data) -> [Data] {
    let bytes = [UInt8](data)
    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    var elements = [Data]()
    func append(_ range: Range<Int>) {
      var slice = bytes[range]
      while let first = slice.first, whitespace.contains(first) {
        slice = slice.dropFirst()
      }
      while let last = slice.last, whitespace.contains(last) {
        slice = slice.dropLast()
      }
      if !slice.isEmpty { elements.append(Data(slice)) }
    }
    var depth = 0
    var inString = false
    var escaped = false
    var start = 0
    for (index, byte) in bytes.enumerated() {
      if inString {
        if escaped { escaped = false }
        else if byte == UInt8(ascii: "\\") { escaped = true }
        else if byte == UInt8(ascii: "\"") { inString = false }
        continue
      }
      switch byte {
      case UInt8(ascii: "\""): inString = true
      case UInt8(ascii: "["), UInt8(ascii: "{"):
        depth += 1
        if depth == 1 { start = index + 1 }
      case UInt8(ascii: "]"), UInt8(ascii: "}"):
        if depth == 1 { append(start..<index) }
        depth -= 1
      case UInt8(ascii: ",") where depth == 1:
        append(start..<index)
        start = index + 1
      default: break
      }
    }
    return elements
  }

  private static func encodeIndex(_ entries: [IndexEntry]) -> Data {
    var data = Data("[".utf8)
    for (index, entry) in entries.enumerated() {
      if index > 0 { data.append(UInt8(ascii: ",")) }
      data.append(entry.raw)
    }
    data.append(UInt8(ascii: "]"))
    return data
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
