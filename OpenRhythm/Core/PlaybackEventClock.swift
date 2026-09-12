import CoreMedia
import Foundation
import AVFoundation

enum IntroAdvance {
  static func nextTime(current: Double, limit: Double,
    nextAudio: Double?, steps: Int) -> Double? {
    guard steps < 1801 else { return nil }
    let next = min(current + 1.0 / 60, limit, nextAudio ?? limit)
    return next.isFinite && next > current ? next : nil
  }
}

enum LeadingAudioSilence {
  /// Only inspect an already-local asset; never fetch another copy of a
  /// streaming song just to shorten its intro. Unknown audio starts at zero.
  static func duration(at url: URL) -> Double {
    guard url.isFileURL, let file = try? AVAudioFile(forReading: url),
      file.processingFormat.commonFormat == .pcmFormatFloat32,
      (1...8).contains(file.processingFormat.channelCount),
      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
        frameCapacity: 4096) else { return 0 }
    let rate = file.processingFormat.sampleRate
    guard rate.isFinite, (8000...192000).contains(rate) else { return 0 }
    let maximum = AVAudioFramePosition(rate * 30)
    var offset: AVAudioFramePosition = 0
    do {
      while offset < maximum {
        if Task.isCancelled { return 0 }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(
          min(4096, maximum - offset)))
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData
        else { return 0 } // Do not skip an entirely silent/invalid song.
        for frame in 0..<Int(buffer.frameLength) {
          // Apple's MP3 decoder dithers nominal silence by up to two 16-bit
          // steps. -80 dBFS is just above that floor; retain 50 ms before onset.
          if (0..<Int(buffer.format.channelCount)).contains(where: {
            !channels[$0][frame].isFinite || abs(channels[$0][frame]) > 0.0001
          }) {
            return max(0, Double(offset + Int64(frame)) / rate - 0.05)
          }
        }
        offset += Int64(buffer.frameLength)
      }
      return 30
    } catch { return 0 }
  }
}

/// Piecewise media-clock mapping, retaining rate changes for queued touches.
/// A current-rate-only conversion misdates events across pause/resume edges.
struct PlaybackClockHistory {
  struct Segment: Equatable {
    let hostTime: Double
    let mediaTime: Double
    let rate: Double
  }
  private(set) var segments = [Segment]()

  mutating func record(_ segment: Segment) {
    guard segment.hostTime.isFinite, segment.mediaTime.isFinite,
      segment.rate.isFinite else { return }
    if segments.last == segment { return }
    // A re-anchor replaces the mapping from that instant onward.
    segments.removeAll { $0.hostTime >= segment.hostTime }
    segments.append(segment)
    if segments.count > 128 { segments.removeFirst(segments.count - 128) }
  }

  func mediaTime(at hostTime: Double) -> Double? {
    guard hostTime.isFinite,
      let segment = segments.last(where: { $0.hostTime <= hostTime })
        ?? segments.first else { return nil }
    return segment.mediaTime + (hostTime - segment.hostTime) * segment.rate
  }
}

/// UIKit event timestamps and Core Media's host clock share system uptime.
/// Capture clock transitions synchronously on the posting thread, so main
/// thread stalls do not move a buffering boundary to notification delivery.
final class PlaybackEventClock: @unchecked Sendable {
  private let timebase: CMTimebase
  private let lock = NSLock()
  private var history = PlaybackClockHistory()
  private var observers = [NSObjectProtocol]()

  init(timebase: CMTimebase) {
    self.timebase = timebase
    for name in [kCMTimebaseNotification_EffectiveRateChanged,
      kCMTimebaseNotification_TimeJumped] {
      observers.append(NotificationCenter.default.addObserver(
        forName: Notification.Name(name as String), object: timebase,
        queue: nil) { [weak self] _ in self?.capture() })
    }
    capture()
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  private func capture() {
    lock.lock()
    defer { lock.unlock() }
    var rate = 0.0
    var media = CMTime.invalid
    var host = CMTime.invalid
    guard CMSyncGetRelativeRateAndAnchorTime(timebase,
      relativeTo: CMClockGetHostTimeClock(), relativeRateOut: &rate,
      anchorTimeOut: &media, relativeToAnchorTimeOut: &host) == noErr else { return }
    history.record(.init(hostTime: host.seconds, mediaTime: media.seconds, rate: rate))
  }

  func mediaTime(at timestamp: Double) -> Double? {
    capture()
    lock.lock()
    defer { lock.unlock() }
    return history.mediaTime(at: timestamp)
  }
}
