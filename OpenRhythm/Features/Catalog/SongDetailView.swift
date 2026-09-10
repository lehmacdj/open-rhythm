import SwiftUI

struct SongDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var song: CatalogSong
  let isOffline: Bool
  private let filter: CatalogFilter
  @State private var selectedLevelID: String
  @State private var isDownloading = false
  @State private var isDownloaded = false
  @State private var downloadError: String?
  @State private var recentResults = [PlayResult]()
  @State private var downloadProgress = ""
  @State private var isLoadingVariants = false
  @State private var discoverySucceeded = false
  @State private var confirmsDelete = false

  init(song: CatalogSong, isOffline: Bool = false, filter: CatalogFilter = CatalogFilter()) {
    _song = State(initialValue: song)
    self.isOffline = isOffline
    self.filter = filter
    _selectedLevelID = State(initialValue:
      filter.matchingVariants(in: song).first?.id ?? song.variants.first?.id ?? "")
  }

  var body: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 16) {
          SongArtwork(url: song.coverURL, contentMode: .fit)
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 12))

          VStack(alignment: .leading, spacing: 6) {
            Text(song.title.displayValue())
              .font(.title3.bold())
            Text(song.artists.displayValue())
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("Chart") {
        Picker("Difficulty", selection: $selectedLevelID) {
          ForEach(song.variants) { level in
            Text(levelLabel(level))
              .tag(level.id)
          }
        }
        .pickerStyle(.navigationLink)
        .disabled(isDownloading || isLoadingVariants)
        if isLoadingVariants { ProgressView("Finding difficulties…") }
      }

      Section {
        if let selectedLevel {
          NavigationLink {
            GameplayView(song: song, level: selectedLevel)
          } label: {
            Label("Play", systemImage: "play.fill")
          }
          .disabled(isDownloading)
        }
        if !isOffline {
          Button {
            Task { await downloadSong() }
          } label: {
            if isDownloading {
              Label(downloadProgress, systemImage: "arrow.down.circle")
            } else if isDownloaded {
              Label("Downloaded", systemImage: "checkmark.circle")
            } else {
              Label("Download", systemImage: "arrow.down.circle")
            }
          }
          .disabled(isDownloading || isDownloaded || isLoadingVariants)
        }
        if isOffline || isDownloaded {
          Button {
            Task { await downloadSong(forceReload: true) }
          } label: {
            Label(isDownloading ? downloadProgress : "Update Download",
              systemImage: "arrow.clockwise")
          }
          .disabled(isDownloading || isLoadingVariants)
          Button("Delete Download", role: .destructive) {
            confirmsDelete = true
          }
          .disabled(isDownloading)
        }
      }

      if let downloadError {
        Section {
          Text(downloadError)
            .foregroundStyle(.red)
        }
      }

      if !recentResults.isEmpty {
        Section("Recent Results") {
          ForEach(recentResults) { result in
            NavigationLink {
              ResultDetailView(result: result)
            } label: {
            LabeledContent {
              Text(result.score.formatted())
                .monospacedDigit()
            } label: {
              VStack(alignment: .leading) {
                Text(
                  result.playedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                  )
                )
                Text("Max combo \(result.maxCombo)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            }
          }
        }
      }

      if let selectedLevel {
        Section("Protocol Information") {
          LabeledContent("Level", value: selectedLevel.name)
          LabeledContent("Rating", value: String(selectedLevel.rating))
          LabeledContent("Server", value: song.server.name)
        }
      }
    }
    .navigationTitle("Song")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("Delete this song and its downloaded difficulties?",
      isPresented: $confirmsDelete, titleVisibility: .visible) {
      Button("Delete Download", role: .destructive) {
        Task {
          do {
            try await OfflineStore.shared.remove(song: song)
            isDownloaded = false
            if isOffline { dismiss() }
          } catch { downloadError = error.localizedDescription }
        }
      }
    } message: {
      Text("Past results are kept. You can download the song again later.")
    }
    .task {
      guard !isOffline, !discoverySucceeded else { return }
      isLoadingVariants = true
      defer { isLoadingVariants = false }
      do {
        let complete = try await SonolusClient().completeSong(song)
        try Task.checkCancellation()
        song = complete
        selectedLevelID = filter.matchingVariants(in: complete).first?.id
          ?? selectedLevelID
        discoverySucceeded = true
        await updateDownloadStatus()
      } catch is CancellationError {
        return
      } catch {
        downloadError = error.localizedDescription
      }
    }
    .task(id: selectedLevelID) {
      guard let selectedLevel else { return }
      let selection = selectedLevelID
      let server = selectedServer
      if !isOffline {
        await updateDownloadStatus()
      }
      let results = (try? await ResultStore.shared.results(
        forAnyLevelID: [
          selectedLevel.resultKey(server: server),
          selectedLevel.id
        ]
      )) ?? []
      guard !Task.isCancelled, selectedLevelID == selection else { return }
      recentResults = results
    }
  }

  private var selectedLevel: SonolusLevelItem? {
    song.variants.first { $0.id == selectedLevelID }
  }

  private var selectedServer: ServerDescriptor {
    selectedLevel.map(song.server(for:)) ?? song.server
  }

  private func levelLabel(_ level: SonolusLevelItem) -> String {
    let base = "\(level.difficulty.displayName) · \(level.rating)"
    let matching = song.variants.filter {
      $0.difficulty == level.difficulty && $0.rating == level.rating
    }
    guard matching.count > 1,
      let index = matching.firstIndex(where: { $0.id == level.id })
    else { return base }
    return "\(base) · Chart \(index + 1)"
  }

  private func updateDownloadStatus() async {
    let snapshot = song
    let discovered = discoverySucceeded
    let downloaded = await OfflineStore.shared.containsAllDifficulties(
      of: snapshot, discoverySucceeded: discovered)
    guard !Task.isCancelled, song == snapshot,
      discoverySucceeded == discovered else { return }
    isDownloaded = downloaded
  }

  private func downloadSong(forceReload: Bool = false) async {
    isDownloading = true
    downloadProgress = "Finding difficulties…"
    downloadError = nil
    defer { isDownloading = false }

    do {
      let complete = try await OfflineStore.shared.download(song: song,
        forceReload: forceReload) { done, total in
        await MainActor.run { downloadProgress = "Downloading \(done)/\(total)…" }
      }
      // Keep offline artwork and origin metadata when updating from Offline.
      if isOffline {
        song = try await OfflineStore.shared.catalogSongs().first {
          $0.variants.contains { $0.id == selectedLevelID }
            && $0.engineKey == complete.engineKey
        } ?? complete
      } else { song = complete }
      discoverySucceeded = true
      isDownloaded = true
    } catch {
      downloadError = error.localizedDescription
    }
  }
}

struct ResultDetailView: View {
  let result: PlayResult

  var body: some View {
    Form {
      Section("Song") {
        Text(result.title).font(.headline)
        LabeledContent("Difficulty",
          value: "\(result.difficulty.displayName) \(result.rating)")
        LabeledContent("Played", value: result.playedAt.formatted())
      }
      Section("Result") {
        LabeledContent("Score", value: result.score.formatted())
        LabeledContent("Max Combo", value: result.maxCombo.formatted())
      }
      Section("Judgements") {
        LabeledContent("Perfect", value: result.perfect.formatted())
        LabeledContent("Great", value: result.great.formatted())
        LabeledContent("Good", value: result.good.formatted())
        LabeledContent("Miss", value: result.miss.formatted())
      }
    }
    .navigationTitle("Result")
    .navigationBarTitleDisplayMode(.inline)
  }
}
