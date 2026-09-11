import AVFoundation
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
  var initialMediaTime: Double { max(0, offset) }
  var initialChartTime: Double { chartTime(mediaTime: initialMediaTime) }
  func chartTime(mediaTime: Double) -> Double { mediaTime - offset }
  func mediaTime(chartTime: Double) -> Double { chartTime + offset }
}

struct JudgementFeedback: Hashable {
  let sequence: Int
  let judgement: NoteJudgement
  let accuracy: Double?

  func text(for mode: JudgementDisplayMode) -> String? {
    guard mode != .off else { return nil }
    let grade = judgement.rawValue.uppercased()
    guard mode == .timing, judgement == .great || judgement == .good,
      let accuracy, accuracy.isFinite, accuracy != 0 else { return grade }
    return (accuracy < 0 ? "Early " : "Late ") + grade
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
  private var preparedInputCount: Int?
  private var musicHasEnded = false
  private var judgementSequence = 0
  private(set) var latestJudgement: JudgementFeedback?
  @ObservationIgnored private(set) var noteTimings = [NoteTiming]()
  @ObservationIgnored private var inputMetadata = [(time: Double?, type: String)]()
  private(set) var engineRuntime: EnginePlayRuntime?
  private(set) var presentationAssets: EnginePresentationAssets?
  private var runtimeBundle: RuntimeBundle?
  private var engineAudio: EngineAudioPlayback?
  private var engineAspectRatio: Double?
  private var preferenceKey = ""
  var settings = GameplayPreferences() {
    didSet {
      if !preferenceKey.isEmpty {
        UserPreferences.shared.save(settings, for: preferenceKey)
      }
    }
  }

  var displayedScore: Int {
    settings.scoreDisplay.score(judgements: judgements, noteCount: noteCount)
  }

  var noteCount: Int {
    engineRuntime?.inputCount ?? preparedInputCount ?? chart.judgementCount
  }

  /// Partway through a play this is the score kept, not the score projected:
  /// notes still unjudged count as nothing yet.
  var score: Int {
    NoteJudgement.score(for: judgements, noteCount: noteCount)
  }

  var playbackTime: TimeInterval {
    if isStartingPlayback { return clockMapping.initialChartTime }
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
  private var clockMapping: BGMClockMapping { BGMClockMapping(offset: bgmOffset) }
  private var player: AVPlayer?
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
    do {
      if let presentation = bundle.presentation {
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
    player = AVPlayer(url: bundle.bgmURL)
    phase = .ready
  }

  func start() {
    guard phase == .ready, let player else { return }
    playbackGeneration += 1
    let generation = playbackGeneration
    isStartingPlayback = true
    audioSeekCompleted = false
    musicHasEnded = false
    latestJudgement = nil
    noteTimings.removeAll(keepingCapacity: true)
    combo = 0
    maxCombo = 0
    currentTime = clockMapping.initialChartTime
    engineRuntime = nil
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
        guard self?.tailStart == nil, self?.presentationAssets == nil,
          self?.playbackGeneration == generation,
          self?.isStartingPlayback == false else { return }
        self?.update(mediaTime: time.seconds)
      }
    }
    Task {
      let sought = await player.seek(to: CMTime(
        seconds: clockMapping.initialMediaTime, preferredTimescale: 60_000),
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

  private func startPreparedAudio() {
    guard phase == .playing, isStartingPlayback, audioSeekCompleted,
      presentationAssets == nil || engineRuntime != nil else { return }
    do {
      try engineAudio?.start()
      isStartingPlayback = false
      player?.play()
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
    }
  }

  func press(lane: Int) {
    guard phase == .playing else { return }
    guard pressedLanes.insert(lane).inserted else { return }
    hit(lane: lane, swingsOnly: false)
  }

  func slide(lane: Int) {
    guard phase == .playing else { return }
    pressedLanes.insert(lane)
    hit(lane: lane, swingsOnly: true)
  }

  private func hit(lane: Int, swingsOnly: Bool) {
    let window = 0.18
    guard let note = chart.notes
      .filter({
        $0.lane == lane
          && (!swingsOnly || $0.kind == .swing)
          && !hitNoteIDs.contains($0.id)
          && abs($0.time - currentTime) <= window
      })
      .min(by: {
        abs($0.time - currentTime) < abs($1.time - currentTime)
      })
    else { return }

    hitNoteIDs.insert(note.id)
    record(difference: currentTime - note.time, note: note)
    if note.endTime != nil {
      activeHolds[lane] = note
    }
  }

  func release(lane: Int) {
    pressedLanes.remove(lane)
    guard
      phase == .playing,
      let hold = activeHolds.removeValue(forKey: lane),
      let endTime = hold.endTime,
      resolvedHoldTailIDs.insert(hold.id).inserted
    else { return }

    let difference = currentTime - endTime
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
    playbackGeneration += 1
    isStartingPlayback = false
    audioSeekCompleted = false
    player?.pause()
    engineAudio?.stop()
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

    for lane in pressedLanes {
      hit(lane: lane, swingsOnly: true)
    }

    while nextMissIndex < chart.notes.count,
      chart.notes[nextMissIndex].time < currentTime - 0.18
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
        endTime < currentTime - 0.18,
        resolvedHoldTailIDs.insert(note.id).inserted
      else { continue }
      if activeHolds[note.lane]?.id == note.id {
        activeHolds.removeValue(forKey: note.lane)
      }
      record(.miss, at: endTime, noteType: "Hold End")
    }

    finishIfReady()
  }

  func engineFrame(size: CGSize, touches: [EngineTouch]) {
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
        engineRuntime = try EnginePlayRuntime(
          engine: bundle.engine, level: bundle.level,
          options: assets.runtimeOptions(noteSpeed: settings.noteSpeed),
          aspectRatio: aspect, skinSpriteIDs: Set(assets.skin.keys),
          effectClipIDs: engineAudio?.clipIDs ?? [],
          particleEffectIDs: Set(assets.particles.keys), rom: bundle.engineROM
        )
      }
      if isStartingPlayback {
        startPreparedAudio()
        return
      }
      guard let runtime = engineRuntime else { return }
      currentTime = playbackTime
      try runtime.update(at: currentTime, touches: touches)
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
      try engineAudio?.update(runtime.host.takeAudioCommands(), at: currentTime,
        advancing: tailStart != nil || player?.timeControlStatus == .playing,
        loopCommands: runtime.host.takeLoopCommands())
      finishIfReady()
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
    }
  }

  private func finishIfReady() {
    guard phase == .playing, musicHasEnded else { return }
    let complete = engineRuntime.map { $0.resolvedInputCount == $0.inputCount }
      ?? (judgements.values.reduce(0, +) == chart.judgementCount)
    guard complete else { return }
    stop()
    phase = .finished
    saveResult()
  }

  private func record(_ judgement: NoteJudgement, accuracy: Double? = nil,
    at time: Double? = nil, noteType: String = "Unknown") {
    let validAccuracy = judgement != .miss && accuracy.map {
      $0.isFinite && abs($0) <= 3_600
    } == true ? accuracy : nil
    let songTime = time ?? currentTime
    noteTimings.append(NoteTiming(id: noteTimings.count,
      songTime: songTime.isFinite ? songTime : currentTime,
      noteType: noteType, judgement: judgement, accuracy: validAccuracy))
    judgementSequence += 1
    latestJudgement = JudgementFeedback(sequence: judgementSequence,
      judgement: judgement, accuracy: accuracy)
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
      level: level, server: resultServer
    )
    resultSaveTask = Task {
      do {
        try await resultStore.record(result)
      } catch {
        resultSaveError = error.localizedDescription
      }
    }
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
