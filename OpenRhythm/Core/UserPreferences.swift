import Foundation

enum ScoreDisplayMode: String, Codable, CaseIterable, Identifiable {
  case countUp
  case countDown
  var id: Self { self }
  var title: String { self == .countUp ? "Count Up" : "Count Down" }

  func score(judgements: [NoteJudgement: Int], noteCount: Int) -> Int {
    let earned = NoteJudgement.score(for: judgements, noteCount: noteCount)
    guard self == .countDown, noteCount > 0 else { return earned }
    let resolved = min(noteCount, judgements.values.reduce(0, +))
    let unjudged = noteCount - resolved
    var projected = judgements
    projected[.perfect, default: 0] += unjudged
    return NoteJudgement.score(for: projected, noteCount: noteCount)
  }
}

struct GameplayPreferences: Codable, Equatable {
  var scoreDisplay = ScoreDisplayMode.countUp
  // Nil uses the engine's default. Values are in its own option units.
  var noteSpeed: Double? = nil
}

@MainActor
final class UserPreferences {
  static let shared = UserPreferences()
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func filter(for engine: String) -> CatalogFilter {
    read(CatalogFilter.self, key: "filter:\(engine)") ?? CatalogFilter()
  }

  func save(_ filter: CatalogFilter, for engine: String) {
    write(filter, key: "filter:\(engine)")
  }

  func gameplay(for engine: String) -> GameplayPreferences {
    read(GameplayPreferences.self, key: "gameplay:\(engine)")
      ?? GameplayPreferences()
  }

  func save(_ gameplay: GameplayPreferences, for engine: String) {
    write(gameplay, key: "gameplay:\(engine)")
  }

  private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    defaults.data(forKey: "OpenRhythm.preferences.v1:\(key)")
      .flatMap { try? JSONDecoder().decode(type, from: $0) }
  }

  private func write<T: Encodable>(_ value: T, key: String) {
    if let data = try? JSONEncoder().encode(value) {
      defaults.set(data, forKey: "OpenRhythm.preferences.v1:\(key)")
    }
  }
}
