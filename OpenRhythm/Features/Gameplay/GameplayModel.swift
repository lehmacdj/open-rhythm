import AVFoundation
import UIKit
import Observation

enum GameplayPhase: Equatable {
  case loading
  case ready
  case playing
  case finished
  case failed(String)
}

struct BGMClockMapping {
  let offset: Double
  var speed: Double = 1
  // Wall-clock seconds, not source-audio seconds: +100 ms delays the chart
  // by 100 ms at every playback speed. Input shares this visual timeline.
  var audioOffset: Double = 0
  // The offset aligns two timelines; it is not permission to trim audio.
  var initialMediaTime: Double { 0 }
  var initialChartTime: Double { chartTime(mediaTime: initialMediaTime) }
  func chartTime(mediaTime: Double) -> Double {
    (mediaTime - offset) / speed - audioOffset
  }
  func mediaTime(chartTime: Double) -> Double {
    (chartTime + audioOffset) * speed + offset
  }
  func inputChartTime(mediaTime: Double, minimumMediaTime: Double) -> Double {
    chartTime(mediaTime: max(minimumMediaTime, mediaTime))
  }
}

struct JudgementFeedback: Hashable {
  let sequence: Int
  let judgement: NoteJudgement
  let accuracy: Double?
  var minimumError: Double? = nil

  func timingPlacement(_ configured: String?) -> String {
    switch configured {
    case "leftRight": return (accuracy ?? 0) < 0 ? "left" : "right"
    case "topBottom": return (accuracy ?? 0) < 0 ? "top" : "bottom"
    case "left", "right", "top", "bottom", "center": return configured!
    default: return "top"
    }
  }

  func timingText(for mode: JudgementDisplayMode, style: String? = nil) -> String? {
    guard mode == .timing, judgement != .miss,
      judgement != .perfect || minimumError != nil,
      let accuracy, accuracy.isFinite, accuracy != 0,
      abs(accuracy) > (minimumError ?? 0) else { return nil }
    let indicator = EngineJudgmentErrorStyle(rawValue: style ?? "late") ?? .late
    return indicator.text(positive: accuracy > 0)
  }

  func text(for mode: JudgementDisplayMode) -> String? {
    guard mode != .off else { return nil }
    let grade = judgement.rawValue.uppercased()
    return timingText(for: mode).map { "\($0) \(grade)" } ?? grade
  }
}

/// Official UI style pairs list the positive-error symbol first. Styles may
/// deliberately reverse the usual wording; they never change the signed error.
enum EngineJudgmentErrorStyle: String, CaseIterable {
  case none, late, early, plus, minus
  case arrowUp, arrowDown, arrowLeft, arrowRight
  case triangleUp, triangleDown, triangleLeft, triangleRight

  func text(positive: Bool) -> String? {
    let pair: (String, String)
    switch self {
    case .none: return nil
    case .late: pair = ("Late", "Early")
    case .early: pair = ("Early", "Late")
    case .plus: pair = ("+", "-")
    case .minus: pair = ("-", "+")
    case .arrowUp: pair = ("↑", "↓")
    case .arrowDown: pair = ("↓", "↑")
    case .arrowLeft: pair = ("←", "→")
    case .arrowRight: pair = ("→", "←")
    case .triangleUp: pair = ("▲", "▼")
    case .triangleDown: pair = ("▼", "▲")
    case .triangleLeft: pair = ("◄", "►")
    case .triangleRight: pair = ("►", "◄")
    }
    return positive ? pair.0 : pair.1
  }
}

enum NoteJudgement: String, Codable, CaseIterable, Sendable {
  case perfect
  case great
  case good
  case miss

  var displayName: String { rawValue.capitalized }

  /// Relative worth of one note. A chart judged entirely `perfect` scores
  /// `maximumScore`, whatever its length.
  var weight: Int {
    switch self {
    case .perfect: 1_000
    case .great: 700
    case .good: 300
    case .miss: 0
    }
  }

  /// Score a flawless play awards, so results compare across charts.
  static let maximumScore = 1_000_000

  /// Score for `counts` over a chart of `noteCount` notes. Judgements are
  /// the only tally worth keeping: a score is a pure function of them, and
  /// summing four terms is cheap enough to derive wherever it is shown.
  static func score(for counts: [NoteJudgement: Int], noteCount: Int) -> Int {
    let maximum = noteCount * NoteJudgement.perfect.weight
    guard maximum > 0 else { return 0 }
    let earned = counts.reduce(0) { $0 + $1.key.weight * $1.value }
    return (earned * maximumScore + maximum / 2) / maximum
  }
}

/// Own the token outside the main actor so deallocation also unregisters it.
private final class AudioInterruptionObservation {
  private let center: NotificationCenter
  private let token: NSObjectProtocol

  init(center: NotificationCenter,
    onBegan: @escaping @MainActor @Sendable () -> Void) {
    self.center = center
    token = center.addObserver(forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(), queue: .main) { notification in
      guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey]
        as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .began
      else { return }
      // The observer runs on the main queue. Handle it before another input
      // frame instead of enqueueing a second, potentially delayed task.
      MainActor.assumeIsolated { onBegan() }
    }
  }

  deinit { center.removeObserver(token) }
}

/// Prepared audio objects can become invalid even while the Ready screen is
/// visible, so this observer lives with the model, not with one play attempt.
private final class AudioServicesObservation {
  private let center: NotificationCenter
  private var tokens = [NSObjectProtocol]()

  init(center: NotificationCenter,
    onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
    self.center = center
    for (name, available) in [
      (AVAudioSession.mediaServicesWereLostNotification, false),
      (AVAudioSession.mediaServicesWereResetNotification, true)
    ] {
      tokens.append(center.addObserver(forName: name,
        object: AVAudioSession.sharedInstance(), queue: .main) { _ in
        MainActor.assumeIsolated { onChange(available) }
      })
    }
  }

  deinit { tokens.forEach(center.removeObserver) }
}

