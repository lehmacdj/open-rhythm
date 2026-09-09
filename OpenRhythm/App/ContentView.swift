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
