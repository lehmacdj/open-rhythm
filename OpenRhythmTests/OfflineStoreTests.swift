import XCTest
@testable import OpenRhythm

final class OfflineStoreTests: XCTestCase {
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