@MainActor
@Observable
final class GameplayModel {
  private(set) var phase = GameplayPhase.loading
  private(set) var currentTime: TimeInterval = 0
  private(set) var combo = 0
  private(set) var maxCombo = 0
  private(set) var judgements = Dictionary(
    uniqueKeysWithValues: NoteJudgement.allCases.map { ($0, 0) }
  )
  private(set) var playbackGeneration = 0
  private(set) var inputGeneration = 0
  private var debugPausedTime: Double?
  var isDebugPaused: Bool { debugPausedTime != nil }
  private(set) var debugLog = [EngineDebugLogEntry]()
  private(set) var isEngineDebugMode = false
  private(set) var isStartingPlayback = false
  @ObservationIgnored private var startupStage = "idle"
  var startupDiagnostics: String {
    "generation=\(playbackGeneration), stage=\(startupStage), "
      + "phase=\(phase), starting=\(isStartingPlayback), "
      + "introSteps=\(startupSteps), seekComplete=\(audioSeekCompleted); "
      + eventClockDiagnostics
  }
  private(set) var playbackNotice: String?
  private(set) var areAudioServicesAvailable = true
  private var audioSeekCompleted = false
  private var startupLimitMediaTime: Double?
  private var startupNextTime = 0.0
  private(set) var startupSteps = 0
  private var startupVisualGuard = EngineIntroVisualGuard()
  private var startupPreparationComplete = false
  private var startupAnalysis: Task<Double, Never>?
  private(set) var skippedIntroDuration = 0.0
  private var preparedInputCount = 0
  private var engineScore: EngineScoreSnapshot?
  private var engineAccuracy: EngineScoreSnapshot?
  private(set) var engineLife: EngineLife?
  private(set) var engineUI = [EngineUIElement]()
  private var musicHasEnded = false
  @ObservationIgnored private var timingHeatmap = EngineErrorHeatmap()
  private(set) var errorHeatmap = EngineErrorHeatmap().snapshot
  @ObservationIgnored private(set) var timingRecorder: PlaybackTimingRecorder?
  @ObservationIgnored private(set) var frameTiming: PlaybackFrameTiming?
  private(set) var playbackTiming: PlaybackTimingReport?
  private var timingRouteObserver: NSObjectProtocol?

  func engineMetric(_ name: String) -> (text: String, fraction: Double)? {
    func metric(_ value: Double, _ maximum: Double, percentage: Bool = false)
      -> (String, Double) {
      let fraction = maximum > 0 ? min(1, max(0, value / maximum)) : 0
      return (percentage ? String(format: "%.2f%%", fraction * 100)
        : value.formatted(.number.precision(.fractionLength(0))), fraction)
    }
    switch name {
    case "errorHeatmap":
      return (errorHeatmap.text,
        0.5 + (errorHeatmap.meanMS ?? 0) / (2 * errorHeatmap.limitMS))
    case "arcade", "arcadePercentage":
      return metric(Double(displayedScore), 1_000_000,
        percentage: name == "arcadePercentage")
    case "accuracy", "accuracyPercentage":
      guard let engineAccuracy else { return nil }
      let value = settings.scoreDisplay == .countDown
        ? engineAccuracy.remaining : engineAccuracy.earned
      return metric(Double(value), 1_000_000,
        percentage: name == "accuracyPercentage")
    case "life":
      guard let engineLife else { return nil }
      return metric(engineLife.value, engineLife.maximum)
    case "perfect", "perfectPercentage", "miss", "missPercentage":
      let grade: NoteJudgement = name.hasPrefix("perfect") ? .perfect : .miss
      return metric(Double(judgements[grade, default: 0]), Double(noteCount),
        percentage: name.hasSuffix("Percentage"))
    case "greatGoodMiss", "greatGoodMissPercentage":
      let values = [NoteJudgement.great, .good, .miss].map {
        metric(Double(judgements[$0, default: 0]), Double(noteCount),
          percentage: name.hasSuffix("Percentage"))
      }
      return (values.map(\.0).joined(separator: " / "),
        values.reduce(0) { $0 + $1.1 })
    case "time":
      let elapsed = max(0, currentTime)
      guard let seconds = Int(exactly: elapsed.rounded(.towardZero)) else { return nil }
      let duration = clockMapping.chartTime(
        mediaTime: player?.currentItem?.duration.seconds ?? 0)
      return ("\(seconds / 60):" + String(format: "%02d", seconds % 60),
        duration.isFinite && duration > 0 ? min(1, elapsed / duration) : 0)
    default: return nil // Do not substitute arcade score for a different metric.
    }
  }
  private var judgementSequence = 0
  private(set) var latestJudgement: JudgementFeedback?
  @ObservationIgnored private(set) var noteTimings = [NoteTiming]()
  private(set) var resultBuckets: [EngineResultBucket]? = nil
  @ObservationIgnored private var inputMetadata = [(time: Double?, type: String)]()
  private(set) var engineRuntime: EnginePlayRuntime?
  private(set) var presentationAssets: EnginePresentationAssets?
  private var runtimeBundle: RuntimeBundle?
  private var preparedAudio: PreparedRuntimeAudio?
  private var preparedBGMURL: URL?
  private var needsAudioRecreation = false
  private(set) var engineAudio: EngineAudioPlayback?
  private let engineHaptics = EngineHapticPlayback()
  private var engineAspectRatio: Double?
  private var preparedRuntime: EnginePlayRuntime?
  private var preparedRuntimeOptions: [Double]?
  private var preparedRuntimeSpeed: Double?
  private var preparedRuntimeInputOffset: Double?
  private var preparedRuntimeAudioOffset: Double?
  private var preparedRuntimeDebugMode: Bool?
  private var preparedRuntimeAspect: Double?
  private var preparedRuntimeSafeArea: [Double]?
  private var preferenceKey = ""
  var settings = GameplayPreferences() {
    didSet {
      if !preferenceKey.isEmpty {
        UserPreferences.shared.save(settings, for: preferenceKey)
      }
    }
  }
  /// Visual and Input Timing for the current audio output, shared by every
  /// engine.
  var timing = TimingCalibration() {
    didSet {
      if timingLoaded { UserPreferences.shared.save(timing, for: timingRoute) }
    }
  }
  private(set) var timingRoute = AudioRouteKind.wired
  private var timingLoaded = false

