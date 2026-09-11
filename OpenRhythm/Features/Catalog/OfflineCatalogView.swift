import Observation
import SwiftUI

@MainActor
@Observable
private final class OfflineCatalogModel {
  var songs = [CatalogSong]()
  var filter = CatalogFilter() {
    didSet {
      if !selectedEngineKey.isEmpty {
        UserPreferences.shared.save(filter, for: selectedEngineKey)
      }
    }
  }
  var selectedEngineKey = "" {
    didSet {
      guard oldValue != selectedEngineKey else { return }
      let query = filter.query
      filter = UserPreferences.shared.filter(for: selectedEngineKey)
      filter.query = query
    }
  }
  var engines: [CatalogEngineChoice] { CatalogEngineChoice.choices(in: songs) }
  var errorMessage: String?

  var visibleSongs: [CatalogSong] {
    filter.apply(to: songs.filter { $0.engineKey == selectedEngineKey })
  }

  func refresh(playedSongs: Bool) async {
    do {
      songs = try await playedSongs ? ResultStore.shared.playedSongs()
        : OfflineStore.shared.catalogSongs()
      if !engines.contains(where: { $0.id == selectedEngineKey }),
        let first = engines.first { selectedEngineKey = first.id }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct OfflineCatalogView: View {
  var playedSongs = false
  @State private var model = OfflineCatalogModel()
  @State private var query = ""
  @State private var showsFilters = false

  var body: some View {
    List {
      if let errorMessage = model.errorMessage {
        ContentUnavailableView(
          playedSongs ? "Couldn’t Load Played Songs" : "Couldn’t Load Downloads",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else if model.visibleSongs.isEmpty {
        ContentUnavailableView(
          model.filter.query.isEmpty
            ? (playedSongs ? "No Played Songs" : "No Offline Songs") : "No Results",
          systemImage: "arrow.down.circle",
          description: Text(emptyDescription)
        )
      }

      ForEach(model.visibleSongs) { song in
        NavigationLink {
          SongDetailView(song: song, isOffline: !playedSongs, filter: model.filter)
        } label: {
          SongRow(song: song)
        }
      }
    }
    .navigationTitle(playedSongs ? "Played Songs" : "Offline")
    .searchable(text: queryBinding, prompt: "Title or artist")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Filter", systemImage: "line.3.horizontal.decrease.circle") {
          showsFilters = true
        }
      }
    }
    .sheet(isPresented: $showsFilters) {
      CatalogFilterPanel(filter: $model.filter, engines: model.engines,
        selectedEngineKey: $model.selectedEngineKey, songs: model.songs)
    }
    .refreshable { await model.refresh(playedSongs: playedSongs) }
    .task { await model.refresh(playedSongs: playedSongs) }
    .task(id: query) {
      do {
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        model.filter.query = query
      } catch { }
    }
  }

  private var emptyDescription: String {
    model.filter.query.isEmpty
      ? (playedSongs
        ? "Songs completed from this version onward appear here for online replay. Older plays remain in Play History."
        : "Download a chart to keep its song, engine, and assets available.")
      : "Try a different title, artist, or difficulty."
  }

  private var queryBinding: Binding<String> {
    Binding(
      get: { query },
      set: { query = $0 }
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
