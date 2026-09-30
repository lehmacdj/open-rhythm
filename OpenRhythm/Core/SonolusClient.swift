import Foundation
import CryptoKit

enum SonolusClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpStatus(Int)
  case missingResourceHash(String)
  case resourceChecksumMismatch(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The server URL is invalid."
    case .invalidResponse: "The server returned an invalid response."
    case .httpStatus(let status): "The server returned HTTP \(status)."
    case .missingResourceHash(let hash):
      "The resource with SHA-1 \(hash) is not cached and has no download URL."
    case .resourceChecksumMismatch(let hash):
      "The resource did not match its advertised SHA-1 (\(hash)). "
        + "It has not been used or cached."
    }
  }
}

actor SonolusClient {
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let cache: SonolusResponseCache?

  init(session: URLSession? = nil, cache: SonolusResponseCache? = nil) {
    self.session = session ?? .shared
    self.cache = cache ?? (session == nil ? .shared : nil)
  }

  func levels(
    on server: ServerDescriptor,
    page: Int,
    query: String = "",
    cursor: String? = nil,
    locale: Locale = .current,
    forceReload: Bool = false
  ) async throws -> SonolusLevelList {
    let language = locale.language.languageCode?.identifier ?? "en"
    var components = URLComponents(
      url: server.baseURL.appendingPathComponent("sonolus/levels/list"),
      resolvingAgainstBaseURL: false
    )
    var queryItems = [
      URLQueryItem(name: "localization", value: language),
      URLQueryItem(name: "page", value: String(page))
    ]
    if !query.isEmpty {
      queryItems.append(URLQueryItem(name: "type", value: "quick"))
      queryItems.append(URLQueryItem(name: "keywords", value: query))
    }
    if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
    components?.queryItems = queryItems

    guard let url = components?.url else {
      throw SonolusClientError.invalidURL
    }

    let data = try await requestData(from: url, forceReload: forceReload)
    var response = try decoder.decode(SonolusLevelList.self, from: data)
    response.fetchedAt = await cache?.storedAt(url) ?? Date()
    return response
  }

  func levelDetails(
    for level: SonolusLevelItem,
    on server: ServerDescriptor,
    locale: Locale = .current,
    forceReload: Bool = false
  ) async throws -> Data {
    let language = locale.language.languageCode?.identifier ?? "en"
    var components = URLComponents(
      url: server.baseURL
        .appendingPathComponent("sonolus/levels")
        .appendingPathComponent(level.name),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "localization", value: language)
    ]
    guard let url = components?.url else {
      throw SonolusClientError.invalidURL
    }
    return try await requestData(from: url, forceReload: forceReload)
  }

  func resource(at url: URL?, expectedSHA1: String? = nil,
    forceReload: Bool = false) async throws -> Data {
    try await requestData(from: url, accept: "*/*", forceReload: forceReload,
      expectedSHA1: expectedSHA1)
  }

  func serverTitle(at baseURL: URL) async throws -> String {
    struct Info: Decodable { let title: LocalizedText }
    let data = try await requestData(from: baseURL.appendingPathComponent("sonolus/info"))
    return try decoder.decode(Info.self, from: data).title.displayValue()
  }

  func completeSong(_ song: CatalogSong, forceReload: Bool = false) async throws -> CatalogSong {
    guard let first = song.variants.first else { return song }
    let server = song.server(for: first)
    let query = song.title.displayValue()
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SonolusClientError.invalidResponse
    }
    var variants = Dictionary(song.variants.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first })
    let firstPage = try await levels(on: server, page: 0, query: query,
      forceReload: forceReload)
    // Do not accidentally crawl a whole server if it ignores keyword search.
    guard firstPage.pageCount <= 20 else {
      throw RuntimeBundleError.missingResource("a bounded song difficulty search")
    }
    var items = firstPage.items
    if firstPage.pageCount < 0 {
      var cursor = firstPage.cursor
      var seen = Set<String>()
      var page = 1
      while let next = cursor {
        guard page < 20, seen.insert(next).inserted else {
          throw RuntimeBundleError.missingResource("a bounded song difficulty search")
        }
        try Task.checkCancellation()
        let response = try await levels(on: server, page: page, query: query,
          cursor: next, forceReload: forceReload)
        guard response.pageCount < 0 else { throw SonolusClientError.invalidResponse }
        items += response.items
        cursor = response.cursor
        page += 1
      }
    } else if firstPage.pageCount > 1 {
      for page in 1..<firstPage.pageCount {
        try Task.checkCancellation()
        items += try await levels(on: server, page: page, query: query,
          forceReload: forceReload).items
      }
    }
    // Music URLs often contain a content hash and change when audio is
    // replaced. A stable chart identity locates the song's current key.
    let current = items.first { $0.id == first.id }
      ?? items.first { variants[$0.id] != nil } ?? first
    let matching = CatalogBuilder.groupedLevels(items, server: server)
      .first { $0.contains { $0.id == current.id } } ?? []
    guard !matching.isEmpty else {
      throw RuntimeBundleError.missingResource("the song's difficulty list")
    }
    for level in matching { variants[level.id] = level }
    return CatalogBuilder.group(levels: Array(variants.values), server: server)
      .first { $0.variants.contains { $0.id == current.id } } ?? song
  }

  private func requestData(
    from url: URL?,
    accept: String = "application/json",
    forceReload: Bool = false,
    expectedSHA1: String? = nil
  ) async throws -> Data {
    let hash = try expectedSHA1.map(ContentAddress.normalizedSHA1)
    let fetch: @Sendable () async throws -> Data = { [session] in
      guard let url else {
        if let hash { throw SonolusClientError.missingResourceHash(hash) }
        throw SonolusClientError.invalidURL
      }
      guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        url.host?.isEmpty == false else { throw SonolusClientError.invalidURL }
      var request = URLRequest(url: url)
      request.timeoutInterval = 60
      request.setValue(accept, forHTTPHeaderField: "Accept")
      request.setValue("1.1.2", forHTTPHeaderField: "Sonolus-Version")
      // Our explicit cache owns freshness and content verification.
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw SonolusClientError.invalidResponse
      }
      guard 200..<300 ~= response.statusCode else {
        throw SonolusClientError.httpStatus(response.statusCode)
      }
      return data
    }
    guard let cache else {
      let data = try await fetch()
      if let hash, data.sha1Hex != hash {
        throw SonolusClientError.resourceChecksumMismatch(hash)
      }
      return data
    }
    return try await cache.data(
      at: url, maximumAge: 600,
      forceReload: forceReload, expectedSHA1: hash, fetch: fetch
    )
  }
}

