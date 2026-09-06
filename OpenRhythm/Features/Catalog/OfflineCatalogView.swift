import Observation
import SwiftUI

@MainActor
@Observable
private final class OfflineCatalogModel {
  var songs = [CatalogSong]()
  var filter = CatalogFilter()
  var errorMessage: String?

  var visibleSongs: [CatalogSong] {
    filter.apply(to: songs)
  }

  func refresh() async {
    do {
      songs = try await OfflineStore.shared.catalogSongs()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct OfflineCatalogView: View {
  @State private var model = OfflineCatalogModel()

  var body: some View {
    List {
      if let errorMessage = model.errorMessage {
        ContentUnavailableView(
          "Couldn’t Load Downloads",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else if model.visibleSongs.isEmpty {
        ContentUnavailableView(
          model.filter.query.isEmpty ? "No Offline Songs" : "No Results",
          systemImage: "arrow.down.circle",
          description: Text(emptyDescription)
        )
      }

      ForEach(model.visibleSongs) { song in
        NavigationLink {
          SongDetailView(song: song, isOffline: true)
        } label: {
          SongRow(song: song)
        }
      }
    }
    .navigationTitle("Offline")
    .searchable(text: queryBinding, prompt: "Title or artist")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Sort", selection: sortBinding) {
            ForEach(CatalogSort.allCases) { sort in
              Text(sort.displayName).tag(sort)
            }
          }
          Divider()
          ForEach(Difficulty.allCases.filter { $0 != .unknown }, id: \.self) {
            difficulty in
            Toggle(
              difficulty.displayName,
              isOn: difficultyBinding(difficulty)
            )
          }
        }
      }
    }
    .refreshable { await model.refresh() }
    .task { await model.refresh() }
  }

  private var emptyDescription: String {
    model.filter.query.isEmpty
      ? "Download a chart to keep its song, engine, and assets available."
      : "Try a different title, artist, or difficulty."
  }

  private var queryBinding: Binding<String> {
    Binding(
      get: { model.filter.query },
      set: { model.filter.query = $0 }
    )
  }

  private var sortBinding: Binding<CatalogSort> {
    Binding(
      get: { model.filter.sort },
      set: { model.filter.sort = $0 }
    )
  }

  private func difficultyBinding(_ difficulty: Difficulty) -> Binding<Bool> {
    Binding(
      get: { model.filter.difficulties.contains(difficulty) },
      set: { isIncluded in
        if isIncluded {
          model.filter.difficulties.insert(difficulty)
        } else {
          model.filter.difficulties.remove(difficulty)
        }
      }
    )
  }
}