  /// Follow the current audio output: each kind keeps its own timing.
  func refreshTimingRoute() {
    let route = AudioRouteKind.current
    guard !timingLoaded || route != timingRoute else { return }
    timingLoaded = false
    timingRoute = route
    timing = UserPreferences.shared.timing(for: route)
    timingLoaded = true
  }

  var displayedScore: Int {
    if let engineScore {
      return settings.scoreDisplay == .countDown
        ? engineScore.remaining : engineScore.earned
    }
    return settings.scoreDisplay.score(judgements: judgements, noteCount: noteCount)
  }

  var noteCount: Int {
    engineRuntime?.inputCount ?? preparedInputCount
  }

  /// Partway through a play this is the score kept, not the score projected:
  /// notes still unjudged count as nothing yet.
  var score: Int {
    engineScore?.earned ?? NoteJudgement.score(for: judgements, noteCount: noteCount)
  }

  var accuracyScore: Int? { engineAccuracy?.earned }

  var modifiedOptions: [EngineOptionOverride] {
    var options = presentationAssets?.configuration
      .modifiedStandardOptions(preferences: settings) ?? []
    if isEngineDebugMode {
      options.append(EngineOptionOverride(name: "Engine Debug Mode", value: "On"))
    }
    if playInputOffset != 0 {
      options.append(EngineOptionOverride(name: "Input Timing",
        value: String(format: "%+.0f ms", playInputOffset * 1000)))
    }
    if playAudioOffset != 0 {
      options.append(EngineOptionOverride(name: "Visual Timing",
        value: String(format: "%+.0f ms", playAudioOffset * 1000)))
    }
    return options
  }

  var playbackTime: TimeInterval {
    if let debugPausedTime { return debugPausedTime }
    if isStartingPlayback { return currentTime }
    if let tailStart {
      return clockMapping.chartTime(mediaTime: tailStart.mediaTime)
        + max(0, ProcessInfo.processInfo.systemUptime - tailStart.uptime)
    }
    let mediaTime = player?.currentTime().seconds ?? 0
    return mediaTime.isFinite ? clockMapping.chartTime(mediaTime: mediaTime) : currentTime
  }

  /// A requested nonzero rate can still be waiting for media. EOF is
  /// different: unresolved chart events use the monotonic tail clock.
  var isPlaybackAdvancing: Bool {
    phase == .playing && !isStartingPlayback && !isDebugPaused
      && (tailStart != nil || player?.timeControlStatus == .playing)
  }

  private let loader: RuntimeBundleLoader
  private let resultStore: ResultStore
  private var bgmOffset = 0.0
  private var playbackSpeed = 1.0
  private(set) var playInputOffset = 0.0
  private(set) var playAudioOffset = 0.0
  private var requestedAudioOffset = 0.0
  private var clockMapping: BGMClockMapping {
    BGMClockMapping(offset: bgmOffset, speed: playbackSpeed,
      audioOffset: playAudioOffset)
  }
  private var player: AVPlayer?
  private let makePlayer: (URL) -> AVPlayer
  private let audioSession: PlaybackAudioSession
  private let audioNotifications: NotificationCenter
  private let audioSessionOwner = UUID()
  private var interruptionObserver: AudioInterruptionObservation?
  private var servicesObserver: AudioServicesObservation?
  private var eventClock: PlaybackEventClock?
  var eventClockDiagnosticObservations: [PlaybackEventClock.Observation] {
    eventClock?.diagnosticObservations ?? []
  }
  var eventClockDiagnostics: String {
    let observations = eventClockDiagnosticObservations
    return "Player rate=\(player?.rate ?? 0), "
      + "status=\(player?.timeControlStatus.rawValue ?? -1), "
      + "waiting=\(player?.reasonForWaitingToPlay?.rawValue ?? "none"); "
      + observations.map {
        "[observed=\($0.observedHostTime), reason=\($0.reason), "
          + "anchor=\($0.segment.hostTime), media=\($0.segment.mediaTime), "
          + "sourceHost=\($0.sourceAnchorHostTime), "
          + "sourceMedia=\($0.sourceAnchorMediaTime), "
          + "transition=\(String(describing: $0.transition)), "
          + "rate=\($0.segment.rate), payload=\($0.notificationPayload ?? "none")]"
      }.joined(separator: " ")
  }
  private var endObserver: NSObjectProtocol?
  private var statusObserver: NSKeyValueObservation?
  private var tailStart: (mediaTime: TimeInterval, uptime: TimeInterval)?
  private(set) var resultSaveTask: Task<Void, Never>?
  private(set) var resultSaveError: String?
  /// The finished play's result until the store accepts it.
  private var unsavedResult: PlayResult?
  private var resultLevel: SonolusLevelItem?
  private var resultServer: ServerDescriptor?
  private var resultLevelID = ""
  private var resultTitle = ""

  func inputTime(at timestamp: TimeInterval) -> TimeInterval {
    if let debugPausedTime { return debugPausedTime }
    if isStartingPlayback { return currentTime }
    if let tailStart, timestamp >= tailStart.uptime {
      return clockMapping.chartTime(mediaTime: tailStart.mediaTime)
        + timestamp - tailStart.uptime
    }
    guard let media = eventClock?.mediaTime(at: timestamp), media.isFinite
    else { return playbackTime }
    // AVPlayer may schedule its moving timebase to start in the future.
    // Extrapolation before that anchor must not go behind the completed seek.
    return clockMapping.inputChartTime(mediaTime: media,
      minimumMediaTime: skippedIntroDuration)
  }

