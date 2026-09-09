import SwiftUI
import UIKit

struct CatalogView: View {
  @State private var model: CatalogModel
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
        ContentUnavailableView.search(text: model.query)
      }

      ForEach(model.visibleSongs) { song in
        NavigationLink {
          SongDetailView(song: song)
        } label: {
          SongRow(song: song)
        }
        .onAppear {
          Task { await model.loadMoreIfNeeded(after: song.id) }
        }
      }
      // Keep a manual fallback when local filters hide the next-page trigger,
      // and when a failed request needs retrying. This is part of the list,
      // rather than an overlay that takes up screen space while browsing.
      if model.hasMorePages && !model.isLoading {
        Button(model.errorMessage == nil ? "Load More Songs" : "Retry") {
          Task { await model.loadNextPage() }
        }
      }
    }
    .navigationTitle("Songs")
    .searchable(text: queryBinding, prompt: "Title or artist")
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 0) {
          Text("Songs")
            .font(.headline)
          Text(server.name)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .combine)
      }
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
      await model.refresh(forceReload: true)
    }
    .task(id: model.query) {
      await model.searchAfterDelay()
    }
  }

  private var progressLabel: String {
    guard model.totalPageCount > 0 else {
      return "Loading songs…"
    }
    return "Loading page \(model.loadedPageCount + 1) of \(model.totalPageCount)…"
  }

  private var queryBinding: Binding<String> {
    Binding(
      get: { model.query },
      set: { model.query = $0 }
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
      SongArtwork(url: song.coverURL, contentMode: .fill)
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

struct SongArtwork: View {
  let url: URL?
  let contentMode: ContentMode

  var body: some View {
    if let url, url.isFileURL {
      if let image = UIImage(contentsOfFile: url.path) {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else {
        placeholder
      }
    } else {
      AsyncImage(url: url) { image in
        image.resizable().aspectRatio(contentMode: contentMode)
      } placeholder: {
        placeholder
      }
    }
  }

  private var placeholder: some View {
    Color.secondary.opacity(0.15)
  }
}
