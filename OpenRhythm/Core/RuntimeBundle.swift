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
  let useSkin: RuntimeResourceSelection?
  let useEffect: RuntimeResourceSelection?
  let useParticle: RuntimeResourceSelection?
}

private struct RuntimeResourceSelection: Decodable {
  let useDefault: Bool
  let item: RuntimePresentationItem?
}

private struct RuntimePresentationItem: Decodable {
  let source: String?
  let data: ResourceLocator
  let texture: ResourceLocator?
  let audio: ResourceLocator?
}

private struct RuntimeEngineItem: Decodable {
  let source: String?
  let version: Int
  let playData: ResourceLocator
  let configuration: ResourceLocator?
  let skin: RuntimePresentationItem?
  let effect: RuntimePresentationItem?
  let particle: RuntimePresentationItem?
}

struct RuntimeResourceReferences: Sendable {
  let engineVersion: Int
  let engineDataURL: URL
  let levelDataURL: URL
  let bgmURL: URL
  let presentationURLs: [String: URL]

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
    var urls = [String: URL]()
    urls["configuration"] = item.engine.configuration?.resolved(
      against: engineBaseURL
    )
    for (name, selection, fallback) in [
      ("skin", item.useSkin, item.engine.skin),
      ("effect", item.useEffect, item.engine.effect),
      ("particle", item.useParticle, item.engine.particle)
    ] {
      let usesDefault = selection?.useDefault ?? true
      let selected = usesDefault ? fallback : selection?.item
      if let selected {
        let base = selected.source.flatMap(URL.init(string:))
          ?? (usesDefault ? engineBaseURL : levelBaseURL)
        urls[name + "Data"] = selected.data.resolved(against: base)
        urls[name + "Texture"] = selected.texture?.resolved(against: base)
        urls[name + "Audio"] = selected.audio?.resolved(against: base)
      }
    }
    presentationURLs = urls
  }
}

struct RuntimeBundle: Sendable {
  let engine: EnginePlayData
  let level: LevelData
  let bgmURL: URL
  let isOffline: Bool
  var presentation: RuntimePresentation? = nil
}

struct RuntimePresentation: Sendable {
  let resources: [String: Data]

  func data(_ name: String) throws -> Data {
    guard let data = resources[name] else {
      throw RuntimeBundleError.missingResource(name)
    }
    return data
  }
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
    let presentation = try await withThrowingTaskGroup(
      of: (String, Data).self
    ) { group in
      for (name, url) in references.presentationURLs {
        group.addTask { (name, try await self.client.resource(at: url)) }
      }
      var resources = [String: Data]()
      for try await (name, data) in group { resources[name] = data }
      return resources.isEmpty ? nil : RuntimePresentation(resources: resources)
    }
    return try await RuntimeBundle(
      engine: CompressedJSONDecoder.decode(
        EnginePlayData.self,
        from: engineData
      ),
      level: CompressedJSONDecoder.decode(LevelData.self, from: levelData),
      bgmURL: references.bgmURL,
      isOffline: false,
      presentation: presentation
    )
  }

  private func validate(version: Int) throws {
    guard version == 13 else {
      throw RuntimeBundleError.unsupportedEngineVersion(version)
    }
  }
}
