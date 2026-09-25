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
  // The offset aligns two timelines; it is not permission to trim audio.
  var initialMediaTime: Double { 0 }
  var initialChartTime: Double { chartTime(mediaTime: initialMediaTime) }
  func chartTime(mediaTime: Double) -> Double { (mediaTime - offset) / speed }
  func mediaTime(chartTime: Double) -> Double { chartTime * speed + offset }
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

@MainActor
@Observable
final class GameplayModel {
  private(set) var phase = GameplayPhase.loading
  private(set) var chart = RhythmChart(
    level: LevelData(bgmOffset: 0, entities: [])
  )
  private(set) var currentTime: TimeInterval = 0
  private(set) var combo = 0
  private(set) var maxCombo = 0
  private(set) var judgements = Dictionary(
    uniqueKeysWithValues: NoteJudgement.allCases.map { ($0, 0) }
  )
  private(set) var hitNoteIDs = Set<String>()
  private(set) var playbackGeneration = 0
  private(set) var isStartingPlayback = false
  private var audioSeekCompleted = false
  private var startupLimitMediaTime: Double?
  private var startupNextTime = 0.0
  private(set) var startupSteps = 0
  private var startupVisualGuard = EngineIntroVisualGuard()
  private var startupPreparationComplete = false
  private var startupAnalysis: Task<Double, Never>?
  private(set) var skippedIntroDuration = 0.0
  private var preparedInputCount: Int?
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
  @ObservationIgnored private var inputMetadata = [(time: Double?, type: String)]()
  private(set) var engineRuntime: EnginePlayRuntime?
  private(set) var presentationAssets: EnginePresentationAssets?
  private var runtimeBundle: RuntimeBundle?
  private var preparedAudio: PreparedRuntimeAudio?
  private var engineAudio: EngineAudioPlayback?
  private let engineHaptics = EngineHapticPlayback()
  private var engineAspectRatio: Double?
  private var preparedRuntime: EnginePlayRuntime?
  private var preparedRuntimeOptions: [Double]?
  private var preparedRuntimeSpeed: Double?
  private var preparedRuntimeInputOffset: Double?
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

  var displayedScore: Int {
    if let engineScore {
      return settings.scoreDisplay == .countDown
        ? engineScore.remaining : engineScore.earned
    }
    return settings.scoreDisplay.score(judgements: judgements, noteCount: noteCount)
  }

  var noteCount: Int {
    engineRuntime?.inputCount ?? preparedInputCount ?? chart.judgementCount
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
    if playInputOffset != 0 {
      options.append(EngineOptionOverride(name: "Input Timing",
        value: String(format: "%+.0f ms", playInputOffset * 1000)))
    }
    return options
  }

  var playbackTime: TimeInterval {
    if isStartingPlayback { return currentTime }
    if let tailStart {
      return clockMapping.chartTime(mediaTime: tailStart.mediaTime)
        + max(0, ProcessInfo.processInfo.systemUptime - tailStart.uptime)
    }
    let mediaTime = player?.currentTime().seconds ?? 0
    return mediaTime.isFinite ? clockMapping.chartTime(mediaTime: mediaTime) : currentTime
  }

  var activeHoldIDs: Set<String> {
    Set(activeHolds.values.map(\.id))
  }

  private let loader: RuntimeBundleLoader
  private let resultStore: ResultStore
  private var bgmOffset = 0.0
  private var playbackSpeed = 1.0
  private(set) var playInputOffset = 0.0
  private var clockMapping: BGMClockMapping {
    BGMClockMapping(offset: bgmOffset, speed: playbackSpeed)
  }
  private var player: AVPlayer?
  private var eventClock: PlaybackEventClock?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var statusObserver: NSKeyValueObservation?
  private var tailTimer: Timer?
  private var tailStart: (mediaTime: TimeInterval, uptime: TimeInterval)?
  private(set) var resultSaveTask: Task<Void, Never>?
  private(set) var resultSaveError: String?
  private var nextMissIndex = 0
  private var resultLevel: SonolusLevelItem?
  private var resultServer: ServerDescriptor?
  private var resultLevelID = ""
  private var resultTitle = ""
  private var pressedLanes = Set<Int>()
  private var activeHolds = [Int: RhythmNote]()
  private var resolvedHoldTailIDs = Set<String>()

