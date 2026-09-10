import SwiftUI
import UIKit

struct CatalogView: View {
  @Environment(\.scenePhase) private var scenePhase
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
          } else if model.hasMorePages && (model.errorMessage != nil
            || model.visibleSongs.isEmpty || model.needsMoreMatches) {
            Button(model.errorMessage == nil ? "Search More Songs" : "Retry") {
              Task { await model.loadNextPage() }
            }
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
        selectedEngineKey: $model.selectedEngineKey, songs: model.songs)
    }
    .refreshable {
      await model.refresh(forceReload: true)
    }
    .task(id: model.query) {
      await model.searchAfterDelay()
    }
    .task(id: model.loadedPageCount) { await model.prefetchNextPages() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await model.searchAfterDelay() } }
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
  let songs: [CatalogSong]
  @State private var initialRatingLimit = 1
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        if engines.count > 1 {
          Picker("Engine", selection: $selectedEngineKey) {
            ForEach(engines) { Text($0.name).tag($0.id) }
          }
        }
        Section("Sort") {
          Picker("Sort by", selection: $filter.sort) {
            ForEach(CatalogSort.allCases) { Text($0.displayName).tag($0) }
          }
        }
        Section("Difficulty Rating") {
          DifficultyRangeSlider(minimum: $filter.minimumRating,
            maximum: $filter.maximumRating, limit: ratingLimit)
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
          Button("Reset Filters") { filter = CatalogFilter() }
        }
      }
      .navigationTitle("Filters")
      .toolbar { Button("Done") { dismiss() } }
      .onAppear { captureRatingLimit() }
      .onChange(of: selectedEngineKey) { _, _ in captureRatingLimit() }
    }
  }

  private var ratingLimit: Int {
    let largest = songs.filter { $0.engineKey == selectedEngineKey }
      .flatMap(\.variants).map(\.rating).max() ?? 10
    let estimated = Int(ceil(min(1_000_000, max(1, Double(largest) * 1.2))))
    return max(estimated, initialRatingLimit)
  }

  private func captureRatingLimit() {
    initialRatingLimit = max(1, filter.maximumRating ?? 0, filter.minimumRating ?? 0)
  }
}

#Preview("Difficulty Filters") {
  @Previewable @State var filter: CatalogFilter = {
    var value = CatalogFilter()
    value.minimumRating = 7
    value.maximumRating = 9
    return value
  }()
  @Previewable @State var engine = "preview"
  CatalogFilterPanel(filter: $filter,
    engines: [CatalogEngineChoice(id: "preview", name: "Love Live!")],
    selectedEngineKey: $engine, songs: [])
}

private struct DifficultyRangeSlider: View {
  @Binding var minimum: Int?
  @Binding var maximum: Int?
  let limit: Int
  @State private var draggingLower: Bool?

  private var lower: Int { min(limit, max(0, minimum ?? 0)) }
  private var upper: Int { min(limit, max(lower, maximum ?? limit)) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("\(lower)")
        Spacer()
        Text(maximum.map(String.init) ?? "Any")
      }
      .monospacedDigit()
      GeometryReader { geometry in
        let width = max(1, geometry.size.width - 44)
        let left = 22 + width * Double(lower) / Double(limit)
        let right = 22 + width * Double(upper) / Double(limit)
        ZStack(alignment: .leading) {
          Capsule().fill(.secondary.opacity(0.2))
            .frame(width: width, height: 4).offset(x: 22)
          Capsule().fill(Color.accentColor)
            .frame(width: max(0, right - left), height: 4).offset(x: left)
          thumb(lower: true).position(x: left, y: 22)
          thumb(lower: false).position(x: right, y: 22)
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
          if draggingLower == nil {
            draggingLower = value.startLocation.x <= (left + right) / 2
          }
          let rating = Int(((value.location.x - 22) / width * Double(limit)).rounded())
          set(rating, lower: draggingLower == true)
        }.onEnded { _ in draggingLower = nil })
      }
      .frame(height: 44)
    }
  }

  private func thumb(lower isLower: Bool) -> some View {
    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 2, y: 1)
      .overlay { Circle().stroke(Color.accentColor, lineWidth: 2) }
      .frame(width: 26, height: 26)
      .frame(width: 44, height: 44)
      .accessibilityElement()
      .accessibilityLabel(isLower ? "Minimum Difficulty" : "Maximum Difficulty")
      .accessibilityValue(String(isLower ? lower : upper))
      .accessibilityAdjustableAction { direction in
        let current = isLower ? lower : upper
        if direction == .increment { set(current + 1, lower: isLower) }
        if direction == .decrement { set(current - 1, lower: isLower) }
      }
  }

  private func set(_ value: Int, lower isLower: Bool) {
    if isLower {
      let bounded = min(upper, max(0, value))
      minimum = bounded == 0 ? nil : bounded
    } else {
      let bounded = max(lower, min(limit, value))
      maximum = bounded == limit ? nil : bounded
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
