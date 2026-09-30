import XCTest
@testable import OpenRhythm

final class CatalogTests: XCTestCase {
  func testBGMAliasesGroupDifficultiesWithoutChangingExistingRows() throws {
    let hash = String(repeating: "a", count: 40)
    func item(_ id: String, hash: String?, url: String?, engine: String? = nil)
      -> SonolusLevelItem {
      let empty = ResourceLocator(hash: nil, url: nil)
      return SonolusLevelItem(name: id, source: nil, version: 1, rating: 7,
        title: LocalizedText("Song"), artists: LocalizedText("Artist"),
        author: "Fixture", tags: [], cover: empty,
        bgm: ResourceLocator(hash: hash, url: url), data: empty,
        engine: engine.map { SonolusEngineIdentity(name: $0) })
    }
    let a = item("a", hash: hash, url: "/music")
    let b = item("b", hash: hash.uppercased(), url: nil)
    let c = item("c", hash: nil, url: "/music")
    let d = item("d", hash: hash, url: "/alias")
    let e = item("e", hash: nil, url: "/alias")
    let all = [a, b, c, d, e]
    for start in all {
      let first = CatalogBuilder.group(levels: [start], server: server)
      let merged = CatalogBuilder.merge(songs: first,
        levels: all.filter { $0.id != start.id }, server: server)
      XCTAssertEqual(merged.count, 1)
      XCTAssertEqual(merged.first?.id, first[0].id)
      XCTAssertEqual(merged.first?.variants.map(\.id), ["a", "b", "c", "d", "e"])
      let repeated = CatalogBuilder.merge(songs: merged, levels: all, server: server)
      XCTAssertEqual(repeated, merged)
    }
    let sameTitleDifferentHash = item("other", hash: String(repeating: "b", count: 40), url: nil)
    let otherEngine = item("other-engine", hash: hash, url: "/music", engine: "another")
    XCTAssertEqual(CatalogBuilder.group(levels: all + [sameTitleDifferentHash, otherEngine],
      server: server).count, 3)
    let unbridged = CatalogBuilder.group(levels: [b, c], server: server)
    XCTAssertEqual(unbridged.count, 2, "A title match is not proof of a resource alias")
    let bridged = CatalogBuilder.merge(songs: unbridged, levels: [a], server: server)
    XCTAssertEqual(bridged.count, 1)
    XCTAssertTrue(unbridged.contains { $0.id == bridged[0].id })
    let original = CatalogBuilder.group(levels: [a, c], server: server)
    let moved = item("a", hash: String(repeating: "c", count: 40), url: "/changed")
    let split = CatalogBuilder.merge(songs: original, levels: [moved], server: server)
    XCTAssertEqual(split.count, 2)
    XCTAssertEqual(Set(split.map(\.id)).count, 2, "A split must not duplicate a SwiftUI ID")
    XCTAssertEqual(split.first { $0.variants.contains { $0.id == "a" } }?.id, original[0].id)
    XCTAssertEqual(split.flatMap(\.variants).filter { $0.id == "a" }, [moved],
      "A metadata update replaces the chart rather than leaving a stale duplicate")
  }

