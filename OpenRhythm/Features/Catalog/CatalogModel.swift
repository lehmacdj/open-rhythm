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
        page: 0,
        query: filter.query
      )
      guard currentGeneration == generation else { return }
      merge(first.items)
      totalPageCount = first.pageCount
      loadedPageCount = 1

      if first.pageCount > 1 {
        for page in 1..<first.pageCount {
          let response = try await client.levels(
            on: server,
            page: page,
            query: filter.query
          )
          guard currentGeneration == generation else { return }
          merge(response.items)
          loadedPageCount = page + 1
        }
      }
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
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

