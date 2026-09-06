import SwiftUI

struct ContentView: View {
  private let servers = ServerRegistry.load()

  var body: some View {
    NavigationStack {
      List {
        Section("Servers") {
          ForEach(servers) { server in
            NavigationLink(server.name) {
              CatalogView(server: server)
            }
          }
        }

        Section {
          NavigationLink {
            ContentUnavailableView(
              "No Offline Songs",
              systemImage: "arrow.down.circle",
              description: Text(
                "Downloaded songs from every server will appear here."
              )
            )
            .navigationTitle("Offline")
          } label: {
            Label("Offline", systemImage: "arrow.down.circle")
          }
        }
      }
      .navigationTitle("OpenRhythm")
    }
  }
}
