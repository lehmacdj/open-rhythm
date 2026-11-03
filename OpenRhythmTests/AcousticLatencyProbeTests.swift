import AVFoundation
import CoreMedia
import XCTest
@testable import OpenRhythm

/// Opt-in physical measurement: the device's speaker (or a wired earbud held
/// to the microphone) plays music clicks through AVPlayer and hit-sound
/// clicks through the effect scheduler, and the microphone records both.
/// Each click is compared with the host time its clock promised.
///
/// Run on a device with `TEST_RUNNER_OPENRHYTHM_ACOUSTIC_PROBE=1`. It needs
/// microphone permission, which only the Debug app build requests.
final class AcousticLatencyProbeTests: XCTestCase {
  private let rate = 48000.0
  private let musicTone = 1000.0
  private let effectTone = 5000.0
  private let burst = 0.004
  private let musicClicks = (0..<12).map { 1.0 + 0.5 * Double($0) }
  private var effectClicks: [Double] { musicClicks.map { $0 + 0.25 } }

  @MainActor
  func testMusicAndHitSoundsReachTheMicrophoneWhenTheirClocksSay() async throws {
    #if targetEnvironment(simulator)
    throw XCTSkip("Acoustic latency needs a physical speaker and microphone.")
    #else
    guard ProcessInfo.processInfo.environment["OPENRHYTHM_ACOUSTIC_PROBE"] == "1"
    else { throw XCTSkip("Set OPENRHYTHM_ACOUSTIC_PROBE=1 to measure.") }
    guard await AVAudioApplication.requestRecordPermission() else {
      throw XCTSkip("Microphone permission was not granted.")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("acoustic-probe-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let music = directory.appendingPathComponent("music.caf")
    try writeClicks(at: musicClicks, tone: musicTone, duration: 8, to: music)
    let effectURL = directory.appendingPathComponent("effect.caf")
    try writeClicks(at: [0], tone: effectTone, duration: 0.05, to: effectURL)

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement,
      options: [.defaultToSpeaker])
    try session.setActive(true)
    defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
    let probeEngine = AVAudioEngine()
    let route = session.currentRoute.outputs.map {
      "\($0.portType.rawValue) (\($0.portName))"
    }.joined(separator: ", ")
    let inputs = session.currentRoute.inputs.map {
      "\($0.portType.rawValue) (\($0.portName))"
    }.joined(separator: ", ")

    let recorder = AVAudioEngine()
    let input = recorder.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    let chunks = ChunkStore()
    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, when in
      guard let samples = buffer.floatChannelData?[0], when.isHostTimeValid
      else { return }
      chunks.append(host: AVAudioTime.seconds(forHostTime: when.hostTime),
        samples: Array(UnsafeBufferPointer(start: samples,
          count: Int(buffer.frameLength))))
    }
    recorder.prepare()
    try recorder.start()
    defer { input.removeTap(onBus: 0); recorder.stop() }

    let effects = try EngineAudioPlayback(clips: [1: Data(contentsOf: effectURL)])
    try effects.start()
    defer { effects.stop() }
    let item = AVPlayerItem(url: music)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = false
    let ready = CACurrentMediaTime() + 5
    while item.status != .readyToPlay {
      guard CACurrentMediaTime() < ready else { return XCTFail("Player not ready") }
      try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(300))
    player.play()
    var queued = false
    var anchors = [(host: Double, media: Double)]()
    let end = CACurrentMediaTime() + 8.5
    while CACurrentMediaTime() < end {
      let media = player.currentTime().seconds
      if player.timeControlStatus == .playing, let timebase = item.timebase {
        var rate = 0.0
        var anchorMedia = CMTime.invalid
        var anchorHost = CMTime.invalid
        if CMSyncGetRelativeRateAndAnchorTime(timebase,
          relativeTo: CMClockGetHostTimeClock(), relativeRateOut: &rate,
          anchorTimeOut: &anchorMedia, relativeToAnchorTimeOut: &anchorHost)
          == noErr, rate == 1 {
          anchors.append((anchorHost.seconds, anchorMedia.seconds))
        }
        try effects.update(queued ? [] : effectClicks.map {
          EngineAudioCommand(clipID: 1, time: $0, minimumDistance: 0)
        }, at: media, currentTime: { player.currentTime().seconds })
        queued = true
      }
      try await Task.sleep(for: .milliseconds(8))
    }
    player.pause()
    let anchor = try XCTUnwrap(anchors.last, "The music clock never ran")
    let drift = anchors.map {
      ($0.host - $0.media) - (anchor.host - anchor.media)
    }.map(abs).max() ?? 0
    func host(media: Double) -> Double { anchor.host + media - anchor.media }

    let recording = chunks.flattened()
    let sampleRate = inputFormat.sampleRate
    func detect(_ expected: [Double], tone: Double) -> [Double] {
      expected.compactMap { media in
        let target = host(media: media) - session.inputLatency
        return onset(in: recording, sampleRate: sampleRate, tone: tone,
          around: target).map { $0 - target }
      }
    }
    let musicErrors = detect(musicClicks, tone: musicTone)
    let effectErrors = detect(effectClicks, tone: effectTone)
    func ms(_ values: [Double]) -> String {
      guard !values.isEmpty else { return "none detected" }
      let sorted = values.sorted()
      let median = sorted[sorted.count / 2]
      return String(format: "median %+.2f ms, range %+.2f…%+.2f ms, n=%d",
        median * 1000, sorted.first! * 1000, sorted.last! * 1000, values.count)
    }
    let report = """
      Acoustic probe on \(route); input \(inputs)
      Reported: output latency \(session.outputLatency * 1000) ms, \
      input latency \(session.inputLatency * 1000) ms, \
      I/O buffer \(session.ioBufferDuration * 1000) ms, \
      sample rate \(session.sampleRate) Hz, \
      engine output presentation latency \
      \(probeEngine.outputNode.presentationLatency * 1000) ms
      Music clock anchors drifted at most \(drift * 1000) ms
      Music (AVPlayer) heard minus its clock: \(ms(musicErrors))
      Hit sounds (effect scheduler) heard minus chart clock: \(ms(effectErrors))
      Positive means heard later than the clock says. Both include any \
      error in the reported input latency; their difference does not.
      """
    print(report)
    let attachment = XCTAttachment(string: report)
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertGreaterThanOrEqual(musicErrors.count, musicClicks.count - 2)
    XCTAssertGreaterThanOrEqual(effectErrors.count, effectClicks.count - 2)
    #endif
  }