  init(
    loader: RuntimeBundleLoader = RuntimeBundleLoader(),
    resultStore: ResultStore = .shared,
    audioSession: PlaybackAudioSession? = nil,
    audioNotifications: NotificationCenter = .default,
    makePlayer: @escaping (URL) -> AVPlayer = { AVPlayer(url: $0) }
  ) {
    self.loader = loader
    self.resultStore = resultStore
    self.audioSession = audioSession ?? .shared
    self.audioNotifications = audioNotifications
    self.makePlayer = makePlayer
    servicesObserver = AudioServicesObservation(center: audioNotifications) {
      [weak self] available in self?.audioServicesChanged(available: available)
    }
  }

  deinit {
    audioSession.release(owner: audioSessionOwner)
  }

  func prepare(
    level: SonolusLevelItem,
    server: ServerDescriptor,
    title: String
  ) async {
    guard phase == .loading else { return }
    do {
      let bundle = try await loader.load(level: level, from: server)
      try Task.checkCancellation()
      prepare(bundle: bundle, level: level, server: server, title: title)
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func prepare(
    bundle: RuntimeBundle,
    level: SonolusLevelItem,
    server: ServerDescriptor,
    title: String
  ) {
    guard phase == .loading else { return }
    preparedRuntime = nil
    preparedRuntimeOptions = nil
    preparedRuntimeSpeed = nil
    preparedRuntimeInputOffset = nil
    preparedRuntimeAudioOffset = nil
    preparedRuntimeDebugMode = nil
    preparedRuntimeAspect = nil
    preparedRuntimeSafeArea = nil
    do {
      guard let presentation = bundle.presentation else {
        throw RuntimeBundleError.missingResource("engine configuration")
      }
      let missing = try bundle.engine.unsupportedFunctions()
      guard missing.isEmpty else {
        throw EngineInterpreterError.unsupportedFunction(missing.joined(separator: ", "))
      }
      presentationAssets = try EnginePresentationAssets(
        engine: bundle.engine, presentation: presentation
      )
      engineAudio = areAudioServicesAvailable ? try EngineAudioPlayback(
        engine: bundle.engine, presentation: presentation
      ) : nil
      runtimeBundle = bundle
    } catch {
      phase = .failed(error.localizedDescription)
      return
    }
    let inputArchetypes = Set(bundle.engine.archetypes.filter(\.hasInput).map(\.name))
    preparedInputCount = bundle.level.entities.filter {
      inputArchetypes.contains($0.archetype)
    }.count
    // Load before setting the key: saving on load would replace stored
    // preferences this build could not decode with defaults.
    let key = level.engineKey(server: server)
    settings = UserPreferences.shared.gameplay(for: key)
    preferenceKey = key
    refreshTimingRoute()
    bgmOffset = bundle.level.bgmOffset
    resultLevel = level
    resultServer = server
    resultLevelID = level.resultKey(server: server)
    resultTitle = title
    preparedAudio = bundle.preparedAudio
    preparedBGMURL = bundle.bgmURL
    player = areAudioServicesAvailable ? makePlayer(bundle.bgmURL) : nil
    needsAudioRecreation = !areAudioServicesAvailable
    phase = .ready
  }

  private func audioServicesChanged(available: Bool) {
    areAudioServicesAvailable = available
    // Cancel pending activation/seek as well as active playback, and retire
    // all objects tied to the old media service. Keep immutable bundle data.
    stop()
    player = nil
    engineAudio = nil
    needsAudioRecreation = true
    playbackNotice = available
      ? "The audio service restarted. Tap Start to play the chart again."
      : "The audio service is unavailable. Wait for it to restart."
  }

  private func recreateAudioIfNeeded() throws {
    guard needsAudioRecreation, let url = preparedBGMURL else { return }
    let audio = try runtimeBundle.map { bundle in
      guard let presentation = bundle.presentation else {
        throw RuntimeBundleError.missingResource("engine configuration")
      }
      return try EngineAudioPlayback(engine: bundle.engine,
        presentation: presentation)
    }
    player = makePlayer(url)
    engineAudio = audio
    needsAudioRecreation = false
  }

  func start() {
    guard phase == .ready, areAudioServicesAvailable else { return }
    do { try recreateAudioIfNeeded() }
    catch {
      let error = error as NSError
      phase = .failed("Audio playback could not be restored. "
        + "\(error.localizedDescription) (\(error.domain), \(error.code))")
      return
    }
    guard let player else { return }
    playbackNotice = nil
    unsavedResult = nil
    resultSaveTask = nil
    resultSaveError = nil
    presentationAssets?.configureRenderMode(preferred: settings.skinRenderMode)
    let speed = presentationAssets?.configuration.playbackSpeed(preferences: settings) ?? 1
    guard speed.isFinite, (0.05...4).contains(speed) else {
      phase = .failed("This playback speed is outside the supported range (0.05–4×).")
      return
    }
    playbackSpeed = speed
    refreshTimingRoute()
    playInputOffset = timing.inputOffsetSeconds
    requestedAudioOffset = timing.visualOffsetSeconds
    playAudioOffset = requestedAudioOffset
    timingRecorder = settings.recordTimingDiagnostics ? PlaybackTimingRecorder() : nil
    playbackTiming = nil
    frameTiming = nil
    player.defaultRate = Float(speed)
    if let bundle = runtimeBundle {
      let timeline = BPMTimeline(level: bundle.level, speed: speed)
      inputMetadata = bundle.level.entities.map { entity in
        (entity.data.first { $0.name == "#BEAT" }?.value.map {
          timeline.time(at: $0)
        }, entity.archetype)
      }
    }
    playbackGeneration += 1
    inputGeneration += 1
    debugPausedTime = nil
    debugLog = []
    isEngineDebugMode = false
    let generation = playbackGeneration
    isStartingPlayback = true
    startupStage = "inspecting intro"
    audioSeekCompleted = false
    startupLimitMediaTime = nil
    startupPreparationComplete = false
    skippedIntroDuration = 0
    musicHasEnded = false
    latestJudgement = nil
    noteTimings.removeAll(keepingCapacity: true)
    resultBuckets = nil
    timingHeatmap = EngineErrorHeatmap()
    errorHeatmap = timingHeatmap.snapshot
    combo = 0
    maxCombo = 0
    currentTime = clockMapping.initialChartTime
    startupNextTime = currentTime
    startupSteps = 0
    startupVisualGuard = EngineIntroVisualGuard()
    engineRuntime = nil
    engineScore = nil
    engineAccuracy = nil
    engineLife = nil
    engineUI = []
    engineAspectRatio = nil
    for judgement in NoteJudgement.allCases {
      judgements[judgement] = 0
    }

    phase = .playing
    // Audio interruptions can occur without a scene-phase transition. Stop
    // both input and audio together, including a pending seek/activation or
    // the post-BGM tail. Like backgrounding, this attempt is not a result.
    interruptionObserver = AudioInterruptionObservation(
      center: audioNotifications
    ) { [weak self] in
      guard let self, self.playbackGeneration == generation else { return }
      self.abandonPlay(notice: "Audio playback was interrupted. "
        + "Tap Start to play the chart again.")
    }
    if let item = player.currentItem {
      endObserver = NotificationCenter.default.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification,
        object: item,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard self?.playbackGeneration == generation else { return }
          self?.playbackEnded()
        }
      }
      statusObserver = item.observe(\.status, options: [.initial, .new]) {
        [weak self] item, _ in
        guard item.status == .failed else { return }
        let message = item.error?.localizedDescription
          ?? "The music could not be played."
        Task { @MainActor in
          guard let self, self.phase == .playing,
            self.playbackGeneration == generation else { return }
          self.stop()
          self.phase = .failed(message)
        }
      }
    }
    let audioURL = player.currentItem?.asset as? AVURLAsset
    startupAnalysis = Task.detached {
      audioURL.map { LeadingAudioSilence.duration(at: $0.url) } ?? 0
    }
    Task {
      let limit = await startupAnalysis?.value ?? 0
      guard phase == .playing, playbackGeneration == generation else { return }
      startupLimitMediaTime = limit
    }
  }

