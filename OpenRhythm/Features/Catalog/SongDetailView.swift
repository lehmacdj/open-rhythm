import SwiftUI

struct SongDetailView: View {
  let song: CatalogSong
  let isOffline: Bool
  @State private var selectedLevelID: String
  @State private var isDownloading = false
  @State private var isDownloaded = false
  @State private var downloadError: String?
  @State private var recentResults = [PlayResult]()

  init(song: CatalogSong, isOffline: Bool = false) {
    self.song = song
    self.isOffline = isOffline
    _selectedLevelID = State(initialValue: song.variants.first?.id ?? "")
  }

  var body: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 16) {
          AsyncImage(url: song.coverURL) { image in
            image.resizable().scaledToFit()
          } placeholder: {
            Color.secondary.opacity(0.15)
          }
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
            Text("\(level.difficulty.displayName) · \(level.rating)")
              .tag(level.id)
          }
        }
        .pickerStyle(.navigationLink)
      }

      Section {
        if let selectedLevel {
          NavigationLink {
            GameplayView(song: song, level: selectedLevel)
          } label: {
            Label("Play", systemImage: "play.fill")
          }
        }
        if !isOffline {
          Button {
            Task { await downloadSelectedLevel() }
          } label: {
            if isDownloading {
              Label("Downloading…", systemImage: "arrow.down.circle")
            } else if isDownloaded {
              Label("Downloaded", systemImage: "checkmark.circle")
            } else {
              Label("Download", systemImage: "arrow.down.circle")
            }
          }
          .disabled(isDownloading || isDownloaded)
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
          ForEach(recentResults.prefix(5)) { result in
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
    .task(id: selectedLevelID) {
      guard let selectedLevel else { return }
      if !isOffline {
        isDownloaded = await OfflineStore.shared.contains(
          level: selectedLevel,
          from: song.server
        )
      }
      recentResults = (try? await ResultStore.shared.results(
        for: selectedLevel.id
      )) ?? []
    }
  }

  private var selectedLevel: SonolusLevelItem? {
    song.variants.first { $0.id == selectedLevelID }
  }

  private func downloadSelectedLevel() async {
    guard let selectedLevel else { return }
    isDownloading = true
    downloadError = nil
    defer { isDownloading = false }

    do {
      _ = try await OfflineStore.shared.download(
        level: selectedLevel,
        from: song.server
      )
      isDownloaded = true
    } catch {
      downloadError = error.localizedDescription
    }
  }
}
