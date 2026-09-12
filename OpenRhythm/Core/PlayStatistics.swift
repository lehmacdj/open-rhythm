import Foundation

struct NoteTiming: Codable, Identifiable, Equatable, Sendable {
  let id: Int
  let songTime: Double
  let noteType: String
  let judgement: NoteJudgement
  // Signed seconds: negative is early. Misses have no timing error.
  let accuracy: Double?

  // Engine archetype names retained in old results let us identify the known
  // automatically timed intermediate hold checkpoints without discarding
  // real zero-error taps, hold heads, releases, or flicks.
  var isIntermediateHold: Bool {
    ["NormalTickNote", "CriticalTickNote", "HiddenTickNote",
     "TransientHiddenTickNote", "TransientNormalTickNote",
     "TransientCriticalTickNote", "SlideTickNote"].contains(noteType)
  }
}

struct PlayStatistics {
  struct DensityPoint: Identifiable {
    let index: Int
    let judgement: NoteJudgement
    let timingMS: Double
    let density: Double
    var id: String { "\(index)-\(judgement.rawValue)" }
  }
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
  let density: [DensityPoint]
  let distributionCount: Int
  let excludedHoldTicks: Int
  let bandwidthMS: Double
  let distributionLimitMS: Double

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

    let distribution = timed.filter { !$0.isIntermediateHold }
    excludedHoldTicks = timed.count - distribution.count
    distributionCount = distribution.count
    let values = distribution.map { $0.accuracy! * 1000 }.sorted()
    let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    let sigma = values.isEmpty ? 0 : sqrt(values.reduce(0) {
      $0 + pow($1 - mean, 2)
    } / Double(values.count))
    let iqr = values.isEmpty ? 0 : values[(values.count - 1) * 3 / 4]
      - values[(values.count - 1) / 4]
    let scale = iqr > 0 ? min(sigma, iqr / 1.349) : sigma
    // Limit the resolution for pathological, hours-wide stored errors too.
    // This is smoothing, not data binning: every input still contributes.
    bandwidthMS = max(1, (values.map(abs).max() ?? 0) / 1024,
      2.34 * scale * pow(Double(max(1, values.count)), -0.2))
    distributionLimitMS = max(25, (values.map(abs).max() ?? 0) + bandwidthMS)
    let bandwidthMS = bandwidthMS
    let distributionLimitMS = distributionLimitMS
    var curve = [DensityPoint]()
    if !values.isEmpty {
      // A broad grid can miss narrow, isolated modes. Sample each occupied
      // kernel neighborhood, coalescing overlapping neighborhoods at h/8.
      // Rendering work stays bounded even with thousands of distinct hits.
      var positions = Set((0...128).map {
        Double($0 - 64) / 64 * distributionLimitMS
      })
      for offset in -4...4 {
        var previous = -Double.infinity
        for value in values {
          let x = value + Double(offset) * bandwidthMS / 4
          if x - previous >= bandwidthMS / 8 {
            positions.insert(x)
            previous = x
          }
        }
      }
      var positivePositions = [0.0]
      for x in Set(positions.map(abs)).sorted() {
        if x - positivePositions.last! >= bandwidthMS / 8 {
          positivePositions.append(x)
        }
      }
      var finalPositions = Set(positivePositions.dropFirst().map { -$0 }
        + positivePositions)
      // Never coalesce away a support boundary. Otherwise a small positive
      // edge can interpolate across a wide empty gap into a spurious tail.
      for judgement in [NoteJudgement.perfect, .great, .good] {
        let group = distribution.filter { $0.judgement == judgement }
          .map { $0.accuracy! * 1000 }.sorted()
        if let first = group.first, let last = group.last {
          finalPositions.insert(first - bandwidthMS)
          finalPositions.insert(last + bandwidthMS)
        }
        for (left, right) in zip(group, group.dropFirst())
          where right - left > 2 * bandwidthMS {
          finalPositions.insert(left + bandwidthMS)
          finalPositions.insert(right - bandwidthMS)
        }
      }
      let positionsInOrder = finalPositions.sorted()
      for judgement in [NoteJudgement.perfect, .great, .good] {
        let group = distribution.filter { $0.judgement == judgement }
          .map { $0.accuracy! * 1000 }.sorted()
        guard !group.isEmpty else { continue }
        let kernel = TimingDensity(values: group, bandwidth: bandwidthMS)
        for (index, x) in positionsInOrder.enumerated() {
          curve.append(DensityPoint(index: index, judgement: judgement,
            timingMS: x, density: kernel.value(at: x)))
        }
      }
    }
    density = curve
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

/// Exact, unbinned Epanechnikov KDE. Prefix moments make each evaluation
/// O(log n), avoiding an expensive kernel loop over every hit on every frame.
private struct TimingDensity {
  let values: [Double]
  let sums: [Double]
  let squares: [Double]
  let origin: Double
  let bandwidth: Double

  init(values: [Double], bandwidth: Double) {
    let origin = values[values.count / 2]
    self.origin = origin
    self.values = values.map { $0 - origin }
    self.bandwidth = bandwidth
    var sums = [0.0]
    var squares = [0.0]
    for value in self.values {
      sums.append(sums.last! + value)
      squares.append(squares.last! + value * value)
    }
    self.sums = sums
    self.squares = squares
  }

  func value(at timing: Double) -> Double {
    let x = timing - origin
    func lowerBound(_ value: Double) -> Int {
      var lower = 0
      var upper = values.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if values[middle] < value { lower = middle + 1 }
        else { upper = middle }
      }
      return lower
    }
    let lower = lowerBound(x - bandwidth)
    let upper = lowerBound(x + bandwidth)
    let count = Double(upper - lower)
    let sum = sums[upper] - sums[lower]
    let square = squares[upper] - squares[lower]
    let distance = max(0, square - 2 * x * sum + count * x * x)
    return max(0, 0.75 / bandwidth * (count - distance / (bandwidth * bandwidth)))
  }
}