  private func prepareStartupAudio() {
    guard !startupPreparationComplete, let player else { return }
    startupPreparationComplete = true
    let generation = playbackGeneration
    let mediaTime = max(0, clockMapping.mediaTime(chartTime: currentTime))
    skippedIntroDuration = mediaTime
    Task {
      guard phase == .playing, playbackGeneration == generation else { return }
      startupStage = "activating session"
      // Own the audio session before seeking can prepare player I/O. This
      // also reports activation failure instead of waiting on a blocked seek.
      do {
        try await audioSession.activate(owner: audioSessionOwner)
      } catch {
        guard phase == .playing, playbackGeneration == generation else { return }
        stop()
        let error = error as NSError
        phase = .failed("Audio playback could not start. "
          + "\(error.localizedDescription) (\(error.domain), \(error.code))")
        return
      }
      guard phase == .playing, playbackGeneration == generation else { return }
      startupStage = "seeking audio"
      let sought = await player.seek(to: CMTime(
        seconds: mediaTime, preferredTimescale: 60_000),
        toleranceBefore: .zero, toleranceAfter: .zero)
      guard phase == .playing, playbackGeneration == generation else { return }
      guard sought else {
        stop()
        phase = .failed("The music could not seek to the chart's start.")
        return
      }
      audioSeekCompleted = true
      startupStage = "waiting for engine"
      startPreparedAudio()
    }
  }

  private func advanceSilentIntro(_ runtime: EnginePlayRuntime) throws {
    guard !startupPreparationComplete, let limit = startupLimitMediaTime else { return }
    let finalTime = clockMapping.chartTime(mediaTime: limit)
    let deadline = ProcessInfo.processInfo.systemUptime + 0.004
    repeat {
      currentTime = startupNextTime
      try runtime.update(at: currentTime)
      startupSteps += 1
      // Activation can precede a note entering the viewport. Simulate beyond
      // it, but never commit an input consumed while searching for visibility.
      // Hidden/instant inputs fall back to the original, untrimmed start.
      if !runtime.judgments.isEmpty {
        try rewindSilentIntro(runtime)
        ingestJudgments(from: runtime)
        prepareStartupAudio()
        return
      }
      // Debug output is visible content too: do not fast-forward past it.
      if captureEngineDebugState(runtime) || !runtime.host.debugLog.isEmpty {
        ingestJudgments(from: runtime)
        prepareStartupAudio()
        return
      }
      if let assets = presentationAssets {
        let frame = EngineIntroVisualFrame(sprites: EngineRenderer.sprites(
          host: runtime.host, assets: assets, cacheParticleRandomVariables: false),
          aspect: engineAspectRatio ?? 1,
          background: (0..<8).map {
            runtime.memory.value(block: EnginePlayBlock.runtimeBackground,
              index: $0)
          },
          ui: (0..<8).map {
            let element = EngineUIElement(memory: runtime.memory, index: $0)
            return element.isVisible ? element.values : []
          }, life: runtime.life.value)
        let decision = startupVisualGuard.observe(frame,
          hasParticles: !runtime.host.particles.isEmpty)
        if decision != .advance {
          if decision == .rewind {
            // Restore before recording this frame's judgments or audio so a
            // retained count-in does not leak future playback side effects.
            try rewindSilentIntro(runtime)
          }
          ingestJudgments(from: runtime)
          prepareStartupAudio()
          return
        }
      }
      ingestJudgments(from: runtime)
      if currentTime >= finalTime
        || runtime.host.nextAudioStartTime.map({ $0 <= currentTime }) == true {
        prepareStartupAudio()
        return
      }
      // Huge finite offsets can make 1/60 smaller than a Double's ULP.
      // The optimization must never leave the song stuck at startup.
      guard let next = IntroAdvance.nextTime(current: currentTime, limit: finalTime,
        nextAudio: runtime.host.nextAudioStartTime, steps: startupSteps) else {
        prepareStartupAudio()
        return
      }
      startupNextTime = next
    } while ProcessInfo.processInfo.systemUptime < deadline
  }

