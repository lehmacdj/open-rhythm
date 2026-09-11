import XCTest
@testable import OpenRhythm

final class CatalogTests: XCTestCase {
  func testRemovedEngineScoreChoiceFallsBackToCurrentDefault() throws {
    let option = try JSONDecoder().decode(EngineConfiguration.Option.self,
      from: Data(#"{"def":1,"name":"Score Mode","values":["Flat","Combo"]}"#.utf8))
    XCTAssertEqual(option.selectedIndex(3), 1)
    XCTAssertEqual(option.selectedIndex(-1), 1)
    XCTAssertEqual(option.selectedIndex(nil), 1)
    XCTAssertEqual(option.selectedIndex(0), 0)
  }

  func testNewJudgementSettingsPreserveExistingPreferences() throws {
    let old = Data(#"{"scoreDisplay":"countDown","noteSpeed":8}"#.utf8)
    var settings = try JSONDecoder().decode(GameplayPreferences.self, from: old)
    XCTAssertEqual(settings.scoreDisplay, .countDown)
    XCTAssertEqual(settings.noteSpeed, 8)
    XCTAssertEqual(settings.judgementDisplay, .timing)
    settings.judgementDisplay = .off
    XCTAssertEqual(try JSONDecoder().decode(GameplayPreferences.self,
      from: JSONEncoder().encode(settings)), settings)
  }

  private let server = ServerDescriptor.defaults[0]

  func testRangeSelectsLowestMatchingChartAndSeparatesEngines() {
    var levels = zip([1, 5, 7, 9, 11],
      ["#EASY", "#NORMAL", "#HARD", "#EXPERT", "#MASTER"]).map {
      level(name: $0.1, rating: $0.0, difficulty: $0.1)
    }
    var filter = CatalogFilter()
    filter.minimumRating = 7
    filter.maximumRating = 9
    let song = CatalogBuilder.group(levels: levels, server: server)[0]
    XCTAssertEqual(filter.matchingVariants(in: song).map(\.rating), [7, 9])
    filter.difficulties = [.easy]
    XCTAssertTrue(filter.apply(to: [song]).isEmpty,
      "The same chart must satisfy both rating and chart-type filters")
    levels[0].engine = SonolusEngineIdentity(name: "one")
    levels[1].engine = SonolusEngineIdentity(name: "two")
    XCTAssertEqual(CatalogBuilder.group(levels: Array(levels.prefix(2)),
      server: server).count, 2, "Shared music must not merge different engines")
  }

  @MainActor
  func testPreferencesPersistPerEngineButNotSearch() throws {
    let name = "OpenRhythmTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = UserPreferences(defaults: defaults)
    var filter = CatalogFilter()
    filter.query = "temporary search"
    filter.sort = .artist
    filter.minimumRating = 7
    filter.maximumRating = 9
    preferences.save(filter, for: "one")
    preferences.save(GameplayPreferences(scoreDisplay: .countDown, noteSpeed: 8,
      judgementDisplay: .off, scoreMode: 2),
      for: "one")
    let reopened = UserPreferences(defaults: defaults)
    filter.query = ""
    XCTAssertEqual(reopened.filter(for: "one"), filter)
    XCTAssertEqual(reopened.filter(for: "two"), CatalogFilter())
    XCTAssertEqual(reopened.gameplay(for: "one").noteSpeed, 8)
    XCTAssertEqual(reopened.gameplay(for: "one").judgementDisplay, .off)
    XCTAssertEqual(reopened.gameplay(for: "one").scoreMode, 2)
    XCTAssertEqual(reopened.gameplay(for: "two"), GameplayPreferences())
    XCTAssertEqual(ScoreDisplayMode.countDown.score(judgements: [:],
      noteCount: 10), 1_000_000)
    XCTAssertEqual(ScoreDisplayMode.countDown.score(judgements: [.miss: 1],
      noteCount: 10), 900_000)
    let all: [NoteJudgement: Int] = [.perfect: 7, .great: 1, .good: 1, .miss: 1]
    XCTAssertEqual(ScoreDisplayMode.countDown.score(judgements: all, noteCount: 10),
      ScoreDisplayMode.countUp.score(judgements: all, noteCount: 10))
  }

  @MainActor
  func testServerEditsPersistAndCorruptConfigurationIsPreserved() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("servers.json")
    let store = ServerStore(fileURL: url)
    let normalized = try ServerDescriptor.normalizedURL(" EXAMPLE.com:443/path/ ")
    XCTAssertEqual(normalized.absoluteString, "https://example.com/path")
    XCTAssertThrowsError(try ServerDescriptor.normalizedURL("file:///tmp"))
    XCTAssertThrowsError(try ServerDescriptor.normalizedURL("https://a:b@example.com"))
    try store.add(url: normalized, name: "New")
    XCTAssertThrowsError(try store.add(url: normalized, name: "Duplicate"))
    try store.move(from: IndexSet(integer: 1), to: 0)
    XCTAssertEqual(ServerStore(fileURL: url).servers.first?.name, "New")
    try store.remove(at: IndexSet(integersIn: 0..<store.servers.count))
    XCTAssertTrue(ServerStore(fileURL: url).servers.isEmpty)
    let corrupt = Data("not JSON".utf8)
    try corrupt.write(to: url)
    let broken = ServerStore(fileURL: url)
    XCTAssertNotNil(broken.loadError)
    XCTAssertThrowsError(try broken.add(url: normalized, name: "New"))
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
  }

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

  func testSearchesJapaneseOnlyTextByJapaneseRomanization() {
    let song = CatalogBuilder.group(
      levels: [level(
        name: "expert",
        rating: 9,
        difficulty: "#EXPERT",
        title: LocalizedText(#"##LOCALIZE:{"ja":"僕ら"}"#)
      )],
      server: server
    )[0]

    XCTAssertTrue(song.matches(query: "bokura"))
    XCTAssertFalse(song.matches(query: "pura"))
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

  func testResultKeysIncludeServerOrigin() {
    let value = level(
      name: "shared",
      rating: 9,
      difficulty: "#EXPERT",
      source: nil
    )
    let otherServer = ServerDescriptor(
      id: "other",
      name: "Other",
      baseURL: URL(string: "https://other.example")!
    )

    XCTAssertNotEqual(
      value.resultKey(server: server),
      value.resultKey(server: otherServer)
    )
  }

  private func level(
    name: String,
    rating: Int,
    difficulty: String,
    title: LocalizedText? = nil,
    source: String? = "https://sonolus.milkbun.org/llsif"
  ) -> SonolusLevelItem {
    SonolusLevelItem(
      name: name,
      source: source,
      version: 1,
      rating: rating,
      title: title ?? LocalizedText(
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
