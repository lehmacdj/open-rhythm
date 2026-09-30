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
  let variants: [SonolusLevelItem]
  let levelOrigins: [CatalogLevelOrigin]

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
    levelOrigins: [CatalogLevelOrigin]
  ) {
    self.id = id
    self.server = server
    self.title = title
    self.artists = artists
    self.coverURL = coverURL
    self.variants = variants
    self.levelOrigins = levelOrigins
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
  static func merge(songs: [CatalogSong], levels: [SonolusLevelItem],
    server: ServerDescriptor
  ) -> [CatalogSong] {
    var byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
    for (key, incoming) in Dictionary(grouping: levels, by: { $0.songKey(server: server) }) {
      let id = "\(server.id):\(key)"
      let previous = byID[id]?.variants ?? []
      let variants = Dictionary((previous + incoming).map { ($0.id, $0) },
        uniquingKeysWith: { _, newest in newest })
      // Re-index only songs touched by this page, not the whole loaded catalog.
      byID[id] = group(levels: Array(variants.values), server: server).first
    }
    return Array(byID.values)
  }

  static func group(
    levels: [SonolusLevelItem],
    server: ServerDescriptor
  ) -> [CatalogSong] {
    Dictionary(grouping: levels) { $0.songKey(server: server) }
      .map { key, variants in
        let ordered = variants.sorted {
          if $0.difficulty.sortOrder == $1.difficulty.sortOrder {
            return $0.rating < $1.rating
          }
          return $0.difficulty.sortOrder < $1.difficulty.sortOrder
        }
        let first = ordered[0]
        return CatalogSong(
          id: "\(server.id):\(key)",
          server: server,
          title: first.title,
          artists: first.artists,
          coverURL: first.cover.resolved(against: server.baseURL),
          variants: ordered,
          levelOrigins: ordered.map {
            CatalogLevelOrigin(level: $0, server: server)
          }
        )
      }
  }
}
