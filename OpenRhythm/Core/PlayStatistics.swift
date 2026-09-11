import Foundation

struct NoteTiming: Codable, Identifiable, Equatable, Sendable {
  let id: Int
  let songTime: Double
  let noteType: String
  let judgement: NoteJudgement
  // Signed seconds: negative is early. Misses have no timing error.
  let accuracy: Double?
}

struct PlayStatistics {
  struct Bin: Identifiable {
    let index: Int
    let judgement: NoteJudgement
    let count: Int
    let base: Int
    let lowerMS: Double
    let upperMS: Double
    var id: String { "\(index)-\(judgement.rawValue)" }
  }

  let samples: [NoteTiming]
  let timingsMS: [Double]
  let bins: [Bin]
  let binWidthMS: Double
  let timingLimitMS: Double

  init(samples: [NoteTiming], noteType: String? = nil) {
    self.samples = samples.filter {
      (noteType == nil || $0.noteType == noteType)
        && $0.songTime.isFinite && abs($0.songTime) <= 86_400
    }
    let timed = self.samples.filter {
      $0.judgement != .miss && $0.accuracy.map {
        $0.isFinite && abs($0) <= 3_600
      } == true
    }
    timingsMS = timed.map { $0.accuracy! * 1000 }.sorted()
    let maximum = timingsMS.map(abs).max() ?? 0
    binWidthMS = max(5, ceil(maximum / 100) * 5)
    timingLimitMS = max(25, ceil(maximum / binWidthMS) * binWidthMS)
    var counts = [Int: [NoteJudgement: Int]]()
    for sample in timed {
      let index = Int(floor(sample.accuracy! * 1000 / binWidthMS))
      counts[index, default: [:]][sample.judgement, default: 0] += 1
    }
    var bins = [Bin]()
    for index in counts.keys.sorted() {
      var base = 0
      for judgement in NoteJudgement.allCases {
        guard let count = counts[index]?[judgement] else { continue }
        bins.append(Bin(index: index, judgement: judgement, count: count, base: base,
          lowerMS: Double(index) * binWidthMS,
          upperMS: Double(index + 1) * binWidthMS))
        base += count
      }
    }
    self.bins = bins
  }

  var misses: Int { samples.filter { $0.judgement == .miss }.count }
  var early: Int { timingsMS.filter { $0 < 0 }.count }
  var late: Int { timingsMS.filter { $0 > 0 }.count }
  var exact: Int { timingsMS.filter { $0 == 0 }.count }
  var hitRate: Double? {
    samples.isEmpty ? nil : Double(samples.count - misses) / Double(samples.count)
  }
  var meanMS: Double? {
    timingsMS.isEmpty ? nil : timingsMS.reduce(0, +) / Double(timingsMS.count)
  }
  var meanAbsoluteMS: Double? {
    timingsMS.isEmpty ? nil : timingsMS.reduce(0) { $0 + abs($1) }
      / Double(timingsMS.count)
  }
  var medianMS: Double? {
    guard !timingsMS.isEmpty else { return nil }
    let middle = timingsMS.count / 2
    return timingsMS.count.isMultiple(of: 2)
      ? (timingsMS[middle - 1] + timingsMS[middle]) / 2 : timingsMS[middle]
  }
  var standardDeviationMS: Double? {
    guard let meanMS else { return nil }
    return sqrt(timingsMS.reduce(0) { $0 + pow($1 - meanMS, 2) }
      / Double(timingsMS.count))
  }
}
