import XCTest
@testable import OpenRhythm

final class OfflineStoreTests: XCTestCase {
  func testMissingConfigurationRejectsOnlineDownloadAndLegacyOfflineBundles() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = RequestRecorder()
    let item: [String: Any] = ["bgm": ["url": "/music"],
      "data": ["url": "/chart"],
      "engine": ["version": 13, "playData": ["url": "/engine"]]]
    let details = try JSONSerialization.data(withJSONObject: ["item": item])
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      return details
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let client = SonolusClient(session: session,
      cache: SonolusResponseCache(rootURL: root.appendingPathComponent("cache")))
    let store = OfflineStore(rootURL: root.appendingPathComponent("offline"), client: client)
    let loader = RuntimeBundleLoader(client: client, offlineStore: store)
    let server = ServerDescriptor(id: "missing-configuration", name: "Fixture",
      baseURL: URL(string: "https://fixture.example")!)
    let empty = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "level", source: nil, version: 1, rating: 1,
      title: LocalizedText("Song"), artists: LocalizedText("Fixture"),
      author: "Fixture", tags: [], cover: empty, bgm: empty, data: empty)
    func check(_ error: Error) {
      guard case RuntimeBundleError.missingResource(let name) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(name, "engine configuration")
    }
    do {
      _ = try await loader.load(level: level, from: server)
      XCTFail("Missing presentation must not silently bypass the engine")
    } catch { check(error) }
    do {
      _ = try await store.download(level: level, from: server)
      XCTFail("Do not save an unplayable resource-free bundle")
    } catch { check(error) }
    let legacy = OfflineLevelManifest(id: "legacy", server: server, level: level,
      itemData: try JSONSerialization.data(withJSONObject: item), resources: [],
      downloadedAt: Date())
    do {
      _ = try await store.runtimeBundle(from: legacy)
      XCTFail("Previously saved malformed bundles must not select basic lanes")
    } catch { check(error) }
    XCTAssertTrue(recorder.urls.allSatisfy { $0.lastPathComponent == "level" },
      "Reject before fetching chart, engine, configuration, or music resources")
    let manifests = try await store.manifests()
    XCTAssertTrue(manifests.isEmpty)
  }

  func testOnlinePlaybackPinsCachedMusicWithoutCreatingADownload() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = RequestRecorder()
    let music = Data("cached music fixture".utf8)
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      switch request.url?.lastPathComponent {
      case "music.mp3": return music
      case "configuration": return Data(#"{"options":[]}"#.utf8)
      case "engine": return Data(#"""
        {"skin":{"sprites":[]},"effect":{"clips":[]},"particle":{"effects":[]},
        "nodes":[],"buckets":[],"archetypes":[]}
        """#.utf8)
      case "chart": return Data(#"{"bgmOffset":0,"entities":[]}"#.utf8)
      default: return Data(#"""
        {"item":{"bgm":{"url":"/music.mp3"},"data":{"url":"/chart"},
        "engine":{"version":13,"playData":{"url":"/engine"},
        "configuration":{"url":"/configuration"}}}}
        """#.utf8)
      }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let cacheRoot = root.appendingPathComponent("cache")
    let client = SonolusClient(session: session,
      cache: SonolusResponseCache(rootURL: cacheRoot))
    let offline = OfflineStore(rootURL: root.appendingPathComponent("offline"), client: client)
    let loader = RuntimeBundleLoader(client: client, offlineStore: offline)
    let server = ServerDescriptor(id: "fixture", name: "Fixture",
      baseURL: URL(string: "https://fixture.example")!)
    let empty = ResourceLocator(hash: nil, url: nil)
    func item(_ name: String) -> SonolusLevelItem {
      SonolusLevelItem(name: name, source: nil, version: 1, rating: 1,
        title: LocalizedText("Song"), artists: LocalizedText("Artist"),
        author: "Fixture", tags: [], cover: empty, bgm: empty, data: empty)
    }
    let first = try await loader.load(level: item("easy"), from: server)
    let second = try await loader.load(level: item("hard"), from: server)
    XCTAssertNotNil(first.presentation)
    XCTAssertEqual(first.playbackMode, .engine)
    XCTAssertFalse(first.isOffline)
    XCTAssertTrue(first.bgmURL.isFileURL)
    XCTAssertEqual(first.preparedAudio?.url, first.bgmURL)
    XCTAssertNotEqual(first.bgmURL, second.bgmURL, "Each play owns its lease")
    XCTAssertEqual(recorder.urls.filter { $0.lastPathComponent == "music.mp3" }.count, 1)
    let downloads = try await offline.manifests()
    XCTAssertTrue(downloads.isEmpty)
    // Cache eviction must not remove a song that's already prepared to play.
    try FileManager.default.removeItem(at: cacheRoot)
    XCTAssertEqual(try Data(contentsOf: first.bgmURL), music)
    XCTAssertEqual(try Data(contentsOf: second.bgmURL), music)
    let requestCount = recorder.urls.count
    let cancelled = Task {
      while !Task.isCancelled { await Task.yield() }
      return try await loader.load(level: item("cancelled"), from: server)
    }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      XCTFail("Cancelled preparation must fail")
    } catch is CancellationError { }
    XCTAssertEqual(recorder.urls.count, requestCount)
  }

  func testUnsupportedEngineDoesNotFetchMusic() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    StubURLProtocol.handler = { request in
      switch request.url?.lastPathComponent {
      case "music":
        XCTFail("Unsupported engines should fail before downloading BGM")
        return Data("unused".utf8)
      case "configuration": return Data(#"{"options":[]}"#.utf8)
      case "chart": return Data(#"{"bgmOffset":0,"entities":[]}"#.utf8)
      case "engine": return Data(#"""
        {"skin":{"sprites":[]},"effect":{"clips":[]},"particle":{"effects":[]},
        "nodes":[{"func":"FutureUnsupportedFunction","args":[]}],"buckets":[],
        "archetypes":[{"name":"note","hasInput":true,"imports":[],"exports":[],
        "touch":{"index":0}}]}
        """#.utf8)
      default: return Data(#"""
        {"item":{"bgm":{"url":"/music"},"data":{"url":"/chart"},
        "engine":{"version":13,"playData":{"url":"/engine"},
        "configuration":{"url":"/configuration"}}}}
        """#.utf8)
      }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let client = SonolusClient(session: session)
    let loader = RuntimeBundleLoader(client: client,
      offlineStore: OfflineStore(rootURL: root, client: client))
    let empty = ResourceLocator(hash: nil, url: nil)
    let item = SonolusLevelItem(name: "level", source: nil, version: 1, rating: 1,
      title: LocalizedText("Song"), artists: LocalizedText("Artist"), author: "Fixture",
      tags: [], cover: empty, bgm: empty, data: empty)
    do {
      _ = try await loader.load(level: item, from: ServerDescriptor(id: "fixture",
        name: "Fixture", baseURL: URL(string: "https://fixture.example")!))
      XCTFail("Unsupported engine must fail")
    } catch EngineInterpreterError.unsupportedFunction(let name) {
      XCTAssertEqual(name, "FutureUnsupportedFunction")
    }
  }

  func testOfflinePlaybackRejectsUnsupportedEngineWithoutNetwork() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    StubURLProtocol.handler = { request in
      switch request.url?.lastPathComponent {
      case "music": return Data("offline music fixture".utf8)
      case "configuration": return Data(#"{"options":[]}"#.utf8)
      case "chart": return Data(#"{"bgmOffset":0,"entities":[]}"#.utf8)
      case "engine": return Data(#"""
        {"skin":{"sprites":[]},"effect":{"clips":[]},"particle":{"effects":[]},
        "nodes":[{"func":"FutureUnsupportedFunction","args":[]}],"buckets":[],
        "archetypes":[{"name":"note","hasInput":true,"imports":[],"exports":[],
        "touch":{"index":0}}]}
        """#.utf8)
      default: return Data(#"""
        {"item":{"bgm":{"url":"/music"},"data":{"url":"/chart"},
        "engine":{"version":13,"playData":{"url":"/engine"},
        "configuration":{"url":"/configuration"}}}}
        """#.utf8)
      }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let client = SonolusClient(session: session,
      cache: SonolusResponseCache(rootURL: root.appendingPathComponent("cache")))
    let store = OfflineStore(rootURL: root.appendingPathComponent("offline"),
      client: client)
    let empty = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "level", source: nil, version: 1, rating: 1,
      title: LocalizedText("Song"), artists: LocalizedText("Artist"),
      author: "Fixture", tags: [], cover: empty, bgm: empty, data: empty)
    let server = ServerDescriptor(id: "fixture", name: "Fixture",
      baseURL: URL(string: "https://fixture.example")!)
    let manifest = try await store.download(level: level, from: server)
    StubURLProtocol.handler = { _ in
      XCTFail("Offline preflight must not make network requests")
      throw URLError(.notConnectedToInternet)
    }
    do {
      _ = try await store.runtimeBundle(from: manifest)
      XCTFail("Offline playback must reject unsupported callbacks too")
    } catch EngineInterpreterError.unsupportedFunction(let name) {
      XCTAssertEqual(name, "FutureUnsupportedFunction")
    }
    let loader = RuntimeBundleLoader(client: client, offlineStore: store)
    do {
      _ = try await loader.load(level: level, from: server)
      XCTFail("The downloaded playback route must preserve preflight")
    } catch EngineInterpreterError.unsupportedFunction(let name) {
      XCTAssertEqual(name, "FutureUnsupportedFunction")
    }
  }

  @MainActor
  func testFirstPageFailureOffersRetryWithoutAnEmptySuccessRow() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    await model.refresh()
    XCTAssertEqual(model.loadedPageCount, 0)
    XCTAssertTrue(model.showsPaginationStatus)
    XCTAssertTrue(model.hasMorePages)
    StubURLProtocol.handler = { _ in Data(#"{"pageCount":0,"items":[]}"#.utf8) }
    await model.loadNextPage()
    XCTAssertNil(model.errorMessage)
    XCTAssertFalse(model.showsPaginationStatus)
  }

  @MainActor
  func testRepeatedEmptySearchAndShrinkingPagesNeverBuildAnInvalidRange()
    async throws {
    // Apple incident 68171806 (0.1.0 build 1): prefetch constructed a range
    // with loadedPageCount 1 and a zero-page search response as its upper end.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    StubURLProtocol.handler = { request in
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "keywords" }?.value ?? ""
      let count = query.count % 3
      return Data("{\"pageCount\":\(count),\"items\":[]}".utf8)
    }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    for length in 0..<30 {
      model.query = String(repeating: "a", count: length)
      await model.refresh()
      await model.prefetchNextPages()
      await model.loadNextPage()
      await model.prefetchNextPages()
      XCTAssertNil(model.errorMessage)
      XCTAssertFalse(model.hasMorePages)
    }
  }

  func testOfflineDateMigrationReadsLegacyISO8601AndPreciseNewDates() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Manifests")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    let manifest: [String: Any] = ["id": "legacy", "downloadedAt": "2026-09-10T12:34:56Z",
      "server": ["id": "legacy", "name": "Fixture", "baseURL": "https://example.com"],
      "level": ["name": "chart", "version": 1, "rating": 1,
        "title": "Song", "artists": "Artist", "author": "Fixture",
        "tags": [], "cover": [:], "bgm": [:], "data": [:]],
      "itemData": "e30=", "resources": []]
    try JSONSerialization.data(withJSONObject: manifest)
      .write(to: directory.appendingPathComponent("legacy.json"))
    let store = OfflineStore(rootURL: root)
    let loaded = try await store.manifests()
    XCTAssertEqual(loaded.first?.downloadedAt,
      ISO8601DateFormatter().date(from: "2026-09-10T12:34:56Z"))
  }

  @MainActor
  func testReaddingServerReusesDownloadsAndLegacyAliasesCanUpdateAndDelete()
    async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let servers = ServerStore(fileURL: root.appendingPathComponent("servers.json"))
    let original = servers.servers[0]
    let level = SonolusLevelItem(name: "chart", source: nil, version: 1,
      rating: 1, title: LocalizedText("Song"), artists: LocalizedText("Artist"),
      author: "Fixture", tags: [], cover: ResourceLocator(hash: nil, url: nil),
      bgm: ResourceLocator(hash: nil, url: "https://assets.example/data"),
      data: ResourceLocator(hash: nil, url: "https://assets.example/data"))
    let details = Data(#"""
      {"item":{"bgm":{"url":"https://assets.example/data"},
      "data":{"url":"https://assets.example/data"},
      "engine":{"version":13,"playData":{"url":"https://assets.example/data"},
      "configuration":{"url":"https://assets.example/data"}}}}
      """#.utf8)
    let list = try JSONEncoder().encode(SonolusLevelList(pageCount: 1, items: [level]))
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      if request.url?.host == "assets.example" { return Data("fixture".utf8) }
      return request.url?.lastPathComponent == "list" ? list : details
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let store = OfflineStore(rootURL: root.appendingPathComponent("Offline"),
      client: SonolusClient(session: session))
    let saved = try await store.download(level: level, from: original)
    try servers.remove(at: IndexSet(integer: 0))
    try servers.add(url: original.baseURL, name: original.name)
    let readded = servers.servers[0]
    XCTAssertNotEqual(original.id, readded.id)
    let before = recorder.urls.count
    let reused = try await store.download(level: level, from: readded)
    XCTAssertEqual(reused.id, saved.id)
    XCTAssertEqual(recorder.urls.count, before, "Alias changes need no download")
    // A forced refresh reproduces the duplicate manifests left by old builds.
    StubURLProtocol.handler = { request in
      if request.url?.host == "assets.example" { return Data("updated".utf8) }
      return request.url?.lastPathComponent == "list" ? list : details
    }
    let refreshed = try await store.download(level: level, from: readded, forceReload: true)
    let historyLookup = try await store.manifest(level: level, from: original)
    let readdedLookup = try await store.manifest(level: level, from: readded)
    XCTAssertEqual(historyLookup, refreshed)
    XCTAssertEqual(readdedLookup, refreshed)
    XCTAssertNotEqual(saved.resources, refreshed.resources)
    let manifests = try await store.manifests()
    XCTAssertEqual(manifests.count, 2)
    let songs = try await store.catalogSongs()
    XCTAssertEqual(songs.count, 1)
    XCTAssertEqual(songs[0].variants.count, 1)
    _ = try await store.download(song: songs[0], forceReload: true)
    // A second URL is a distinct server, even with the same chart and audio.
    let other = ServerDescriptor(id: "other", name: "Other",
      baseURL: URL(string: "https://other.example")!)
    _ = try await store.download(level: level, from: other)
    let separate = try await store.catalogSongs()
    XCTAssertEqual(separate.count, 2)
    try await store.remove(song: songs[0])
    let remaining = try await store.manifests()
    XCTAssertEqual(remaining.map(\.server.id), [other.id])
  }

  @MainActor
  func testPaginationModeChangeDoesNotSilentlyAppendAnUnrelatedPage() async throws {
    StubURLProtocol.handler = { request in
      let hasCursor = request.url!.absoluteString.contains("cursor=")
      return Data((hasCursor ? #"{"pageCount":3,"items":[]}"#
        : #"{"pageCount":-1,"cursor":"next","items":[]}"#).utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    await model.refresh()
    await model.prefetchNextPages()
    await model.loadNextPage()
    XCTAssertEqual(model.loadedPageCount, 1)
    XCTAssertTrue(model.hasMorePages)
    XCTAssertNotNil(model.errorMessage)
  }
  @MainActor
  func testCursorPaginationPrefetchesTwoPagesAndUsesQuickSearch() async throws {
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      XCTAssertEqual(query.first { $0.name == "type" }?.value, "quick")
      let cursor = query.first { $0.name == "cursor" }?.value
      switch cursor {
      case nil: return Data(#"{"pageCount":-1,"cursor":"opaque +/?","items":[]}"#.utf8)
      case "opaque +/?": return Data(#"{"pageCount":-1,"cursor":"last","items":[]}"#.utf8)
      case "last": return Data(#"{"pageCount":-1,"items":[]}"#.utf8)
      default: throw SonolusClientError.invalidResponse
      }
    }
    defer { StubURLProtocol.handler = nil }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    model.query = "song"
    await model.refresh()
    XCTAssertTrue(model.hasMorePages)
    await model.prefetchNextPages()
    XCTAssertEqual(recorder.urls.count, 3)
    await model.loadNextPage()
    XCTAssertTrue(model.hasMorePages)
    await model.loadNextPage()
    XCTAssertFalse(model.hasMorePages)
    XCTAssertEqual(model.loadedPageCount, 3)
    XCTAssertEqual(recorder.urls.count, 3, "Use buffered cursor pages")
    await model.refresh(forceReload: true)
    XCTAssertEqual(URLComponents(url: recorder.urls.last!,
      resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }, nil)
  }

  func testDifficultyDiscoveryFollowsCursorsAndRejectsCycles() async throws {
    let levels = (1...2).map { index in
      SonolusLevelItem(name: "chart-\(index)", source: nil, version: 1,
        rating: Double(index) + 0.9, title: LocalizedText("Song"),
        artists: LocalizedText("Artist"), author: "Fixture", tags: [],
        cover: ResourceLocator(hash: nil, url: nil),
        bgm: ResourceLocator(hash: nil, url: "music"),
        data: ResourceLocator(hash: nil, url: "chart-\(index)"))
    }
    let server = ServerDescriptor.defaults[0]
    let song = CatalogBuilder.group(levels: [levels[0]], server: server)[0]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
    let client = SonolusClient(session: session)
    let first = try JSONEncoder().encode(SonolusLevelList(pageCount: -1,
      items: [levels[0]], cursor: "next"))
    let last = try JSONEncoder().encode(SonolusLevelList(pageCount: -1,
      items: [levels[1]]))
    StubURLProtocol.handler = { request in
      request.url!.absoluteString.contains("cursor=") ? last : first
    }
    let complete = try await client.completeSong(song)
    XCTAssertEqual(complete.variants.map(\.rating), [1.9, 2.9])
    StubURLProtocol.handler = { _ in first }
    do {
      _ = try await client.completeSong(song)
      XCTFail("A cursor loop must not report a partial download as complete")
    } catch { }
  }
  @MainActor
  func testAppendingPagesPreservesRowsUntilExplicitSortChange() async throws {
    let pages = try ["Zulu", "Alpha"].map { title in
      try JSONEncoder().encode(SonolusLevelList(pageCount: 2, items: [
        SonolusLevelItem(name: title, source: nil, version: 1, rating: 1,
          title: LocalizedText(title), artists: LocalizedText(title),
          author: "Fixture", tags: [],
          cover: ResourceLocator(hash: nil, url: nil),
          bgm: ResourceLocator(hash: nil, url: title),
          data: ResourceLocator(hash: nil, url: title))
      ]))
    }
    StubURLProtocol.handler = { request in
      let page = URLComponents(url: request.url!,
        resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "page" }?.value ?? "0"
      return pages[Int(page)!]
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    model.filter = CatalogFilter()
    await model.refresh()
    let firstID = try XCTUnwrap(model.visibleSongs.first).id
    await model.loadNextPage()
    XCTAssertEqual(model.visibleSongs.first?.id, firstID)
    XCTAssertEqual(model.visibleSongs.map { $0.title.displayValue() },
      ["Zulu", "Alpha"])
    model.filter.sort = .artist
    XCTAssertEqual(model.visibleSongs.map { $0.title.displayValue() },
      ["Alpha", "Zulu"])
  }

  func testEngineROMAndBackgroundLoadIdenticallyOnlineAndOffline() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = ServerDescriptor(id: "rom", name: "ROM Fixture",
      baseURL: URL(string: "https://server.example")!)
    let details = Data(#"""
      {"item":{"bgm":{"url":"/bgm"},"data":{"url":"/level"},
      "engine":{"version":13,"source":"https://engine.example",
      "playData":{"url":"/play"},"rom":{"url":"/rom"},
      "configuration":{"url":"/configuration"},
      "background":{"source":"https://background.example",
        "data":{"url":"/backgroundData"},"image":{"url":"/backgroundImage"},
        "configuration":{"url":"/backgroundConfiguration"}}}}}
      """#.utf8)
    let rom = Data([0, 0, 128, 63, 0, 0, 32, 192])
    StubURLProtocol.handler = { request in
      switch request.url?.lastPathComponent {
      case "rom":
        XCTAssertEqual(request.url?.host, "engine.example")
        return rom
      case "play":
        return Data(#"""
          {"skin":{"sprites":[]},"effect":{"clips":[]},
          "particle":{"effects":[]},"archetypes":[],"nodes":[],"buckets":[]}
          """#.utf8)
      case "level": return Data(#"{"bgmOffset":0,"entities":[]}"#.utf8)
      case "configuration": return Data(#"{"options":[]}"#.utf8)
      case "bgm": return Data("audio fixture".utf8)
      case "backgroundData", "backgroundImage", "backgroundConfiguration":
        XCTAssertEqual(request.url?.host, "background.example")
        return Data(request.url!.lastPathComponent.utf8)
      default: return details
      }
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = SonolusClient(session: session)
    let store = OfflineStore(rootURL: root, client: client)
    let loader = RuntimeBundleLoader(client: client, offlineStore: store)
    let empty = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "chart", source: nil, version: 1,
      rating: 1, title: LocalizedText("Song"), artists: LocalizedText("Artist"),
      author: "Fixture", tags: [], cover: empty, bgm: empty, data: empty)
    let online = try await loader.load(level: level, from: server)
    XCTAssertFalse(online.isOffline)
    XCTAssertEqual(online.engineROM, rom)
    _ = try await store.download(level: level, from: server)
    StubURLProtocol.handler = { _ in
      XCTFail("Offline ROM loading must not fetch resources")
      throw URLError(.notConnectedToInternet)
    }
    let offline = try await loader.load(level: level, from: server)
    XCTAssertTrue(offline.isOffline)
    XCTAssertEqual(offline.engineROM, rom)
    for name in ["backgroundData", "backgroundImage", "backgroundConfiguration"] {
      XCTAssertEqual(online.presentation?.resources[name], Data(name.utf8))
      XCTAssertEqual(offline.presentation?.resources[name], Data(name.utf8))
    }
    let runtime = try EnginePlayRuntime(engine: offline.engine, level: offline.level,
      options: [], aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [],
      particleEffectIDs: [], rom: offline.engineROM)
    XCTAssertEqual(runtime.memory.value(block: 3000, index: 1), -2.5)
  }

  @MainActor
  func testPrefetchStopsForEmptySearchAndLastPage() async throws {
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      let query = URLComponents(url: request.url!,
        resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "keywords" }?.value ?? "0"
      return Data("{\"pageCount\":\(query),\"items\":[]}".utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    for pageCount in [0, -1, 1] {
      model.query = String(pageCount)
      await model.searchAfterDelay()
      XCTAssertNil(model.errorMessage)
      XCTAssertEqual(model.loadedPageCount, 1)
      XCTAssertFalse(model.hasMorePages)
      XCTAssertFalse(model.showsPaginationStatus,
        "No empty footer row after an empty search or the final page")
      let requestCount = recorder.urls.count
      await model.prefetchNextPages()
      await model.loadNextPage()
      XCTAssertEqual(recorder.urls.count, requestCount,
        "Empty searches and exhausted lists must not fetch more pages")
    }
    XCTAssertEqual(recorder.urls.count, 3)
  }

  @MainActor
  func testPrefetchStopsWhenRemotePageCountShrinks() async throws {
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      let page = URLComponents(url: request.url!,
        resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "page" }?.value
      let count = page == "0" ? 96 : 1
      return Data("{\"pageCount\":\(count),\"items\":[]}".utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    await model.refresh()
    await model.loadNextPage()
    XCTAssertEqual(model.loadedPageCount, 2)
    XCTAssertEqual(model.totalPageCount, 1)
    XCTAssertFalse(model.hasMorePages)
    await model.prefetchNextPages()
    XCTAssertEqual(recorder.urls.count, 2)
  }

  @MainActor
  func testPrefetchIsBoundedAndExpiredPagesRestartFromBeginning() async throws {
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
      recorder.append(request.url!)
      return Data(#"{"pageCount":96,"items":[]}"#.utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var clock = Date().addingTimeInterval(1)
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session), now: { clock })
    await model.refresh()
    await model.prefetchNextPages()
    XCTAssertEqual(recorder.urls.count, 3)
    XCTAssertEqual(model.loadedPageCount, 1,
      "Prefetch must not insert rows or change the scroll extent")
    await model.prefetchNextPages()
    XCTAssertEqual(recorder.urls.count, 3)
    await model.loadNextPage()
    XCTAssertEqual(recorder.urls.count, 3, "Consume the buffered page")
    XCTAssertEqual(model.loadedPageCount, 2)
    clock = clock.addingTimeInterval(601)
    await model.loadNextPage()
    XCTAssertEqual(model.loadedPageCount, 1)
    let last = try XCTUnwrap(recorder.urls.last)
    XCTAssertEqual(URLComponents(url: last, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "page" }?.value, "0")
    XCTAssertEqual(recorder.urls.count, 4, "Expired buffers cannot bypass refresh")
  }

  func testOfflineUpdateIsVerifiedAndDeletionRetainsSharedAssets() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = ServerDescriptor(id: "fixture", name: "Fixture",
      baseURL: URL(string: "https://server.example")!)
    let levels = (0..<2).map { index in
      SonolusLevelItem(name: "level-\(index)", source: nil, version: 1,
        rating: Double(index + 1), title: LocalizedText("Song"),
        artists: LocalizedText("Artist"), author: "Fixture", tags: [],
        cover: ResourceLocator(hash: nil, url: nil),
        bgm: ResourceLocator(hash: nil, url: "https://assets.example/data"),
        data: ResourceLocator(hash: nil, url: "https://assets.example/data"))
    }
    let details = Data(#"""
      {"item":{"bgm":{"url":"https://assets.example/data"},
      "data":{"url":"https://assets.example/data"},
      "engine":{"version":13,"playData":{"url":"https://assets.example/data"},
      "configuration":{"url":"https://assets.example/data"}}}}
      """#.utf8)
    let list = try JSONEncoder().encode(SonolusLevelList(pageCount: 1, items: levels))
    let recorder = RequestRecorder()
    func installResponse(_ bytes: Data, fail: Bool = false) {
      StubURLProtocol.handler = { request in
        recorder.append(request.url!)
        if request.url?.host == "assets.example" {
          if fail { throw URLError(.cannotConnectToHost) }
          return bytes
        }
        return request.url?.lastPathComponent == "list" ? list : details
      }
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let store = OfflineStore(rootURL: root.appendingPathComponent("Offline"),
      client: SonolusClient(session: session,
        cache: SonolusResponseCache(rootURL: root.appendingPathComponent("Cache"))))
    let song = CatalogBuilder.group(levels: levels, server: server)[0]
    installResponse(Data("original".utf8))
    _ = try await store.download(song: song)
    let old = try await store.manifests()
    let originalLocation = await store.localURL(
      for: URL(string: "https://assets.example/data")!, in: old[0])
    let originalURL = try XCTUnwrap(originalLocation)
    installResponse(Data("replacement".utf8))
    let before = recorder.urls.filter { $0.host == "assets.example" }.count
    _ = try await store.download(song: song, forceReload: true)
    XCTAssertEqual(recorder.urls.filter { $0.host == "assets.example" }.count,
      before + 1, "Mutable shared assets refresh once per song update")
    let updated = try await store.manifests()
    let newLocation = await store.localURL(
      for: URL(string: "https://assets.example/data")!, in: updated[0])
    let newURL = try XCTUnwrap(newLocation)
    XCTAssertEqual(try Data(contentsOf: newURL), Data("replacement".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    installResponse(Data(), fail: true)
    do {
      _ = try await store.download(song: song, forceReload: true)
      XCTFail("Expected the update to fail")
    } catch { }
    let retained = try await store.manifests()
    XCTAssertEqual(retained, updated, "Failed replacements preserve working charts")
    try await store.remove(updated[0])
    XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path),
      "Another difficulty still references this asset")
    try await store.remove(song: song)
    let remaining = try await store.manifests()
    XCTAssertTrue(remaining.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))

    installResponse(Data("replacement".utf8))
    _ = try await store.download(song: song)
    let started = expectation(description: "Update resource request started")
    let resume = DispatchSemaphore(value: 0)
    StubURLProtocol.handler = { request in
      if request.url?.host == "assets.example" {
        started.fulfill()
        guard resume.wait(timeout: .now() + 5) == .success else {
          throw URLError(.timedOut)
        }
        return Data("new replacement".utf8)
      }
      return request.url?.lastPathComponent == "list" ? list : details
    }
    let update = Task { try await store.download(song: song, forceReload: true) }
    await fulfillment(of: [started], timeout: 5)
    try await store.remove(song: song)
    resume.signal()
    do {
      _ = try await update.value
      XCTFail("A deleted song must cancel its in-flight replacement")
    } catch is CancellationError { }
    let afterRace = try await store.manifests()
    XCTAssertTrue(afterRace.isEmpty, "An update must not resurrect deleted downloads")
  }

  func testDiscoveryFollowsStableChartIDWhenMusicURLChanges() async throws {
    let server = ServerDescriptor.defaults[0]
    let original = SonolusLevelItem(name: "chart", source: nil, version: 1,
      rating: 7, title: LocalizedText("Song"), artists: LocalizedText("Artist"),
      author: "Fixture", tags: [], cover: ResourceLocator(hash: nil, url: nil),
      bgm: ResourceLocator(hash: nil, url: "/old-hash"),
      data: ResourceLocator(hash: nil, url: nil))
    let fresh = SonolusLevelItem(name: "chart", source: nil, version: 1,
      rating: 8, title: original.title, artists: original.artists,
      author: "Fixture", tags: [], cover: original.cover,
      bgm: ResourceLocator(hash: nil, url: "/new-hash"), data: original.data)
    let list = try JSONEncoder().encode(SonolusLevelList(pageCount: 1, items: [fresh]))
    StubURLProtocol.handler = { _ in list }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = SonolusClient(session: session)
    let song = CatalogBuilder.group(levels: [original], server: server)[0]
    let updated = try await client.completeSong(song, forceReload: true)
    XCTAssertEqual(updated.variants.first?.bgm.url, "/new-hash")
    XCTAssertEqual(updated.variants.first?.rating, 8)
    let retired = SonolusLevelItem(name: "retired-easy", source: nil, version: 1,
      rating: 1, title: original.title, artists: original.artists,
      author: "Fixture", tags: [], cover: original.cover,
      bgm: original.bgm, data: original.data)
    let oldSong = CatalogBuilder.group(levels: [retired, original], server: server)[0]
    XCTAssertEqual(oldSong.variants.first?.id, retired.id)
    let refreshed = try await client.completeSong(oldSong, forceReload: true)
    XCTAssertEqual(refreshed.variants.map(\.id), [fresh.id],
      "A retired first chart must not select its stale audio group")
    XCTAssertEqual(refreshed.variants.first?.bgm.url, "/new-hash")
  }

  func testSongDownloadDiscoversAllDifficultiesAndReusesSharedResources() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = ServerDescriptor(id: "fixture", name: "Fixture",
      baseURL: URL(string: "https://server.example")!)
    let locator = ResourceLocator(
      hash: "043c442d55264f4fb778fc32b387254d6dc40f92",
      url: "https://assets.example/data")
    let levels = ["#EASY", "#EXPERT"].enumerated().map { index, difficulty in
      SonolusLevelItem(name: "level-\(index)", source: nil, version: 1,
        rating: Double(index + 1), title: LocalizedText("Song"),
        artists: LocalizedText("Artist"), author: "Fixture",
        tags: [SonolusTag(title: difficulty)],
        cover: ResourceLocator(hash: nil, url: nil), bgm: locator, data: locator)
    }
    let song = CatalogBuilder.group(levels: [levels[0]], server: server)[0]
    let list = try JSONEncoder().encode(SonolusLevelList(pageCount: 1, items: levels))
    let details = Data(#"""
      {"item":{"source":"https://server.example",
      "bgm":{"url":"https://assets.example/data",
      "hash":"043c442d55264f4fb778fc32b387254d6dc40f92"},
      "data":{"url":"https://assets.example/data",
      "hash":"043c442d55264f4fb778fc32b387254d6dc40f92"},
      "engine":{"version":13,"playData":{"url":"https://assets.example/data",
      "hash":"043c442d55264f4fb778fc32b387254d6dc40f92"},
      "configuration":{"url":"https://assets.example/data",
      "hash":"043c442d55264f4fb778fc32b387254d6dc40f92"}}}}
      """#.utf8)
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      if request.url?.host == "assets.example" { return Data("valid data".utf8) }
      return request.url?.lastPathComponent == "list" ? list : details
    }
    defer { StubURLProtocol.handler = nil }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let client = SonolusClient(session: session,
      cache: SonolusResponseCache(rootURL: root.appendingPathComponent("Responses")))
    let store = OfflineStore(rootURL: root.appendingPathComponent("Offline"),
      client: client)
    _ = try await store.download(level: levels[0], from: server)
    let partialStatus = await store.containsAllDifficulties(
      of: song, discoverySucceeded: false)
    XCTAssertFalse(partialStatus,
      "A cached known chart is not a complete song if discovery failed")
    let complete = try await store.download(song: song)
    XCTAssertEqual(Set(complete.variants.map(\.id)), Set(levels.map(\.id)))
    let manifests = try await store.manifests()
    XCTAssertEqual(manifests.count, 2)
    let completeStatus = await store.containsAllDifficulties(
      of: complete, discoverySucceeded: true)
    XCTAssertTrue(completeStatus)
    XCTAssertEqual(recorder.urls.filter { $0.host == "assets.example" }.count, 1)
    let count = recorder.urls.count
    _ = try await store.download(song: song)
    XCTAssertEqual(recorder.urls.count, count, "Retry reuses complete downloads")
  }

  @MainActor
  func testScrollingLoadsOneNextPageAndIgnoresStaleSearchRows() async throws {
    let recorder = RequestRecorder()
    let levels = (0..<10).map { index in
      SonolusLevelItem(name: "song-\(index)", source: nil, version: 1,
        rating: 1, title: LocalizedText("Song \(index)"),
        artists: LocalizedText("Artist"), author: "Fixture",
        tags: [SonolusTag(title: "#EASY")],
        cover: ResourceLocator(hash: nil, url: nil),
        bgm: ResourceLocator(hash: nil, url: "bgm-\(index)"),
        data: ResourceLocator(hash: nil, url: "data-\(index)"))
    }
    let data = try JSONEncoder().encode(SonolusLevelList(pageCount: 96,
      items: levels))
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      return data
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    await model.refresh()
    await model.loadMoreIfNeeded(after: try XCTUnwrap(model.visibleSongs.first).id)
    XCTAssertEqual(recorder.urls.count, 1, "Top rows must not prefetch pages")
    let last = try XCTUnwrap(model.visibleSongs.last).id
    async let first: Void = model.loadMoreIfNeeded(after: last)
    async let duplicate: Void = model.loadMoreIfNeeded(after: last)
    _ = await (first, duplicate)
    XCTAssertEqual(recorder.urls.count, 3,
      "Duplicate-only pages advance at most two pages per scroll trigger")
    XCTAssertEqual(model.loadedPageCount, 3)
    XCTAssertTrue(model.needsMoreMatches)
    model.query = "new search"
    await model.loadMoreIfNeeded(after: last)
    XCTAssertEqual(recorder.urls.count, 3,
      "Do not paginate the old search while the new query is debouncing")
  }

  @MainActor
  func testCatalogLoadsOnlyRequestedPagesAndCancelsDebouncedSearch() async throws {
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      return Data(#"{"pageCount":96,"items":[]}"#.utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let model = CatalogModel(server: ServerDescriptor.defaults[0],
      client: SonolusClient(session: session))
    await model.refresh()
    XCTAssertEqual(recorder.urls.count, 1)
    XCTAssertEqual(model.loadedPageCount, 1)
    XCTAssertTrue(model.hasMorePages)
    await model.loadNextPage()
    XCTAssertEqual(recorder.urls.count, 2)
    XCTAssertEqual(model.loadedPageCount, 2)
    await model.searchAfterDelay()
    XCTAssertEqual(model.loadedPageCount, 2,
      "Returning from details must preserve previously loaded pages")
    XCTAssertEqual(recorder.urls.count, 2)
    model.query = "b"
    let cancelled = Task { await model.searchAfterDelay() }
    cancelled.cancel()
    await cancelled.value
    XCTAssertEqual(recorder.urls.count, 2)
    model.query = "bokura"
    await model.searchAfterDelay()
    XCTAssertEqual(recorder.urls.count, 3)
    XCTAssertEqual(model.loadedPageCount, 1)
    let query = URLComponents(url: try XCTUnwrap(recorder.urls.last),
      resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(query.first { $0.name == "keywords" }?.value, "bokura")
    XCTAssertEqual(query.first { $0.name == "page" }?.value, "0")
  }

  func testResponsesAreCoalescedPersistedAndExplicitlyRefreshable() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = SonolusResponseCache(rootURL: root)
    let counter = FetchCounter()
    let url = URL(string: "https://example.test/page?keywords=song&page=0")!
    let fetch: @Sendable () async throws -> Data = {
      await counter.increment()
      try await Task.sleep(for: .milliseconds(20))
      return Data("response".utf8)
    }
    async let first = cache.data(at: url, maximumAge: 600, fetch: fetch)
    async let second = cache.data(at: url, maximumAge: 600, fetch: fetch)
    let responses = try await [first, second]
    XCTAssertEqual(responses, [Data("response".utf8), Data("response".utf8)])
    var count = await counter.count
    XCTAssertEqual(count, 1)
    let reopened = SonolusResponseCache(rootURL: root)
    _ = try await reopened.data(at: url, maximumAge: 600, fetch: fetch)
    count = await counter.count
    XCTAssertEqual(count, 1, "Disk cache survives new client/cache instances")
    _ = try await reopened.data(at: url, maximumAge: 600,
      forceReload: true, fetch: fetch)
    count = await counter.count
    XCTAssertEqual(count, 2)
    _ = try await reopened.data(at: url, maximumAge: 0, fetch: fetch)
    count = await counter.count
    XCTAssertEqual(count, 3, "Expired entries refresh")
    let cachedFile = root.appendingPathComponent(Data(url.absoluteString.utf8).sha256Hex)
    for date in [Date().addingTimeInterval(-601), Date().addingTimeInterval(601)] {
      try FileManager.default.setAttributes([.modificationDate: date],
        ofItemAtPath: cachedFile.path)
      let data = try await reopened.data(at: url, maximumAge: 600) {
        await counter.increment()
        return Data("changed remote response".utf8)
      }
      XCTAssertEqual(data, Data("changed remote response".utf8))
    }
    count = await counter.count
    XCTAssertEqual(count, 5, "Expired or future-dated cache files must revalidate")
  }

  func testArtworkResourcesShareCacheAcrossClientInstances() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = RequestRecorder()
    StubURLProtocol.handler = { request in
      recorder.append(request.url!)
      return Data("artwork".utf8)
    }
    defer { StubURLProtocol.handler = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let cache = SonolusResponseCache(rootURL: root)
    let first = SonolusClient(session: session, cache: cache)
    let second = SonolusClient(session: session, cache: cache)
    let url = URL(string: "https://assets.example/cover.png")!
    async let one = first.resource(at: url)
    async let two = second.resource(at: url)
    let values = try await [one, two]
    XCTAssertEqual(values, [Data("artwork".utf8), Data("artwork".utf8)])
    _ = try await second.resource(at: url)
    XCTAssertEqual(recorder.urls.count, 1,
      "Artwork must share persistent caching even without HTTP cache headers")
  }

  func testCollectsAndResolvesNestedResourcesWithoutDuplicates() throws {
    let json = #"""
      {
        "cover": {"url": "/repository/a", "hash": "a"},
        "engine": {
          "playData": {"url": "/repository/b", "hash": "b"},
          "same": {"url": "/repository/a", "hash": "a"}
        },
        "bgm": {"url": "https://assets.example/song.mp3"}
      }
      """#
    let data = Data(json.utf8)
    let baseURL = URL(string: "https://example.com/server")!

    let resources = try ResourceLocatorCollector.collect(
      from: data,
      baseURL: baseURL
    )
    let values = Dictionary(
      uniqueKeysWithValues: resources.map { ($0.url.absoluteString, $0.hash) }
    )

    XCTAssertEqual(values.count, 3)
    XCTAssertEqual(values["https://example.com/server/repository/a"]!, "a")
    XCTAssertEqual(values["https://example.com/server/repository/b"]!, "b")
    XCTAssertTrue(values.keys.contains("https://assets.example/song.mp3"))
  }

  func testContentAddressesRejectCorruptionAndUnsafeHashes() throws {
    let data = Data("valid data".utf8)
    let remoteURL = URL(string: "https://assets.example/data")!
    let sha1 = "043c442d55264f4fb778fc32b387254d6dc40f92"
    let sha256 =
      "d63e23e8a7cbe080f2a79984fb4b2e08d22924e0f27fa7b30220e4e351489962"

    XCTAssertEqual(try ContentAddress.normalizedSHA1(sha1.uppercased()), sha1)
    XCTAssertThrowsError(try ContentAddress.normalizedSHA1("../unsafe"))

    XCTAssertTrue(ContentAddress.validates(
      data,
      as: OfflineResource(
        remoteURL: remoteURL,
        objectName: sha1,
        expectedSHA1: sha1
      )
    ))
    XCTAssertTrue(ContentAddress.validates(
      data,
      as: OfflineResource(
        remoteURL: remoteURL,
        objectName: sha256,
        expectedSHA1: nil
      )
    ))
    XCTAssertFalse(ContentAddress.validates(
      Data("corrupt".utf8),
      as: OfflineResource(
        remoteURL: remoteURL,
        objectName: sha1,
        expectedSHA1: sha1
      )
    ))
    XCTAssertFalse(ContentAddress.validates(
      data,
      as: OfflineResource(
        remoteURL: remoteURL,
        objectName: "../unsafe",
        expectedSHA1: sha1
      )
    ))
  }

  func testCorruptedCachedResourceIsDownloadedAgain() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let validData = Data("valid data".utf8)
    let sha1 = "043c442d55264f4fb778fc32b387254d6dc40f92"
    let details = Data(#"""
      {
        "item": {
          "source": "https://server.example",
          "bgm": {
            "url": "https://assets.example/data",
            "hash": "\#(sha1)"
          },
          "data": {
            "url": "https://assets.example/data",
            "hash": "\#(sha1)"
          },
          "engine": {
            "source": "https://server.example",
            "version": 13,
            "playData": {
              "url": "https://assets.example/data",
              "hash": "\#(sha1)"
            },
            "configuration": {
              "url": "https://assets.example/data",
              "hash": "\#(sha1)"
            }
          }
        }
      }
      """#.utf8)
    StubURLProtocol.handler = { request in
      request.url?.host == "assets.example" ? validData : details
    }
    defer { StubURLProtocol.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = SonolusClient(session: session)
    let store = OfflineStore(rootURL: rootURL, client: client)
    let server = ServerDescriptor(
      id: "test",
      name: "Test",
      baseURL: URL(string: "https://server.example")!
    )
    let level = SonolusLevelItem(
      name: "level",
      source: server.baseURL.absoluteString,
      version: 1,
      rating: 1,
      title: LocalizedText("Song"),
      artists: LocalizedText("Artist"),
      author: "Test",
      tags: [SonolusTag(title: "#EASY")],
      cover: ResourceLocator(hash: nil, url: nil),
      bgm: ResourceLocator(hash: nil, url: nil),
      data: ResourceLocator(hash: sha1, url: "https://assets.example/data")
    )

    _ = try await store.download(level: level, from: server)
    let objectURL = rootURL
      .appendingPathComponent("Objects", isDirectory: true)
      .appendingPathComponent(sha1)
    try Data("corrupt".utf8).write(to: objectURL, options: [.atomic])
    let containsCorruption = await store.contains(level: level, from: server)
    XCTAssertFalse(containsCorruption)

    _ = try await store.download(level: level, from: server)
    XCTAssertEqual(try Data(contentsOf: objectURL), validData)
    let containsRepair = await store.contains(level: level, from: server)
    XCTAssertTrue(containsRepair)
  }
}

private actor FetchCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private final class RequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values = [URL]()
  var urls: [URL] { lock.withLock { values } }
  func append(_ url: URL) { lock.withLock { values.append(url) } }
}

private final class StubURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> Data)?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let data = try handler(request)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      client?.urlProtocol(
        self,
        didReceive: response,
        cacheStoragePolicy: .notAllowed
      )
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
