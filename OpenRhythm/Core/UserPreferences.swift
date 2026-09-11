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

enum JudgementDisplayMode: String, Codable, CaseIterable, Identifiable {
  case off, judgement, timing
  var id: Self { self }
  var title: String {
    switch self {
    case .off: "Off"
    case .judgement: "Judgement Only"
    case .timing: "Judgement + Early/Late"
    }
  }
}

struct GameplayPreferences: Codable, Equatable {
  var scoreDisplay = ScoreDisplayMode.countUp
  // Nil uses the engine's default. Values are in its own option units.
  var noteSpeed: Double? = nil
  var judgementDisplay = JudgementDisplayMode.timing
  var scoreMode: Int? = nil

  init(scoreDisplay: ScoreDisplayMode = .countUp, noteSpeed: Double? = nil,
    judgementDisplay: JudgementDisplayMode = .timing, scoreMode: Int? = nil) {
    self.scoreDisplay = scoreDisplay
    self.noteSpeed = noteSpeed
    self.judgementDisplay = judgementDisplay
    self.scoreMode = scoreMode
  }

  private enum CodingKeys: String, CodingKey {
    case scoreDisplay, noteSpeed, judgementDisplay, scoreMode
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    scoreDisplay = try values.decodeIfPresent(ScoreDisplayMode.self,
      forKey: .scoreDisplay) ?? .countUp
    noteSpeed = try values.decodeIfPresent(Double.self, forKey: .noteSpeed)
    scoreMode = try values.decodeIfPresent(Int.self, forKey: .scoreMode)
    judgementDisplay = try values.decodeIfPresent(JudgementDisplayMode.self,
      forKey: .judgementDisplay) ?? .timing
  }
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
