import XCTest
@testable import OpenRhythm

final class OfflineStoreTests: XCTestCase {
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
}
