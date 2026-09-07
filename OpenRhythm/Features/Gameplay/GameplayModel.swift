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

  var activeHoldIDs: Set<String> {
    Set(activeHolds.values.map(\.id))
  }

  private let loader: RuntimeBundleLoader
  private let resultStore: ResultStore
  private var bgmOffset = 0.0
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var nextMissIndex = 0
  private var resultLevel: SonolusLevelItem?
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
      chart = RhythmChart(level: bundle.level)
      bgmOffset = bundle.level.bgmOffset
      resultLevel = level
      resultTitle = title
      player = AVPlayer(url: bundle.bgmURL)
      phase = .ready
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func start() {
    guard phase == .ready, let player else { return }
    score = 0
    combo = 0
    maxCombo = 0
    currentTime = 0
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
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 60),
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
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
    let window = 0.18
    guard let note = chart.notes
      .filter({
        $0.lane == lane
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
    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    Task { await Self.setAudioSession(active: false) }
  }

  private func update(mediaTime: TimeInterval) {
    guard phase == .playing, mediaTime.isFinite else { return }
    currentTime = mediaTime + bgmOffset

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
      levelID: level.id,
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
    Task { try? await resultStore.record(result) }
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
