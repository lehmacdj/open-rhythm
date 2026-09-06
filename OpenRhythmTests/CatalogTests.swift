import XCTest
@testable import OpenRhythm

final class CatalogTests: XCTestCase {
  private let server = ServerDescriptor.defaults[0]

  func testGroupsDifficultiesByBGM() {
    let levels = [
      level(name: "easy", rating: 1, difficulty: "#EASY"),
      level(name: "expert", rating: 9, difficulty: "#EXPERT")
    ]

    let songs = CatalogBuilder.group(levels: levels, server: server)

    XCTAssertEqual(songs.count, 1)
    XCTAssertEqual(songs[0].variants.map(\.difficulty), [.easy, .expert])
  }

  func testSearchesAcrossJapaneseAndEnglishValues() {
    let song = CatalogBuilder.group(
      levels: [level(name: "expert", rating: 9, difficulty: "#EXPERT")],
      server: server
    )[0]

    XCTAssertTrue(song.matches(query: "Bokura"))
    XCTAssertTrue(song.matches(query: "僕ら"))
    XCTAssertTrue(song.matches(query: "muse"))
    XCTAssertFalse(song.matches(query: "Aqours"))
  }

  func testDifficultyFilter() {
    let song = CatalogBuilder.group(
      levels: [level(name: "expert", rating: 9, difficulty: "#EXPERT")],
      server: server
    )[0]
    var filter = CatalogFilter()
    filter.difficulties = [.master]

    XCTAssertTrue(filter.apply(to: [song]).isEmpty)
  }

  private func level(
    name: String,
    rating: Int,
    difficulty: String
  ) -> SonolusLevelItem {
    SonolusLevelItem(
      name: name,
      source: server.baseURL.absoluteString,
      version: 1,
      rating: rating,
      title: LocalizedText(
        #"##LOCALIZE:{"ja":"僕らのLIVE 君とのLIFE","en":"Bokura no LIVE Kimi to no LIFE"}"#
      ),
      artists: LocalizedText(
        #"##LOCALIZE:{"ja":"μ's","en":"Muse"}"#
      ),
      author: "Test",
      tags: [SonolusTag(title: difficulty)],
      cover: ResourceLocator(hash: nil, url: "/cover.png"),
      bgm: ResourceLocator(hash: nil, url: "/song.mp3"),
      data: ResourceLocator(hash: nil, url: "/level.json")
    )
  }
}

