import SwiftUI

struct SongDetailView: View {
  let song: CatalogSong
  @State private var selectedLevelID: String

  init(song: CatalogSong) {
    self.song = song
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
        Button("Play", systemImage: "play.fill") {}
          .disabled(true)
        Button("Download", systemImage: "arrow.down.circle") {}
          .disabled(true)
      } footer: {
        Text("Gameplay and offline bundles are the next implementation stage.")
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
  }

  private var selectedLevel: SonolusLevelItem? {
    song.variants.first { $0.id == selectedLevelID }
  }
}
