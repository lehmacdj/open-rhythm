import Foundation

enum RuntimeBundleError: LocalizedError {
  case malformedLevelDetails
  case missingResource(String)
  case unsupportedEngineVersion(Int)
  case invalidResourceURL(String)
  case unsupportedPresentationValue(field: String, value: String)

  var errorDescription: String? {
    switch self {
    case .malformedLevelDetails:
      "The server returned malformed runtime details."
    case .missingResource(let name):
      "The playback bundle is missing \(name)."
    case .unsupportedEngineVersion(let version):
      "Engine version \(version) is not supported."
    case .invalidResourceURL(let name):
      "The \(name) resource must use an HTTP or HTTPS URL."
    case .unsupportedPresentationValue(let field, let value):
      "The engine uses an unsupported \(field) value: \(value)."
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
  let useBackground: RuntimeResourceSelection?
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
  let image: ResourceLocator?
  let configuration: ResourceLocator?
}

private struct RuntimeEngineItem: Decodable {
  let source: String?
  let version: Int
  let playData: ResourceLocator
  let configuration: ResourceLocator?
  let rom: ResourceLocator?
  let skin: RuntimePresentationItem?
  let background: RuntimePresentationItem?
  let effect: RuntimePresentationItem?
  let particle: RuntimePresentationItem?
}

struct RuntimeResourceReferences: Sendable {
  let engineVersion: Int
  let engineDataURL: URL
  let levelDataURL: URL
  let bgmURL: URL
  let engineROMURL: URL?
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

    func resource(_ locator: ResourceLocator?, _ name: String, base: URL)
      throws -> URL {
      guard let url = locator?.resolved(against: base) else {
        throw RuntimeBundleError.missingResource(name)
      }
      guard let scheme = url.scheme?.lowercased(),
        ["http", "https"].contains(scheme), url.host?.isEmpty == false else {
        throw RuntimeBundleError.invalidResourceURL(name)
      }
      return url
    }
    engineVersion = item.engine.version
    engineDataURL = try resource(item.engine.playData, "engine play data",
      base: engineBaseURL)
    levelDataURL = try resource(item.data, "level data", base: levelBaseURL)
    bgmURL = try resource(item.bgm, "music", base: levelBaseURL)
    engineROMURL = try item.engine.rom.map {
      try resource($0, "engine ROM", base: engineBaseURL)
    }
    var urls = [String: URL]()
    urls["configuration"] = try resource(item.engine.configuration,
      "engine configuration", base: engineBaseURL)
    for (name, selection, fallback) in [
      ("skin", item.useSkin, item.engine.skin),
      ("background", item.useBackground, item.engine.background),
      ("effect", item.useEffect, item.engine.effect),
      ("particle", item.useParticle, item.engine.particle)
    ] {
      let usesDefault = selection?.useDefault ?? true
      let selected = usesDefault ? fallback : selection?.item
      guard usesDefault || selected != nil else {
        throw RuntimeBundleError.missingResource("selected \(name)")
      }
      if let selected {
        let base = selected.source.flatMap(URL.init(string:))
          ?? (usesDefault ? engineBaseURL : levelBaseURL)
        urls[name + "Data"] = try resource(selected.data, "\(name) data", base: base)
        switch name {
        case "skin", "particle":
          urls[name + "Texture"] = try resource(selected.texture,
            "\(name) texture", base: base)
        case "effect":
          urls[name + "Audio"] = try resource(selected.audio, "effect audio", base: base)
        default:
          urls[name + "Image"] = try resource(selected.image,
            "background image", base: base)
          urls[name + "Configuration"] = try resource(selected.configuration,
            "background configuration", base: base)
        }
      }
    }
    presentationURLs = urls
  }
}

struct RuntimeBundle: Sendable {
  enum PlaybackMode: Sendable {
    case engine
    // Explicit internal lane-chart mode, never decoded from a server payload.
    // Missing engine resources must not select a different game implicitly.
    case basicLanes
  }
  let engine: EnginePlayData
  let level: LevelData
  let bgmURL: URL
  let isOffline: Bool
  var presentation: RuntimePresentation? = nil
  var engineROM: Data? = nil
  var preparedAudio: PreparedRuntimeAudio? = nil
  var playbackMode: PlaybackMode = .engine
}

/// A playback lease over a private file, separate from the evictable HTTP
/// cache and the user's Downloads library. Keep it alive through restarts.
final class PreparedRuntimeAudio: Sendable {
  let url: URL

  init(data: Data, sourceURL: URL, temporaryDirectory: URL =
    FileManager.default.temporaryDirectory) throws {
    guard !data.isEmpty, data.count <= 128 * 1024 * 1024 else {
      throw RuntimeBundleError.missingResource("music smaller than 128 MiB")
    }
    let directory = temporaryDirectory.appendingPathComponent(
      "OpenRhythmPlayback-\(UUID().uuidString)", isDirectory: true)
    let suffix = sourceURL.pathExtension.lowercased()
    let safeSuffix = !suffix.isEmpty && suffix.count <= 10
      && suffix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
      ? suffix : "audio"
    url = directory.appendingPathComponent("music.\(safeSuffix)")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    do { try data.write(to: url, options: .atomic) } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
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
    try Task.checkCancellation()
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
    async let romData = loadROM(at: references.engineROMURL)
    let presentation = try await withThrowingTaskGroup(
      of: (String, Data).self
    ) { group in
      for (name, url) in references.presentationURLs {
        group.addTask { (name, try await self.client.resource(at: url)) }
      }
      var resources = [String: Data]()
      for try await (name, data) in group { resources[name] = data }
      return RuntimePresentation(resources: resources)
    }
    let engine = try await CompressedJSONDecoder.decode(
      EnginePlayData.self, from: engineData)
    let parsedLevel = try await CompressedJSONDecoder.decode(LevelData.self, from: levelData)
    let missing = try engine.unsupportedFunctions()
    guard missing.isEmpty else {
      throw EngineInterpreterError.unsupportedFunction(missing.joined(separator: ", "))
    }
    try Task.checkCancellation()
    // Fetch music only after validating the chart and supported callbacks.
    // The shared response cache reuses it across difficulties; playback and
    // silence inspection then use the same pinned local copy.
    let audio = try await PreparedRuntimeAudio(data: client.resource(at: references.bgmURL),
      sourceURL: references.bgmURL)
    try Task.checkCancellation()
    return try await RuntimeBundle(
      engine: engine,
      level: parsedLevel,
      bgmURL: audio.url,
      isOffline: false,
      presentation: presentation,
      engineROM: romData, preparedAudio: audio
    )
  }

  private func validate(version: Int) throws {
    guard version == 13 else {
      throw RuntimeBundleError.unsupportedEngineVersion(version)
    }
  }

  private func loadROM(at url: URL?) async throws -> Data? {
    guard let url else { return nil }
    return try await client.resource(at: url)
  }
}
