import SwiftUI
import Charts

struct PlaybackTimingSection: View {
  let report: PlaybackTimingReport?

  var body: some View {
    if let report {
      Section("Playback Diagnostics") {
        ForEach(PlaybackTimingMetric.allCases, id: \.self) { metric in
          if let value = report.metrics[metric.rawValue] {
            VStack(alignment: .leading) {
              Text(metric.title)
              Text(value.text).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        ForEach(report.counters.keys.sorted(), id: \.self) { key in
          LabeledContent(key, value: report.counters[key, default: 0].formatted())
        }
        if let route = report.audioRoute {
          LabeledContent("Latest Output Type", value: route)
        }
        if let latency = report.outputLatencyMS {
          LabeledContent("Reported Output Latency",
            value: String(format: "%.2f ms", latency))
        }
        if let duration = report.ioBufferDurationMS {
          LabeledContent("Reported I/O Buffer",
            value: String(format: "%.2f ms", duration))
        }
        Text(PlaybackTimingReport.scope)
          .font(.caption).foregroundStyle(.secondary)
        ShareLink("Share Timing Diagnostics", item: report.text)
      }
    }
  }
}

/// Shared by the just-completed play and saved result details.
struct ResultStatisticsSections: View {
  let samples: [NoteTiming]?
  let duration: Double?
  var engineBuckets: [EngineResultBucket]? = nil
  @State private var noteType: String?

  var body: some View {
    if let samples {
      let stats = PlayStatistics(samples: samples, noteType: noteType)
      Section("Timing Analysis") {
        Picker("Note Type", selection: $noteType) {
          Text("All Notes").tag(String?.none)
          ForEach(Set(samples.map(\.noteType)).sorted(), id: \.self) { type in
            Text(type.replacingOccurrences(of: "([a-z0-9])([A-Z])",
              with: "$1 $2", options: .regularExpression))
              .tag(Optional(type))
          }
        }
        Text("Filters both charts and the timing statistics below.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Timing Through the Song") {
        TimingScatterplot(stats: stats, duration: duration)
        Text("Below zero is early; above zero is late. Red lines mark misses.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Early / Late Distribution") {
        TimingHistogram(stats: stats)
        Text("Continuous timing density; no bins. Misses and \(stats.excludedHoldTicks) intermediate hold ticks are excluded. Smoothing width: \(stats.bandwidthMS.formatted(.number.precision(.fractionLength(1)))) ms.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Timing Statistics") {
        LabeledContent("Notes", value: stats.samples.count.formatted())
        LabeledContent("Hit Rate", value: stats.hitRate.map {
          $0.formatted(.percent.precision(.fractionLength(1)))
        } ?? "—")
        LabeledContent("Early / Exact / Late",
          value: "\(stats.early) / \(stats.exact) / \(stats.late)")
        LabeledContent("Misses", value: stats.misses.formatted())
        LabeledContent("Mean Timing", value: milliseconds(stats.meanMS))
        LabeledContent("Median Timing", value: milliseconds(stats.medianMS))
        LabeledContent("Mean Absolute Error",
          value: milliseconds(stats.meanAbsoluteMS))
        LabeledContent("Timing Spread (σ)",
          value: milliseconds(stats.standardDeviationMS))
        Text("Signed timings are negative for early hits. Lower absolute error and spread indicate more accurate, consistent timing.")
          .font(.caption).foregroundStyle(.secondary)
        let missing = stats.samples.count - stats.misses - stats.timingsMS.count
        if missing > 0 {
          Text("Timing was unavailable for \(missing) hits.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let engineBuckets, !engineBuckets.isEmpty {
        EngineBucketSection(samples: stats.samples, buckets: engineBuckets)
      }
    } else {
      Section("Timing Analysis") {
        Text("Per-note timing was not recorded for this older result.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func milliseconds(_ value: Double?) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(1))) + " ms" }
      ?? "—"
  }
}

struct EngineBucketSection: View {
  let samples: [NoteTiming]
  let buckets: [EngineResultBucket]
  @State private var selected = 0

  var body: some View {
    if !buckets.isEmpty {
      let index = buckets.indices.contains(selected) ? selected : 0
      let bucket = buckets[index]
      let stats = EngineBucketStatistics(samples: samples, index: index, bucket: bucket)
      Section("Engine Buckets") {
        Picker("Bucket", selection: $selected) {
          ForEach(buckets.indices, id: \.self) { index in
            Text("Bucket \(index + 1)").tag(index)
          }
        }
        if let data = bucket.imagePNG, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity).frame(height: 64)
            .accessibilityLabel("Engine graphic for bucket \(index + 1)")
        } else if !bucket.definition.sprites.isEmpty {
          Text(bucket.imageError ?? "The bucket graphic was not recorded or is unavailable.")
            .font(.caption).foregroundStyle(.secondary)
        }
        LabeledContent("Inputs / Misses",
          value: "\(stats.samples.count) / \(stats.misses)")
        LabeledContent("Unit", value: stats.unit ?? "Not specified by engine")
        EngineBucketPlot(stats: stats)
        ForEach(0..<3, id: \.self) { grade in
          LabeledContent("\(judgementLabels[grade]) Window", value:
            stats.windows[grade].map {
              "\(EngineBucketStatistics.formatValue($0.lowerBound)) … \(EngineBucketStatistics.formatValue($0.upperBound))"
            } ?? "Unavailable")
        }
        Text("Engine-assigned values, in the unit shown above. Misses and inputs without a finite bucket value are not plotted. The note-type filter also applies here.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct EngineBucketPlot: View {
  let stats: EngineBucketStatistics
  @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 220

  var body: some View {
    // Normalize only drawing coordinates so even very large custom units do
    // not overflow Charts' domain arithmetic. Axis labels retain engine units.
    let values = stats.points.compactMap(\.bucketValue)
      + stats.windows.compactMap { $0 }.flatMap { [$0.lowerBound, $0.upperBound] }
    let scale = values.map(abs).max().flatMap { $0 > 0 ? $0 : nil } ?? 1
    Chart {
      ForEach(stats.points) { sample in
        PointMark(x: .value("Song time", sample.songTime),
          y: .value("Engine value", sample.bucketValue! / scale))
          .symbolSize(18)
          .foregroundStyle(by: .value("Judgement", sample.judgement.rawValue.uppercased()))
      }
      ForEach(0..<3, id: \.self) { grade in
        if let window = stats.windows[grade] {
          RuleMark(y: .value("Minimum window", window.lowerBound / scale))
            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            .foregroundStyle(.secondary)
          RuleMark(y: .value("Maximum window", window.upperBound / scale))
            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            .foregroundStyle(.secondary)
        }
      }
    }
    .chartForegroundStyleScale(domain: judgementLabels)
    .chartYScale(domain: -1.0...1.0)
    .chartYAxis {
      AxisMarks(values: [-1.0, -0.5, 0, 0.5, 1.0]) { value in
        AxisGridLine()
        AxisValueLabel {
          if let value = value.as(Double.self) {
            Text(EngineBucketStatistics.formatValue(value * scale))
          }
        }
      }
    }
    .chartXAxisLabel("Song time (s)")
    .chartYAxisLabel(stats.unit ?? "Engine value")
    .frame(height: chartHeight)
    .accessibilityLabel("Engine bucket values across the song")
    .overlay {
      if stats.points.isEmpty { Text("No recorded values").foregroundStyle(.secondary) }
    }
  }
}

private let judgementLabels = ["PERFECT", "GREAT", "GOOD"]

struct TimingScatterplot: View {
  let stats: PlayStatistics
  let duration: Double?

  private var timeRange: ClosedRange<Double> {
    let last = stats.samples.map(\.songTime).max() ?? 0
    let validDuration = duration.flatMap {
      $0.isFinite && $0 <= 86_400 ? $0 : nil
    } ?? 0
    let first = min(0, stats.samples.map(\.songTime).min() ?? 0)
    return first...max(1, last, validDuration)
  }

  var body: some View {
    Chart {
      RuleMark(y: .value("Perfect timing", 0))
        .foregroundStyle(.secondary.opacity(0.5))
        .lineStyle(StrokeStyle(lineWidth: 0.5))
      ForEach(stats.samples) { sample in
        if sample.judgement == .miss {
          RuleMark(x: .value("Song time", sample.songTime))
            .foregroundStyle(.red.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 0.5))
            .accessibilityLabel("Miss at \(sample.songTime.formatted()) seconds")
        } else if let error = sample.accuracy,
          error.isFinite, abs(error) <= 3_600 {
          PointMark(x: .value("Song time", sample.songTime),
            y: .value("Timing error", error * 1000))
            .symbolSize(16)
            .foregroundStyle(by: .value("Judgement",
              sample.judgement.rawValue.uppercased()))
        }
      }
    }
    .chartForegroundStyleScale(domain: judgementLabels)
    .chartXScale(domain: timeRange)
    .chartYScale(domain: -stats.timingLimitMS...stats.timingLimitMS)
    .chartXAxisLabel("Song time (s)")
    .chartYAxisLabel("Timing error (ms)")
    .frame(height: 220)
    .accessibilityLabel("Note timing across the song")
  }
}

struct TimingHistogram: View {
  let stats: PlayStatistics
  @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 200

  private var errorRange: ClosedRange<Double> {
    (-stats.distributionLimitMS)...stats.distributionLimitMS
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text("EARLY")
        Spacer()
        Text("LATE")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      Chart {
        ForEach(stats.density) { point in
          AreaMark(x: .value("Timing error", point.timingMS),
            y: .value("Density", point.density), stacking: .standard)
            .foregroundStyle(by: .value("Judgement",
              point.judgement.rawValue.uppercased()))
            .interpolationMethod(.linear)
        }
        RuleMark(x: .value("Perfect timing", 0))
          .foregroundStyle(.primary.opacity(0.65))
          .lineStyle(StrokeStyle(lineWidth: 0.75))
      }
      .chartForegroundStyleScale(domain: judgementLabels)
      .chartXScale(domain: errorRange)
      .chartYScale(domain: .automatic(includesZero: true))
      .chartXAxis {
        AxisMarks(preset: .aligned, values: stats.distributionTicksMS) { value in
          AxisTick().foregroundStyle(.secondary)
          AxisValueLabel(centered: false,
            anchor: .top, horizontalSpacing: 0) {
            if let timing = value.as(Double.self) {
              Text(timing.formatted(.number.notation(.compactName)
                .precision(.fractionLength(0...1))))
            }
          }
            .foregroundStyle(.secondary)
        }
      }
      .chartYAxis(.hidden)
      .chartXAxisLabel("Timing error (ms)")
      .chartLegend(position: .bottom, spacing: 8)
      .foregroundStyle(.secondary)
      .frame(height: chartHeight)
      .accessibilityLabel("Timing error distribution, colored by judgement")
      .accessibilityValue("\(stats.distributionCount) timed hits. Vertical height is density in notes per millisecond.")
      .overlay {
        if stats.distributionCount == 0 {
          Text("No timed hits").foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 10))
  }

}

#Preview("Engine Bucket Results") {
  let samples: [NoteTiming] = (0..<30).map { index in
    let grade: NoteJudgement = index.isMultiple(of: 7) ? .great : .perfect
    let error = Double(index % 7 - 3) / 1000
    let value = Double(index % 11 - 5)
    return NoteTiming(id: index, songTime: Double(index) * 4,
      noteType: "CustomInput", judgement: grade, accuracy: error,
      bucketIndex: 0, bucketValue: value)
  }
  let bucket = EngineResultBucket(definition: EngineBucket(sprites: [],
    unit: "degrees"), windows: [-3, 3, -6, 6, -10, 10],
    imagePNG: UIImage(systemName: "music.note")?.pngData())
  NavigationStack {
    Form { EngineBucketSection(samples: samples, buckets: [bucket]) }
      .navigationTitle("Result")
  }
}

#Preview("Timing Charts") {
  let samples = (0..<100).map { index in
    NoteTiming(id: index, songTime: Double(index),
      noteType: index.isMultiple(of: 3) ? "Flick" : "Tap",
      judgement: index.isMultiple(of: 19) ? .miss
        : index.isMultiple(of: 7) ? .good
        : index.isMultiple(of: 5) ? .great : .perfect,
      accuracy: index.isMultiple(of: 19) ? nil
        : sin(Double(index)) * (index.isMultiple(of: 7) ? 0.12 : 0.035))
  }
  NavigationStack {
    Form { ResultStatisticsSections(samples: samples, duration: 110) }
      .navigationTitle("Timing Analysis")
  }
}

#Preview("Playback Diagnostics") {
  let recorder = PlaybackTimingRecorder()
  let _ = recorder.record(.presentation, seconds: 0.022)
  let _ = recorder.record(.deadline, seconds: 0.006)
  let _ = recorder.audio(route: "Speaker", outputLatency: 0.01,
    bufferDuration: 0.005)
  let _ = recorder.increment(.submitted)
  let _ = recorder.increment(.presented)
  NavigationStack {
    Form { PlaybackTimingSection(report: recorder.snapshot()) }
      .navigationTitle("Result")
  }
}

#Preview("Histogram") {
  let samples = (0..<120).map { index in
    NoteTiming(id: index, songTime: Double(index), noteType: "Tap",
      judgement: index.isMultiple(of: 4) ? .great : .perfect,
      accuracy: Double(index % 11 - 5) * 0.006)
  }
  Form { TimingHistogram(stats: PlayStatistics(samples: samples)) }
}

#Preview("Distribution States", traits: .fixedLayout(width: 420, height: 1180)) {
  let dense = (0..<500).map { index in
    let x = Double(index)
    let error = (sin(x * 1.37) + sin(x * 2.17) + sin(x * 0.79)) * 0.028 - 0.008
    return NoteTiming(id: index, songTime: x, noteType: "Tap",
      judgement: abs(error) < 0.025 ? .perfect : abs(error) < 0.055 ? .great : .good,
      accuracy: error)
  }
  VStack(spacing: 8) {
    TimingHistogram(stats: PlayStatistics(samples: dense))
    TimingHistogram(stats: PlayStatistics(samples: [
      NoteTiming(id: 0, songTime: 0, noteType: "Tap",
        judgement: .perfect, accuracy: 0)]))
    TimingHistogram(stats: PlayStatistics(samples: []))
    TimingHistogram(stats: PlayStatistics(samples: [
      NoteTiming(id: 0, songTime: 0, noteType: "Tap",
        judgement: .perfect, accuracy: 0),
      NoteTiming(id: 1, songTime: 1, noteType: "Tap",
        judgement: .good, accuracy: 1)]))
  }
  .padding()
  .background(Color(.systemGroupedBackground))
}
