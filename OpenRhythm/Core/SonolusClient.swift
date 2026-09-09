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
    return try decoder.decode(SonolusLevelList.self, from: data)
  }

  func levelDetails(
    for level: SonolusLevelItem,
    on server: ServerDescriptor,
    locale: Locale = .current
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
    return try await requestData(from: url)
  }

  func resource(at url: URL) async throws -> Data {
    try await requestData(from: url, accept: "*/*")
  }

  func completeSong(_ song: CatalogSong) async throws -> CatalogSong {
    guard let first = song.variants.first else { return song }
    let server = song.server(for: first)
    let key = first.songKey(server: server)
    let query = song.title.displayValue()
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SonolusClientError.invalidResponse
    }
    var variants = Dictionary(song.variants.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first })
    let firstPage = try await levels(on: server, page: 0, query: query)
    // Do not accidentally crawl a whole server if it ignores keyword search.
    guard firstPage.pageCount <= 20 else {
      throw RuntimeBundleError.missingResource("a bounded song difficulty search")
    }
    var found = false
    func merge(_ items: [SonolusLevelItem]) {
      for level in items where level.songKey(server: server) == key {
        found = true
        variants[level.id] = level
      }
    }
    merge(firstPage.items)
    if firstPage.pageCount > 1 {
      for page in 1..<firstPage.pageCount {
        try Task.checkCancellation()
        merge(try await levels(on: server, page: page, query: query).items)
      }
    }
    guard found else {
      throw RuntimeBundleError.missingResource("the song's difficulty list")
    }
    return CatalogBuilder.group(levels: Array(variants.values), server: server)
      .first { $0.variants.contains { $0.id == first.id } } ?? song
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
    if forceReload { request.cachePolicy = .reloadIgnoringLocalCacheData }
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
    let immutable = url.lastPathComponent.count == 40
      && url.lastPathComponent.allSatisfy(\.isHexDigit)
    return try await cache.data(
      at: url, maximumAge: immutable ? 365 * 86_400 : 600,
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
