import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
  private let server: ServerDescriptor
  private let client: SonolusClient
  private let preferences: UserPreferences
  private let now: () -> Date
  private var generation = 0
  private var activeQuery = ""
  private var firstPageFetchedAt: Date?
  private var reloadPages = false
  private var prefetchedPages = [Int: SonolusLevelList]()

  private(set) var songs = [CatalogSong]()
  var query = ""
  var filter = CatalogFilter() {
    didSet {
      preferences.save(filter, for: selectedEngineKey)
      updateVisibleSongs()
    }
  }
  var selectedEngineKey: String {
    didSet {
      guard oldValue != selectedEngineKey else { return }
      filter = preferences.filter(for: selectedEngineKey)
    }
  }
  var engines: [CatalogEngineChoice] { CatalogEngineChoice.choices(in: songs) }
  private(set) var visibleSongs = [CatalogSong]()
  private(set) var isLoading = false
  private(set) var loadedPageCount = 0
  private(set) var totalPageCount = 0
  private(set) var errorMessage: String?
  private(set) var needsMoreMatches = false

  var hasMorePages: Bool { loadedPageCount < totalPageCount }

  init(server: ServerDescriptor, client: SonolusClient = SonolusClient(),
    preferences: UserPreferences = .shared, now: @escaping () -> Date = Date.init
  ) {
    self.server = server
    self.client = client
    self.preferences = preferences
    self.now = now
    selectedEngineKey = server.preferenceKey
    filter = preferences.filter(for: server.preferenceKey)
  }

  private func updateVisibleSongs() {
    visibleSongs = filter.apply(to: songs.filter { $0.engineKey == selectedEngineKey })
  }

  func refresh(forceReload: Bool = false) async {
    generation += 1
    activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    reloadPages = forceReload
    prefetchedPages.removeAll()
    songs.removeAll()
    visibleSongs.removeAll()
    loadedPageCount = 0
    needsMoreMatches = false
    totalPageCount = 1
    isLoading = false
    await loadNextPage(forceReload: forceReload)
  }

  func searchAfterDelay() async {
    do {
      try await Task.sleep(for: .milliseconds(300))
      try Task.checkCancellation()
      let expired = firstPageFetchedAt.map {
        !isFresh($0)
      } ?? false
      guard loadedPageCount == 0 || normalizedQuery != activeQuery || expired else { return }
      await refresh(forceReload: expired)
    } catch { }
  }

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func loadMoreIfNeeded(after songID: String) async {
    // Ignore appearances from old search results during the debounce interval.
    // An error requires an explicit retry, not repeated scroll-driven requests.
    guard normalizedQuery == activeQuery, errorMessage == nil,
      visibleSongs.suffix(max(3, min(12, visibleSongs.count / 2)))
        .contains(where: { $0.id == songID }) else { return }
    let currentGeneration = generation
    for _ in 0..<2 {
      await loadNextPage()
      guard generation == currentGeneration, needsMoreMatches,
        hasMorePages, errorMessage == nil else { return }
    }
  }

  func prefetchNextPages() async {
    guard loadedPageCount > 0, normalizedQuery == activeQuery else { return }
    let currentGeneration = generation
    let query = activeQuery
    let start = loadedPageCount
    for page in start..<min(start + 2, totalPageCount) {
      guard !Task.isCancelled, generation == currentGeneration else { return }
      if let buffered = prefetchedPages[page], isFresh(buffered.fetchedAt) { continue }
      do {
        let response = try await client.levels(on: server, page: page,
          query: query, forceReload: reloadPages)
        // A list append cancels its old prefetch task. Keep a completed
        // response in the same generation so forced refreshes don't fetch
        // that page twice when the replacement task starts.
        guard generation == currentGeneration else { return }
        if page >= loadedPageCount { prefetchedPages[page] = response }
      } catch { return } // A visible load reports errors and offers retry.
    }
  }

  func loadNextPage(forceReload: Bool = false) async {
    guard !isLoading, hasMorePages else { return }
    if loadedPageCount > 0, let firstPageFetchedAt, !isFresh(firstPageFetchedAt) {
      await refresh(forceReload: true)
      return
    }
    let currentGeneration = generation
    let requestedQuery = activeQuery
    let page = loadedPageCount
    isLoading = true
    errorMessage = nil
    defer {
      if currentGeneration == generation { isLoading = false }
    }
    do {
      let response: SonolusLevelList
      if !forceReload, let buffered = prefetchedPages.removeValue(forKey: page),
        isFresh(buffered.fetchedAt) {
        response = buffered
      } else {
        response = try await client.levels(on: server, page: page,
          query: requestedQuery, forceReload: forceReload || reloadPages)
      }
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      let previous = songs
      let server = server
      let grouped = await Task.detached(priority: .userInitiated) {
        CatalogBuilder.merge(songs: previous, levels: response.items, server: server)
      }.value
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      let previousIDs = Set(visibleSongs.map(\.id))
      songs = grouped
      if page == 0 { firstPageFetchedAt = response.fetchedAt }
      if !engines.contains(where: { $0.id == selectedEngineKey }),
        let first = engines.first {
        selectedEngineKey = first.id
      }
      // Server search covers unloaded pages. Local filters only select sort
      // and difficulty, preserving aliases supported by the server.
      updateVisibleSongs()
      needsMoreMatches = !previousIDs.isEmpty
        && Set(visibleSongs.map(\.id)).subtracting(previousIDs).isEmpty
      totalPageCount = max(0, response.pageCount)
      loadedPageCount = page + 1
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }

  private func isFresh(_ date: Date) -> Bool {
    let age = now().timeIntervalSince(date)
    return age >= 0 && age < 600
  }
}