  @MainActor
  func testOfflineVisibleRowsFollowSongsFiltersAndEnginePreferences() throws {
    let suite = "OfflineVisibleRows.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = UserPreferences(defaults: defaults)
    let first = server.preferenceKey
    var other = level(name: "other", rating: 18, difficulty: "#HARD")
    other.engine = SonolusEngineIdentity(name: "other-engine")
    let second = other.engineKey(server: server)
    var firstFilter = CatalogFilter()
    firstFilter.sort = .artist
    firstFilter.minimumRating = 7
    firstFilter.maximumRating = 8
    preferences.save(firstFilter, for: first)
    var secondFilter = CatalogFilter()
    secondFilter.minimumRating = 17
    preferences.save(secondFilter, for: second)
    func song(_ id: String, title: String, artist: String,
      level: SonolusLevelItem) -> CatalogSong {
      CatalogSong(id: id, server: server, title: LocalizedText(title),
        artists: LocalizedText(artist), coverURL: nil, variants: [level],
        levelOrigins: [])
    }
    let a = song("a", title: "Zulu", artist: "Alpha", level:
      level(name: "a", rating: 7, difficulty: "#HARD"))
    let b = song("b", title: "Alpha", artist: "Zulu", level:
      level(name: "b", rating: 9, difficulty: "#HARD"))
    let c = song("c", title: "Other", artist: "Other", level: other)
    let model = OfflineCatalogModel(preferences: preferences)
    model.songs = [b, c, a]
    model.selectedEngineKey = first
    XCTAssertEqual(model.visibleSongs.map(\.id), ["a"])
    model.filter.maximumRating = 10
    XCTAssertEqual(model.visibleSongs.map(\.id), ["a", "b"])
    for _ in 0..<10 {
      XCTAssertEqual(model.visibleSongs.map(\.id), ["a", "b"])
    }
    model.filter.query = "Zulu"
    model.selectedEngineKey = second
    XCTAssertEqual(model.filter.query, "Zulu", "Search stays session-only")
    XCTAssertEqual(model.filter.minimumRating, 17)
    XCTAssertTrue(model.visibleSongs.isEmpty)
    model.filter.query = ""
    XCTAssertEqual(model.visibleSongs.map(\.id), ["c"])
    model.selectedEngineKey = first
    XCTAssertEqual(model.filter.maximumRating, 10)
    XCTAssertEqual(model.filter.sort, .artist)
    XCTAssertEqual(model.visibleSongs.map(\.id), ["a", "b"])
    model.filter.sort = .title
    XCTAssertEqual(model.visibleSongs.map(\.id), ["b", "a"])
    // Refreshes can replace metadata without changing the stable row ID.
    let updated = song("b", title: "Updated", artist: "Zulu",
      level: b.variants[0])
    model.songs = [updated, c]
    XCTAssertEqual(model.visibleSongs.map(\.id), ["b"])
    XCTAssertEqual(model.visibleSongs.first?.title, LocalizedText("Updated"))
    model.songs.removeAll()
    XCTAssertTrue(model.visibleSongs.isEmpty, "Deletion must invalidate rows")
    model.songs = [a, b, c]
    model.filter.query = "no match"
    XCTAssertTrue(model.visibleSongs.isEmpty)
    let reopened = OfflineCatalogModel(preferences: preferences)
    reopened.songs = model.songs
    reopened.selectedEngineKey = first
    XCTAssertEqual(reopened.filter.query, "")
    XCTAssertEqual(reopened.filter.sort, .title)
    XCTAssertEqual(reopened.visibleSongs.map(\.id), ["b", "a"])
  }

  func testSortKeysPreserveFilteringLocalizationAndStableTies() {
    let songs: [CatalogSong] = (0..<40).map { index in
      let title = LocalizedText(
        "##LOCALIZE:{\"en\":\"Song \(index % 7)\","
          + "\"ja\":\"曲 \(6 - index % 7)\"}")
      let variants = [
        level(name: "\(index)-easy", rating: Double(index % 9) + 0.5,
          difficulty: "#EASY", title: title),
        level(name: "\(index)-hard", rating: Double(index % 11) + 5.5,
          difficulty: "#HARD", title: title),
        level(name: "\(index)-expert", rating: Double(index % 13) + 7.5,
          difficulty: "#EXPERT", title: title)
      ]
      return CatalogSong(id: String(index), server: server, title: title,
        artists: LocalizedText("Artist \(index % 4)"), coverURL: nil,
        variants: index == 39 ? [] : variants.reversed(), levelOrigins: [])
    }
    // Independent simple reference: materialize the ordered matching charts,
    // then compare song metadata directly, as the previous implementation did.
    for locale in [Locale(identifier: "en_US"), Locale(identifier: "ja_JP")] {
      for sort in CatalogSort.allCases {
        for query in ["", "Song 2", "Artist 1", "no matches"] {
          for bounded in [false, true] {
            var filter = CatalogFilter()
            filter.sort = sort
            filter.query = query
            if bounded {
              filter.minimumRating = 7.5
              filter.maximumRating = 12.5
              filter.difficulties = [.hard, .expert]
            }
            let expected = songs.filter {
              !filter.matchingVariants(in: $0).isEmpty
                && (query.isEmpty || $0.matches(query: query))
            }.sorted { left, right in
              if sort == .difficulty {
                let a = filter.matchingVariants(in: left).first!.rating
                let b = filter.matchingVariants(in: right).first!.rating
                if a != b { return a < b }
              }
              let a = (sort == .artist ? left.artists : left.title)
                .displayValue(locale: locale)
              let b = (sort == .artist ? right.artists : right.title)
                .displayValue(locale: locale)
              let order = a.localizedStandardCompare(b)
              return order == .orderedSame ? left.id < right.id
                : order == .orderedAscending
            }.map(\.id)
            XCTAssertEqual(filter.apply(to: songs, locale: locale).map(\.id),
              expected, "\(locale.identifier) \(sort) \(query) \(bounded)")
            XCTAssertEqual(
              filter.apply(to: songs.reversed(), locale: locale).map(\.id),
              expected, "Input order must not change deterministic tie breaks")
          }
        }
      }
    }
  }

