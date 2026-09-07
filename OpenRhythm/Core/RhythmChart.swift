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
          bpm > 0
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
    segments = result
  }

  func time(at beat: Double) -> TimeInterval {
    guard let segment = segments.last(where: { $0.beat <= beat })
      ?? segments.first
    else { return beat }
    return segment.time + (beat - segment.beat) * 60 / segment.bpm
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
    let namedEntities = Dictionary(
      uniqueKeysWithValues: level.entities.compactMap { entity in
        entity.name.map { ($0, entity) }
      }
    )
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
    let holdTails = Dictionary(uniqueKeysWithValues: holdPairs)

    notes = level.entities.enumerated().compactMap {
      (index, entity) -> RhythmNote? in
      guard
        entity.archetype == "TapNote" || entity.archetype == "SwingNote",
        let beat = entity.value(named: "#BEAT"),
        let laneValue = entity.value(named: "lane")
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
        lane: Int(laneValue),
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
