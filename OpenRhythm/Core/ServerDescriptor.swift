import Foundation
import Observation

struct ServerDescriptor: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let baseURL: URL
  var preferenceKey: String { "server:\(baseURL.absoluteString)" }

  static let defaults = [
    ServerDescriptor(
      id: "llsif",
      name: "Love Live! School idol festival",
      baseURL: URL(string: "https://sonolus.milkbun.org/llsif")!
    )
  ]

  static let suggested = [
    ServerDescriptor(id: "sekai", name: "Project SEKAI",
      baseURL: URL(string: "https://sonolus.sekai.best")!),
    ServerDescriptor(id: "sif-custom", name: "SIF Custom Charts",
      baseURL: URL(string: "https://sonolus.milkbun.org/sif")!)
  ]

  static func normalizedURL(_ text: String) throws -> URL {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let input = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard var components = URLComponents(string: input),
      let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = components.host, !host.isEmpty,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil else {
      throw ServerStoreError.invalidURL
    }
    components.scheme = scheme
    components.host = host.lowercased()
    if components.port == (scheme == "https" ? 443 : 80) { components.port = nil }
    while components.path.hasSuffix("/") { components.path.removeLast() }
    guard let url = components.url else { throw ServerStoreError.invalidURL }
    return url
  }
}

enum ServerStoreError: LocalizedError {
  case invalidURL
  case duplicate
  case unreadableConfiguration

  var errorDescription: String? {
    switch self {
    case .invalidURL: "Enter an HTTP or HTTPS server URL without credentials, a query, or a fragment."
    case .duplicate: "This server is already in your list."
    case .unreadableConfiguration: "The saved server list could not be read. It has not been overwritten."
    }
  }
}

@MainActor
@Observable
final class ServerStore {
  private let fileURL: URL
  private(set) var servers: [ServerDescriptor]
  private(set) var loadError: String?

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? FileManager.default.urls(for: .documentDirectory,
      in: .userDomainMask)[0].appendingPathComponent("servers.json")
    if FileManager.default.fileExists(atPath: self.fileURL.path) {
      do {
        servers = try JSONDecoder().decode([ServerDescriptor].self,
          from: Data(contentsOf: self.fileURL))
      } catch {
        servers = []
        loadError = ServerStoreError.unreadableConfiguration.localizedDescription
      }
    } else {
      servers = ServerDescriptor.defaults
    }
  }

  func add(url: URL, name: String) throws {
    let normalized = try ServerDescriptor.normalizedURL(url.absoluteString)
    guard !servers.contains(where: {
      (try? ServerDescriptor.normalizedURL($0.baseURL.absoluteString)) == normalized
    }) else { throw ServerStoreError.duplicate }
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    try save(servers + [ServerDescriptor(id: normalized.absoluteString,
      name: title.isEmpty ? normalized.host! : title, baseURL: normalized)])
  }

  func remove(at offsets: IndexSet) throws {
    try save(servers.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
  }

  func move(from offsets: IndexSet, to destination: Int) throws {
    guard offsets.allSatisfy(servers.indices.contains),
      (0...servers.count).contains(destination) else { return }
    let moving = offsets.sorted().map { servers[$0] }
    var reordered = servers.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    reordered.insert(contentsOf: moving,
      at: destination - offsets.filter { $0 < destination }.count)
    try save(reordered)
  }

  private func save(_ value: [ServerDescriptor]) throws {
    guard loadError == nil else { throw ServerStoreError.unreadableConfiguration }
    let bytes = try JSONEncoder().encode(value)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try bytes.write(to: fileURL, options: .atomic)
    servers = value
  }
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
