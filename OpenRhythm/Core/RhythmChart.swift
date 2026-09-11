import Foundation

enum RhythmNoteKind: Sendable {
  case tap
  case swing
  case hold
}

struct RhythmNote: Identifiable, Sendable {
  let id: String
  let beat: Double
  let time: TimeInterval
  let lane: Int
  let kind: RhythmNoteKind
  let endTime: TimeInterval?
}

struct BPMTimeline: Sendable {
  struct Segment: Sendable {
    let beat: Double
    let time: TimeInterval
    let bpm: Double
  }

  let segments: [Segment]

  init(level: LevelData) {
    var changes = level.entities
      .filter { $0.archetype == "#BPM_CHANGE" }
      .compactMap { entity -> (beat: Double, bpm: Double)? in
        guard
          let beat = entity.value(named: "#BEAT"),
          let bpm = entity.value(named: "#BPM"),
          beat.isFinite, bpm.isFinite, bpm > 0
        else { return nil }
        return (beat, bpm)
      }
      .sorted { $0.beat < $1.beat }

    if changes.isEmpty || changes[0].beat > 0 {
      changes.insert((beat: 0, bpm: 60), at: 0)
    }

    var result = [Segment]()
    var time = 0.0
    for (index, change) in changes.enumerated() {
      if index > 0 {
        let previous = changes[index - 1]
        time += (change.beat - previous.beat) * 60 / previous.bpm
      }
      result.append(
        Segment(beat: change.beat, time: time, bpm: change.bpm)
      )
    }
    // Beat zero is time zero even when the chart defines tempo beforehand.
    let origin = result.last { $0.beat <= 0 } ?? result[0]
    let zeroTime = origin.time - origin.beat * 60 / origin.bpm
    segments = result.map {
      Segment(beat: $0.beat, time: $0.time - zeroTime, bpm: $0.bpm)
    }
  }

  func time(at beat: Double) -> TimeInterval {
    let segment = segment(at: beat)
    return segment.time + (beat - segment.beat) * 60 / segment.bpm
  }

  func bpm(at beat: Double) -> Double {
    segment(at: beat).bpm
  }

  func segment(at beat: Double) -> Segment {
    var lower = 0
    var upper = segments.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if segments[middle].beat <= beat { lower = middle + 1 }
      else { upper = middle }
    }
    return segments[max(0, lower - 1)]
  }
}

/// Integral of the level's built-in time-scale changes. This affects engine
/// animation time, never the BGM clock or audio playback speed.
struct TimeScaleTimeline {
  struct Segment {
    let time: Double
    let scaledTime: Double
    let scale: Double
  }
  let segments: [Segment]

  init(level: LevelData, bpm: BPMTimeline) {
    var changes = level.entities.compactMap { entity -> (Double, Double)? in
      guard entity.archetype == "#TIMESCALE_CHANGE",
        let beat = entity.value(named: "#BEAT"), beat.isFinite,
        let scale = entity.value(named: "#TIMESCALE"), scale.isFinite else { return nil }
      return (bpm.time(at: beat), scale)
    }.sorted { $0.0 < $1.0 }
    if changes.isEmpty || changes[0].0 > 0 { changes.insert((0, 1), at: 0) }
    var result = [Segment]()
    var scaled = 0.0
    for (time, scale) in changes {
      if let last = result.last { scaled += (time - last.time) * last.scale }
      result.append(Segment(time: time, scaledTime: scaled, scale: scale))
    }
    let origin = result.last { $0.time <= 0 } ?? result[0]
    let zero = origin.scaledTime - origin.time * origin.scale
    segments = result.map {
      Segment(time: $0.time, scaledTime: $0.scaledTime - zero, scale: $0.scale)
    }
  }

  func segment(at time: Double) -> Segment {
    var lower = 0
    var upper = segments.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if segments[middle].time <= time { lower = middle + 1 }
      else { upper = middle }
    }
    return segments[max(0, lower - 1)]
  }

  func scaledTime(at time: Double) -> Double {
    let segment = segment(at: time)
    return segment.scaledTime + (time - segment.time) * segment.scale
  }
}

struct RhythmChart: Sendable {
  let notes: [RhythmNote]
  let duration: TimeInterval

  var judgementCount: Int {
    notes.count + notes.filter { $0.endTime != nil }.count
  }

  init(level: LevelData) {
    let timeline = BPMTimeline(level: level)
    let namedEntities = level.entities.reduce(into: [String: LevelEntity]()) {
      if let name = $1.name { $0[name] = $1 }
    }
    let holdPairs: [(String, LevelEntity)] = level.entities.compactMap {
      entity in
        guard
          entity.archetype == "HoldConnector",
          let head = entity.reference(named: "head"),
          let tail = entity.reference(named: "tail"),
          let tailEntity = namedEntities[tail]
        else { return nil }
        return (head, tailEntity)
      }
    let holdTails = Dictionary(holdPairs, uniquingKeysWith: { _, last in last })

    notes = level.entities.enumerated().compactMap {
      (index, entity) -> RhythmNote? in
      guard
        entity.archetype == "TapNote" || entity.archetype == "SwingNote",
        let beat = entity.value(named: "#BEAT"),
        let laneValue = entity.value(named: "lane"),
        let lane = Int(exactly: laneValue), (-4...4).contains(lane)
      else { return nil }

      let endBeat = entity.name
        .flatMap { holdTails[$0] }
        .flatMap { $0.value(named: "#BEAT") }
      let kind: RhythmNoteKind = if endBeat != nil {
        .hold
      } else if entity.archetype == "SwingNote" {
        .swing
      } else {
        .tap
      }
      return RhythmNote(
        id: entity.name ?? "entity-\(index)",
        beat: beat,
        time: timeline.time(at: beat),
        lane: lane,
        kind: kind,
        endTime: endBeat.map(timeline.time)
      )
    }
    .sorted { $0.time < $1.time }

    duration = notes.map { $0.endTime ?? $0.time }.max() ?? 0
  }
}

private extension LevelEntity {
  func value(named name: String) -> Double? {
    data.first { $0.name == name }?.value
  }

  func reference(named name: String) -> String? {
    data.first { $0.name == name }?.ref
  }
}
