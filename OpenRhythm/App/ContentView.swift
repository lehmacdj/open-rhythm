import SwiftUI

struct ContentView: View {
  @State private var store = ServerStore()
  @State private var showsAddServer = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        Section("Servers") {
          ForEach(store.servers) { server in
            NavigationLink(server.name) {
              CatalogView(server: server)
            }
          }
          .onDelete { offsets in
            do { try store.remove(at: offsets) }
            catch { errorMessage = error.localizedDescription }
          }
          .onMove { offsets, destination in
            do { try store.move(from: offsets, to: destination) }
            catch { errorMessage = error.localizedDescription }
          }
          Button("Add Server", systemImage: "plus") { showsAddServer = true }
            .disabled(store.loadError != nil)
        }
        if let error = store.loadError {
          Section { Text(error).foregroundStyle(.red) }
        }

        Section {
          NavigationLink {
            PlayHistoryView()
          } label: {
            Label("Play History", systemImage: "clock")
          }
          NavigationLink {
            OfflineCatalogView(playedSongs: true)
          } label: {
            Label("Played Songs", systemImage: "music.note.list")
          }
          NavigationLink {
            OfflineCatalogView()
          } label: {
            Label("Offline", systemImage: "arrow.down.circle")
          }
        }
      }
      .navigationTitle("OpenRhythm")
      .toolbar { EditButton().disabled(store.loadError != nil) }
      .sheet(isPresented: $showsAddServer) { AddServerPanel(store: store) }
      .alert("Couldn’t Update Servers", isPresented: Binding(
        get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
          Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
  }
}

struct PlayHistoryView: View {
  @State private var results = [PlayResult]()
  @State private var errorMessage: String?
  private let store: ResultStore?

  init(results: [PlayResult] = [], store: ResultStore? = .shared) {
    _results = State(initialValue: results)
    self.store = store
  }

  var body: some View {
    List {
      if let errorMessage {
        ContentUnavailableView("Couldn’t Load History",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage))
      } else if results.isEmpty {
        ContentUnavailableView("No Plays Yet", systemImage: "clock")
      }
      ForEach(results) { result in
        NavigationLink {
          ResultDetailView(result: result)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(result.title)
            Text("\(result.difficulty.displayName) \(result.rating) · \(result.score.formatted())")
              .font(.subheadline)
            Text(result.playedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Play History")
    .task { await refresh() }
    .refreshable { await refresh() }
  }

  private func refresh() async {
    guard let store else { return }
    do {
      results = try await store.allResults()
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }
}

#Preview("Play History") {
  NavigationStack {
    PlayHistoryView(results: [
      PlayResult(id: UUID(), levelID: "preview", title: "光",
        difficulty: .hard, rating: 18, playedAt: Date(), maxCombo: 280,
        perfect: 450, great: 24, good: 3, miss: 2),
      PlayResult(id: UUID(), levelID: "preview-2", title: "Eleventh",
        difficulty: .hard, rating: 16,
        playedAt: Date().addingTimeInterval(-600), maxCombo: 120,
        perfect: 390, great: 20, good: 5, miss: 4)
    ], store: nil)
  }
}

private struct AddServerPanel: View {
  let store: ServerStore
  @State private var url = ""
  @State private var name = ""
  @State private var isAdding = false
  @State private var errorMessage: String?
  @State private var task: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Server") {
          TextField("URL", text: $url)
            .keyboardType(.URL).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Name (optional)", text: $name)
          Text("Enter the server’s base URL, not a song link. Removing a server later keeps its downloaded songs.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Compatibility Candidates") {
          ForEach(ServerDescriptor.suggested) { server in
            Button(server.name) { url = server.baseURL.absoluteString; name = server.name }
          }
          Text("Additional engines are experimental; some charts may not run yet.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        if isAdding { ProgressView("Checking server…") }
      }
      .disabled(isAdding)
      .navigationTitle("Add Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { task?.cancel(); dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            task = Task {
              isAdding = true
              errorMessage = nil
              defer { isAdding = false }
              do {
                let base = try ServerDescriptor.normalizedURL(url)
                let title = try await SonolusClient().serverTitle(at: base)
                try Task.checkCancellation()
                try store.add(url: base, name: name.isEmpty ? title : name)
                dismiss()
              } catch is CancellationError { return }
              catch { errorMessage = error.localizedDescription }
            }
          }
          .disabled(isAdding || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .onDisappear { task?.cancel() }
    }
  }
}