  private func rewindSilentIntro(_ runtime: EnginePlayRuntime) throws {
    runtime.restart()
    currentTime = clockMapping.initialChartTime
    try runtime.update(at: currentTime)
    captureEngineDebugState(runtime)
  }

  private func startPreparedAudio() {
    guard phase == .playing, !isDebugPaused,
      isStartingPlayback, audioSeekCompleted, engineRuntime != nil else { return }
    do {
      if let recorder = timingRecorder {
        Self.recordAudioRoute(recorder)
        timingRouteObserver = NotificationCenter.default.addObserver(
          forName: AVAudioSession.routeChangeNotification,
          object: AVAudioSession.sharedInstance(), queue: nil
        ) { _ in Self.recordAudioRoute(recorder) }
      }
      startupStage = "starting engine audio"
      try engineAudio?.start()
      engineHaptics.start()
      if let timebase = player?.currentItem?.timebase {
        eventClock = PlaybackEventClock(timebase: timebase,
          recordTransitions: timingRecorder != nil)
      }
      isStartingPlayback = false
      startupStage = "play requested"
      player?.play()
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
    }
  }

  func restart() {
    stop(deactivateAudio: false)
    if phase == .finished { phase = .ready }
    start()
  }

  /// Pause at a frame boundary, never by unwinding an engine callback.
  /// Keep the runtime, pending commands, startup seek and EOF observers alive.
  func pauseForDebug() {
    guard phase == .playing, isEngineDebugMode, !isDebugPaused else { return }
    player?.pause()
    debugPausedTime = playbackTime
    inputGeneration += 1
    eventClock = nil
    engineAudio?.pause(at: playbackTime)
    engineHaptics.stop()
    frameTiming = nil
  }

  func resumeFromDebugPause() {
    guard phase == .playing, let pausedTime = debugPausedTime else { return }
    debugPausedTime = nil
    inputGeneration += 1
    if isStartingPlayback {
      startPreparedAudio()
      return
    }
    if musicHasEnded {
      tailStart = (clockMapping.mediaTime(chartTime: pausedTime),
        ProcessInfo.processInfo.systemUptime)
    } else {
      if let timebase = player?.currentItem?.timebase {
        eventClock = PlaybackEventClock(timebase: timebase,
          recordTransitions: timingRecorder != nil)
      }
      player?.play()
    }
    engineHaptics.start()
    finishIfReady()
  }

  @discardableResult
  private func captureEngineDebugState(_ runtime: EnginePlayRuntime) -> Bool {
    isEngineDebugMode = runtime.host.isDebugMode
    if debugLog.last?.id != runtime.host.debugLog.last?.id {
      debugLog = runtime.host.debugLog
    }
    if runtime.host.takeDebugPause() { pauseForDebug() }
    return isDebugPaused
  }

  func stop(deactivateAudio: Bool = true) {
    frameTiming = nil
    interruptionObserver = nil
    if let timingRouteObserver {
      NotificationCenter.default.removeObserver(timingRouteObserver)
      self.timingRouteObserver = nil
    }
    playbackGeneration += 1
    inputGeneration += 1
    debugPausedTime = nil
    isStartingPlayback = false
    startupStage = "stopped"
    audioSeekCompleted = false
    startupAnalysis?.cancel()
    startupAnalysis = nil
    player?.pause()
    eventClock = nil
    engineAudio?.stop()
    engineHaptics.stop()
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    statusObserver = nil
    tailStart = nil
    if phase == .playing { phase = .ready }
    if deactivateAudio {
      audioSession.release(owner: audioSessionOwner)
    }
  }

  /// Stop an attempt that cannot continue and tell the player why. Like any
  /// stop before the end, the attempt is not a result.
  func abandonPlay(notice: String) {
    guard phase == .playing else { return }
    stop()
    playbackNotice = notice
  }

  func playbackEnded(
    uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    guard phase == .playing, tailStart == nil else { return }
    musicHasEnded = true
    finishIfReady()
    guard phase == .playing else { return }
    // AVPlayer stops its clock at EOF. Continue the chart's remaining notes
    // and final judgement window using a monotonic clock.
    let mediaTime = player?.currentTime().seconds
      ?? clockMapping.mediaTime(chartTime: currentTime)
    tailStart = (
      mediaTime: max(
        mediaTime.isFinite ? mediaTime : 0,
        clockMapping.mediaTime(chartTime: currentTime)
      ),
      uptime: uptime
    )
  }

  /// The most a frame's chart time runs ahead of the music clock: the
  /// display link targets a vsync one or two 60 Hz refreshes after its
  /// callback (`preferredFrameLatency` 1). A longer wait is drawn late by
  /// the excess rather than delaying judgment further.
  static let displayLead = 2.0 / 60

