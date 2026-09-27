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
  struct Entry {
    let validFrom: Double
    let mapping: Segment
  }
  struct Transition {
    let earliestHostTime: Double
    let latestHostTime: Double
    let appliedHostTime: Double
    let usedNotificationTime: Bool
  }
  private(set) var segments = [Entry]()
  private var lastObservation: Double?

  mutating func record(_ segment: Segment, validFrom: Double? = nil) {
    let boundary = validFrom ?? segment.hostTime
    guard segment.hostTime.isFinite, segment.mediaTime.isFinite,
      segment.rate.isFinite, boundary.isFinite else { return }
    if segments.last?.mapping == segment { return }
    // Conversion origins may be zero, old, or future. They are not the
    // instant at which this newly observed mapping replaced the previous one.
    segments.removeAll { $0.validFrom >= boundary }
    segments.append(Entry(validFrom: boundary, mapping: segment))
    if segments.count > 128 { segments.removeFirst(segments.count - 128) }
  }

  @discardableResult
  mutating func observe(_ segment: Segment, at hostTime: Double,
    transitionHostTime: Double? = nil) -> Transition? {
    guard hostTime.isFinite, segment.hostTime.isFinite,
      segment.mediaTime.isFinite, segment.rate.isFinite,
      lastObservation.map({ hostTime > $0 }) ?? true else { return nil }
    // A notification can refine a boundary only within the interval in
    // which this mapping could have changed. Never rewrite an observed past
    // because a clock drift calibration chose a different affine origin.
    let earliest = lastObservation ?? hostTime
    lastObservation = hostTime
    guard segments.last?.mapping != segment else { return nil }
    let candidate = transitionHostTime.flatMap {
      $0.isFinite && $0 > earliest && $0 <= hostTime ? $0 : nil
    }
    let boundary = candidate ?? hostTime
    record(segment, validFrom: boundary)
    return Transition(earliestHostTime: earliest, latestHostTime: hostTime,
      appliedHostTime: boundary, usedNotificationTime: candidate != nil)
  }

  func mediaTime(at hostTime: Double) -> Double? {
    guard hostTime.isFinite,
      let entry = segments.last(where: { $0.validFrom <= hostTime })
        ?? segments.first else { return nil }
    let segment = entry.mapping
    return segment.mediaTime + (hostTime - segment.hostTime) * segment.rate
  }
}

/// UIKit event timestamps and Core Media's host clock share system uptime.
/// Capture transitions on the posting thread. Moving notification times can
/// be inverted into host time; stopped mappings have only an observation
/// bracket, not a documented exact host timestamp.
final class PlaybackEventClock: @unchecked Sendable {
  struct Observation {
    let observedHostTime: Double
    let reason: String
    let notificationPayload: String?
    let segment: PlaybackClockHistory.Segment
    let sourceAnchorHostTime: Double
    let sourceAnchorMediaTime: Double
    let transition: PlaybackClockHistory.Transition?
  }

  private let timebase: CMTimebase
  private let recordTransitions: Bool
  private let lock = NSLock()
  private var history = PlaybackClockHistory()
  private var observations = [Observation]()
  private var observers = [NSObjectProtocol]()

  init(timebase: CMTimebase, recordTransitions: Bool = false) {
    self.timebase = timebase
    self.recordTransitions = recordTransitions
    for name in [kCMTimebaseNotification_EffectiveRateChanged,
      kCMTimebaseNotification_TimeJumped] {
      observers.append(NotificationCenter.default.addObserver(
        forName: Notification.Name(name as String), object: timebase,
        queue: nil) { [weak self] notification in
          guard let self else { return }
          self.capture(reason: notification.name.rawValue,
            eventTime: (notification.userInfo?[
              kCMTimebaseNotificationKey_EventTime as String] as? NSDictionary)
              .map { CMTimeMakeFromDictionary($0).seconds },
            payload: recordTransitions ? String(describing: notification.userInfo) : nil)
        })
    }
    capture(reason: "initial")
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  var diagnosticObservations: [Observation] {
    lock.lock()
    defer { lock.unlock() }
    return observations
  }

  private func capture(reason: String, eventTime: Double? = nil,
    payload: String? = nil) {
    lock.lock()
    defer { lock.unlock() }
    var rate = 0.0
    var media = CMTime.invalid
    var host = CMTime.invalid
    guard CMSyncGetRelativeRateAndAnchorTime(timebase,
      relativeTo: CMClockGetHostTimeClock(), relativeRateOut: &rate,
      anchorTimeOut: &media, relativeToAnchorTimeOut: &host) == noErr else { return }
    let segment = PlaybackClockHistory.Segment(hostTime: host.seconds,
      mediaTime: media.seconds, rate: rate)
    let observedHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds
    var sourceHost = CMTime.invalid
    var sourceMedia = CMTime.invalid
    if recordTransitions {
      let source = CMTimebaseCopyUltimateSourceClock(timebase)
      var sourceTime = CMTime.invalid
      if CMSyncGetRelativeRateAndAnchorTime(timebase, relativeTo: source,
        relativeRateOut: nil, anchorTimeOut: &sourceMedia,
        relativeToAnchorTimeOut: &sourceTime) == noErr {
        sourceHost = CMSyncConvertTime(sourceTime, from: source,
          to: CMClockGetHostTimeClock())
      }
    }
    let transition: Double?
    if let eventTime, rate != 0 {
      transition = host.seconds + (eventTime - media.seconds) / rate
    } else {
      transition = nil
    }
    let recorded = history.observe(segment, at: observedHost,
      transitionHostTime: transition)
    if recordTransitions,
      observations.last?.segment != segment || payload != nil {
      if observations.count == 64 { observations.removeFirst() }
      observations.append(Observation(
        observedHostTime: observedHost,
        reason: reason, notificationPayload: payload, segment: segment,
        sourceAnchorHostTime: sourceHost.seconds,
        sourceAnchorMediaTime: sourceMedia.seconds, transition: recorded))
    }
  }

  func mediaTime(at timestamp: Double) -> Double? {
    capture(reason: "read")
    lock.lock()
    defer { lock.unlock() }
    return history.mediaTime(at: timestamp)
  }
}
