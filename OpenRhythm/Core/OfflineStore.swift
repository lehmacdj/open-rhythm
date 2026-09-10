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

  var catalogLevel: SonolusLevelItem {
    struct Identity: Decodable { let engine: SonolusEngineIdentity? }
    var result = level
    if result.engine == nil {
      result.engine = (try? JSONDecoder().decode(Identity.self, from: itemData))?
        .engine
    }
    return result
  }
}

private struct OfflineResourceDownload: Sendable {
  let resource: OfflineResource
  let data: Data
}

enum OfflineStoreError: LocalizedError {
  case malformedLevelDetails
  case invalidResourceHash(String)
  case missingCachedResource(URL)
  case checksumMismatch(URL)

  var errorDescription: String? {
    switch self {
    case .malformedLevelDetails:
      "The server returned malformed level details."
    case .invalidResourceHash(let hash):
      "The server supplied an invalid resource hash: \(hash)"
    case .missingCachedResource(let url):
      "A downloaded resource is missing: \(url.absoluteString)"
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
  private var activeDownloads = 0
  private var cleanupRequested = false
  private var deletionVersions = [String: Int]()

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
    from server: ServerDescriptor,
    forceReload: Bool = false,
    reusedResources: [URL: OfflineResource] = [:],
    expectedVersions: [String: Int] = [:]
  ) async throws -> OfflineLevelManifest {
    let id = manifestID(level: level, server: server)
    var versions = expectedVersions
    if versions[id] == nil { versions[id] = deletionVersions[id, default: 0] }
    try checkVersions(versions)
    activeDownloads += 1
    defer { finishDownload() }
    if !forceReload, let existing = try manifest(level: level, from: server) {
      return existing
    }
    let detailsData = try await client.levelDetails(
      for: level, on: server, forceReload: forceReload)
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
    let references = try RuntimeResourceReferences(
      itemData: itemData,
      serverBaseURL: server.baseURL
    )
    guard references.engineVersion == 13 else {
      throw RuntimeBundleError.unsupportedEngineVersion(
        references.engineVersion
      )
    }
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
      let hash = try locator.hash.map(ContentAddress.normalizedSHA1)
      if let hash {
        let objectURL = objectsURL.appendingPathComponent(hash)
        if cachedObjectIsValid(at: objectURL, expectedSHA1: hash) {
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
      if let resource = reusedResources[locator.url],
        resource.expectedSHA1 == hash,
        ContentAddress.isSafeObjectName(resource.objectName),
        let data = try? Data(contentsOf:
          objectsURL.appendingPathComponent(resource.objectName)),
        ContentAddress.validates(data, as: resource) {
        resources.append(resource)
        continue
      }
      pending.append((url: locator.url, hash: hash))
    }

    let downloads = try await downloadResources(pending,
      forceReload: forceReload)
    try Task.checkCancellation()
    try checkVersions(versions)
    for download in downloads {
      let objectURL = objectsURL.appendingPathComponent(
        download.resource.objectName
      )
      try download.data.write(to: objectURL, options: [.atomic])
      resources.append(download.resource)
    }
    resources.sort { $0.remoteURL.absoluteString < $1.remoteURL.absoluteString }

    let manifest = OfflineLevelManifest(
      id: id,
      server: server,
      level: (try? JSONDecoder().decode(SonolusLevelItem.self, from: itemData))
        .flatMap { $0.id == level.id ? $0 : nil } ?? level,
      itemData: itemData,
      resources: resources,
      downloadedAt: Date()
    )
    let manifestData = try JSONEncoder.offline.encode(manifest)
    try manifestData.write(
      to: manifestsURL.appendingPathComponent("\(id).json"),
      options: [.atomic]
    )
    if forceReload { cleanupRequested = true }
    return manifest
  }

  func download(
    song: CatalogSong,
    forceReload: Bool = false,
    progress: @Sendable (Int, Int) async -> Void = { _, _ in }
  ) async throws -> CatalogSong {
    activeDownloads += 1
    defer { finishDownload() }
    let startVersions = deletionVersions
    var expectedVersions = Dictionary(uniqueKeysWithValues: song.variants.map {
      let id = manifestID(level: $0, server: song.server(for: $0))
      return (id, startVersions[id, default: 0])
    })
    let complete = try await client.completeSong(song, forceReload: forceReload)
    for level in complete.variants {
      let id = manifestID(level: level, server: complete.server(for: level))
      expectedVersions[id] = startVersions[id, default: 0]
    }
    var refreshedResources = [URL: OfflineResource]()
    await progress(0, complete.variants.count)
    // Sequential charts reuse the first chart's cached common resources.
    for (index, level) in complete.variants.enumerated() {
      try Task.checkCancellation()
      let manifest = try await download(level: level,
        from: complete.server(for: level), forceReload: forceReload,
        reusedResources: refreshedResources, expectedVersions: expectedVersions)
      for resource in manifest.resources {
        refreshedResources[resource.remoteURL] = resource
      }
      await progress(index + 1, complete.variants.count)
    }
    return complete
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

  func manifest(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) throws -> OfflineLevelManifest? {
    if server.id == "offline" {
      let candidates = try manifests().filter { $0.level.id == level.id }
      if let exact = candidates.first(where: {
        $0.level.source == level.source
      }) {
        return exact
      }
      return candidates.count == 1 ? candidates[0] : nil
    }
    let id = Data("\(server.id):\(level.id)".utf8).sha256Hex
    let url = manifestsURL.appendingPathComponent("\(id).json")
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let manifest = try JSONDecoder.offline.decode(
      OfflineLevelManifest.self,
      from: Data(contentsOf: url)
    )
    return resourcesAreValid(in: manifest) ? manifest : nil
  }

  func runtimeBundle(
    from manifest: OfflineLevelManifest
  ) throws -> RuntimeBundle {
    try validateResources(in: manifest)
    let references = try RuntimeResourceReferences(
      itemData: manifest.itemData,
      serverBaseURL: manifest.server.baseURL
    )
    guard references.engineVersion == 13 else {
      throw RuntimeBundleError.unsupportedEngineVersion(
        references.engineVersion
      )
    }
    guard let engineURL = localURL(
      for: references.engineDataURL,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("engine play data")
    }
    guard let levelURL = localURL(
      for: references.levelDataURL,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("level data")
    }
    guard let storedBGMURL = localURL(
      for: references.bgmURL,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("music")
    }
    let bgmURL = try playableURL(
      for: storedBGMURL,
      remoteURL: references.bgmURL
    )

    var presentation = [String: Data]()
    for (name, remoteURL) in references.presentationURLs {
      guard let url = localURL(for: remoteURL, in: manifest) else {
        throw RuntimeBundleError.missingResource(name)
      }
      presentation[name] = try Data(contentsOf: url)
    }
    return try RuntimeBundle(
      engine: CompressedJSONDecoder.decode(
        EnginePlayData.self,
        from: Data(contentsOf: engineURL)
      ),
      level: CompressedJSONDecoder.decode(
        LevelData.self,
        from: Data(contentsOf: levelURL)
      ),
      bgmURL: bgmURL,
      isOffline: true,
      presentation: presentation.isEmpty ? nil
        : RuntimePresentation(resources: presentation)
    )
  }

  func containsAllDifficulties(
    of song: CatalogSong, discoverySucceeded: Bool
  ) -> Bool {
    // A catalog page can contain only some variants of a song. Even if every
    // known chart is cached, that does not establish a complete song download.
    guard discoverySucceeded, !song.variants.isEmpty else { return false }
    return song.variants.allSatisfy {
      contains(level: $0, from: song.server(for: $0))
    }
  }

  func contains(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) -> Bool {
    let id = Data("\(server.id):\(level.id)".utf8).sha256Hex
    let url = manifestsURL.appendingPathComponent("\(id).json")
    guard
      let data = try? Data(contentsOf: url),
      let manifest = try? JSONDecoder.offline.decode(
        OfflineLevelManifest.self,
        from: data
      )
    else { return false }
    return resourcesAreValid(in: manifest)
  }

  func catalogSongs() throws -> [CatalogSong] {
    let entries = try manifests()
    let offlineServer = ServerDescriptor(
      id: "offline",
      name: "Offline",
      baseURL: rootURL
    )
    let grouped = Dictionary(grouping: entries) { manifest in
      manifest.catalogLevel.songKey(server: manifest.server)
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
        variants: ordered.map(\.catalogLevel),
        levelOrigins: ordered.map {
          CatalogLevelOrigin(level: $0.catalogLevel, server: $0.server)
        }
      )
    }
  }

  func localURL(
    for remoteURL: URL,
    in manifest: OfflineLevelManifest
  ) -> URL? {
    guard let resource = manifest.resources.first(where: {
      $0.remoteURL == remoteURL
    }), ContentAddress.isSafeObjectName(resource.objectName) else {
      return nil
    }
    return objectsURL.appendingPathComponent(resource.objectName)
  }

  func remove(_ manifest: OfflineLevelManifest) throws {
    // Derive the filename, never trust a path from a decoded manifest.
    let id = Data("\(manifest.server.id):\(manifest.level.id)".utf8).sha256Hex
    deletionVersions[id, default: 0] += 1
    let url = manifestsURL.appendingPathComponent("\(id).json")
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    cleanupRequested = true
    if activeDownloads == 0 { try collectUnusedResources() }
  }

  func remove(song: CatalogSong) throws {
    let targets = Set(song.variants.map { level in
      Data("\(song.server(for: level).id):\(level.id)".utf8).sha256Hex
    })
    // Read all manifests before deleting any; malformed metadata must not
    // cause shared assets to be mistaken for unreferenced files.
    let entries = try manifests()
    // Mark even missing charts so a first download cannot resurrect the song.
    for id in targets { deletionVersions[id, default: 0] += 1 }
    activeDownloads += 1
    defer { finishDownload() }
    for entry in entries where targets.contains(
      Data("\(entry.server.id):\(entry.level.id)".utf8).sha256Hex) {
      try remove(entry)
    }
  }

  private func finishDownload() {
    activeDownloads -= 1
    if activeDownloads == 0, cleanupRequested {
      try? collectUnusedResources()
    }
  }

  private func manifestID(level: SonolusLevelItem, server: ServerDescriptor)
    -> String {
    Data("\(server.id):\(level.id)".utf8).sha256Hex
  }

  private func checkVersions(_ expected: [String: Int]) throws {
    guard expected.allSatisfy({ deletionVersions[$0.key, default: 0] == $0.value })
    else { throw CancellationError() }
  }

  private func collectUnusedResources() throws {
    let retained = Set(try manifests().flatMap(\.resources).map(\.objectName))
    for directory in [objectsURL, playbackURL] {
      guard fileManager.fileExists(atPath: directory.path) else { continue }
      let files = try fileManager.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: [.isRegularFileKey])
      for file in files {
        let name = directory == playbackURL
          ? file.deletingPathExtension().lastPathComponent : file.lastPathComponent
        guard ContentAddress.isSafeObjectName(name), !retained.contains(name),
          try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { continue }
        try fileManager.removeItem(at: file)
      }
    }
    cleanupRequested = false
  }

  private var objectsURL: URL {
    rootURL.appendingPathComponent("Objects", isDirectory: true)
  }

  private var manifestsURL: URL {
    rootURL.appendingPathComponent("Manifests", isDirectory: true)
  }

  private var playbackURL: URL {
    rootURL.appendingPathComponent("Playback", isDirectory: true)
  }

  private func playableURL(
    for storedURL: URL,
    remoteURL: URL
  ) throws -> URL {
    let pathExtension = remoteURL.pathExtension
    guard storedURL.pathExtension.isEmpty, !pathExtension.isEmpty else {
      return storedURL
    }

    try fileManager.createDirectory(
      at: playbackURL,
      withIntermediateDirectories: true
    )
    let aliasURL = playbackURL
      .appendingPathComponent(storedURL.lastPathComponent)
      .appendingPathExtension(pathExtension)
    if !fileManager.fileExists(atPath: aliasURL.path) {
      try fileManager.linkItem(at: storedURL, to: aliasURL)
    }
    return aliasURL
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
    _ locators: [(url: URL, hash: String?)],
    forceReload: Bool
  ) async throws -> [OfflineResourceDownload] {
    try await withThrowingTaskGroup(
      of: OfflineResourceDownload.self,
      returning: [OfflineResourceDownload].self
    ) { group in
      for locator in locators {
        group.addTask { [client] in
          let data = try await client.resource(at: locator.url,
            forceReload: forceReload)
          if let expected = locator.hash,
            data.sha1Hex != expected {
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

  private func cachedObjectIsValid(
    at url: URL,
    expectedSHA1: String
  ) -> Bool {
    guard let data = try? Data(contentsOf: url) else { return false }
    return data.sha1Hex == expectedSHA1
  }

  private func resourcesAreValid(in manifest: OfflineLevelManifest) -> Bool {
    manifest.resources.allSatisfy { resource in
      guard ContentAddress.isSafeObjectName(resource.objectName) else {
        return false
      }
      let url = objectsURL.appendingPathComponent(resource.objectName)
      guard let data = try? Data(contentsOf: url) else { return false }
      return ContentAddress.validates(data, as: resource)
    }
  }

  private func validateResources(
    in manifest: OfflineLevelManifest
  ) throws {
    for resource in manifest.resources {
      guard ContentAddress.isSafeObjectName(resource.objectName) else {
        throw OfflineStoreError.checksumMismatch(resource.remoteURL)
      }
      let url = objectsURL.appendingPathComponent(resource.objectName)
      guard let data = try? Data(contentsOf: url) else {
        throw OfflineStoreError.missingCachedResource(resource.remoteURL)
      }
      guard ContentAddress.validates(data, as: resource) else {
        throw OfflineStoreError.checksumMismatch(resource.remoteURL)
      }
    }
  }
}

enum ContentAddress {
  static func isSafeObjectName(_ value: String) -> Bool {
    let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
    return (value.utf8.count == 40 || value.utf8.count == 64)
      && value.unicodeScalars.allSatisfy(hexadecimal.contains)
  }

  static func normalizedSHA1(_ hash: String) throws -> String {
    let normalized = hash.lowercased()
    guard
      normalized.utf8.count == 40,
      isSafeObjectName(normalized)
    else {
      throw OfflineStoreError.invalidResourceHash(hash)
    }
    return normalized
  }

  static func validates(_ data: Data, as resource: OfflineResource) -> Bool {
    guard isSafeObjectName(resource.objectName) else { return false }
    if let expectedSHA1 = resource.expectedSHA1 {
      guard let normalized = try? normalizedSHA1(expectedSHA1) else {
        return false
      }
      return resource.objectName == normalized && data.sha1Hex == normalized
    }
    return data.sha256Hex == resource.objectName.lowercased()
  }
}

extension Data {
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
