import SwiftUI
import UIKit

struct CatalogView: View {
  @State private var model: CatalogModel
  @State private var showsFilters = false
  private let server: ServerDescriptor

  init(server: ServerDescriptor) {
    self.server = server
    _model = State(initialValue: CatalogModel(server: server))
  }

  var body: some View {
    List {
      if model.isLoading && model.loadedPageCount == 0 {
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
          SongDetailView(song: song, filter: model.filter)
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
      if model.loadedPageCount > 0 {
        HStack {
          if model.isLoading {
            ProgressView()
            Text(progressLabel)
          } else if model.hasMorePages {
            Button(model.errorMessage == nil ? "Load More Songs" : "Retry") {
              Task { await model.loadNextPage() }
            }
          } else {
            Text("All loaded songs shown").foregroundStyle(.secondary)
          }
        }
        .frame(height: 32)
        .id("pagination-status")
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
        Button("Filter", systemImage: "line.3.horizontal.decrease.circle") {
          showsFilters = true
        }
      }
    }
    .sheet(isPresented: $showsFilters) {
      CatalogFilterPanel(filter: $model.filter, engines: model.engines,
        selectedEngineKey: $model.selectedEngineKey)
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

struct CatalogFilterPanel: View {
  @Binding var filter: CatalogFilter
  let engines: [CatalogEngineChoice]
  @Binding var selectedEngineKey: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        if engines.count > 1 {
          Picker("Engine", selection: $selectedEngineKey) {
            ForEach(engines) { Text($0.name).tag($0.id) }
          }
        } else if let engine = engines.first {
          Section { Text(engine.name) }
        }
        Section("Sort") {
          Picker("Sort by", selection: $filter.sort) {
            ForEach(CatalogSort.allCases) { Text($0.displayName).tag($0) }
          }
        }
        Section("Difficulty Rating") {
          Toggle("Limit rating range", isOn: Binding(
            get: { filter.minimumRating != nil || filter.maximumRating != nil },
            set: {
              filter.minimumRating = $0 ? 0 : nil
              filter.maximumRating = $0 ? 50 : nil
            }))
          if filter.minimumRating != nil || filter.maximumRating != nil {
            Stepper("Minimum: \(filter.minimumRating ?? 0)", value: Binding(
              get: { filter.minimumRating ?? 0 },
              set: { filter.minimumRating = $0 }),
              in: 0...(filter.maximumRating ?? 100))
            Stepper("Maximum: \(filter.maximumRating ?? 100)", value: Binding(
              get: { filter.maximumRating ?? 100 },
              set: { filter.maximumRating = $0 }),
              in: (filter.minimumRating ?? 0)...100)
          }
        }
        Section("Chart Types") {
          ForEach(Difficulty.allCases, id: \.self) { difficulty in
            Toggle(difficulty == .unknown ? "Other" : difficulty.displayName,
              isOn: Binding(
                get: { filter.difficulties.contains(difficulty) },
                set: {
                  if $0 { filter.difficulties.insert(difficulty) }
                  else { filter.difficulties.remove(difficulty) }
                }))
          }
        }
        Section {
          Text("Filters and sorting are saved for this engine. Search is not saved.")
            .foregroundStyle(.secondary)
          Button("Reset Filters") { filter = CatalogFilter() }
        }
      }
      .navigationTitle("Filters")
      .toolbar { Button("Done") { dismiss() } }
    }
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
  @State private var loadedImage: UIImage?

  var body: some View {
    Group {
      if let image = loadedImage {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else {
        placeholder
      }
    }
    .task(id: url) {
      loadedImage = nil
      guard let url else { return }
      do {
        let bytes: Data
        if url.isFileURL {
          bytes = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
          }.value
        } else {
          // Artwork shares the same persistent, coalescing response cache as
          // catalog pages and downloads, even if HTTP cache headers are absent.
          bytes = try await SonolusClient().resource(at: url)
        }
        let image = await Task.detached(priority: .utility) {
          UIImage(data: bytes)?.preparingForDisplay()
        }.value
        try Task.checkCancellation()
        loadedImage = image
      } catch {
        // Missing artwork is nonfatal; keep the row's placeholder.
      }
    }
  }

  private var placeholder: some View {
    Color.secondary.opacity(0.15)
  }
}