  func inputTime(at timestamp: TimeInterval) -> TimeInterval {
    if isStartingPlayback { return currentTime }
    if let tailStart, timestamp >= tailStart.uptime {
      return clockMapping.chartTime(mediaTime: tailStart.mediaTime)
        + timestamp - tailStart.uptime
    }
    guard let media = eventClock?.mediaTime(at: timestamp), media.isFinite
    else { return playbackTime }
    // AVPlayer may schedule its moving timebase to start in the future.
    // Extrapolation before that anchor must not go behind the completed seek.
    return clockMapping.chartTime(mediaTime: max(skippedIntroDuration, media))
  }

  init(
    loader: RuntimeBundleLoader = RuntimeBundleLoader(),
    resultStore: ResultStore = .shared
  ) {
    self.loader = loader
    self.resultStore = resultStore
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
    preparedRuntimeAspect = nil
    preparedRuntimeSafeArea = nil
    do {
      if let presentation = bundle.presentation {
        let missing = try bundle.engine.unsupportedFunctions()
        guard missing.isEmpty else {
          throw EngineInterpreterError.unsupportedFunction(missing.joined(separator: ", "))
        }
        presentationAssets = try EnginePresentationAssets(
          engine: bundle.engine, presentation: presentation
        )
        engineAudio = try EngineAudioPlayback(
          engine: bundle.engine, presentation: presentation
        )
        runtimeBundle = bundle
      }
    } catch {
      phase = .failed(error.localizedDescription)
      return
    }
    chart = RhythmChart(level: bundle.level)
    let timeline = BPMTimeline(level: bundle.level)
    inputMetadata = bundle.level.entities.map {
      ($0.data.first { $0.name == "#BEAT" }?.value.map {
        timeline.time(at: $0)
      }, $0.archetype)
    }
    if presentationAssets != nil {
      let inputArchetypes = Set(bundle.engine.archetypes.filter(\.hasInput).map(\.name))
      preparedInputCount = bundle.level.entities.filter {
        inputArchetypes.contains($0.archetype)
      }.count
    }
    preferenceKey = level.engineKey(server: server)
    settings = UserPreferences.shared.gameplay(for: preferenceKey)
    bgmOffset = bundle.level.bgmOffset
    resultLevel = level
    resultServer = server
    resultLevelID = level.resultKey(server: server)
    resultTitle = title
    preparedAudio = bundle.preparedAudio
    player = AVPlayer(url: bundle.bgmURL)
    phase = .ready
  }

