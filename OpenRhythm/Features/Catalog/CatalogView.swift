import SwiftUI

struct CatalogView: View {
  @State private var model: CatalogModel
  @State private var searchTask: Task<Void, Never>?
  private let server: ServerDescriptor

  init(server: ServerDescriptor) {
    self.server = server
    _model = State(initialValue: CatalogModel(server: server))
  }

  var body: some View {
    List {
      if model.isLoading {
        Section {
          HStack {
            ProgressView()
            Text(progressLabel)
              .foregroundStyle(.secondary)
          }
        }
      }

      if let errorMessage = model.errorMessage {
        ContentUnavailableView(
          "Couldn’t Load Songs",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else if !model.isLoading && model.visibleSongs.isEmpty {
        ContentUnavailableView.search(text: model.filter.query)
      }

      ForEach(model.visibleSongs) { song in
        NavigationLink {
          SongDetailView(song: song)
        } label: {
          SongRow(song: song)
        }
      }
    }
    .navigationTitle(server.name)
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
    .refreshable {
      await model.refresh()
    }
    .task {
      if model.songs.isEmpty {
        await model.refresh()
      }
    }
  }

  private var progressLabel: String {
    guard model.totalPageCount > 0 else {
      return "Loading songs…"
    }
    return "Loading page \(model.loadedPageCount) of \(model.totalPageCount)…"
  }

  private var queryBinding: Binding<String> {
    Binding(
      get: { model.filter.query },
      set: { value in
        model.filter.query = value
        searchTask?.cancel()
        searchTask = Task {
          try? await Task.sleep(for: .milliseconds(350))
          guard !Task.isCancelled else { return }
          await model.refresh()
        }
      }
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

struct SongRow: View {
  let song: CatalogSong

  var body: some View {
    HStack(spacing: 12) {
      AsyncImage(url: song.coverURL) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color.secondary.opacity(0.15)
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(song.title.displayValue())
          .font(.headline)
        Text(song.artists.displayValue())
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(difficultySummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)
    }
  }

  private var difficultySummary: String {
    song.variants
      .map { "\($0.difficulty.displayName) \($0.rating)" }
      .joined(separator: " · ")
  }
}
