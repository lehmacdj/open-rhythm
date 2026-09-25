import XCTest
@testable import OpenRhythm

final class PlaybackTimingDiagnosticsTests: XCTestCase {
  func testRawAndEffectiveClockMetricsKeepDistinctLabelsAndStoredKeys() throws {
    let recorder = PlaybackTimingRecorder()
    recorder.record(.clockDifference, seconds: -0.1)
    recorder.record(.inputClockDifference, seconds: 0)
    let report = recorder.snapshot()
    let decoded = try JSONDecoder().decode(PlaybackTimingReport.self,
      from: JSONEncoder().encode(report))
    XCTAssertEqual(decoded.metrics["Event clock minus player clock"]?.meanMS, -100)
    XCTAssertEqual(decoded.metrics["Input clock minus player clock"]?.meanMS, 0)
    XCTAssertTrue(decoded.text.contains("Unclamped event clock minus player clock"))
  }

  func testSignedQuantilesAndNonfiniteSamples() throws {
    var empty = PlaybackTimingAccumulator()
    for invalid in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
      empty.record(seconds: invalid)
    }
    XCTAssertNil(empty.summary)
    for ms in [-1001.0, -1000, -0.25, 0, 0.25, 999.75, 1000, 1001] {
      var value = PlaybackTimingAccumulator()
      value.record(seconds: ms / 1000)
      let summary = try XCTUnwrap(value.summary)
      XCTAssertEqual(summary.meanMS, ms, accuracy: 1e-9)
      XCTAssertEqual(summary.minimumMS, ms, accuracy: 1e-9)
      XCTAssertEqual(summary.maximumMS, ms, accuracy: 1e-9)
      if ms < -1000 {
        XCTAssertNil(summary.p95LowerMS)
        XCTAssertEqual(summary.p95UpperMS, -1000)
      } else if ms >= 1000 {
        XCTAssertEqual(summary.p95LowerMS, 1000)
        XCTAssertNil(summary.p95UpperMS)
      } else {
        XCTAssertEqual(summary.p95LowerMS, ms)
        XCTAssertEqual(summary.p95UpperMS, ms + 0.25)
      }
    }
  }

  func testWholePlayAggregationDoesNotRetainOnlyInitialFrames() throws {
    var value = PlaybackTimingAccumulator()
    for _ in 0..<9000 { value.record(seconds: -0.01) }
    for _ in 0..<1000 { value.record(seconds: 0.02) }
    let summary = try XCTUnwrap(value.summary)
    XCTAssertEqual(summary.count, 10000)
    XCTAssertEqual(summary.meanMS, -7, accuracy: 1e-9)
    XCTAssertEqual(summary.p95LowerMS, 20)
    XCTAssertEqual(summary.p95UpperMS, 20.25)
  }

  func testActualPresentationTimeAndPerPlayIsolation() throws {
    let first = PlaybackTimingRecorder()
    let frame = PlaybackFrameTiming(recorder: first,
      sampleHostTime: 100, targetHostTime: 100.016)
    frame.presented(at: 0)
    frame.presented(at: .nan)
    frame.presented(at: 100.020)
    let snapshot = first.snapshot()
    let second = PlaybackTimingRecorder()
    // A late callback still belongs to the first play, not its successor or
    // the already-saved value snapshot.
    frame.presented(at: 100.030)
    XCTAssertTrue(second.snapshot().metrics.isEmpty)
    XCTAssertEqual(snapshot.counters[PlaybackTimingCounter.unavailable.rawValue], 2)
    XCTAssertEqual(snapshot.counters[PlaybackTimingCounter.presented.rawValue], 1)
    XCTAssertEqual(try XCTUnwrap(snapshot.metrics[
      PlaybackTimingMetric.presentation.rawValue]).meanMS, 20, accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(snapshot.metrics[
      PlaybackTimingMetric.deadline.rawValue]).meanMS, 4, accuracy: 1e-8)
    XCTAssertEqual(first.snapshot().metrics[
      PlaybackTimingMetric.presentation.rawValue]?.count, 2)
  }

  func testConcurrentCallbacksAndAudioMetadataRoundTrip() throws {
    let recorder = PlaybackTimingRecorder()
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in
      recorder.record(.gpu, seconds: 0.002)
      recorder.increment(.presented)
    }
    recorder.audio(route: "Speaker", outputLatency: 0.01, bufferDuration: 0.005)
    recorder.audio(route: "Speaker", outputLatency: 0.01, bufferDuration: 0.005)
    recorder.audio(route: "BluetoothA2DP", outputLatency: 0.15,
      bufferDuration: 0.01)
    let report = recorder.snapshot()
    XCTAssertEqual(report.metrics[PlaybackTimingMetric.gpu.rawValue]?.count, 1000)
    XCTAssertEqual(report.counters[PlaybackTimingCounter.presented.rawValue], 1000)
    XCTAssertEqual(report.counters[PlaybackTimingCounter.routeChanges.rawValue], 1)
    XCTAssertEqual(report.outputLatencyMS, 150)
    XCTAssertEqual(report.ioBufferDurationMS, 10)
    XCTAssertEqual(try JSONDecoder().decode(PlaybackTimingReport.self,
      from: JSONEncoder().encode(report)), report)
    XCTAssertTrue(report.text.contains("BluetoothA2DP"))
    recorder.audio(route: "Speaker", outputLatency: .nan, bufferDuration: -1)
    XCTAssertNil(recorder.snapshot().outputLatencyMS)
    XCTAssertNil(recorder.snapshot().ioBufferDurationMS)
  }

  @MainActor
  func testPreferencesDefaultOffAndPersistPerEngine() throws {
    let legacy = try JSONDecoder().decode(GameplayPreferences.self,
      from: Data("{}".utf8))
    XCTAssertFalse(legacy.recordTimingDiagnostics)
    let name = "PlaybackTimingDiagnosticsTests-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = UserPreferences(defaults: defaults)
    preferences.save(GameplayPreferences(recordTimingDiagnostics: true),
      for: "engine-a")
    let reloaded = UserPreferences(defaults: defaults)
    XCTAssertTrue(reloaded.gameplay(for: "engine-a").recordTimingDiagnostics)
    XCTAssertFalse(reloaded.gameplay(for: "engine-b").recordTimingDiagnostics)
  }
}
