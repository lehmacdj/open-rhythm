import Foundation
import CryptoKit

enum SonolusClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The server URL is invalid."
    case .invalidResponse: "The server returned an invalid response."
    case .httpStatus(let status): "The server returned HTTP \(status)."
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
      queryItems.append(URLQueryItem(name: "type", value: "advanced"))
      queryItems.append(URLQueryItem(name: "keywords", value: query))
    }
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

  func resource(at url: URL, forceReload: Bool = false) async throws -> Data {
    try await requestData(from: url, accept: "*/*", forceReload: forceReload)
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
    if firstPage.pageCount > 1 {
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
    let key = current.songKey(server: server)
    let matching = items.filter { $0.songKey(server: server) == key }
    guard !matching.isEmpty else {
      throw RuntimeBundleError.missingResource("the song's difficulty list")
    }
    for level in matching { variants[level.id] = level }
    return CatalogBuilder.group(levels: Array(variants.values), server: server)
      .first { $0.variants.contains { $0.id == current.id } } ?? song
  }

  private func requestData(
    from url: URL,
    accept: String = "application/json",
    forceReload: Bool = false
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("1.1.2", forHTTPHeaderField: "Sonolus-Version")
    // The explicit response cache owns freshness. A second URLSession cache
    // must never return an old response and give it a new ten-minute lifetime.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let fetchRequest = request
    let fetch: @Sendable () async throws -> Data = { [session] in
      let (data, response) = try await session.data(for: fetchRequest)
      guard let response = response as? HTTPURLResponse else {
        throw SonolusClientError.invalidResponse
      }
      guard 200..<300 ~= response.statusCode else {
        throw SonolusClientError.httpStatus(response.statusCode)
      }
      return data
    }
    guard let cache else { return try await fetch() }
    return try await cache.data(
      at: url, maximumAge: 600,
      forceReload: forceReload, fetch: fetch
    )
  }
}

/// Persistent public responses shared across all client instances. Identical
/// in-flight requests are coalesced; repeated view loads need no network trip.
actor SonolusResponseCache {
  static let shared = SonolusResponseCache()
  private let rootURL: URL
  private var inFlight = [URL: Task<Data, Error>]()
  private let maximumBytes = 256 * 1024 * 1024

  init(rootURL: URL? = nil) {
    self.rootURL = rootURL ?? FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask
    )[0].appendingPathComponent("OpenRhythmResponses", isDirectory: true)
  }

  func data(
    at url: URL, maximumAge: TimeInterval, forceReload: Bool = false,
    fetch: @escaping @Sendable () async throws -> Data
  ) async throws -> Data {
    if let task = inFlight[url] { return try await task.value }
    let key = SHA256.hash(data: Data(url.absoluteString.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let file = rootURL.appendingPathComponent(key)
    if !forceReload,
      let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
      let date = attributes.contentModificationDate,
      Date().timeIntervalSince(date) >= 0,
      Date().timeIntervalSince(date) < maximumAge,
      let data = try? Data(contentsOf: file) {
      return data
    }
    let task = Task { try await fetch() }
    inFlight[url] = task
    defer { inFlight[url] = nil }
    let data = try await task.value
    if data.count <= maximumBytes {
      try? FileManager.default.createDirectory(at: rootURL,
        withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
      trim()
    }
    return data
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
      guard url.lastPathComponent.count == 64,
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
