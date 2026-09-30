import CryptoKit
import Foundation

struct OfflineResource: Codable, Hashable, Sendable {
  let remoteURL: URL?
  let objectName: String
  let expectedSHA1: String?

  var reference: RuntimeResourceReference {
    RuntimeResourceReference(url: remoteURL, hash: expectedSHA1)
  }
  var diagnosticName: String {
    remoteURL?.absoluteString ?? "SHA-1 \(expectedSHA1 ?? objectName)"
  }
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

struct OfflineManifestIssue: Identifiable, Sendable, LocalizedError {
  let fileName: String
  let diagnostic: String
  var id: String { fileName }
  var errorDescription: String? {
    "Couldn’t read download record \(fileName). \(diagnostic)"
  }
}

struct OfflineCatalogSnapshot: Sendable {
  let songs: [CatalogSong]
  let issues: [OfflineManifestIssue]
}

private struct OfflineResourceDownload: Sendable {
  let resource: OfflineResource
  let data: Data
}

enum OfflineStoreError: LocalizedError {
  case malformedLevelDetails
  case invalidResourceHash(String)
  case missingCachedResource(String)
  case checksumMismatch(String)

  var errorDescription: String? {
    switch self {
    case .malformedLevelDetails:
      "The server returned malformed level details."
    case .invalidResourceHash(let hash):
      "The server supplied an invalid resource hash: \(hash)"
    case .missingCachedResource(let name):
      "A downloaded resource is missing: \(name)"
    case .checksumMismatch(let name):
      "The downloaded resource failed verification: \(name)"
    }
  }
}

enum ResourceLocatorCollector {
  static func collect(from data: Data, baseURL: URL) throws
    -> [RuntimeResourceReference]
  {
    let object = try JSONSerialization.jsonObject(with: data)
    var resources = Set<RuntimeResourceReference>()
    try visit(object, baseURL: baseURL, resources: &resources)
    return Array(resources)
  }

