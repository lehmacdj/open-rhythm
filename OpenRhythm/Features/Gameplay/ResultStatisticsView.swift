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
