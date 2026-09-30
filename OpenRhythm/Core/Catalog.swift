import Foundation

struct CatalogEngineChoice: Identifiable {
  let id: String
  let name: String

  static func choices(in songs: [CatalogSong]) -> [Self] {
    Dictionary(songs.map { ($0.engineKey, $0.engineName) },
      uniquingKeysWith: { first, _ in first })
      .map { Self(id: $0.key, name: $0.value) }
      .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
  }
}

struct CatalogSong: Identifiable, Hashable, Sendable {
  let id: String
  let server: ServerDescriptor
  let title: LocalizedText
  let artists: LocalizedText
  let coverURL: URL?
  let coverHash: String?
  var artworkReference: RuntimeResourceReference {
    RuntimeResourceReference(url: coverURL, hash: coverHash)
  }
  let variants: [SonolusLevelItem]
  let levelOrigins: [CatalogLevelOrigin]
  let songIdentityKeys: Set<String>

  var engineKey: String {
    variants.first.map { $0.engineKey(server: server(for: $0)) }
      ?? server.preferenceKey
  }

  var engineName: String {
    variants.first?.engine?.title?.displayValue()
      ?? variants.first?.engine?.name ?? server.name
  }

  func server(for level: SonolusLevelItem) -> ServerDescriptor {
    if let exact = levelOrigins.first(where: { $0.matches(level) }) {
      return exact.server
    }

    let matchingIDs = levelOrigins.filter { $0.levelID == level.id }
    return matchingIDs.count == 1 ? matchingIDs[0].server : server
  }

  var difficulties: Set<Difficulty> {
    Set(variants.map(\.difficulty))
  }

  var ratings: ClosedRange<Double> {
    let values = variants.map(\.rating)
    return (values.min() ?? 0)...(values.max() ?? 0)
  }

  let searchIndex: Set<String>

  init(
    id: String, server: ServerDescriptor, title: LocalizedText,
    artists: LocalizedText, coverURL: URL?, variants: [SonolusLevelItem],
    levelOrigins: [CatalogLevelOrigin], coverHash: String? = nil
  ) {
    self.id = id
    self.server = server
    self.title = title
    self.artists = artists
    self.coverURL = coverURL
    self.coverHash = coverHash
    self.variants = variants
    self.levelOrigins = levelOrigins
    songIdentityKeys = Set(variants.flatMap { level in
      let origin = levelOrigins.first { $0.matches(level) }?.server ?? server
      return level.songIdentityKeys(server: origin)
    })
    searchIndex = Set(
      title.values.flatMap { language, value in
        SearchNormalizer.searchableForms(
          of: value,
          languageCode: language
        )
      } + artists.values.flatMap { language, value in
        SearchNormalizer.searchableForms(
          of: value,
          languageCode: language
        )
      }
    )
  }

  func matches(query: String) -> Bool {
    let tokens = SearchNormalizer.tokens(in: query)
    let index = searchIndex
    return tokens.allSatisfy { token in
      index.contains { $0.contains(token) }
    }
  }
}

struct CatalogLevelOrigin: Hashable, Sendable {
  let levelID: String
  let source: String?
  let server: ServerDescriptor

  init(level: SonolusLevelItem, server: ServerDescriptor) {
    levelID = level.id
    source = level.source
    self.server = server
  }

  func matches(_ level: SonolusLevelItem) -> Bool {
    levelID == level.id && source == level.source
  }
}

enum CatalogSort: String, Codable, CaseIterable, Identifiable, Sendable {
  case title
  case artist
  case difficulty

  var id: Self { self }

  var displayName: String {
    rawValue.capitalized
  }
}

struct CatalogFilter: Codable, Equatable, Sendable {
  var query = ""
  var difficulties = Set(Difficulty.allCases)
  var sort = CatalogSort.title
  var minimumRating: Double? = nil
  var maximumRating: Double? = nil

  // Search is deliberately session-only.
  private enum CodingKeys: String, CodingKey {
    case difficulties, sort, minimumRating, maximumRating
  }

  func matchingVariants(in song: CatalogSong) -> [SonolusLevelItem] {
    song.variants.filter(matches).sorted {
      if $0.rating != $1.rating { return $0.rating < $1.rating }
      if $0.difficulty != $1.difficulty {
        return $0.difficulty.sortOrder < $1.difficulty.sortOrder
      }
      return $0.id < $1.id
    }
  }

