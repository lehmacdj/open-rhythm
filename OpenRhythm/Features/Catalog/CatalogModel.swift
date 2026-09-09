import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
  private let server: ServerDescriptor
  private let client: SonolusClient
  private var levelsByID = [String: SonolusLevelItem]()
  private var generation = 0
  private var activeQuery = ""

  private(set) var songs = [CatalogSong]()
  var query = ""
  var filter = CatalogFilter() {
    didSet { visibleSongs = filter.apply(to: songs) }
  }
  private(set) var visibleSongs = [CatalogSong]()
  private(set) var isLoading = false
  private(set) var loadedPageCount = 0
  private(set) var totalPageCount = 0
  private(set) var errorMessage: String?

  var hasMorePages: Bool { loadedPageCount < totalPageCount }

  init(server: ServerDescriptor, client: SonolusClient = SonolusClient()) {
    self.server = server
    self.client = client
  }

  func refresh(forceReload: Bool = false) async {
    generation += 1
    activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    levelsByID.removeAll()
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
      await refresh()
    } catch { }
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
      for level in response.items { levelsByID[level.id] = level }
      let levels = Array(levelsByID.values)
      let server = server
      let grouped = await Task.detached(priority: .userInitiated) {
        CatalogBuilder.group(levels: levels, server: server)
      }.value
      try Task.checkCancellation()
      guard currentGeneration == generation else { return }
      songs = grouped
      // Server search covers unloaded pages. Local filters only select sort
      // and difficulty, preserving aliases supported by the server.
      visibleSongs = filter.apply(to: songs)
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
