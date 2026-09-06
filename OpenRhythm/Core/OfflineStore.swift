import CryptoKit
import Foundation

struct OfflineResource: Codable, Hashable, Sendable {
  let remoteURL: URL
  let objectName: String
  let expectedSHA1: String?
}

struct OfflineLevelManifest: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let server: ServerDescriptor
  let level: SonolusLevelItem
  let itemData: Data
  let resources: [OfflineResource]
  let downloadedAt: Date
}

private struct OfflineResourceDownload: Sendable {
  let resource: OfflineResource
  let data: Data
}

enum OfflineStoreError: LocalizedError {
  case malformedLevelDetails
  case checksumMismatch(URL)

  var errorDescription: String? {
    switch self {
    case .malformedLevelDetails:
      "The server returned malformed level details."
    case .checksumMismatch(let url):
      "The downloaded resource failed verification: \(url.absoluteString)"
    }
  }
}

enum ResourceLocatorCollector {
  static func collect(from data: Data, baseURL: URL) throws
    -> [(url: URL, hash: String?)]
  {
    let object = try JSONSerialization.jsonObject(with: data)
    var resources = [URL: String]()
    visit(object, baseURL: baseURL, resources: &resources)
    return resources.map {
      (url: $0.key, hash: $0.value.isEmpty ? nil : $0.value)
    }
  }

  private static func visit(
    _ value: Any,
    baseURL: URL,
    resources: inout [URL: String]
  ) {
    if let dictionary = value as? [String: Any] {
      let childBaseURL = (dictionary["source"] as? String)
        .flatMap(URL.init(string:)) ?? baseURL
      if let path = dictionary["url"] as? String,
        let url = ResourceLocator(
          hash: dictionary["hash"] as? String,
          url: path
        ).resolved(against: childBaseURL)
      {
        resources[url] = dictionary["hash"] as? String ?? ""
        return
      }

      for child in dictionary.values {
        visit(child, baseURL: childBaseURL, resources: &resources)
      }
    } else if let array = value as? [Any] {
      for child in array {
        visit(child, baseURL: baseURL, resources: &resources)
      }
    }
  }
}