  /// `displayHostTime` is when this frame is expected on screen (host
  /// seconds); nil draws the chart at the music clock's current time.
  @discardableResult
  func engineFrame(size: CGSize, touches: [EngineTouch],
    safeAreaInsets: UIEdgeInsets = .zero,
    displayHostTime: Double? = nil) -> Bool {
    frameTiming = nil
    guard phase == .playing, !isDebugPaused,
      size.width > 0, size.height > 0,
      let bundle = runtimeBundle, let assets = presentationAssets else { return false }
    do {
      let aspect = Double(size.width / size.height)
      if let engineAspectRatio, abs(engineAspectRatio - aspect) > 0.001 {
        // The runtime's screen geometry is fixed for a play.
        abandonPlay(notice: "Playback stopped because the screen size "
          + "changed. Tap Start to play again.")
        return false
      }
      if engineRuntime == nil {
        engineAspectRatio = aspect
        let safeArea = [
          -aspect + Double(safeAreaInsets.left * 2 / size.height),
          aspect - Double(safeAreaInsets.right * 2 / size.height),
          -1 + Double(safeAreaInsets.bottom * 2 / size.height),
          1 - Double(safeAreaInsets.top * 2 / size.height)
        ]
        let options = assets.configuration.runtimeOptions(preferences: settings)
        if let preparedRuntime, preparedRuntimeOptions == options,
          preparedRuntimeSpeed == playbackSpeed,
          preparedRuntimeInputOffset == playInputOffset,
          preparedRuntimeAudioOffset == requestedAudioOffset,
          preparedRuntimeDebugMode == settings.engineDebugMode,
          preparedRuntimeAspect == aspect, preparedRuntimeSafeArea == safeArea {
          preparedRuntime.restart()
          engineRuntime = preparedRuntime
        } else {
          engineRuntime = try EnginePlayRuntime(
            engine: bundle.engine, level: bundle.level,
            options: options,
            aspectRatio: aspect, skinSpriteIDs: Set(assets.skin.keys),
            effectClipIDs: engineAudio?.clipIDs ?? [],
            particleEffectIDs: Set(assets.particles.keys), rom: bundle.engineROM,
            uiConfiguration: assets.ui?.runtimeValues
              ?? Array(repeating: 1, count: 10),
            safeArea: safeArea, playbackSpeed: playbackSpeed,
            inputOffset: playInputOffset,
            displayLead: Self.displayLead,
            audioOffset: requestedAudioOffset,
            debugMode: settings.engineDebugMode,
            backgroundQuad: try assets.background?.initialQuad(screenAspect: aspect)
          )
          preparedRuntime = engineRuntime
          preparedRuntimeOptions = options
          preparedRuntimeSpeed = playbackSpeed
          preparedRuntimeInputOffset = playInputOffset
          preparedRuntimeAudioOffset = requestedAudioOffset
          preparedRuntimeDebugMode = settings.engineDebugMode
          preparedRuntimeAspect = aspect
          preparedRuntimeSafeArea = safeArea
        }
        if let runtime = engineRuntime {
          // Preprocessing may refine the supplied environment. Honor its
          // result before intro analysis, seeking, event clocks or rendering.
          playAudioOffset = try runtime.audioOffset
          currentTime = clockMapping.initialChartTime
          startupNextTime = currentTime
          engineUI = (0..<8).map { EngineUIElement(memory: runtime.memory, index: $0) }
          engineLife = runtime.life
          if captureEngineDebugState(runtime) {
            prepareStartupAudio()
            return false
          }
        }
      }
      if isStartingPlayback {
        if let runtime = engineRuntime { try advanceSilentIntro(runtime) }
        startPreparedAudio()
        return false
      }
      guard let runtime = engineRuntime else { return false }
      guard isPlaybackAdvancing else {
        // Preserve the last engine frame and all unconsumed input. Calling
        // update with empty touches would instead look like released holds.
        engineAudio?.pause(at: playbackTime)
        return false
      }
      let sampleStart = CACurrentMediaTime()
      let audioNow = playbackTime
      let sampleEnd = CACurrentMediaTime()
      let sampleHostTime = sampleStart + (sampleEnd - sampleStart) / 2
      // Draw the chart as it should look when this frame reaches the screen.
      // Chart seconds are wall-clock seconds at every playback speed.
      let lead = displayHostTime.map {
        min(Self.displayLead, max(0, $0 - sampleHostTime))
      } ?? 0
      // A shorter lead than the last frame's must not step time backwards.
      currentTime = max(audioNow + lead,
        min(currentTime, audioNow + Self.displayLead))
      if let recorder = timingRecorder {
        recorder.record(.clockRead, seconds: sampleEnd - sampleStart)
        if let displayHostTime {
          recorder.record(.displayLead, seconds: displayHostTime - sampleHostTime)
        }
        frameTiming = PlaybackFrameTiming(recorder: recorder,
          sampleHostTime: sampleHostTime,
          frameHostTime: sampleHostTime + currentTime - audioNow)
        if tailStart == nil, player?.timeControlStatus == .playing,
          let mediaTime = eventClock?.mediaTime(at: sampleHostTime) {
          recorder.record(.clockDifference,
            seconds: clockMapping.chartTime(mediaTime: mediaTime) - audioNow)
          // A scheduled player start can anchor the moving timebase in the
          // future. Keep its raw extrapolation visible, but separately compare
          // the same seek-floor clamp actually used for input timestamps.
          recorder.record(.inputClockDifference,
            seconds: clockMapping.inputChartTime(mediaTime: mediaTime,
              minimumMediaTime: skippedIntroDuration) - audioNow)
        }
      }
      let runtimeStart = timingRecorder.map { _ in CACurrentMediaTime() }
      try runtime.update(at: currentTime, audioNow: audioNow, touches: touches)
      if let runtimeStart {
        timingRecorder?.record(.runtime,
          seconds: CACurrentMediaTime() - runtimeStart)
      }
      let bookkeepingStart = timingRecorder.map { _ in CACurrentMediaTime() }
      engineScore = runtime.arcadeScore?.snapshot
      engineLife = runtime.life
      ingestJudgments(from: runtime)
      if let bookkeepingStart {
        timingRecorder?.record(.bookkeeping,
          seconds: CACurrentMediaTime() - bookkeepingStart)
      }
      if captureEngineDebugState(runtime) { return true }
      // Interpretation can consume a substantial part of a frame. Schedule
      // against the clock now, not its value before that work, or scheduled
      // hit sounds inherit the entire interpreter delay.
      let audioStart = engineAudio == nil ? nil
        : timingRecorder.map { _ in CACurrentMediaTime() }
      try engineAudio?.update(runtime.host.takeAudioCommands(), at: playbackTime,
        advancing: tailStart != nil || player?.timeControlStatus == .playing,
        loopCommands: runtime.host.takeLoopCommands(),
        currentTime: { self.playbackTime })
      if let audioStart, let engineAudio {
        timingRecorder?.record(.effectAudio,
          seconds: CACurrentMediaTime() - audioStart)
        timingRecorder?.record(.effectCompensation,
          seconds: engineAudio.outputCompensation)
      }
      finishIfReady()
      return true
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
      return false
    }
  }

