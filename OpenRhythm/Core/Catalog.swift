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

  var ratings: ClosedRange<Int> {
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
  var minimumRating: Int? = nil
  var maximumRating: Int? = nil

  // Search is deliberately session-only.
  private enum CodingKeys: String, CodingKey {
    case difficulties, sort, minimumRating, maximumRating
  }

  func matchingVariants(in song: CatalogSong) -> [SonolusLevelItem] {
    song.variants.filter { level in
      difficulties.contains(level.difficulty)
        && (minimumRating.map { level.rating >= $0 } ?? true)
        && (maximumRating.map { level.rating <= $0 } ?? true)
    }.sorted {
      if $0.rating != $1.rating { return $0.rating < $1.rating }
      if $0.difficulty != $1.difficulty {
        return $0.difficulty.sortOrder < $1.difficulty.sortOrder
      }
      return $0.id < $1.id
    }
  }

  func apply(to songs: [CatalogSong], locale: Locale = .current)
    -> [CatalogSong]
  {
    let filtered = songs.filter { song in
      !matchingVariants(in: song).isEmpty
        && (query.isEmpty || song.matches(query: query))
    }

    return filtered.sorted { left, right in
      func ordered(_ a: String, _ b: String) -> Bool {
        let comparison = a.localizedStandardCompare(b)
        return comparison == .orderedSame ? left.id < right.id
          : comparison == .orderedAscending
      }
      switch sort {
      case .title:
        return ordered(
          left.title.displayValue(locale: locale),
          right.title.displayValue(locale: locale)
        )
      case .artist:
        return ordered(
          left.artists.displayValue(locale: locale),
          right.artists.displayValue(locale: locale)
        )
      case .difficulty:
        let leftRating = matchingVariants(in: left).first?.rating ?? 0
        let rightRating = matchingVariants(in: right).first?.rating ?? 0
        return leftRating == rightRating
          ? ordered(
            left.title.displayValue(locale: locale),
            right.title.displayValue(locale: locale)
          )
          : leftRating < rightRating
      }
    }
  }

  private func compare(_ left: String, _ right: String) -> Bool {
    left.localizedStandardCompare(right) == .orderedAscending
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