actor OfflineStore {
  static let shared = OfflineStore()

  private let fileManager: FileManager
  private let rootURL: URL
  private let client: SonolusClient

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    client: SonolusClient = SonolusClient()
  ) {
    self.fileManager = fileManager
    self.client = client

    if let rootURL {
      self.rootURL = rootURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.rootURL = applicationSupport.appendingPathComponent(
        "Offline",
        isDirectory: true
      )
    }
  }

  func download(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) async throws -> OfflineLevelManifest {
    let detailsData = try await client.levelDetails(for: level, on: server)
    guard
      let details = try JSONSerialization.jsonObject(with: detailsData)
        as? [String: Any],
      let item = details["item"]
    else {
      throw OfflineStoreError.malformedLevelDetails
    }

    let itemData = try JSONSerialization.data(
      withJSONObject: item,
      options: [.sortedKeys]
    )
    let locators = try ResourceLocatorCollector.collect(
      from: itemData,
      baseURL: server.baseURL
    )

    try prepareDirectories()
    var resources = [OfflineResource]()
    var pending = [(url: URL, hash: String?)]()
    for locator in locators.sorted(by: {
      $0.url.absoluteString < $1.url.absoluteString
    }) {
      if let hash = locator.hash {
        let objectURL = objectsURL.appendingPathComponent(hash)
        if fileManager.fileExists(atPath: objectURL.path) {
          resources.append(
            OfflineResource(
              remoteURL: locator.url,
              objectName: hash,
              expectedSHA1: hash
            )
          )
          continue
        }
      }
      pending.append(locator)
    }

    let downloads = try await downloadResources(pending)
    for download in downloads {
      let objectURL = objectsURL.appendingPathComponent(
        download.resource.objectName
      )
      if !fileManager.fileExists(atPath: objectURL.path) {
        try download.data.write(to: objectURL, options: [.atomic])
      }
      resources.append(download.resource)
    }
    resources.sort { $0.remoteURL.absoluteString < $1.remoteURL.absoluteString }

    let id = Data("\(server.id):\(level.id)".utf8).sha256Hex
    let manifest = OfflineLevelManifest(
      id: id,
      server: server,
      level: level,
      itemData: itemData,
      resources: resources,
      downloadedAt: Date()
    )
    let manifestData = try JSONEncoder.offline.encode(manifest)
    try manifestData.write(
      to: manifestsURL.appendingPathComponent("\(id).json"),
      options: [.atomic]
    )
    return manifest
  }

  func manifests() throws -> [OfflineLevelManifest] {
    guard fileManager.fileExists(atPath: manifestsURL.path) else {
      return []
    }

    return try fileManager.contentsOfDirectory(
      at: manifestsURL,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .map { try Data(contentsOf: $0) }
    .map { try JSONDecoder.offline.decode(OfflineLevelManifest.self, from: $0) }
    .sorted { $0.downloadedAt > $1.downloadedAt }
  }

  func contains(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) -> Bool {
    let id = Data("\(server.id):\(level.id)".utf8).sha256Hex
    return fileManager.fileExists(
      atPath: manifestsURL.appendingPathComponent("\(id).json").path
    )
  }

  func catalogSongs() throws -> [CatalogSong] {
    let entries = try manifests()
    let offlineServer = ServerDescriptor(
      id: "offline",
      name: "Offline",
      baseURL: rootURL
    )
    let grouped = Dictionary(grouping: entries) { manifest in
      manifest.level.songKey(server: manifest.server)
    }

    return grouped.map { key, manifests in
      let ordered = manifests.sorted {
        if $0.level.difficulty.sortOrder == $1.level.difficulty.sortOrder {
          return $0.level.rating < $1.level.rating
        }
        return $0.level.difficulty.sortOrder
          < $1.level.difficulty.sortOrder
      }
      let first = ordered[0]
      let remoteCover = first.level.cover.resolved(
        against: first.server.baseURL
      )
      let coverURL = remoteCover.flatMap {
        localURL(for: $0, in: first)
      }
      return CatalogSong(
        id: "offline:\(key)",
        server: offlineServer,
        title: first.level.title,
        artists: first.level.artists,
        coverURL: coverURL,
        variants: ordered.map(\.level)
      )
    }
  }

  func localURL(
    for remoteURL: URL,
    in manifest: OfflineLevelManifest
  ) -> URL? {
    guard let resource = manifest.resources.first(where: {
      $0.remoteURL == remoteURL
    }) else {
      return nil
    }
    return objectsURL.appendingPathComponent(resource.objectName)
  }

  func remove(_ manifest: OfflineLevelManifest) throws {
    let url = manifestsURL.appendingPathComponent("\(manifest.id).json")
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private var objectsURL: URL {
    rootURL.appendingPathComponent("Objects", isDirectory: true)
  }

  private var manifestsURL: URL {
    rootURL.appendingPathComponent("Manifests", isDirectory: true)
  }

  private func prepareDirectories() throws {
    try fileManager.createDirectory(
      at: objectsURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: manifestsURL,
      withIntermediateDirectories: true
    )
  }

  private func downloadResources(
    _ locators: [(url: URL, hash: String?)]
  ) async throws -> [OfflineResourceDownload] {
    try await withThrowingTaskGroup(
      of: OfflineResourceDownload.self,
      returning: [OfflineResourceDownload].self
    ) { group in
      for locator in locators {
        group.addTask { [client] in
          let data = try await client.resource(at: locator.url)
          if let expected = locator.hash,
            data.sha1Hex.caseInsensitiveCompare(expected) != .orderedSame
          {
            throw OfflineStoreError.checksumMismatch(locator.url)
          }

          return OfflineResourceDownload(
            resource: OfflineResource(
              remoteURL: locator.url,
              objectName: locator.hash ?? data.sha256Hex,
              expectedSHA1: locator.hash
            ),
            data: data
          )
        }
      }

      var downloads = [OfflineResourceDownload]()
      for try await download in group {
        downloads.append(download)
      }
      return downloads
    }
  }
}

private extension Data {
  var sha1Hex: String {
    Insecure.SHA1.hash(data: self).map { String(format: "%02x", $0) }.joined()
  }

  var sha256Hex: String {
    SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
  }
}

private extension JSONEncoder {
  static var offline: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

private extension JSONDecoder {
  static var offline: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