  func selectedLevelID(in song: CatalogSong, preserving preferred: String? = nil)
    -> String {
    if let preferred, song.variants.contains(where: { $0.id == preferred }) {
      return preferred
    }
    return matchingVariants(in: song).first?.id ?? song.variants.first?.id ?? ""
  }

  func apply(to songs: [CatalogSong], locale: Locale = .current)
    -> [CatalogSong]
  {
    // These keys are immutable for this pass. Resolving them in the sort
    // comparator repeatedly decoded difficulty tags and sorted each song's
    // variants, multiplying main-thread work as the catalog grew.
    let keyed = songs.compactMap { song
      -> (song: CatalogSong, rating: Double, label: String)? in
      var rating: Double?
      for level in song.variants where matches(level) {
        rating = min(rating ?? level.rating, level.rating)
      }
      guard let rating, query.isEmpty || song.matches(query: query) else {
        return nil
      }
      let label = (sort == .artist ? song.artists : song.title)
        .displayValue(locale: locale)
      return (song, rating, label)
    }

    return keyed.sorted { left, right in
      if sort == .difficulty, left.rating != right.rating {
        return left.rating < right.rating
      }
      let comparison = left.label.localizedStandardCompare(right.label)
      return comparison == .orderedSame ? left.song.id < right.song.id
        : comparison == .orderedAscending
    }.map(\.song)
  }

  private func matches(_ level: SonolusLevelItem) -> Bool {
    difficulties.contains(level.difficulty)
      && (minimumRating.map { level.rating >= $0 } ?? true)
      && (maximumRating.map { level.rating <= $0 } ?? true)
  }
}

enum CatalogBuilder {
  /// A URL+hash locator bridges URL-only and hash-only aliases. Keep this
  /// relation scoped to the engine and never infer an alias from title alone.
  static func groupedLevels(_ levels: [SonolusLevelItem],
    server: ServerDescriptor) -> [[SonolusLevelItem]] {
    groupedIndices(levels.map { $0.songIdentityKeys(server: server) })
      .map { $0.map { levels[$0] } }
  }

  private static func groupedIndices(_ keys: [[String]]) -> [[Int]] {
    var parents = Array(keys.indices)
    func root(_ index: Int) -> Int {
      var current = index
      while parents[current] != current {
        parents[current] = parents[parents[current]]
        current = parents[current]
      }
      return current
    }
    var aliases = [String: Int]()
    for (index, identities) in keys.enumerated() {
      for key in identities {
        if let previous = aliases[key] {
          let a = root(index), b = root(previous)
          parents[max(a, b)] = min(a, b)
        } else { aliases[key] = index }
      }
    }
    var groups = [[Int]]()
    var positions = [Int: Int]()
    for index in keys.indices {
      let key = root(index)
      if let position = positions[key] { groups[position].append(index) }
      else {
        positions[key] = groups.count
        groups.append([index])
      }
    }
    return groups
  }

  static func merge(songs: [CatalogSong], levels: [SonolusLevelItem],
    server: ServerDescriptor
  ) -> [CatalogSong] {
    let incoming = Dictionary(levels.map { ($0.id, $0) },
      uniquingKeysWith: { _, newest in newest })
    // Removing an alias can split an existing song; only that uncommon case
    // needs a chart-level regroup. Additions can treat old groups as units.
    for song in songs {
      for previous in song.variants {
        guard let updated = incoming[previous.id] else { continue }
        let oldKeys = Set(previous.songIdentityKeys(server: server))
        if !oldKeys.isSubset(of: Set(updated.songIdentityKeys(server: server))) {
          return regroup(songs: songs, levels: Array(incoming.values), server: server)
        }
      }
    }
    let added = Array(incoming.values)
    let keys = songs.map { Array($0.songIdentityKeys) }
      + added.map { $0.songIdentityKeys(server: server) }
    var reserved = Set(songs.map(\.id))
    return groupedIndices(keys).map { indices in
      if indices.count == 1, let index = indices.first, index < songs.count {
        return songs[index]
      }
      let previous = indices.filter { $0 < songs.count }.map { songs[$0] }
      let fresh = indices.filter { $0 >= songs.count }.map { added[$0 - songs.count] }
      let variants = Dictionary((previous.flatMap(\.variants) + fresh).map { ($0.id, $0) },
        uniquingKeysWith: { _, newest in newest })
      let ordered = ordered(Array(variants.values))
      let oldID = previous.map(\.id).min()
      var id = oldID ?? "\(server.id):\(songKey(ordered, server: server))"
      if oldID == nil {
        while reserved.contains(id) { id += "\u{0}" + ordered[0].id }
        reserved.insert(id)
      }
      return makeSong(ordered, server: server, id: id)
    }
  }

