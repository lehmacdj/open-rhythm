import Foundation

struct CatalogSong: Identifiable, Hashable, Sendable {
  let id: String
  let server: ServerDescriptor
  let title: LocalizedText
  let artists: LocalizedText
  let coverURL: URL?
  let variants: [SonolusLevelItem]
  let levelOrigins: [CatalogLevelOrigin]

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

  var searchIndex: Set<String> {
    Set(
      (title.searchValues + artists.searchValues)
        .flatMap(SearchNormalizer.searchableForms)
    )
  }

  func matches(query: String) -> Bool {
    let tokens = SearchNormalizer.tokens(in: query)
    return tokens.allSatisfy { token in
      searchIndex.contains { $0.contains(token) }
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

enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
  case title
  case artist
  case difficulty

  var id: Self { self }

  var displayName: String {
    rawValue.capitalized
  }
}

struct CatalogFilter: Sendable {
  var query = ""
  var difficulties = Set(Difficulty.allCases.filter { $0 != .unknown })
  var sort = CatalogSort.title

  func apply(to songs: [CatalogSong], locale: Locale = .current)
    -> [CatalogSong]
  {
    let filtered = songs.filter { song in
      !song.difficulties.isDisjoint(with: difficulties)
        && (query.isEmpty || song.matches(query: query))
    }

    return filtered.sorted { left, right in
      switch sort {
      case .title:
        return compare(
          left.title.displayValue(locale: locale),
          right.title.displayValue(locale: locale)
        )
      case .artist:
        return compare(
          left.artists.displayValue(locale: locale),
          right.artists.displayValue(locale: locale)
        )
      case .difficulty:
        let leftRating = left.variants.map(\.rating).min() ?? 0
        let rightRating = right.variants.map(\.rating).min() ?? 0
        return leftRating == rightRating
          ? compare(
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
