import AVFoundation
import Observation

enum GameplayPhase: Equatable {
  case loading
  case ready
  case playing
  case finished
  case failed(String)
}

enum NoteJudgement: String, CaseIterable, Sendable {
  case perfect
  case great
  case good
  case miss

  var displayName: String { rawValue.capitalized }
}

@MainActor
@Observable
final class GameplayModel {
  private(set) var phase = GameplayPhase.loading
  private(set) var chart = RhythmChart(
    level: LevelData(bgmOffset: 0, entities: [])
  )
  private(set) var currentTime: TimeInterval = 0
  private(set) var score = 0
  private(set) var combo = 0
  private(set) var maxCombo = 0
  private(set) var judgements = Dictionary(
    uniqueKeysWithValues: NoteJudgement.allCases.map { ($0, 0) }
  )
  private(set) var hitNoteIDs = Set<String>()
  private(set) var engineRuntime: EnginePlayRuntime?
  private(set) var presentationAssets: EnginePresentationAssets?
  private var runtimeBundle: RuntimeBundle?
  private var engineAudio: EngineAudioPlayback?
  private var engineAspectRatio: Double?

  var noteCount: Int { engineRuntime?.inputCount ?? chart.judgementCount }

  var playbackTime: TimeInterval {
    if let tailStart {
      return tailStart.mediaTime + bgmOffset
        + max(0, ProcessInfo.processInfo.systemUptime - tailStart.uptime)
    }
    let mediaTime = player?.currentTime().seconds ?? 0
    return mediaTime.isFinite ? mediaTime + bgmOffset : currentTime
  }

  var activeHoldIDs: Set<String> {
    Set(activeHolds.values.map(\.id))
  }

  private let loader: RuntimeBundleLoader
  private let resultStore: ResultStore
  private var bgmOffset = 0.0
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
    bgmOffset = bundle.level.bgmOffset
    resultLevel = level
    resultLevelID = level.resultKey(server: server)
    resultTitle = title
    player = AVPlayer(url: bundle.bgmURL)
    phase = .ready
  }

  func start() {
    guard phase == .ready, let player else { return }
    score = 0
    combo = 0
    maxCombo = 0
    currentTime = bgmOffset
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

    player.seek(to: .zero)
    phase = .playing
    if let item = player.currentItem {
      endObserver = NotificationCenter.default.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification,
        object: item,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.playbackEnded()
        }
      }
      statusObserver = item.observe(\.status, options: [.initial, .new]) {
        [weak self] item, _ in
        guard item.status == .failed else { return }
        let message = item.error?.localizedDescription
          ?? "The music could not be played."
        Task { @MainActor in
          guard let self, self.phase == .playing else { return }
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
        guard self?.tailStart == nil, self?.presentationAssets == nil else { return }
        self?.update(mediaTime: time.seconds)
      }
    }
    Task {
      await Self.setAudioSession(active: true)
      guard phase == .playing else { return }
      player.play()
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
    record(difference: abs(note.time - currentTime))
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

    let difference = abs(endTime - currentTime)
    if difference <= 0.18 {
      record(difference: difference)
    } else {
      record(.miss, points: 0)
    }
  }

  func stop() {
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
    Task { await Self.setAudioSession(active: false) }
  }

  func playbackEnded(
    uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    guard phase == .playing, tailStart == nil else { return }
    let mediaTime = player?.currentTime().seconds ?? (currentTime - bgmOffset)
    tailStart = (
      mediaTime: max(
        mediaTime.isFinite ? mediaTime : 0, currentTime - bgmOffset
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
    currentTime = mediaTime + bgmOffset

    for lane in pressedLanes {
      hit(lane: lane, swingsOnly: true)
    }

    while nextMissIndex < chart.notes.count,
      chart.notes[nextMissIndex].time < currentTime - 0.18
    {
      let note = chart.notes[nextMissIndex]
      if !hitNoteIDs.contains(note.id) {
        hitNoteIDs.insert(note.id)
        record(.miss, points: 0)
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
      record(.miss, points: 0)
    }

    if nextMissIndex == chart.notes.count,
      currentTime > chart.duration + 1
    {
      stop()
      phase = .finished
      saveResult()
    }
  }

  func engineFrame(size: CGSize, touches: [EngineTouch]) {
    guard phase == .playing, size.width > 0, size.height > 0,
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
          engine: bundle.engine, level: bundle.level, options: assets.options,
          aspectRatio: aspect, skinSpriteIDs: Set(assets.skin.keys),
          effectClipIDs: engineAudio?.clipIDs ?? [],
          particleEffectIDs: Set(assets.particles.keys)
        )
      }
      guard let runtime = engineRuntime else { return }
      currentTime = playbackTime
      try runtime.update(at: currentTime, touches: touches)
      for judgment in runtime.judgments {
        switch judgment.grade {
        case 1: record(.perfect, points: 1_000)
        case 2: record(.great, points: 700)
        case 3: record(.good, points: 300)
        default: record(.miss, points: 0)
        }
      }
      try engineAudio?.update(runtime.host.takeAudioCommands(), at: currentTime,
        advancing: tailStart != nil || player?.timeControlStatus == .playing)
      if runtime.resolvedInputCount == runtime.inputCount,
        currentTime > chart.duration + 1 {
        stop()
        phase = .finished
        saveResult()
      }
    } catch {
      stop()
      phase = .failed(error.localizedDescription)
    }
  }

  private func record(_ judgement: NoteJudgement, points: Int) {
    judgements[judgement, default: 0] += 1
    score += points
    if judgement == .miss {
      combo = 0
    } else {
      combo += 1
      maxCombo = max(maxCombo, combo)
    }
  }

  private func record(difference: TimeInterval) {
    if difference <= 0.05 {
      record(.perfect, points: 1_000)
    } else if difference <= 0.10 {
      record(.great, points: 700)
    } else {
      record(.good, points: 300)
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
      score: score,
      maxCombo: maxCombo,
      perfect: judgements[.perfect, default: 0],
      great: judgements[.great, default: 0],
      good: judgements[.good, default: 0],
      miss: judgements[.miss, default: 0]
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
