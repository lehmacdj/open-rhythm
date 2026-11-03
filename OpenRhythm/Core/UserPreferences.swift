import AVFoundation
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

  init(scoreDisplay: ScoreDisplayMode = .countUp, noteSpeed: Double? = nil,
    judgementDisplay: JudgementDisplayMode = .timing, scoreMode: Int? = nil,
    engineOptions: [String: Double] = [:],
    skinRenderMode: EngineSkinRenderMode = .standard,
    recordTimingDiagnostics: Bool = false, engineDebugMode: Bool = false) {
    self.scoreDisplay = scoreDisplay
    self.noteSpeed = noteSpeed
    self.judgementDisplay = judgementDisplay
    self.scoreMode = scoreMode
    self.engineOptions = engineOptions
    self.skinRenderMode = skinRenderMode
    self.recordTimingDiagnostics = recordTimingDiagnostics
    self.engineDebugMode = engineDebugMode
  }

  private enum CodingKeys: String, CodingKey {
    case scoreDisplay, noteSpeed, judgementDisplay, scoreMode, engineOptions
    case skinRenderMode, recordTimingDiagnostics, engineDebugMode
  }

  // Each field falls back alone: a value this build cannot read (such as a
  // newer enum case) must not reset the player's other preferences.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    scoreDisplay = values.lenient(ScoreDisplayMode.self,
      forKey: .scoreDisplay) ?? .countUp
    noteSpeed = values.lenient(Double.self, forKey: .noteSpeed)
    scoreMode = values.lenient(Int.self, forKey: .scoreMode)
    engineOptions = values.lenient([String: Double].self,
      forKey: .engineOptions) ?? [:]
    judgementDisplay = values.lenient(JudgementDisplayMode.self,
      forKey: .judgementDisplay) ?? .timing
    skinRenderMode = values.lenient(EngineSkinRenderMode.self,
      forKey: .skinRenderMode) ?? .standard
    recordTimingDiagnostics = values.lenient(Bool.self,
      forKey: .recordTimingDiagnostics) ?? false
    engineDebugMode = values.lenient(Bool.self,
      forKey: .engineDebugMode) ?? false
  }
}

/// The audio outputs a timing calibration belongs to. Latency comes from the
/// device and its output, not from the engine, so all engines share one.
enum AudioRouteKind: String, Codable, CaseIterable, Sendable {
  /// The built-in speaker or receiver and wired outputs, whose reported
  /// latency hit sounds are compensated for automatically.
  case wired
  /// Bluetooth, AirPlay, CarPlay and HDMI: left to the player's calibration.
  case wireless

  init(_ route: AVAudioSessionRouteDescription) {
    let wired: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver,
      .headphones, .usbAudio, .lineOut]
    self = !route.outputs.isEmpty
      && route.outputs.allSatisfy({ wired.contains($0.portType) })
      ? .wired : .wireless
  }

  static var current: AudioRouteKind {
    AudioRouteKind(AVAudioSession.sharedInstance().currentRoute)
  }

  var title: String {
    switch self {
    case .wired: "Speaker & Wired"
    case .wireless: "Bluetooth & Other"
    }
  }
}

/// The player's Visual Timing and Input Timing for one kind of audio route.
struct TimingCalibration: Codable, Equatable, Sendable {
  static let range = -250.0...250.0
  var visualOffsetMilliseconds = 0.0 {
    didSet { visualOffsetMilliseconds = Self.clamped(visualOffsetMilliseconds) }
  }
  var inputOffsetMilliseconds = 0.0 {
    didSet { inputOffsetMilliseconds = Self.clamped(inputOffsetMilliseconds) }
  }

  var visualOffsetSeconds: Double { visualOffsetMilliseconds / 1000 }
  var inputOffsetSeconds: Double { inputOffsetMilliseconds / 1000 }

  init(visualOffsetMilliseconds: Double = 0, inputOffsetMilliseconds: Double = 0) {
    self.visualOffsetMilliseconds = Self.clamped(visualOffsetMilliseconds)
    self.inputOffsetMilliseconds = Self.clamped(inputOffsetMilliseconds)
  }

  static func clamped(_ value: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 0
  }

  private enum CodingKeys: String, CodingKey {
    case visualOffsetMilliseconds, inputOffsetMilliseconds
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      visualOffsetMilliseconds: values.lenient(Double.self,
        forKey: .visualOffsetMilliseconds) ?? 0,
      inputOffsetMilliseconds: values.lenient(Double.self,
        forKey: .inputOffsetMilliseconds) ?? 0)
  }
}

private extension KeyedDecodingContainer {
  func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
    (try? decodeIfPresent(type, forKey: key)) ?? nil
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

  /// The catalog engine last chosen on a server, if any.
  func catalogEngine(for server: String) -> CatalogEngineChoice? {
    read(StoredEngine.self, key: "catalogEngine:\(server)")
      .map { CatalogEngineChoice(id: $0.id, name: $0.name) }
  }

  func saveCatalogEngine(_ engine: CatalogEngineChoice, for server: String) {
    write(StoredEngine(id: engine.id, name: engine.name),
      key: "catalogEngine:\(server)")
  }

  private struct StoredEngine: Codable {
    let id: String
    let name: String
  }

  func gameplay(for engine: String) -> GameplayPreferences {
    read(GameplayPreferences.self, key: "gameplay:\(engine)")
      ?? GameplayPreferences()
  }

  func save(_ gameplay: GameplayPreferences, for engine: String) {
    write(gameplay, key: "gameplay:\(engine)")
  }

  /// Timing for a route kind. Values saved per engine before November 2026
  /// compensated for display and hit-sound delays the app now removes
  /// itself, so they are deliberately not carried over.
  func timing(for route: AudioRouteKind) -> TimingCalibration {
    read(TimingCalibration.self, key: "timing:\(route.rawValue)")
      ?? TimingCalibration()
  }

  func save(_ timing: TimingCalibration, for route: AudioRouteKind) {
    write(timing, key: "timing:\(route.rawValue)")
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