  private func writeClicks(at times: [Double], tone: Double, duration: Double,
    to url: URL) throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate,
      channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: AVAudioFrameCount(rate * duration)))
    buffer.frameLength = buffer.frameCapacity
    let samples = buffer.floatChannelData![0]
    for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
    let length = Int(rate * burst)
    for time in times {
      let start = Int((time * rate).rounded())
      for index in 0..<length where start + index < Int(buffer.frameLength) {
        let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(length))
        samples[start + index] = Float(0.8 * window
          * sin(2 * .pi * tone * Double(index) / rate))
      }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }

  /// Host time of the burst start nearest `around`, from a quadrature matched
  /// filter, with parabolic peak interpolation. Nil if nothing stands out.
  private func onset(in recording: [(host: Double, samples: [Float])],
    sampleRate: Double, tone: Double, around target: Double) -> Double? {
    let length = Int(sampleRate * burst)
    let template = (0..<length).map { index -> (Double, Double) in
      let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(length))
      let phase = 2 * .pi * tone * Double(index) / sampleRate
      return (window * sin(phase), window * cos(phase))
    }
    var hosts = [Double]()
    var signal = [Float]()
    for chunk in recording {
      for index in chunk.samples.indices {
        let time = chunk.host + Double(index) / sampleRate
        guard abs(time - target) < 0.2 else { continue }
        hosts.append(time)
        signal.append(chunk.samples[index])
      }
    }
    guard signal.count > length * 2 else { return nil }
    var energy = [Double](repeating: 0, count: signal.count - length)
    for start in energy.indices {
      var sine = 0.0
      var cosine = 0.0
      for index in 0..<length {
        let value = Double(signal[start + index])
        sine += value * template[index].0
        cosine += value * template[index].1
      }
      energy[start] = sine * sine + cosine * cosine
    }
    guard let peak = energy.indices.max(by: { energy[$0] < energy[$1] })
    else { return nil }
    let sorted = energy.sorted()
    guard energy[peak] > 25 * sorted[sorted.count / 2] else { return nil }
    var offset = 0.0
    if peak > 0, peak < energy.count - 1 {
      let a = energy[peak - 1], b = energy[peak], c = energy[peak + 1]
      let denominator = a - 2 * b + c
      if denominator != 0 { offset = 0.5 * (a - c) / denominator }
    }
    return hosts[peak] + offset / sampleRate
  }
}

private final class ChunkStore: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks = [(host: Double, samples: [Float])]()

  func append(host: Double, samples: [Float]) {
    lock.lock()
    defer { lock.unlock() }
    chunks.append((host, samples))
  }

  func flattened() -> [(host: Double, samples: [Float])] {
    lock.lock()
    defer { lock.unlock() }
    return chunks
  }
}
