import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
  private let server: ServerDescriptor
  private let client: SonolusClient
  private var levelsByID = [String: SonolusLevelItem]()
  private var generation = 0

  var songs = [CatalogSong]()
  var filter = CatalogFilter()
  var isLoading = false
  var loadedPageCount = 0
  var totalPageCount = 0
  var errorMessage: String?

  init(server: ServerDescriptor, client: SonolusClient = SonolusClient()) {
    self.server = server
    self.client = client
  }

  var visibleSongs: [CatalogSong] {
    filter.apply(to: songs)
  }

  func refresh() async {
    generation += 1
    let currentGeneration = generation
    levelsByID.removeAll()
    songs.removeAll()
    loadedPageCount = 0
    totalPageCount = 0
    errorMessage = nil
    isLoading = true
    defer {
      if currentGeneration == generation {
        isLoading = false
      }
    }

    do {
      let first = try await client.levels(
        on: server,
        page: 0
      )
      guard currentGeneration == generation else { return }
      merge(first.items)
      totalPageCount = first.pageCount
      loadedPageCount = 1

      try await loadRemainingPages(
        in: first.pageCount,
        generation: currentGeneration
      )
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }

  private func loadRemainingPages(
    in pageCount: Int,
    generation currentGeneration: Int
  ) async throws {
    guard pageCount > 1 else { return }

    try await withThrowingTaskGroup(
      of: [SonolusLevelItem].self
    ) { group in
      let maximumConcurrentRequests = 6
      var nextPage = 1

      func addNextPage() {
        guard nextPage < pageCount else { return }
        let page = nextPage
        nextPage += 1
        group.addTask { [client, server] in
          try await client.levels(on: server, page: page).items
        }
      }

      for _ in 0..<min(maximumConcurrentRequests, pageCount - 1) {
        addNextPage()
      }

      while let items = try await group.next() {
        guard currentGeneration == generation else {
          group.cancelAll()
          return
        }
        merge(items)
        loadedPageCount += 1
        addNextPage()
      }
    }
  }

  private func merge(_ levels: [SonolusLevelItem]) {
    for level in levels {
      levelsByID[level.id] = level
    }
    songs = CatalogBuilder.group(
      levels: Array(levelsByID.values),
      server: server
    )
  }
}