/// Persistent public responses shared across all client instances. Identical
/// in-flight requests are coalesced; repeated view loads need no network trip.
/// Metadata reloads bypass stored URL responses but join active URL fetches.
/// Hashed resources are verified and keyed/coalesced by content identity, not
/// URL or age. Neither mechanism is an atomic snapshot of a changing catalog.
actor SonolusResponseCache {
  static let shared = SonolusResponseCache()
  private let rootURL: URL
  private var inFlight = [String: Task<Data, Error>]()
  private let maximumBytes = 256 * 1024 * 1024

  init(rootURL: URL? = nil) {
    self.rootURL = rootURL ?? FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask
    )[0].appendingPathComponent("OpenRhythmResponses", isDirectory: true)
  }

  func data(
    at url: URL?, maximumAge: TimeInterval, forceReload: Bool = false,
    expectedSHA1: String? = nil,
    fetch: @escaping @Sendable () async throws -> Data
  ) async throws -> Data {
    let hash = try expectedSHA1.map(ContentAddress.normalizedSHA1)
    let urlKey = url.map { Data($0.absoluteString.utf8).sha256Hex }
    guard let key = hash ?? urlKey else { throw SonolusClientError.invalidURL }
    // Content identity coalesces aliases, but never joins a different hash
    // or an unverified URL request that happens to use the same address.
    if let task = inFlight[key] { return try await task.value }
    let file = rootURL.appendingPathComponent(key)
    if let hash {
      // Verified content is immutable. A refresh fetches metadata, not the
      // same known bytes again. Also migrate a matching legacy URL-cache hit.
      for candidate in [key, urlKey].compactMap({ $0 }) {
        if let data = try? Data(contentsOf: rootURL.appendingPathComponent(candidate)),
          data.sha1Hex == hash {
          if candidate != key { store(data, at: file) }
          return data
        }
      }
    } else if !forceReload,
      let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
      let date = attributes.contentModificationDate,
      Date().timeIntervalSince(date) >= 0,
      Date().timeIntervalSince(date) < maximumAge,
      let data = try? Data(contentsOf: file) {
      return data
    }
    let task = Task {
      let data = try await fetch()
      if let hash, data.sha1Hex != hash {
        throw SonolusClientError.resourceChecksumMismatch(hash)
      }
      return data
    }
    inFlight[key] = task
    defer { inFlight[key] = nil }
    let data = try await task.value
    store(data, at: file)
    return data
  }

  private func store(_ data: Data, at file: URL) {
    guard data.count <= maximumBytes else { return }
    try? FileManager.default.createDirectory(at: rootURL,
      withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
    trim()
  }

  func storedAt(_ url: URL) -> Date? {
    let key = SHA256.hash(data: Data(url.absoluteString.utf8))
      .map { String(format: "%02x", $0) }.joined()
    return (try? rootURL.appendingPathComponent(key).resourceValues(
      forKeys: [.contentModificationDateKey]))?.contentModificationDate
  }

  private func trim() {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: rootURL, includingPropertiesForKeys: Array(keys)
    ) else { return }
    let entries = files.compactMap { url -> (URL, Int, Date)? in
      guard [40, 64].contains(url.lastPathComponent.count),
        url.lastPathComponent.allSatisfy(\.isHexDigit),
        let values = try? url.resourceValues(forKeys: keys) else { return nil }
      return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var size = entries.reduce(0) { $0 + $1.1 }
    for (url, bytes, _) in entries where size > maximumBytes {
      try? FileManager.default.removeItem(at: url)
      size -= bytes
    }
  }
}
