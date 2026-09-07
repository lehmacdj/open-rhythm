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
          from: selectedServer
        )
      }
      recentResults = (try? await ResultStore.shared.results(
        forAnyLevelID: [
          selectedLevel.resultKey(server: selectedServer),
          selectedLevel.id
        ]
      )) ?? []
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

  private func downloadSelectedLevel() async {
    guard let selectedLevel else { return }
    isDownloading = true
    downloadError = nil
    defer { isDownloading = false }

    do {
      _ = try await OfflineStore.shared.download(
        level: selectedLevel,
        from: selectedServer
      )
      isDownloaded = true
    } catch {
      downloadError = error.localizedDescription
    }
  }
}