  func start() {
    guard phase == .ready, let player else { return }
    presentationAssets?.configureRenderMode(preferred: settings.skinRenderMode)
    let speed = presentationAssets?.configuration.playbackSpeed(preferences: settings) ?? 1
    guard speed.isFinite, (0.05...4).contains(speed) else {
      phase = .failed("This playback speed is outside the supported range (0.05–4×).")
      return
    }
    playbackSpeed = speed
    playInputOffset = settings.inputOffsetSeconds
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
    let generation = playbackGeneration
    isStartingPlayback = true
    audioSeekCompleted = false
    startupLimitMediaTime = nil
    startupPreparationComplete = false
    skippedIntroDuration = 0
    musicHasEnded = false
    latestJudgement = nil
    noteTimings.removeAll(keepingCapacity: true)
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
    nextMissIndex = 0
    hitNoteIDs.removeAll()
    pressedLanes.removeAll()
    activeHolds.removeAll()
    resolvedHoldTailIDs.removeAll()
    for judgement in NoteJudgement.allCases {
      judgements[judgement] = 0
    }

    phase = .playing
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
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 60),
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        guard self?.tailStart == nil,
          self?.presentationAssets == nil,
          self?.playbackGeneration == generation,
          self?.isStartingPlayback == false else { return }
        self?.update(mediaTime: time.seconds)
      }
    }
    let audioURL = player.currentItem?.asset as? AVURLAsset
    let canInspectIntro = presentationAssets != nil
    startupAnalysis = Task.detached {
      canInspectIntro ? audioURL.map { LeadingAudioSilence.duration(at: $0.url) } ?? 0 : 0
    }
    Task {
      let limit = await startupAnalysis?.value ?? 0
      guard phase == .playing, playbackGeneration == generation else { return }
      startupLimitMediaTime = limit
      if presentationAssets == nil { prepareStartupAudio() }
    }
  }

  private func prepareStartupAudio() {
    guard !startupPreparationComplete, let player else { return }
    startupPreparationComplete = true
    let generation = playbackGeneration
    let mediaTime = max(0, clockMapping.mediaTime(chartTime: currentTime))
    skippedIntroDuration = mediaTime
    Task {
      let sought = await player.seek(to: CMTime(
        seconds: mediaTime, preferredTimescale: 60_000),
        toleranceBefore: .zero, toleranceAfter: .zero)
      guard phase == .playing, playbackGeneration == generation else { return }
      guard sought else {
        stop()
        phase = .failed("The music could not seek to the chart's start.")
        return
      }
      await Self.setAudioSession(active: true)
      guard phase == .playing, playbackGeneration == generation else { return }
      audioSeekCompleted = true
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
      if let assets = presentationAssets {
        let frame = EngineIntroVisualFrame(sprites: EngineRenderer.sprites(
          host: runtime.host, assets: assets, cacheParticleRandomVariables: false),
          aspect: engineAspectRatio ?? 1,
          background: (0..<8).map { runtime.memory.value(block: 1005, index: $0) },
          ui: (0..<8).map {
            let element = EngineUIElement(memory: runtime.memory, index: $0)
            return element.isVisible ? element.values : []
          })
        let decision = startupVisualGuard.observe(frame,
          hasParticles: !runtime.host.particles.isEmpty)
        if decision != .advance {
          if decision == .rewind {
            // No earlier frame activated an input, or we would have stopped.
            // Restore before recording this frame's judgments or audio so a
            // retained count-in does not leak future playback side effects.
            runtime.restart()
            currentTime = clockMapping.initialChartTime
            try runtime.update(at: currentTime)
          }
          ingestJudgments(from: runtime)
          prepareStartupAudio()
          return
        }
      }
      ingestJudgments(from: runtime)
      if runtime.hasActivatedInput || currentTime >= finalTime
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

  private func startPreparedAudio() {
    guard phase == .playing, isStartingPlayback, audioSeekCompleted,
      presentationAssets == nil || engineRuntime != nil else { return }
    do {
      if let recorder = timingRecorder {
        Self.recordAudioRoute(recorder)
        timingRouteObserver = NotificationCenter.default.addObserver(
          forName: AVAudioSession.routeChangeNotification,
          object: AVAudioSession.sharedInstance(), queue: nil
        ) { _ in Self.recordAudioRoute(recorder) }
      }
      try engineAudio?.start()
      if engineRuntime != nil { engineHaptics.start() }
      if let timebase = player?.currentItem?.timebase {
        eventClock = PlaybackEventClock(timebase: timebase)
      }
      isStartingPlayback = false
      player?.play()
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
    }
  }

  func press(lane: Int, at time: TimeInterval? = nil) {
    guard phase == .playing else { return }
    guard pressedLanes.insert(lane).inserted else { return }
    hit(lane: lane, swingsOnly: false,
      at: (time ?? currentTime) - playInputOffset)
  }

  func slide(lane: Int, at time: TimeInterval? = nil) {
    guard phase == .playing else { return }
    pressedLanes.insert(lane)
    hit(lane: lane, swingsOnly: true,
      at: (time ?? currentTime) - playInputOffset)
  }

  private func hit(lane: Int, swingsOnly: Bool, at time: TimeInterval) {
    let window = 0.18
    guard let note = chart.notes
      .filter({
        $0.lane == lane
          && (!swingsOnly || $0.kind == .swing)
          && !hitNoteIDs.contains($0.id)
          && abs($0.time - time) <= window
      })
      .min(by: {
        abs($0.time - time) < abs($1.time - time)
      })
    else { return }

    hitNoteIDs.insert(note.id)
    record(difference: time - note.time, note: note)
    if note.endTime != nil {
      activeHolds[lane] = note
    }
  }

  func release(lane: Int, at time: TimeInterval? = nil) {
    pressedLanes.remove(lane)
    guard
      phase == .playing,
      let hold = activeHolds.removeValue(forKey: lane),
      let endTime = hold.endTime,
      resolvedHoldTailIDs.insert(hold.id).inserted
    else { return }

    let difference = (time ?? currentTime) - playInputOffset - endTime
    if abs(difference) <= 0.18 {
      record(difference: difference, note: hold, tail: true)
    } else {
      record(.miss, at: endTime, noteType: "Hold End")
    }
  }

  func restart() {
    stop(deactivateAudio: false)
    if phase == .finished { phase = .ready }
    start()
  }

  func stop(deactivateAudio: Bool = true) {
    frameTiming = nil
    if let timingRouteObserver {
      NotificationCenter.default.removeObserver(timingRouteObserver)
      self.timingRouteObserver = nil
    }
    playbackGeneration += 1
    isStartingPlayback = false
    audioSeekCompleted = false
    startupAnalysis?.cancel()
    startupAnalysis = nil
    player?.pause()
    eventClock = nil
    engineAudio?.stop()
    engineHaptics.stop()
    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    statusObserver = nil
    tailTimer?.invalidate()
    tailTimer = nil
    tailStart = nil
    pressedLanes.removeAll()
    activeHolds.removeAll()
    if phase == .playing { phase = .ready }
    if deactivateAudio {
      Task {
        guard phase != .playing else { return }
        await Self.setAudioSession(active: false)
      }
    }
  }

  func playbackEnded(
    uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    guard phase == .playing, tailStart == nil else { return }
    musicHasEnded = true
    finishIfReady()
    guard phase == .playing else { return }
    let mediaTime = player?.currentTime().seconds
      ?? clockMapping.mediaTime(chartTime: currentTime)
    tailStart = (
      mediaTime: max(
        mediaTime.isFinite ? mediaTime : 0,
        clockMapping.mediaTime(chartTime: currentTime)
      ),
      uptime: uptime
    )
    // AVPlayer stops its clock at EOF. Continue the chart's remaining notes
    // and final judgement window using a monotonic clock.
    tailTimer = Timer.scheduledTimer(
      withTimeInterval: 1.0 / 60, repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        self?.advanceAfterAudioEnd()
      }
    }
  }

  func advanceAfterAudioEnd(
    uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    guard let tailStart, presentationAssets == nil else { return }
    update(mediaTime: tailStart.mediaTime + max(0, uptime - tailStart.uptime))
  }

  func update(mediaTime: TimeInterval) {
    guard phase == .playing, mediaTime.isFinite else { return }
    currentTime = clockMapping.chartTime(mediaTime: mediaTime)
    let inputTime = currentTime - playInputOffset

    for lane in pressedLanes {
      hit(lane: lane, swingsOnly: true, at: inputTime)
    }

    while nextMissIndex < chart.notes.count,
      chart.notes[nextMissIndex].time < inputTime - 0.18
    {
      let note = chart.notes[nextMissIndex]
      if !hitNoteIDs.contains(note.id) {
        hitNoteIDs.insert(note.id)
        record(.miss, at: note.time, noteType: type(of: note))
      }
      nextMissIndex += 1
    }

    for note in chart.notes {
      guard
        let endTime = note.endTime,
        endTime < inputTime - 0.18,
        resolvedHoldTailIDs.insert(note.id).inserted
      else { continue }
      if activeHolds[note.lane]?.id == note.id {
        activeHolds.removeValue(forKey: note.lane)
      }
      record(.miss, at: endTime, noteType: "Hold End")
    }

    finishIfReady()
  }

  func engineFrame(size: CGSize, touches: [EngineTouch],
    safeAreaInsets: UIEdgeInsets = .zero) {
    frameTiming = nil
    guard phase == .playing,
      size.width > 0, size.height > 0,
      let bundle = runtimeBundle, let assets = presentationAssets else { return }
    do {
      let aspect = Double(size.width / size.height)
      if let engineAspectRatio, abs(engineAspectRatio - aspect) > 0.001 {
        stop()
        return
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
            backgroundQuad: try assets.background?.initialQuad(screenAspect: aspect)
          )
          preparedRuntime = engineRuntime
          preparedRuntimeOptions = options
          preparedRuntimeSpeed = playbackSpeed
          preparedRuntimeInputOffset = playInputOffset
          preparedRuntimeAspect = aspect
          preparedRuntimeSafeArea = safeArea
        }
        if let runtime = engineRuntime {
          engineUI = (0..<8).map { EngineUIElement(memory: runtime.memory, index: $0) }
          engineLife = runtime.life
        }
      }
      if isStartingPlayback {
        if let runtime = engineRuntime { try advanceSilentIntro(runtime) }
        startPreparedAudio()
        return
      }
      guard let runtime = engineRuntime else { return }
      let sampleStart = timingRecorder.map { _ in CACurrentMediaTime() }
      currentTime = playbackTime
      if let recorder = timingRecorder, let sampleStart {
        let sampleEnd = CACurrentMediaTime()
        let midpoint = sampleStart + (sampleEnd - sampleStart) / 2
        recorder.record(.clockRead, seconds: sampleEnd - sampleStart)
        frameTiming = PlaybackFrameTiming(recorder: recorder,
          sampleHostTime: midpoint)
        if tailStart == nil, player?.timeControlStatus == .playing,
          let mediaTime = eventClock?.mediaTime(at: midpoint) {
          recorder.record(.clockDifference,
            seconds: clockMapping.chartTime(mediaTime: mediaTime) - currentTime)
        }
      }
      let runtimeStart = timingRecorder.map { _ in CACurrentMediaTime() }
      try runtime.update(at: currentTime, touches: touches)
      if let runtimeStart {
        timingRecorder?.record(.runtime,
          seconds: CACurrentMediaTime() - runtimeStart)
      }
      engineScore = runtime.arcadeScore?.snapshot
      engineLife = runtime.life
      ingestJudgments(from: runtime)
      // Interpretation can consume a substantial part of a frame. Schedule
      // against the clock now, not its value before that work, or scheduled
      // hit sounds inherit the entire interpreter delay.
      try engineAudio?.update(runtime.host.takeAudioCommands(), at: playbackTime,
        advancing: tailStart != nil || player?.timeControlStatus == .playing,
        loopCommands: runtime.host.takeLoopCommands())
      finishIfReady()
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
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
        at: metadata.time, noteType: metadata.type)
    }
  }

  private func finishIfReady() {
    guard phase == .playing, musicHasEnded else { return }
    let complete = engineRuntime.map { $0.resolvedInputCount == $0.inputCount }
      ?? (judgements.values.reduce(0, +) == chart.judgementCount)
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
    at time: Double? = nil, noteType: String = "Unknown") {
    let validAccuracy = judgement != .miss && accuracy.map {
      $0.isFinite && abs($0) <= 3_600
    } == true ? accuracy : nil
    let songTime = time ?? currentTime
    let timing = NoteTiming(id: noteTimings.count,
      songTime: songTime.isFinite ? songTime : currentTime,
      noteType: noteType, judgement: judgement, accuracy: validAccuracy)
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

  private func type(of note: RhythmNote) -> String {
    if note.endTime != nil { return "Hold Start" }
    return note.kind == .swing ? "Swing" : "Tap"
  }

  private func record(difference: TimeInterval, note: RhythmNote,
    tail: Bool = false) {
    let time = tail ? note.endTime : note.time
    let noteType = tail ? "Hold End" : type(of: note)
    if abs(difference) <= 0.05 {
      record(.perfect, accuracy: difference, at: time, noteType: noteType)
    } else if abs(difference) <= 0.10 {
      record(.great, accuracy: difference, at: time, noteType: noteType)
    } else {
      record(.good, accuracy: difference, at: time, noteType: noteType)
    }
  }

  private func saveResult() {
    guard let level = resultLevel else { return }
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
      playbackTiming: playbackTiming
    )
    resultSaveTask = Task {
      do {
        try await resultStore.record(result)
      } catch {
        resultSaveError = error.localizedDescription
      }
    }
  }

  private var scoreModeName: String? {
    guard let option = presentationAssets?.scoreModeOption,
      let values = option.values else { return nil }
    return option.selectedIndex(settings.scoreMode).map { values[$0].displayValue() }
  }

  private nonisolated static func recordAudioRoute(_ recorder: PlaybackTimingRecorder) {
    let session = AVAudioSession.sharedInstance()
    recorder.audio(route: session.currentRoute.outputs.map { $0.portType.rawValue }
      .sorted().joined(separator: ", "), outputLatency: session.outputLatency,
      bufferDuration: session.ioBufferDuration)
  }

  private nonisolated static func setAudioSession(active: Bool) async {
    await Task.detached(priority: .userInitiated) {
      let session = AVAudioSession.sharedInstance()
      if active {
        try? session.setCategory(.playback)
      }
      try? session.setActive(active)
    }.value
  }
}
