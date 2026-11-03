import AVFoundation
import Metal
import QuartzCore
import SwiftUI
import UIKit

/// Visual Timing and Input Timing controls, saved for the current kind of
/// audio output and shared by every engine.
struct TimingSettingsSections: View {
  @Binding var timing: TimingCalibration
  let route: AudioRouteKind

  var body: some View {
    Section {
      NavigationLink("Calibrate…") {
        TimingCalibrationView(timing: $timing, route: route)
      }
    } header: {
      Text("Timing for \(route.title)")
    } footer: {
      Text("Shared by all engines. Speaker & Wired and Bluetooth & Other keep separate values; the current output is \(route.title).")
    }
    Section("Visual Timing") {
      OffsetControl(name: "Visual Timing",
        value: $timing.visualOffsetMilliseconds)
      Text("Positive values show notes later relative to music; negative values show them earlier. Input timing follows the notes. Music is not trimmed, and judgment-window sizes are unchanged. Applies on the next play.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    Section("Input Timing") {
      OffsetControl(name: "Input Timing", value: $timing.inputOffsetMilliseconds)
      Text("Negative values compensate for early inputs; positive values compensate for late inputs. This does not change music timing or judgment-window sizes.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}

private struct OffsetControl: View {
  let name: String
  @Binding var value: Double

  var body: some View {
    LabeledContent("Offset", value: String(format: "%+.0f ms", value))
    Slider(value: $value, in: TimingCalibration.range, step: 1)
      .accessibilityLabel("\(name) Offset in milliseconds")
    Stepper("Adjust by 1 ms", value: $value, in: TimingCalibration.range, step: 1)
    Button("Reset \(name)") { value = 0 }
  }
}

/// A metronome to set Visual Timing by eye and ear, then Input Timing by
/// tapping along. Both use the same clocks as gameplay: music through
/// AVPlayer, frames timed for when they reach the screen, and touches by
/// their hardware timestamps.
struct TimingCalibrationView: View {
  @Binding var timing: TimingCalibration
  let route: AudioRouteKind
  @State private var metronome = CalibrationMetronome()

  var body: some View {
    Form {
      Section {
        Button(metronome.isRunning ? "Stop Clicks" : "Start Clicks",
          systemImage: metronome.isRunning ? "stop.fill" : "play.fill") {
          if metronome.isRunning { metronome.stop() } else { metronome.start() }
        }
        if let error = metronome.error {
          Text(error).foregroundStyle(.red)
        }
      } footer: {
        Text("Calibrating for \(route.title). Use the output you play with.")
      }
      Section {
        CalibrationFlashView(metronome: metronome,
          visualOffset: timing.visualOffsetSeconds)
          .frame(height: 120)
          .listRowInsets(EdgeInsets())
        OffsetControl(name: "Visual Timing",
          value: $timing.visualOffsetMilliseconds)
      } header: {
        Text("1. Visual Timing")
      } footer: {
        Text("Adjust until the flash and the click happen together. If the flash comes first, increase it.")
      }
      Section {
        CalibrationTapView { metronome.tap(at: $0, visualOffset: timing.visualOffsetSeconds) }
          .frame(height: 160)
          .overlay {
            Text(metronome.isRunning ? "Tap here with each click" : "Start the clicks, then tap here")
              .foregroundStyle(.secondary)
              .allowsHitTesting(false)
          }
          .listRowInsets(EdgeInsets())
        if let summary = metronome.tapSummary {
          LabeledContent("Taps", value: summary.count.formatted())
          LabeledContent("Median", value: String(format: "%+.0f ms", summary.median * 1000))
          LabeledContent("Spread", value: String(format: "±%.0f ms", summary.spread * 1000))
          if summary.count >= CalibrationMetronome.minimumTaps {
            Button(String(format: "Use %+.0f ms", (summary.median * 1000).rounded())) {
              timing.inputOffsetMilliseconds = (summary.median * 1000).rounded()
              metronome.clearTaps()
            }
          } else {
            Text("Keep tapping: \(CalibrationMetronome.minimumTaps - summary.count) more.")
              .foregroundStyle(.secondary)
          }
        }
        OffsetControl(name: "Input Timing", value: $timing.inputOffsetMilliseconds)
      } header: {
        Text("2. Input Timing")
      } footer: {
        Text("Set Visual Timing first. Tap along to the clicks; the first four of each start are ignored. The median of your taps becomes Input Timing.")
      }
    }
    .navigationTitle("Calibrate Timing")
    .onChange(of: timing.visualOffsetMilliseconds) { metronome.clearTaps() }
    .onDisappear { metronome.stop() }
  }
}

/// Clicks every half second through AVPlayer, from one second into the file.
@MainActor @Observable
final class CalibrationMetronome {
  static let interval = 0.5
  static let firstBeat = 1.0
  static let ignoredBeats = 4
  static let minimumTaps = 12
  private static let beats = 120

  struct TapSummary: Equatable {
    let count: Int
    let median: Double
    let spread: Double
  }

  private(set) var isRunning = false
  private(set) var error: String?
  private(set) var tapSummary: TapSummary?
  @ObservationIgnored private var errors = [Double]()
  @ObservationIgnored private(set) var clock: PlaybackEventClock?
  @ObservationIgnored private var player: AVPlayer?
  @ObservationIgnored private var endObserver: NSObjectProtocol?
  @ObservationIgnored private let owner = UUID()
  @ObservationIgnored private var generation = 0

  func start() {
    stop()
    error = nil
    generation += 1
    let generation = generation
    isRunning = true
    Task {
      do {
        try await PlaybackAudioSession.shared.activate(owner: owner)
        let url = try Self.clicksFile()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        while item.status == .unknown, generation == self.generation {
          try await Task.sleep(for: .milliseconds(10))
        }
        guard generation == self.generation else { return }
        guard item.status == .readyToPlay, let timebase = item.timebase else {
          throw item.error ?? CocoaError(.fileReadCorruptFile)
        }
        clock = PlaybackEventClock(timebase: timebase)
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
          forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) {
          [weak self] _ in Task { @MainActor in self?.stop() }
        }
        player.play()
      } catch {
        guard generation == self.generation else { return }
        stop()
        let nsError = error as NSError
        self.error = "Couldn’t play the clicks: \(nsError.localizedDescription) "
          + "(\(nsError.domain), \(nsError.code))"
      }
    }
  }

  func stop() {
    generation += 1
    player?.pause()
    player = nil
    clock = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    if isRunning { PlaybackAudioSession.shared.release(owner: owner) }
    isRunning = false
    clearTaps()
  }

  func clearTaps() {
    errors.removeAll()
    tapSummary = nil
  }

  /// Seconds after the beat nearest `hostTime`, on the chart timeline that
  /// Visual Timing shifts, or nil before the music or between beats.
  func beatOffset(at hostTime: Double, visualOffset: Double) -> (beat: Int, offset: Double)? {
    guard isRunning, player?.timeControlStatus == .playing,
      let media = clock?.mediaTime(at: hostTime) else { return nil }
    let chart = media - visualOffset
    let beat = ((chart - Self.firstBeat) / Self.interval).rounded()
    guard beat >= 0, beat < Double(Self.beats) else { return nil }
    return (Int(beat), chart - (Self.firstBeat + beat * Self.interval))
  }

  func tap(at hostTime: Double, visualOffset: Double) {
    guard let (beat, offset) = beatOffset(at: hostTime, visualOffset: visualOffset),
      beat >= Self.ignoredBeats, abs(offset) < Self.interval * 0.4 else { return }
    errors.append(offset)
    tapSummary = Self.summary(errors)
  }

  /// Median and median absolute deviation: robust to a stray tap.
  static func summary(_ errors: [Double]) -> TapSummary? {
    guard !errors.isEmpty else { return nil }
    func median(_ values: [Double]) -> Double {
      let sorted = values.sorted()
      let middle = sorted.count / 2
      return sorted.count.isMultiple(of: 2)
        ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    let center = median(errors)
    return TapSummary(count: errors.count, median: center,
      spread: median(errors.map { abs($0 - center) }))
  }

  /// A click with a sharp onset at each beat, accented every fourth. Written
  /// once to a fixed temporary file and reused.
  private static func clicksFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenRhythmCalibrationClicks.caf")
    if FileManager.default.fileExists(atPath: url.path) { return url }
    let rate = 48000.0
    let duration = firstBeat + Double(beats) * interval + 0.5
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
      let buffer = AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: AVAudioFrameCount(rate * duration)),
      let samples = buffer.floatChannelData?[0] else {
      throw CocoaError(.fileWriteUnknown)
    }
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
    let length = Int(rate * 0.03)
    for beat in 0..<beats {
      let start = Int(((firstBeat + Double(beat) * interval) * rate).rounded())
      let tone = beat.isMultiple(of: 4) ? 2400.0 : 1600.0
      for index in 0..<length where start + index < Int(buffer.frameLength) {
        let time = Double(index) / rate
        samples[start + index] = Float(0.7 * exp(-time / 0.006)
          * sin(2 * .pi * tone * time))
      }
    }
    // AVAudioFile picks the file type from the extension.
    let partial = url.deletingLastPathComponent()
      .appendingPathComponent("OpenRhythmCalibrationClicks-partial.caf")
    try? FileManager.default.removeItem(at: partial)
    do {
      let file = try AVAudioFile(forWriting: partial, settings: format.settings)
      try file.write(from: buffer)
    }
    try FileManager.default.moveItem(at: partial, to: url)
    return url
  }
}

/// Flashes for 60 ms from each beat, timed for when the frame reaches the
/// screen, through the same display-link path as gameplay.
private struct CalibrationFlashView: UIViewRepresentable {
  let metronome: CalibrationMetronome
  let visualOffset: Double

  func makeUIView(context: Context) -> CalibrationFlashUIView {
    CalibrationFlashUIView()
  }

  func updateUIView(_ view: CalibrationFlashUIView, context: Context) {
    view.metronome = metronome
    view.visualOffset = visualOffset
  }
}

final class CalibrationFlashUIView: UIView, CAMetalDisplayLinkDelegate {
  var metronome: CalibrationMetronome?
  var visualOffset = 0.0
  private let device = MTLCreateSystemDefaultDevice()
  private lazy var queue = device?.makeCommandQueue()
  private let metalLayer = CAMetalLayer()
  private var link: CAMetalDisplayLink?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true
    layer.addSublayer(metalLayer)
    isAccessibilityElement = true
    accessibilityLabel = "Flash on each click"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func layoutSubviews() {
    super.layoutSubviews()
    metalLayer.frame = bounds
    let scale = window?.screen.scale ?? traitCollection.displayScale
    metalLayer.drawableSize = CGSize(width: max(1, bounds.width * scale),
      height: max(1, bounds.height * scale))
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    link?.invalidate()
    link = nil
    guard window != nil, device != nil else { return }
    let link = CAMetalDisplayLink(metalLayer: metalLayer)
    link.delegate = self
    link.preferredFrameLatency = 1
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func metalDisplayLink(_ link: CAMetalDisplayLink,
    needsUpdate update: CAMetalDisplayLink.Update) {
    let beat = metronome?.beatOffset(at: update.targetPresentationTimestamp,
      visualOffset: visualOffset)
    let lit = beat.map { (0..<0.06).contains($0.offset) } ?? false
    let accent = beat.map { $0.beat.isMultiple(of: 4) } ?? false
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = update.drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = lit
      ? (accent ? MTLClearColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        : MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1))
      : MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    guard let buffer = queue?.makeCommandBuffer(),
      let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    encoder.endEncoding()
    buffer.present(update.drawable)
    buffer.commit()
  }
}

/// Reports each new touch's hardware timestamp (host seconds).
private struct CalibrationTapView: UIViewRepresentable {
  let onTap: (Double) -> Void

  func makeUIView(context: Context) -> CalibrationTapUIView {
    let view = CalibrationTapUIView()
    view.onTap = onTap
    return view
  }

  func updateUIView(_ view: CalibrationTapUIView, context: Context) {
    view.onTap = onTap
  }
}

final class CalibrationTapUIView: UIView {
  var onTap: ((Double) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .secondarySystemFill
    isMultipleTouchEnabled = true
    isAccessibilityElement = true
    accessibilityLabel = "Tap along to the clicks"
    accessibilityTraits = .allowsDirectInteraction
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches { onTap?(touch.timestamp) }
  }
}

#Preview("Timing Settings") {
  NavigationStack {
    Form {
      TimingSettingsSections(timing: .constant(TimingCalibration(
        visualOffsetMilliseconds: 12, inputOffsetMilliseconds: -8)), route: .wired)
    }
  }
}

#Preview("Calibrate Timing") {
  NavigationStack {
    TimingCalibrationView(timing: .constant(TimingCalibration()), route: .wireless)
  }
}
