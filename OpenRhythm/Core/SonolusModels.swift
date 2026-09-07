import Foundation

struct ResourceLocator: Codable, Hashable, Sendable {
  let hash: String?
  let url: String?

  func resolved(against baseURL: URL) -> URL? {
    guard let url, !url.isEmpty else {
      return nil
    }

    if let absoluteURL = URL(string: url), absoluteURL.scheme != nil {
      return absoluteURL
    }

    let baseDirectory = baseURL.appendingPathComponent("")
    let relativePath = url.hasPrefix("/") ? String(url.dropFirst()) : url
    return URL(string: relativePath, relativeTo: baseDirectory)?.absoluteURL
  }
}

struct SonolusTag: Codable, Hashable, Sendable {
  let title: String
}

struct SonolusLevelItem: Codable, Hashable, Identifiable, Sendable {
  let name: String
  let source: String?
  let version: Int
  let rating: Int
  let title: LocalizedText
  let artists: LocalizedText
  let author: String
  let tags: [SonolusTag]
  let cover: ResourceLocator
  let bgm: ResourceLocator
  let data: ResourceLocator

  var id: String { name }

  var difficulty: Difficulty {
    Difficulty(tags: tags)
  }

  func resultKey(server: ServerDescriptor) -> String {
    let origin = source ?? server.baseURL.absoluteString
    return "\(origin)\u{0}\(id)"
  }

  func songKey(server: ServerDescriptor) -> String {
    if let bgmURL = bgm.resolved(against: server.baseURL) {
      return bgmURL.absoluteString
    }

    return SearchNormalizer.normalize(
      title.searchValues.joined(separator: " ")
        + "\u{0}"
        + artists.searchValues.joined(separator: " ")
    )
  }
}

struct SonolusLevelList: Codable, Sendable {
  let pageCount: Int
  let items: [SonolusLevelItem]
}

enum Difficulty: String, CaseIterable, Codable, Hashable, Sendable {
  case easy
  case normal
  case hard
  case expert
  case master
  case unknown

  init(tags: [SonolusTag]) {
    let value = tags.map(\.title).joined(separator: " ").lowercased()
    self = Self.allCases.first {
      $0 != .unknown && value.contains($0.rawValue)
    } ?? .unknown
  }

  var displayName: String {
    rawValue.capitalized
  }

  var sortOrder: Int {
    switch self {
    case .easy: 0
    case .normal: 1
    case .hard: 2
    case .expert: 3
    case .master: 4
    case .unknown: 5
    }
  }
}
