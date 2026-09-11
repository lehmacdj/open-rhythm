import SwiftUI
import Charts

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
        Text("\(stats.binWidthMS.formatted()) ms bins. Misses have no timing error and are excluded.")
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

private let judgementLabels = ["PERFECT", "GREAT", "GOOD", "MISS"]
private let judgementColors: [Color] = [.cyan, .green, .orange, .red]

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
    .chartForegroundStyleScale(domain: judgementLabels, range: judgementColors)
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

  private var errorRange: ClosedRange<Double> {
    let upper = max(stats.timingLimitMS, stats.bins.map(\.upperMS).max() ?? 0)
    return (-stats.timingLimitMS)...upper
  }

  var body: some View {
    Chart {
      ForEach(stats.bins) { bin in
        RectangleMark(xStart: .value("From", bin.lowerMS),
          xEnd: .value("To", bin.upperMS),
          yStart: .value("Notes", bin.base),
          yEnd: .value("Notes", bin.base + bin.count))
          .foregroundStyle(by: .value("Judgement",
            bin.judgement.rawValue.uppercased()))
      }
      RuleMark(x: .value("Perfect timing", 0))
        .foregroundStyle(.secondary.opacity(0.5))
        .lineStyle(StrokeStyle(lineWidth: 0.5))
    }
    .chartForegroundStyleScale(domain: Array(judgementLabels.prefix(3)),
      range: Array(judgementColors.prefix(3)))
    .chartXScale(domain: errorRange)
    .chartXAxisLabel("Early ← Timing error (ms) → Late")
    .chartYAxisLabel("Notes")
    .frame(height: 200)
    .accessibilityLabel("Timing error distribution, colored by judgement")
    .overlay {
      if stats.timingsMS.isEmpty {
        Text("No timed hits").foregroundStyle(.secondary)
      }
    }
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

#Preview("Histogram") {
  let samples = (0..<120).map { index in
    NoteTiming(id: index, songTime: Double(index), noteType: "Tap",
      judgement: index.isMultiple(of: 4) ? .great : .perfect,
      accuracy: Double(index % 11 - 5) * 0.006)
  }
  Form { TimingHistogram(stats: PlayStatistics(samples: samples)) }
}
