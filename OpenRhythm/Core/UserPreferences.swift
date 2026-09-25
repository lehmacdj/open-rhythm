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
  var engineOptions: [String: Double] = [:]
  var skinRenderMode = EngineSkinRenderMode.standard
  var recordTimingDiagnostics = false
  var engineDebugMode = false
  var visualOffsetMilliseconds: Double = 0 {
    didSet {
      visualOffsetMilliseconds = Self.clampedInputOffset(visualOffsetMilliseconds)
    }
  }
  var inputOffsetMilliseconds: Double = 0 {
    didSet {
      inputOffsetMilliseconds = Self.clampedInputOffset(inputOffsetMilliseconds)
    }
  }

  static func clampedInputOffset(_ value: Double) -> Double {
    value.isFinite ? min(250, max(-250, value)) : 0
  }

  var inputOffsetSeconds: Double { inputOffsetMilliseconds / 1000 }
  var visualOffsetSeconds: Double { visualOffsetMilliseconds / 1000 }

  init(scoreDisplay: ScoreDisplayMode = .countUp, noteSpeed: Double? = nil,
    judgementDisplay: JudgementDisplayMode = .timing, scoreMode: Int? = nil,
    engineOptions: [String: Double] = [:],
    skinRenderMode: EngineSkinRenderMode = .standard,
    inputOffsetMilliseconds: Double = 0, recordTimingDiagnostics: Bool = false,
    visualOffsetMilliseconds: Double = 0, engineDebugMode: Bool = false) {
    self.scoreDisplay = scoreDisplay
    self.noteSpeed = noteSpeed
    self.judgementDisplay = judgementDisplay
    self.scoreMode = scoreMode
    self.engineOptions = engineOptions
    self.skinRenderMode = skinRenderMode
    self.recordTimingDiagnostics = recordTimingDiagnostics
    self.engineDebugMode = engineDebugMode
    self.inputOffsetMilliseconds = Self.clampedInputOffset(inputOffsetMilliseconds)
    self.visualOffsetMilliseconds = Self.clampedInputOffset(visualOffsetMilliseconds)
  }

  private enum CodingKeys: String, CodingKey {
    case scoreDisplay, noteSpeed, judgementDisplay, scoreMode, engineOptions
    case skinRenderMode, inputOffsetMilliseconds, recordTimingDiagnostics
    case visualOffsetMilliseconds
    case engineDebugMode
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    scoreDisplay = try values.decodeIfPresent(ScoreDisplayMode.self,
      forKey: .scoreDisplay) ?? .countUp
    noteSpeed = try values.decodeIfPresent(Double.self, forKey: .noteSpeed)
    scoreMode = try values.decodeIfPresent(Int.self, forKey: .scoreMode)
    engineOptions = try values.decodeIfPresent([String: Double].self,
      forKey: .engineOptions) ?? [:]
    judgementDisplay = try values.decodeIfPresent(JudgementDisplayMode.self,
      forKey: .judgementDisplay) ?? .timing
    skinRenderMode = try values.decodeIfPresent(EngineSkinRenderMode.self,
      forKey: .skinRenderMode) ?? .standard
    recordTimingDiagnostics = try values.decodeIfPresent(Bool.self,
      forKey: .recordTimingDiagnostics) ?? false
    engineDebugMode = try values.decodeIfPresent(Bool.self,
      forKey: .engineDebugMode) ?? false
    inputOffsetMilliseconds = Self.clampedInputOffset(
      try values.decodeIfPresent(Double.self,
        forKey: .inputOffsetMilliseconds) ?? 0)
    visualOffsetMilliseconds = Self.clampedInputOffset(
      try values.decodeIfPresent(Double.self,
        forKey: .visualOffsetMilliseconds) ?? 0)
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