  private static func regroup(songs: [CatalogSong], levels: [SonolusLevelItem],
    server: ServerDescriptor) -> [CatalogSong] {
    var variants = Dictionary(songs.flatMap(\.variants).map { ($0.id, $0) },
      uniquingKeysWith: { _, newest in newest })
    for level in levels { variants[level.id] = level }
    let owners = Dictionary(songs.flatMap { song in
      song.variants.map { ($0.id, song) }
    }, uniquingKeysWith: { first, _ in first })
    let plans = groupedLevels(Array(variants.values), server: server).map { group in
      let ids = Set(group.map(\.id))
      let previous = group.compactMap { owners[$0.id] }.filter {
        $0.variants.first.map { ids.contains($0.id) } == true
      }.min { $0.id < $1.id }
      return (group, previous)
    }
    var reserved = Set(plans.compactMap { $0.1?.id })
    return plans.map { group, previous in
      // Reuse unchanged search indices. Alias discovery can merge rows, but
      // adding a locator to an existing song must not replace its row ID.
      if let previous, previous.variants.count == group.count,
        previous.variants.allSatisfy({ variants[$0.id] == $0 }) { return previous }
      let ordered = ordered(group)
      var id = previous?.id ?? "\(server.id):\(songKey(ordered, server: server))"
      if previous == nil {
        // A metadata refresh may split a prior group. Its original row ID
        // belongs to only the component containing its original first chart.
        while reserved.contains(id) { id += "\u{0}" + ordered[0].id }
        reserved.insert(id)
      }
      return makeSong(ordered, server: server, id: id)
    }
  }

  static func group(
    levels: [SonolusLevelItem],
    server: ServerDescriptor
  ) -> [CatalogSong] {
    groupedLevels(levels, server: server).map {
      makeSong(ordered($0), server: server)
    }
  }

  private static func ordered(_ variants: [SonolusLevelItem]) -> [SonolusLevelItem] {
    variants.sorted {
      if $0.difficulty.sortOrder == $1.difficulty.sortOrder {
        return $0.rating == $1.rating ? $0.id < $1.id : $0.rating < $1.rating
      }
      return $0.difficulty.sortOrder < $1.difficulty.sortOrder
    }
  }

  static func songKey(_ levels: [SonolusLevelItem], server: ServerDescriptor) -> String {
    let urlBearing = levels.filter {
      $0.bgm.resolved(against: $0.resourceBaseURL(server: server)) != nil
    }
    return (urlBearing.isEmpty ? levels : urlBearing)
      .map { $0.songKey(server: server) }.min()!
  }

  private static func makeSong(_ ordered: [SonolusLevelItem],
    server: ServerDescriptor, id: String? = nil) -> CatalogSong {
    let first = ordered[0]
    return CatalogSong(
      id: id ?? "\(server.id):\(songKey(ordered, server: server))",
      server: server,
      title: first.title,
      artists: first.artists,
      coverURL: first.cover.resolved(against: first.resourceBaseURL(server: server)),
      variants: ordered,
      levelOrigins: ordered.map {
        CatalogLevelOrigin(level: $0, server: server)
      }, coverHash: first.cover.hash
    )
  }
}

/// Keeps artwork's content identity through cache and Downloads lookup.
/// Image decoding stays in the view's background preparation task.
struct CatalogArtworkLoader: Sendable {
  var client = SonolusClient()
  var offlineStore = OfflineStore.shared

  func data(for reference: RuntimeResourceReference) async throws -> Data {
    let hash = try reference.hash.map(ContentAddress.normalizedSHA1)
    if let url = reference.url, url.isFileURL {
      let bytes = try await Task.detached(priority: .utility) {
        try Data(contentsOf: url)
      }.value
      if let hash, bytes.sha1Hex != hash {
        throw SonolusClientError.resourceChecksumMismatch(hash)
      }
      return bytes
    }
    if let hash, let bytes = try await offlineStore.cachedResource(expectedSHA1: hash) {
      return bytes
    }
    return try await client.resource(at: reference.url, expectedSHA1: hash)
  }
}