  private func ingestJudgments(from runtime: EnginePlayRuntime) {
    engineAccuracy = runtime.accuracyScore.snapshot(noteCount: runtime.inputCount)
    if !isStartingPlayback {
      engineHaptics.play(EngineHaptic.combined(runtime.judgments.map(\.haptic)))
    }
    for judgment in runtime.judgments {
      let metadata = inputMetadata.indices.contains(judgment.entityIndex)
        ? inputMetadata[judgment.entityIndex] : (time: nil, type: "Unknown")
      let grade: NoteJudgement
      switch judgment.grade {
      case 1: grade = .perfect
      case 2: grade = .great
      case 3: grade = .good
      default: grade = .miss
      }
      record(grade, accuracy: judgment.accuracy,
        at: metadata.time, noteType: metadata.type,
        bucketIndex: judgment.bucketIndex, bucketValue: judgment.bucketValue)
    }
  }

  private func finishIfReady() {
    guard phase == .playing, !isDebugPaused, musicHasEnded else { return }
    // Without a runtime nothing has been judged yet.
    let complete = engineRuntime.map { $0.resolvedInputCount == $0.inputCount }
      ?? (preparedInputCount == 0)
    guard complete else { return }
    stop()
    phase = .finished
    playbackTiming = timingRecorder?.snapshot()
    saveResult()
  }

  func renderingFailed(_ error: Error) {
    guard phase == .playing else { return }
    stop()
    phase = .failed(error.localizedDescription)
  }

  private func record(_ judgement: NoteJudgement, accuracy: Double? = nil,
    at time: Double? = nil, noteType: String = "Unknown",
    bucketIndex: Double? = nil, bucketValue: Double? = nil) {
    let validAccuracy = judgement != .miss && accuracy.map {
      $0.isFinite && abs($0) <= 3_600
    } == true ? accuracy : nil
    let songTime = time ?? currentTime
    let timing = NoteTiming(id: noteTimings.count,
      songTime: songTime.isFinite ? songTime : currentTime,
      noteType: noteType, judgement: judgement, accuracy: validAccuracy,
      bucketIndex: bucketIndex, bucketValue: bucketValue)
    noteTimings.append(timing)
    let ui = presentationAssets?.ui
    if ui?.primaryMetric == "errorHeatmap" || ui?.secondaryMetric == "errorHeatmap",
      timingHeatmap.record(timing) {
      errorHeatmap = timingHeatmap.snapshot
    }
    judgementSequence += 1
    latestJudgement = JudgementFeedback(sequence: judgementSequence,
      judgement: judgement, accuracy: accuracy,
      minimumError: presentationAssets?.judgementErrorMinimum)
    judgements[judgement, default: 0] += 1
    if judgement == .miss {
      combo = 0
    } else {
      combo += 1
      maxCombo = max(maxCombo, combo)
    }
  }

  private func saveResult() {
    guard let level = resultLevel else { return }
    if let runtime = engineRuntime, let assets = presentationAssets {
      let used = Set(noteTimings.compactMap(\.bucketIndex))
      // Bound optional thumbnail work independently of retained result data.
      var previewPixels = 0
      resultBuckets = runtime.resultBuckets.enumerated().map { index, bucket in
        guard used.contains(Double(index)) else { return bucket }
        var snapshot = bucket
        do {
          guard previewPixels <= 8_000_000 - 128 * 128 else {
            throw EngineInterpreterError.resourceLimitExceeded("result bucket previews")
          }
          previewPixels += 128 * 128
          snapshot.imagePNG = try assets.bucketImage(bucket.definition)
        }
        catch { snapshot.imageError = error.localizedDescription }
        return snapshot
      }
    }
    let result = PlayResult(
      id: UUID(),
      levelID: resultLevelID,
      title: resultTitle,
      difficulty: level.difficulty,
      rating: level.rating,
      playedAt: Date(),
      maxCombo: maxCombo,
      perfect: judgements[.perfect, default: 0],
      great: judgements[.great, default: 0],
      good: judgements[.good, default: 0],
      miss: judgements[.miss, default: 0],
      noteTimings: noteTimings, duration: currentTime,
      level: level, server: resultServer, engineScore: engineScore?.earned,
      scoreMode: scoreModeName, finalLife: engineLife?.value,
      maximumLife: engineLife?.maximum, failed: engineLife?.failed,
      modifiedOptions: modifiedOptions, accuracyScore: accuracyScore,
      playbackTiming: playbackTiming,
      engineBuckets: resultBuckets
    )
    save(result)
  }

  func retryResultSave() {
    guard resultSaveError != nil, let unsavedResult else { return }
    save(unsavedResult)
  }

  private func save(_ result: PlayResult) {
    unsavedResult = result
    resultSaveError = nil
    resultSaveTask = Task {
      do {
        try await resultStore.record(result)
        if unsavedResult?.id == result.id { unsavedResult = nil }
      } catch {
        // A restarted play discards this result; do not report on it.
        guard unsavedResult?.id == result.id else { return }
        let error = error as NSError
        resultSaveError = "\(error.localizedDescription) "
          + "(\(error.domain), \(error.code))"
      }
    }
  }

  private var scoreModeName: String? {
    guard let option = presentationAssets?.scoreModeOption else { return nil }
    return option.valueLabel(option.value(option.preferredValue(in: settings)))
  }

  private nonisolated static func recordAudioRoute(_ recorder: PlaybackTimingRecorder) {
    let session = AVAudioSession.sharedInstance()
    recorder.audio(route: session.currentRoute.outputs.map { $0.portType.rawValue }
      .sorted().joined(separator: ", "), outputLatency: session.outputLatency,
      bufferDuration: session.ioBufferDuration)
  }

}
