import Foundation

struct ServerDescriptor: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let baseURL: URL

  static let defaults = [
    ServerDescriptor(
      id: "llsif",
      name: "Love Live! School idol festival",
      baseURL: URL(string: "https://sonolus.milkbun.org/llsif")!
    )
  ]
}

enum ServerRegistry {
  static func load(fileManager: FileManager = .default) -> [ServerDescriptor] {
    guard
      let documents = fileManager.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first
    else {
      return ServerDescriptor.defaults
    }

    let configurationURL = documents.appendingPathComponent("servers.json")
    guard
      let data = try? Data(contentsOf: configurationURL),
      let servers = try? JSONDecoder().decode(
        [ServerDescriptor].self,
        from: data
      ),
      !servers.isEmpty
    else {
      return ServerDescriptor.defaults
    }

    return servers
  }
}

