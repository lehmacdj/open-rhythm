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
  private struct PrefetchedPage {
    let requestCursor: String?
    let response: SonolusLevelList
  }
  private var prefetchedPages = [Int: PrefetchedPage]()
  private var prefetchRevision = 0
  private var pageCursors = [Int: String]()
  private var usesCursors = false

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
  var canRefreshAfterError: Bool { errorMessage != nil && loadedPageCount > 0 }
  var showsPaginationStatus: Bool {
    if errorMessage != nil && !isLoading { return true }
    return loadedPageCount > 0 && (isLoading || (hasMorePages
      && (visibleSongs.isEmpty || needsMoreMatches)))
  }

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

  private func updateVisibleSongs(preservingOrder: Bool = false) {
    let matching = filter.apply(to:
      songs.filter { $0.engineKey == selectedEngineKey })
    guard preservingOrder else { visibleSongs = matching; return }
    // Sorting an enlarged partial catalog would insert new pages above the
    // reader's scroll position. Keep existing rows (with refreshed metadata)
    // in place and append sorted new matches. An explicit filter/sort change
    // still sorts the entire loaded selection.
    let byID = Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })
    let previousIDs = Set(visibleSongs.map(\.id))
    visibleSongs = visibleSongs.compactMap { byID[$0.id] }
      + matching.filter { !previousIDs.contains($0.id) }
  }

  func refresh(forceReload: Bool = false) async {
    generation += 1
    activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    reloadPages = forceReload
    prefetchRevision += 1
    prefetchedPages.removeAll()
    pageCursors.removeAll()
    usesCursors = false
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
    // Empty searches may report zero pages even though page 0 was fetched.
    guard loadedPageCount > 0, hasMorePages,
      normalizedQuery == activeQuery, errorMessage == nil else { return }
    let currentGeneration = generation
    let currentRevision = prefetchRevision
    let query = activeQuery
    let start = loadedPageCount
    let count = usesCursors ? 2 : min(2, totalPageCount - start)
    var cursor = pageCursors[start]
    var numberedEnd = totalPageCount
    for page in start..<(start + count) {
      guard !Task.isCancelled, generation == currentGeneration,
        prefetchRevision == currentRevision, errorMessage == nil,
        usesCursors ? cursor != nil : page < numberedEnd else { return }
      if let buffered = prefetchedPages[page], buffered.requestCursor == cursor,
        isFresh(buffered.response.fetchedAt) {
        cursor = buffered.response.cursor
        if !usesCursors { numberedEnd = min(numberedEnd, buffered.response.pageCount) }
        continue
      }
      do {
        let response = try await client.levels(on: server, page: page,
          query: query, cursor: cursor, forceReload: reloadPages)
        // A list append cancels its old prefetch task. Keep a completed
        // response in the same generation so forced refreshes don't fetch
        // that page twice when the replacement task starts.
        guard generation == currentGeneration,
          prefetchRevision == currentRevision, errorMessage == nil else { return }
        guard (response.pageCount < 0) == usesCursors else { return }
        if page >= loadedPageCount {
          prefetchedPages[page] = PrefetchedPage(requestCursor: cursor,
            response: response)
        }
        if usesCursors, let next = response.cursor,
          next == cursor || pageCursors.values.contains(next) { return }
        if !usesCursors { numberedEnd = min(numberedEnd, response.pageCount) }
        cursor = response.cursor
      } catch { return } // A visible load reports errors and offers retry.
    }
  }

  func retryPage() async {
    guard errorMessage != nil else { return }
    await loadNextPage(forceReload: true)
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
      let buffered = prefetchedPages.removeValue(forKey: page)
      if !forceReload, let buffered,
        buffered.requestCursor == pageCursors[page],
        isFresh(buffered.response.fetchedAt) {
        response = buffered.response
      } else {
        // A refetched parent can change the cursor or numbered-page ordering.
        // Discard its speculative descendants, including in-flight completions.
        prefetchRevision += 1
        prefetchedPages = prefetchedPages.filter { $0.key < page }
        if forceReload || buffered != nil { reloadPages = true }
        response = try await client.levels(on: server, page: page,
          query: requestedQuery, cursor: pageCursors[page],
          forceReload: forceReload || reloadPages)
      }
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      if page > 0, (response.pageCount < 0) != usesCursors {
        throw SonolusClientError.invalidResponse
      }
      if response.pageCount < 0, let next = response.cursor,
        pageCursors.values.contains(next) {
        throw SonolusClientError.invalidResponse
      }
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
      updateVisibleSongs(preservingOrder: page > 0)
      needsMoreMatches = !previousIDs.isEmpty
        && Set(visibleSongs.map(\.id)).subtracting(previousIDs).isEmpty
      usesCursors = response.pageCount < 0
      if usesCursors {
        pageCursors[page + 1] = response.cursor
        totalPageCount = page + (response.cursor == nil ? 1 : 2)
      } else {
        totalPageCount = max(0, response.pageCount)
      }
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
