import Foundation

struct BPMTimeline: Sendable {
  struct Segment: Sendable {
    let beat: Double
    let time: TimeInterval
    let bpm: Double
  }

  let segments: [Segment]

  init(level: LevelData, speed: Double = 1) {
    var changes = level.entities
      .filter { $0.archetype == "#BPM_CHANGE" }
      .compactMap { entity -> (beat: Double, bpm: Double)? in
        guard
          let beat = entity.value(named: "#BEAT"),
          let bpm = entity.value(named: "#BPM"),
          beat.isFinite, bpm.isFinite, bpm > 0
        else { return nil }
        return (beat, bpm * speed)
      }
      .sorted { $0.beat < $1.beat }

    if changes.isEmpty || changes[0].beat > 0 {
      changes.insert((beat: 0, bpm: 60 * speed), at: 0)
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

private extension LevelEntity {
  func value(named name: String) -> Double? {
    data.first { $0.name == name }?.value
  }
}
