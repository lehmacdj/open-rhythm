import Foundation

enum PlaybackTimingMetric: String, Codable, CaseIterable, Sendable {
  case runtime = "Engine update"
  case sprites = "Sprite generation"
  case encoding = "Metal encoding"
  case drawableWait = "Drawable wait"
  case gpu = "GPU execution"
  case presentation = "Chart sample to presentation"
  case deadline = "Presentation minus display target"
  case clockRead = "Clock sampling duration"
  case clockDifference = "Event clock minus player clock"
  case inputClockDifference = "Input clock minus player clock"
  case touchDelivery = "OS touch timestamp to delivery"

  var title: String {
    self == .clockDifference ? "Unclamped event clock minus player clock" : rawValue
  }
}

enum PlaybackTimingCounter: String, Sendable {
  case submitted = "Submitted Metal frames"
  case presented = "Presented frames"
  case unavailable = "Unavailable presentation timestamps"
  case queueFull = "GPU queue full"
  case noDrawable = "Unavailable drawable or command buffer"
  case software = "Software-rendered frames (presentation unmeasured)"
  case routeChanges = "Observed output port-type changes"
}

struct PlaybackTimingSummary: Codable, Equatable, Sendable {
  let count: Int
  let meanMS: Double
  let minimumMS: Double
  let maximumMS: Double
  let p95LowerMS: Double?
  let p95UpperMS: Double?

  var text: String {
    let p95: String
    if let low = p95LowerMS, let high = p95UpperMS {
      p95 = String(format: "[%.2f, %.2f) ms", low, high)
    } else if let low = p95LowerMS {
      p95 = String(format: "≥ %.2f ms", low)
    } else {
      p95 = String(format: "< %.2f ms", p95UpperMS ?? -1000)
    }
    return String(format: "mean %.2f ms · min %.2f · max %.2f", meanMS,
      minimumMS, maximumMS) + " · p95 \(p95) · n=\(count)"
  }
}

struct PlaybackTimingReport: Codable, Equatable, Sendable {
  let metrics: [String: PlaybackTimingSummary]
  let counters: [String: Int]
  let audioRoute: String?
  let outputLatencyMS: Double?
  let ioBufferDurationMS: Double?

  static let scope = "Recorded locally after intro preparation, including buffering and any post-audio tail. Presentation uses actual drawable timestamps, not callback arrival; unavailable in Simulator. Only callbacks received before the result snapshot are included. Audio latency is reported by iOS, not an acoustic measurement. No automatic calibration is applied."

  var text: String {
    var lines = ["OpenRhythm playback timing diagnostics", Self.scope]
    for metric in PlaybackTimingMetric.allCases {
      if let value = metrics[metric.rawValue] {
        lines.append("\(metric.title): \(value.text)")
      }
    }
    for key in counters.keys.sorted() {
      lines.append("\(key): \(counters[key]!)")
    }
    if let audioRoute { lines.append("Latest observed route: \(audioRoute)") }
    if let outputLatencyMS {
      lines.append("Latest reported output latency: \(outputLatencyMS) ms")
    }
    if let ioBufferDurationMS {
      lines.append("Latest reported I/O buffer: \(ioBufferDurationMS) ms")
    }
    return lines.joined(separator: "\n")
  }
}

/// Whole-play aggregates with fixed storage, including signed differences.
/// Quantiles are intervals, never presented as exact sample percentiles.
struct PlaybackTimingAccumulator {
  private var bins = [Int](repeating: 0, count: 8002)
  private var count = 0
  private var mean = 0.0
  private var minimum = Double.infinity
  private var maximum = -Double.infinity

  mutating func record(seconds: Double) {
    let ms = seconds * 1000
    guard ms.isFinite else { return }
    let index = ms < -1000 ? 0 : ms >= 1000 ? 8001
      : Int(floor((ms + 1000) * 4)) + 1
    bins[index] += 1
    count += 1
    // Convex combination avoids overflowing a subtraction of opposite extremes.
    mean = mean * (Double(count - 1) / Double(count)) + ms / Double(count)
    minimum = min(minimum, ms)
    maximum = max(maximum, ms)
  }

  var summary: PlaybackTimingSummary? {
    guard count > 0 else { return nil }
    let rank = Int(ceil(Double(count) * 0.95))
    var cumulative = 0
    let index = bins.firstIndex {
      cumulative += $0
      return cumulative >= rank
    }!
    return PlaybackTimingSummary(count: count, meanMS: mean,
      minimumMS: minimum, maximumMS: maximum,
      p95LowerMS: index == 0 ? nil : Double(index - 1) / 4 - 1000,
      p95UpperMS: index == 8001 ? nil : Double(index) / 4 - 1000)
  }
}

/// All mutable state is protected by lock; GPU callbacks retain only this
/// play's recorder, so late completion cannot contaminate a restarted play.
final class PlaybackTimingRecorder: @unchecked Sendable {
  private let lock = NSLock()
  // Allocate before playback rather than injecting first-use allocation into
  // the frame whose age we are trying to measure.
  private var metrics = Dictionary(uniqueKeysWithValues:
    PlaybackTimingMetric.allCases.map { ($0, PlaybackTimingAccumulator()) })
  private var counters = [String: Int]()
  private var audioRoute: String?
  private var outputLatencyMS: Double?
  private var ioBufferDurationMS: Double?

  func record(_ metric: PlaybackTimingMetric, seconds: Double) {
    lock.lock()
    defer { lock.unlock() }
    metrics[metric, default: PlaybackTimingAccumulator()].record(seconds: seconds)
  }

  func increment(_ counter: PlaybackTimingCounter) {
    lock.lock()
    defer { lock.unlock() }
    counters[counter.rawValue, default: 0] += 1
  }

  func audio(route: String, outputLatency: Double, bufferDuration: Double) {
    lock.lock()
    defer { lock.unlock() }
    if let audioRoute, audioRoute != route {
      counters[PlaybackTimingCounter.routeChanges.rawValue, default: 0] += 1
    }
    audioRoute = route
    outputLatencyMS = Self.milliseconds(outputLatency)
    ioBufferDurationMS = Self.milliseconds(bufferDuration)
  }

  private static func milliseconds(_ value: Double) -> Double? {
    let ms = value * 1000
    return ms.isFinite && ms >= 0 ? ms : nil
  }

  func snapshot() -> PlaybackTimingReport {
    lock.lock()
    defer { lock.unlock() }
    return PlaybackTimingReport(metrics: Dictionary(uniqueKeysWithValues:
      metrics.compactMap { key, value in
        value.summary.map { (key.rawValue, $0) }
      }), counters: counters, audioRoute: audioRoute,
      outputLatencyMS: outputLatencyMS, ioBufferDurationMS: ioBufferDurationMS)
  }
}

struct PlaybackFrameTiming: Sendable {
  let recorder: PlaybackTimingRecorder
  let sampleHostTime: Double
  var targetHostTime: Double? = nil

  func presented(at timestamp: Double) {
    guard timestamp.isFinite, timestamp > 0 else {
      recorder.increment(.unavailable)
      return
    }
    recorder.record(.presentation, seconds: timestamp - sampleHostTime)
    if let targetHostTime, targetHostTime.isFinite, targetHostTime > 0 {
      recorder.record(.deadline, seconds: timestamp - targetHostTime)
    }
    recorder.increment(.presented)
  }
}