  @MainActor
  func testFractionalRatingsDecodeFilterAndPersistWithoutTruncation() throws {
    let json = #"""
      {"pageCount":1,"items":[{"name":"nanaon-pro","version":1,
      "rating":4.9,"title":"Song","artists":"Artist","author":"Fixture",
      "tags":[{"title":"#PRO"}],"cover":{},"bgm":{"url":"music.mp3"},"data":{}}]}
      """#
    let page = try JSONDecoder().decode(SonolusLevelList.self, from: Data(json.utf8))
    XCTAssertEqual(page.items[0].rating, 4.9)
    XCTAssertEqual(page.items[0].difficulty, .pro)
    let variants = [page.items[0], level(name: "hard", rating: 2.9, difficulty: "#HARD"),
      level(name: "expert", rating: 3.4, difficulty: "#EXPERT")]
    var song = CatalogBuilder.group(levels: [page.items[0]], server: server)[0]
    // Helpers use different BGM URLs; explicitly compose this one-song fixture.
    song = CatalogSong(id: song.id, server: server, title: song.title,
      artists: song.artists, coverURL: nil, variants: variants, levelOrigins: [])
    var filter = CatalogFilter()
    filter.minimumRating = 2.9
    filter.maximumRating = 3.4
    XCTAssertEqual(filter.matchingVariants(in: song).map(\.rating), [2.9, 3.4])
    let suite = "FractionalRatings.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    UserPreferences(defaults: defaults).save(filter, for: "nanaon")
    XCTAssertEqual(UserPreferences(defaults: defaults).filter(for: "nanaon"), filter)
    let integerJSON = json.replacingOccurrences(of: "4.9", with: "18")
    XCTAssertEqual(try JSONDecoder().decode(SonolusLevelList.self,
      from: Data(integerJSON.utf8)).items[0].rating, 18)
  }
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
    settings.engineOptions = ["#MIRROR": 1, "custom": 0.75]
    settings.judgementDisplay = .off
    XCTAssertEqual(try JSONDecoder().decode(GameplayPreferences.self,
      from: JSONEncoder().encode(settings)), settings)
  }

  private let server = ServerDescriptor.defaults[0]

  func testUpdatedDownloadRepairsRemovedDifficultySelection() {
    let levels = [level(name: "easy", rating: 1, difficulty: "#EASY"),
      level(name: "hard", rating: 7, difficulty: "#HARD"),
      level(name: "expert", rating: 9, difficulty: "#EXPERT")]
    let base = CatalogBuilder.group(levels: [levels[0]], server: server)[0]
    let updated = CatalogSong(id: base.id, server: server, title: base.title,
      artists: base.artists, coverURL: nil, variants: levels, levelOrigins: [])
    var filter = CatalogFilter()
    filter.minimumRating = 7
    filter.maximumRating = 9
    XCTAssertEqual(filter.selectedLevelID(in: updated, preserving: "retired"), "hard")
    XCTAssertEqual(filter.selectedLevelID(in: updated, preserving: "expert"), "expert")
    XCTAssertEqual(filter.selectedLevelID(in: updated), "hard")
    filter.minimumRating = 20
    XCTAssertEqual(filter.selectedLevelID(in: updated, preserving: "retired"), "easy")
    let empty = CatalogSong(id: base.id, server: server, title: base.title,
      artists: base.artists, coverURL: nil, variants: [], levelOrigins: [])
    XCTAssertEqual(filter.selectedLevelID(in: empty, preserving: "retired"), "")
  }

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
      judgementDisplay: .off, scoreMode: 2, engineOptions: ["#MIRROR": 1],
      skinRenderMode: .lightweight, inputOffsetMilliseconds: -35,
      visualOffsetMilliseconds: 42),
      for: "one")
    let reopened = UserPreferences(defaults: defaults)
    filter.query = ""
    XCTAssertEqual(reopened.filter(for: "one"), filter)
    XCTAssertEqual(reopened.filter(for: "two"), CatalogFilter())
    XCTAssertEqual(reopened.gameplay(for: "one").noteSpeed, 8)
    XCTAssertEqual(reopened.gameplay(for: "one").judgementDisplay, .off)
    XCTAssertEqual(reopened.gameplay(for: "one").scoreMode, 2)
    XCTAssertEqual(reopened.gameplay(for: "one").skinRenderMode, .lightweight)
    XCTAssertEqual(reopened.gameplay(for: "one").inputOffsetSeconds, -0.035)
    XCTAssertEqual(reopened.gameplay(for: "one").visualOffsetSeconds, 0.042)
    XCTAssertEqual(reopened.gameplay(for: "one").engineOptions, ["#MIRROR": 1])
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
    rating: Double,
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
