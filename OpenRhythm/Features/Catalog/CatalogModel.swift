import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
  private let server: ServerDescriptor
  private let client: SonolusClient
  private let preferences: UserPreferences
  private var generation = 0
  private var activeQuery = ""

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

  var hasMorePages: Bool { loadedPageCount < totalPageCount }

  init(server: ServerDescriptor, client: SonolusClient = SonolusClient(),
    preferences: UserPreferences = .shared
  ) {
    self.server = server
    self.client = client
    self.preferences = preferences
    selectedEngineKey = server.preferenceKey
    filter = preferences.filter(for: server.preferenceKey)
  }

  private func updateVisibleSongs() {
    visibleSongs = filter.apply(to: songs.filter { $0.engineKey == selectedEngineKey })
  }

  func refresh(forceReload: Bool = false) async {
    generation += 1
    activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    songs.removeAll()
    visibleSongs.removeAll()
    loadedPageCount = 0
    totalPageCount = 1
    isLoading = false
    await loadNextPage(forceReload: forceReload)
  }

  func searchAfterDelay() async {
    do {
      try await Task.sleep(for: .milliseconds(300))
      try Task.checkCancellation()
      guard loadedPageCount == 0 || normalizedQuery != activeQuery else { return }
      await refresh()
    } catch { }
  }

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func loadMoreIfNeeded(after songID: String) async {
    // Ignore appearances from old search results during the debounce interval.
    // An error requires an explicit retry, not repeated scroll-driven requests.
    guard normalizedQuery == activeQuery, errorMessage == nil,
      visibleSongs.suffix(3).contains(where: { $0.id == songID }) else { return }
    await loadNextPage()
  }

  func loadNextPage(forceReload: Bool = false) async {
    guard !isLoading, hasMorePages else { return }
    let currentGeneration = generation
    let requestedQuery = activeQuery
    let page = loadedPageCount
    isLoading = true
    errorMessage = nil
    defer {
      if currentGeneration == generation { isLoading = false }
    }
    do {
      let response = try await client.levels(on: server, page: page,
        query: requestedQuery, forceReload: forceReload)
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      let previous = songs
      let server = server
      let grouped = await Task.detached(priority: .userInitiated) {
        CatalogBuilder.merge(songs: previous, levels: response.items, server: server)
      }.value
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      songs = grouped
      if !engines.contains(where: { $0.id == selectedEngineKey }),
        let first = engines.first {
        selectedEngineKey = first.id
      }
      // Server search covers unloaded pages. Local filters only select sort
      // and difficulty, preserving aliases supported by the server.
      updateVisibleSongs()
      totalPageCount = max(0, response.pageCount)
      loadedPageCount = page + 1
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }
}
