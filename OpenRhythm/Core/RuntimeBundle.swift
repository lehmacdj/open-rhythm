import Foundation

enum RuntimeBundleError: LocalizedError {
  case malformedLevelDetails
  case missingResource(String)
  case unsupportedEngineVersion(Int)

  var errorDescription: String? {
    switch self {
    case .malformedLevelDetails:
      "The server returned malformed runtime details."
    case .missingResource(let name):
      "The playback bundle is missing \(name)."
    case .unsupportedEngineVersion(let version):
      "Engine version \(version) is not supported."
    }
  }
}

private struct RuntimeLevelDetails: Decodable {
  let item: RuntimeLevelItem
}

private struct RuntimeLevelItem: Decodable {
  let source: String?
  let bgm: ResourceLocator
  let data: ResourceLocator
  let engine: RuntimeEngineItem
}

private struct RuntimeEngineItem: Decodable {
  let source: String?
  let version: Int
  let playData: ResourceLocator
}

struct RuntimeResourceReferences: Sendable {
  let engineVersion: Int
  let engineDataURL: URL
  let levelDataURL: URL
  let bgmURL: URL

  init(itemData: Data, serverBaseURL: URL) throws {
    let item = try JSONDecoder().decode(RuntimeLevelItem.self, from: itemData)
    try self.init(item: item, serverBaseURL: serverBaseURL)
  }

  init(detailsData: Data, serverBaseURL: URL) throws {
    let details = try JSONDecoder().decode(
      RuntimeLevelDetails.self,
      from: detailsData
    )
    try self.init(item: details.item, serverBaseURL: serverBaseURL)
  }

  private init(item: RuntimeLevelItem, serverBaseURL: URL) throws {
    let levelBaseURL = item.source.flatMap(URL.init(string:)) ?? serverBaseURL
    let engineBaseURL = item.engine.source.flatMap(URL.init(string:))
      ?? levelBaseURL

    guard let engineDataURL = item.engine.playData.resolved(
      against: engineBaseURL
    ) else {
      throw RuntimeBundleError.missingResource("engine play data")
    }
    guard let levelDataURL = item.data.resolved(against: levelBaseURL) else {
      throw RuntimeBundleError.missingResource("level data")
    }
    guard let bgmURL = item.bgm.resolved(against: levelBaseURL) else {
      throw RuntimeBundleError.missingResource("music")
    }

    engineVersion = item.engine.version
    self.engineDataURL = engineDataURL
    self.levelDataURL = levelDataURL
    self.bgmURL = bgmURL
  }
}

struct RuntimeBundle: Sendable {
  let engine: EnginePlayData
  let level: LevelData
  let bgmURL: URL
  let isOffline: Bool
}

actor RuntimeBundleLoader {
  private let client: SonolusClient
  private let offlineStore: OfflineStore

  init(
    client: SonolusClient = SonolusClient(),
    offlineStore: OfflineStore = .shared
  ) {
    self.client = client
    self.offlineStore = offlineStore
  }

  func load(
    level: SonolusLevelItem,
    from server: ServerDescriptor
  ) async throws -> RuntimeBundle {
    if let manifest = try await offlineStore.manifest(
      level: level,
      from: server
    ) {
      return try await offlineStore.runtimeBundle(from: manifest)
    }

    let detailsData = try await client.levelDetails(for: level, on: server)
    let references = try RuntimeResourceReferences(
      detailsData: detailsData,
      serverBaseURL: server.baseURL
    )
    try validate(version: references.engineVersion)

    async let engineData = client.resource(at: references.engineDataURL)
    async let levelData = client.resource(at: references.levelDataURL)
    return try await RuntimeBundle(
      engine: CompressedJSONDecoder.decode(
        EnginePlayData.self,
        from: engineData
      ),
      level: CompressedJSONDecoder.decode(LevelData.self, from: levelData),
      bgmURL: references.bgmURL,
      isOffline: false
    )
  }

  private func validate(version: Int) throws {
    guard version == 13 else {
      throw RuntimeBundleError.unsupportedEngineVersion(version)
    }
  }
}