  private static func visit(
    _ value: Any,
    baseURL: URL,
    resources: inout Set<RuntimeResourceReference>
  ) throws {
    if let dictionary = value as? [String: Any] {
      let childBaseURL = (dictionary["source"] as? String)
        .flatMap(URL.init(string:)) ?? baseURL
      let hash = dictionary["hash"] as? String
      let url = ResourceLocator(hash: hash, url: dictionary["url"] as? String)
        .resolved(against: childBaseURL)
      if url != nil || hash != nil {
        resources.insert(RuntimeResourceReference(url: url,
          hash: try hash.map(ContentAddress.normalizedSHA1)))
        return
      }

      for child in dictionary.values {
        try visit(child, baseURL: childBaseURL, resources: &resources)
      }
    } else if let array = value as? [Any] {
      for child in array {
        try visit(child, baseURL: baseURL, resources: &resources)
      }
    }
  }
}

actor OfflineStore {
  static let shared = OfflineStore()

  private struct ResourceValidationKey: Hashable {
    let objectName: String
    let expectedSHA1: String?
  }

  private let fileManager: FileManager
  private let rootURL: URL
  private let client: SonolusClient
  private let readStoredData: @Sendable (URL) throws -> Data
  private var activeDownloads = 0
  private var cleanupRequested = false
  private var deletionVersions = [String: Int]()

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    client: SonolusClient = SonolusClient(),
    readStoredData: @escaping @Sendable (URL) throws -> Data = {
      try Data(contentsOf: $0)
    }
  ) {
    self.fileManager = fileManager
    self.client = client
    self.readStoredData = readStoredData

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
    reusedResources: [RuntimeResourceReference: OfflineResource] = [:],
    expectedVersions: [String: Int] = [:]
  ) async throws -> OfflineLevelManifest {
    let id = manifestID(level: level, server: server)
    var versions = expectedVersions
    if versions[id] == nil { versions[id] = deletionVersions[id, default: 0] }
    let originID = originKey(level: level, server: server)
    if versions[originID] == nil {
      versions[originID] = deletionVersions[originID, default: 0]
    }
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
      let item = details["item"] as? [String: Any]
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
    // Archive the same selected play resources used by online playback. A
    // recursive walk of the entire item also requires overridden defaults,
    // non-play engine modes and unrelated thumbnails to remain available.
    var locators = Set([references.engineData, references.levelData,
      references.bgm] + Array(references.presentation.values))
    if let rom = references.engineROM { locators.insert(rom) }
    if let cover = item["cover"] {
      guard let cover = cover as? [String: Any] else {
        throw OfflineStoreError.malformedLevelDetails
      }
      let base = (item["source"] as? String).flatMap(URL.init(string:))
        ?? server.baseURL
      let artwork = try JSONSerialization.data(withJSONObject: cover)
      locators.formUnion(try ResourceLocatorCollector.collect(
        from: artwork, baseURL: base))
    }

    try prepareDirectories()
    var resources = [OfflineResource]()
    var pending = [RuntimeResourceReference]()
    for locator in locators.sorted(by: {
      ($0.url?.absoluteString ?? "", $0.hash ?? "")
        < ($1.url?.absoluteString ?? "", $1.hash ?? "")
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
      if let resource = reusedResources[locator],
        resource.expectedSHA1 == hash,
        ContentAddress.isSafeObjectName(resource.objectName),
        let data = try? readStoredData(
          objectsURL.appendingPathComponent(resource.objectName)),
        ContentAddress.validates(data, as: resource) {
        resources.append(resource)
        continue
      }
      pending.append(RuntimeResourceReference(url: locator.url, hash: hash))
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
    resources.sort {
      ($0.remoteURL?.absoluteString ?? "", $0.objectName)
        < ($1.remoteURL?.absoluteString ?? "", $1.objectName)
    }

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
    var expectedVersions = Dictionary(song.variants.map {
      let id = manifestID(level: $0, server: song.server(for: $0))
      return (id, startVersions[id, default: 0])
    }, uniquingKeysWith: { first, _ in first })
    for level in song.variants {
      let id = originKey(level: level, server: song.server(for: level))
      expectedVersions[id] = startVersions[id, default: 0]
    }
    let complete = try await client.completeSong(song, forceReload: forceReload)
    for level in complete.variants {
      let id = manifestID(level: level, server: complete.server(for: level))
      expectedVersions[id] = startVersions[id, default: 0]
      let originID = originKey(level: level, server: complete.server(for: level))
      expectedVersions[originID] = startVersions[originID, default: 0]
    }
    var refreshedResources = [RuntimeResourceReference: OfflineResource]()
    await progress(0, complete.variants.count)
    // Sequential charts reuse the first chart's cached common resources.
    for (index, level) in complete.variants.enumerated() {
      try Task.checkCancellation()
      let manifest = try await download(level: level,
        from: complete.server(for: level), forceReload: forceReload,
        reusedResources: refreshedResources, expectedVersions: expectedVersions)
      for resource in manifest.resources {
        refreshedResources[resource.reference] = resource
      }
      await progress(index + 1, complete.variants.count)
    }
    return complete
  }

  func manifests() throws -> [OfflineLevelManifest] {
    try readManifests(allowPartial: false).manifests
  }

  private func readManifests(allowPartial: Bool) throws
    -> (manifests: [OfflineLevelManifest], issues: [OfflineManifestIssue]) {
    guard fileManager.fileExists(atPath: manifestsURL.path) else { return ([], []) }
    // Enumeration failures still fail the whole read. Only individual record
    // failures can yield a partial, explicitly diagnosed catalog.
    let files = try fileManager.contentsOfDirectory(at: manifestsURL,
      includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var manifests = [OfflineLevelManifest]()
    var issues = [OfflineManifestIssue]()
    for file in files {
      do {
        manifests.append(try JSONDecoder.offline.decode(OfflineLevelManifest.self,
          from: readStoredData(file)))
      } catch {
        let error = error as NSError
        let issue = OfflineManifestIssue(fileName: file.lastPathComponent,
          diagnostic: "\(error.localizedDescription) (\(error.domain), \(error.code))")
        guard allowPartial else { throw issue }
        issues.append(issue)
      }
    }
    return (manifests.sorted { $0.downloadedAt > $1.downloadedAt }, issues)
  }

  func manifest(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) throws -> OfflineLevelManifest? {
    // An unrelated damaged record must not prevent valid offline playback or
    // cause the download-status check to report the whole library as absent.
    let manifests = try readManifests(allowPartial: true).manifests
    return manifest(level: level, from: server, in: manifests,
      validating: resourcesAreValid)
  }

  private func manifest(
    level: SonolusLevelItem, from server: ServerDescriptor,
    in manifests: [OfflineLevelManifest],
    validating: (OfflineLevelManifest) -> Bool
  ) -> OfflineLevelManifest? {
    if server.id == "offline" {
      let candidates = manifests.filter { $0.level.id == level.id }
      if let exact = candidates.first(where: {
        $0.level.source == level.source
      }) {
        return exact
      }
      return candidates.count == 1 ? candidates[0] : nil
    }
    // History can retain an old server-list ID after removal/re-addition.
    // Always resolve the newest valid canonical copy, including when an old
    // exact-ID manifest still exists. No metadata needs destructive migration.
    let key = originKey(level: level, server: server)
    return manifests.first {
      originKey(level: $0.level, server: $0.server) == key
        && validating($0)
    }
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
      for: references.engineData,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("engine play data")
    }
    guard let levelURL = localURL(
      for: references.levelData,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("level data")
    }
    guard let storedBGMURL = localURL(
      for: references.bgm,
      in: manifest
    ) else {
      throw RuntimeBundleError.missingResource("music")
    }
    let bgmURL = try playableURL(
      for: storedBGMURL,
      remoteURL: references.bgmURL
    )

    var presentation = [String: Data]()
    let rom: Data?
    if let reference = references.engineROM {
      guard let url = localURL(for: reference, in: manifest) else {
        throw RuntimeBundleError.missingResource("engine ROM")
      }
      rom = try readStoredData(url)
    } else { rom = nil }
    for (name, reference) in references.presentation {
      guard let url = localURL(for: reference, in: manifest) else {
        throw RuntimeBundleError.missingResource(name)
      }
      presentation[name] = try readStoredData(url)
    }
    let engine = try CompressedJSONDecoder.decode(EnginePlayData.self,
      from: readStoredData(engineURL))
    let missing = try engine.unsupportedFunctions()
    guard missing.isEmpty else {
      throw EngineInterpreterError.unsupportedFunction(missing.joined(separator: ", "))
    }
    return try RuntimeBundle(
      engine: engine,
      level: CompressedJSONDecoder.decode(
        LevelData.self,
        from: readStoredData(levelURL)
      ),
      bgmURL: bgmURL,
      isOffline: true,
      presentation: RuntimePresentation(resources: presentation),
      engineROM: rom
    )
  }

  func containsAllDifficulties(
    of song: CatalogSong, discoverySucceeded: Bool
  ) -> Bool {
    // A catalog page can contain only some variants of a song. Even if every
    // known chart is cached, that does not establish a complete song download.
    guard discoverySucceeded, !song.variants.isEmpty else { return false }
    guard let listing = try? readManifests(allowPartial: true) else { return false }
    // All difficulties share one fresh inventory and integrity pass. This
    // synchronous actor operation does not retain positive/negative results
    // across requests, downloads, repairs or deletions.
    var verified = [ResourceValidationKey: Bool]()
    return song.variants.allSatisfy { level in
      manifest(level: level, from: song.server(for: level), in: listing.manifests,
        validating: { resourcesAreValid(in: $0, verified: &verified) }) != nil
    }
  }

  func contains(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) -> Bool {
    (try? manifest(level: level, from: server)) != nil
  }

  func catalogSongs() throws -> [CatalogSong] {
    try catalogSnapshot().songs
  }

  func catalogSnapshot() throws -> OfflineCatalogSnapshot {
    let listing = try readManifests(allowPartial: true)
    return OfflineCatalogSnapshot(songs: catalogSongs(from: listing.manifests),
      issues: listing.issues)
  }

  private func catalogSongs(from manifests: [OfflineLevelManifest]) -> [CatalogSong] {
    // Older builds may have retained one manifest per alias of a server.
    // Prefer the newest copy without deleting recoverable on-disk metadata.
    let entries = Dictionary(manifests.map {
      (originKey(level: $0.level, server: $0.server), $0)
    }, uniquingKeysWith: { first, _ in first }).values
    let offlineServer = ServerDescriptor(
      id: "offline",
      name: "Offline",
      baseURL: rootURL
    )
    let grouped = Dictionary(grouping: entries) { serverOrigin($0.server) }
      .flatMap { origin, manifests -> [(String, [OfflineLevelManifest])] in
        let server = manifests[0].server
        let byLevel = Dictionary(manifests.map { ($0.catalogLevel, $0) },
          uniquingKeysWith: { first, _ in first })
        return CatalogBuilder.groupedLevels(manifests.map(\.catalogLevel), server: server)
          .map { levels in
            (origin + "\u{0}" + CatalogBuilder.songKey(levels, server: server),
              levels.compactMap { byLevel[$0] })
          }
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
        against: first.level.source.flatMap(URL.init(string:))
          ?? first.server.baseURL
      )
      let coverURL = localURL(for: RuntimeResourceReference(url: remoteCover,
        hash: first.level.cover.hash?.lowercased()), in: first)
      return CatalogSong(
        id: "offline:\(key)",
        server: offlineServer,
        title: first.level.title,
        artists: first.level.artists,
        coverURL: coverURL,
        variants: ordered.map(\.catalogLevel),
        levelOrigins: ordered.map {
          CatalogLevelOrigin(level: $0.catalogLevel, server: $0.server)
        }, coverHash: first.level.cover.hash
      )
    }
  }

  func localURL(
    for remoteURL: URL,
    in manifest: OfflineLevelManifest
  ) -> URL? {
    localURL(for: RuntimeResourceReference(url: remoteURL, hash: nil), in: manifest)
  }

  private func localURL(for reference: RuntimeResourceReference,
    in manifest: OfflineLevelManifest) -> URL? {
    let safe = manifest.resources.filter {
      ContentAddress.isSafeObjectName($0.objectName)
    }
    if let hash = reference.hash {
      // Ordinary catalog cover lookup must stay metadata-only. A declared
      // different hash is not a legacy candidate: never read its BGM/engine.
      if let exact = safe.first(where: { $0.expectedSHA1?.lowercased() == hash }) {
        return objectsURL.appendingPathComponent(exact.objectName)
      }
      // A genuinely hashless legacy record may hold the requested content.
      for resource in safe where resource.expectedSHA1 == nil {
        if let url = reference.url, resource.remoteURL != url { continue }
        let url = objectsURL.appendingPathComponent(resource.objectName)
        if let data = try? readStoredData(url),
          ContentAddress.validates(data, as: resource), data.sha1Hex == hash {
          return url
        }
      }
      return nil
    }
    let matchingURL = safe.filter { $0.remoteURL == reference.url }
    guard reference.url != nil,
      let resource = matchingURL.first(where: { $0.expectedSHA1 == nil })
        ?? matchingURL.first
    else { return nil }
    return objectsURL.appendingPathComponent(resource.objectName)
  }

  func cachedResource(expectedSHA1: String) throws -> Data? {
    let hash = try ContentAddress.normalizedSHA1(expectedSHA1)
    guard let data = try? readStoredData(objectsURL.appendingPathComponent(hash)),
      data.sha1Hex == hash else { return nil }
    return data
  }

  func remove(_ manifest: OfflineLevelManifest) throws {
    // Derive the filename, never trust a path from a decoded manifest.
    let id = Data("\(manifest.server.id):\(manifest.level.id)".utf8).sha256Hex
    deletionVersions[id, default: 0] += 1
    deletionVersions[originKey(level: manifest.level, server: manifest.server),
      default: 0] += 1
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
    let origins = Set(song.variants.map {
      originKey(level: $0, server: song.server(for: $0))
    })
    // Read all manifests before deleting any; malformed metadata must not
    // cause shared assets to be mistaken for unreferenced files.
    let entries = try manifests()
    // Mark even missing charts so a first download cannot resurrect the song.
    for id in targets { deletionVersions[id, default: 0] += 1 }
    for id in origins { deletionVersions[id, default: 0] += 1 }
    activeDownloads += 1
    defer { finishDownload() }
    for entry in entries where targets.contains(
      Data("\(entry.server.id):\(entry.level.id)".utf8).sha256Hex)
      || origins.contains(originKey(level: entry.level, server: entry.server)) {
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

  private func serverOrigin(_ server: ServerDescriptor) -> String {
    (try? ServerDescriptor.normalizedURL(server.baseURL.absoluteString))?
      .absoluteString ?? server.baseURL.absoluteString
  }

  private func originKey(level: SonolusLevelItem, server: ServerDescriptor)
    -> String {
    serverOrigin(server) + "\u{0}" + level.id
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
    remoteURL: URL?
  ) throws -> URL {
    let pathExtension = remoteURL?.pathExtension ?? ""
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
    _ locators: [RuntimeResourceReference],
    forceReload: Bool
  ) async throws -> [OfflineResourceDownload] {
    try await withThrowingTaskGroup(
      of: OfflineResourceDownload.self,
      returning: [OfflineResourceDownload].self
    ) { group in
      for locator in locators {
        group.addTask { [client] in
          let data = try await client.resource(at: locator.url,
            expectedSHA1: locator.hash, forceReload: forceReload)
          if let expected = locator.hash,
            data.sha1Hex != expected {
            throw SonolusClientError.resourceChecksumMismatch(expected)
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
    guard let data = try? readStoredData(url) else { return false }
    return data.sha1Hex == expectedSHA1
  }

  private func resourcesAreValid(in manifest: OfflineLevelManifest) -> Bool {
    var verified = [ResourceValidationKey: Bool]()
    return resourcesAreValid(in: manifest, verified: &verified)
  }

  private func resourcesAreValid(in manifest: OfflineLevelManifest,
    verified: inout [ResourceValidationKey: Bool]) -> Bool {
    manifest.resources.allSatisfy { resource in
      // Remote URL aliases can share bytes, but a contradictory hash claim
      // must not inherit another resource's successful verification.
      let key = ResourceValidationKey(objectName: resource.objectName,
        expectedSHA1: resource.expectedSHA1)
      if let result = verified[key] { return result }
      let result = resourceIsValid(resource)
      verified[key] = result
      return result
    }
  }

  private func resourceIsValid(_ resource: OfflineResource) -> Bool {
    guard ContentAddress.isSafeObjectName(resource.objectName) else {
      return false
    }
    let url = objectsURL.appendingPathComponent(resource.objectName)
    guard let data = try? readStoredData(url) else { return false }
    return ContentAddress.validates(data, as: resource)
  }

  private func validateResources(
    in manifest: OfflineLevelManifest
  ) throws {
    for resource in manifest.resources {
      guard ContentAddress.isSafeObjectName(resource.objectName) else {
        throw OfflineStoreError.checksumMismatch(resource.diagnosticName)
      }
      let url = objectsURL.appendingPathComponent(resource.objectName)
      guard let data = try? readStoredData(url) else {
        throw OfflineStoreError.missingCachedResource(resource.diagnosticName)
      }
      guard ContentAddress.validates(data, as: resource) else {
        throw OfflineStoreError.checksumMismatch(resource.diagnosticName)
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
    // Preserve subsecond ordering when two server aliases are updated during
    // one second; ISO8601's default encoding discards those fractions.
    encoder.dateEncodingStrategy = .deferredToDate
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

private extension JSONDecoder {
  static var offline: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer()
      if let seconds = try? value.decode(Double.self) {
        return Date(timeIntervalSinceReferenceDate: seconds)
      }
      let text = try value.decode(String.self)
      guard let date = ISO8601DateFormatter().date(from: text) else {
        throw DecodingError.dataCorruptedError(in: value,
          debugDescription: "Invalid download date")
      }
      return date
    }
    return decoder
  }
}
