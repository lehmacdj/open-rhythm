import XCTest
import CoreMedia
import AVFoundation
import UIKit
@testable import OpenRhythm

final class PlaybackClockTests: XCTestCase {
  func testVisualCalibrationMapsMusicAndInputOnceAtEverySpeed() {
    for speed in [0.5, 1.0, 2.0] {
      let neutral = BGMClockMapping(offset: 0.4, speed: speed)
      for offset in [-0.25, 0, 0.25] {
        let mapping = BGMClockMapping(offset: 0.4, speed: speed,
          audioOffset: offset)
        XCTAssertEqual(mapping.initialMediaTime, 0)
        XCTAssertEqual(mapping.initialChartTime,
          neutral.initialChartTime - offset, accuracy: 1e-12)
        for mediaTime in [0.0, 0.4, 12.0] {
          let time = mapping.chartTime(mediaTime: mediaTime)
          XCTAssertEqual(time, neutral.chartTime(mediaTime: mediaTime) - offset,
            accuracy: 1e-12)
          XCTAssertEqual(mapping.mediaTime(chartTime: time), mediaTime,
            accuracy: 1e-12)
          XCTAssertEqual(mapping.inputChartTime(mediaTime: mediaTime,
            minimumMediaTime: 0), time, accuracy: 1e-12)
          // The host maps scheduled SFX into runtime time by subtracting the
          // same offset: reaching it always corresponds to unmodified music.
          XCTAssertEqual(mapping.mediaTime(chartTime: 2 - offset),
            neutral.mediaTime(chartTime: 2), accuracy: 1e-12)
        }
      }
    }
  }

  @MainActor
  func testMetalDisplayLinkFollowsPlayfieldWindowLifetime() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.first)
    let priorKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    let controller = UIViewController()
    window.rootViewController = controller
    defer { window.isHidden = true; priorKeyWindow?.makeKey() }
    let playfield = EnginePlayfieldView(frame:
      CGRect(x: 0, y: 0, width: 300, height: 500))
    XCTAssertFalse(playfield.isUsingMetalDisplayLink)
    controller.view.addSubview(playfield)
    window.makeKeyAndVisible()
    XCTAssertTrue(playfield.isUsingMetalDisplayLink)
    playfield.removeFromSuperview()
    XCTAssertFalse(playfield.isUsingMetalDisplayLink)
    controller.view.addSubview(playfield)
    XCTAssertTrue(playfield.isUsingMetalDisplayLink)
    playfield.removeFromSuperview()
    XCTAssertFalse(playfield.isUsingMetalDisplayLink)
  }

  func testScheduledAudioStartClampsInputWithoutHidingRawClockDifference() {
    for speed in [0.5, 1.0, 2.0] {
      let mapping = BGMClockMapping(offset: 0.25, speed: speed)
      for floor in [0.0, 1.5] {
        let rawMedia = floor - 0.1 * speed
        let current = mapping.chartTime(mediaTime: floor)
        XCTAssertEqual(mapping.chartTime(mediaTime: rawMedia) - current,
          -0.1, accuracy: 1e-12)
        XCTAssertEqual(mapping.inputChartTime(mediaTime: rawMedia,
          minimumMediaTime: floor), current, accuracy: 1e-12)
        XCTAssertEqual(mapping.inputChartTime(mediaTime: floor + 0.1 * speed,
          minimumMediaTime: floor) - current, 0.1, accuracy: 1e-12)
      }
    }
  }

  @MainActor
  func testLivePlayerAndInputClocksAgreeAcrossSpeedsAndRestarts() async throws {
    try await checkLiveClocks(nativePlayfield: false)
  }

  @MainActor
  func testLivePlayfieldCombinesPlayerClockDisplayLinkAndPresentation() async throws {
    try await checkLiveClocks(nativePlayfield: true)
  }

  @MainActor
  func testSoftwareFallbackKeepsDisplayDrivenClockAdvancing() async throws {
    try await checkLiveClocks(nativePlayfield: true, softwareFallback: true)
  }

  @MainActor
  func testLiveVisualCalibrationAndRestartsKeepPlayerAndInputAligned() async throws {
    try await checkLiveClocks(nativePlayfield: true, calibrateVisuals: true)
  }

  @MainActor
  func testLiveEngineAudioOverridePrecedesIntroSeekAndSurvivesRestart() async throws {
    try await checkLiveClocks(nativePlayfield: false, calibrateVisuals: true,
      engineAdjustsAudioOffset: true)
  }

  @MainActor
  private func checkLiveClocks(nativePlayfield: Bool,
    softwareFallback: Bool = false, calibrateVisuals: Bool = false,
    engineAdjustsAudioOffset: Bool = false) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("live-clock-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audio = directory.appendingPathComponent("clock.caf")
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 48000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: 48000 * 4))
    buffer.frameLength = buffer.frameCapacity
    // Quiet generated tone, above the intro analyzer's silence threshold.
    // No downloaded audio, external service, or user library is involved.
    for frame in 0..<Int(buffer.frameLength) {
      buffer.floatChannelData![0][frame] = Float(
        sin(Double(frame) * 2 * .pi * 440 / 48000) * 0.0002)
    }
    do {
      let file = try AVAudioFile(forWriting: audio, settings: format.settings)
      try file.write(from: buffer)
    }
    let engineJSON = engineAdjustsAudioOffset ? #"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[{"name":"Offset","hasInput":false,
         "imports":[],"exports":[],"preprocess":{"index":5}}],
       "nodes":[{"value":1000},{"value":2},{"func":"Get","args":[0,1]},
         {"value":0.02},{"func":"Add","args":[2,3]},
         {"func":"Set","args":[0,1,4]}]}
      """# : #"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"archetypes":[],"nodes":[],"buckets":[]}
      """#
    let engine = try JSONDecoder().decode(EnginePlayData.self,
      from: Data(engineJSON.utf8))
    let presentation = RuntimePresentation(resources: [
      "configuration": Data(#"""
        {"options":[{"name":"#SPEED","type":"slider","def":1,
          "min":0.5,"max":2,"step":0.5}]}
        """#.utf8)])
    let resource = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "live-clock-\(UUID())", source: nil,
      version: 1, rating: 1, title: LocalizedText("Live clock fixture"),
      artists: LocalizedText("Generated"), author: "Fixture", tags: [],
      cover: resource, bgm: resource, data: resource)
    let model = GameplayModel(resultStore: ResultStore(rootURL: directory))
    model.prepare(bundle: RuntimeBundle(engine: engine,
      level: LevelData(bgmOffset: 0.25, entities: engineAdjustsAudioOffset
        ? [LevelEntity(archetype: "Offset", name: nil, data: [])] : []), bgmURL: audio,
      isOffline: true, presentation: presentation), level: level,
      server: ServerDescriptor(id: "live-clock", name: "Fixture",
        baseURL: URL(string: "https://example.com")!), title: "Live clock fixture")
    let original = model.settings
    defer { model.stop(); model.settings = original }
    model.settings = GameplayPreferences(recordTimingDiagnostics: true)
    let size = CGSize(width: 800, height: 400)
    var window: UIWindow?
    var priorKeyWindow: UIWindow?
    if nativePlayfield {
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }.first)
      priorKeyWindow = scene.windows.first(where: \.isKeyWindow)
      let nativeWindow = UIWindow(windowScene: scene)
      let controller = UIViewController()
      nativeWindow.rootViewController = controller
      let playfield = EnginePlayfieldView(frame:
        CGRect(x: 0, y: 0, width: 300, height: 500))
      playfield.model = model
      playfield.prepareAssets()
      controller.view.addSubview(playfield)
      nativeWindow.makeKeyAndVisible()
      XCTAssertTrue(playfield.isUsingMetalDisplayLink)
      if softwareFallback {
        playfield.fallBackToSoftware()
        XCTAssertFalse(playfield.isUsingMetalDisplayLink)
      }
      window = nativeWindow
    }
    defer { window?.isHidden = true; priorKeyWindow?.makeKey() }
    let idleDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    defer { UIApplication.shared.isIdleTimerDisabled = idleDisabled }
    for (index, speed) in [0.5, 1.0, 2.0, 1.0].enumerated() {
      let audioOffset = calibrateVisuals ? [0.125, -0.125, 0.25, -0.25][index] : 0
      model.settings.visualOffsetMilliseconds = audioOffset * 1000
      model.settings.engineOptions["#SPEED"] = speed
      if model.phase == .ready { model.start() } else { model.restart() }
      let initial = BGMClockMapping(offset: 0.25, speed: speed,
        audioOffset: audioOffset).initialChartTime
      XCTAssertEqual(model.currentTime, initial, accuracy: 1e-9,
        "Verify the requested speed before both clock paths can agree at a wrong rate")
      let effectiveOffset = audioOffset + (engineAdjustsAudioOffset ? 0.02 : 0)
      if engineAdjustsAudioOffset {
        model.engineFrame(size: size, touches: [])
        XCTAssertEqual(model.currentTime, initial - 0.02, accuracy: 1e-9,
          "Preprocess must change the initial clock before intro analysis or seeking")
      }
      let deadline = CACurrentMediaTime() + 8
      while model.phase == .playing,
        model.isStartingPlayback || model.currentTime < initial + 0.1 {
        if !nativePlayfield { model.engineFrame(size: size, touches: []) }
        guard CACurrentMediaTime() < deadline else {
          XCTFail("Local audio did not advance at \(speed)×: \(model.phase)")
          return
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertEqual(model.phase, .playing)
      XCTAssertEqual(model.skippedIntroDuration, 0, accuracy: 0.001)
      let runtime = try XCTUnwrap(model.engineRuntime)
      XCTAssertEqual(try runtime.audioOffset, effectiveOffset)
      XCTAssertEqual(model.playAudioOffset, effectiveOffset)
      XCTAssertEqual(model.modifiedOptions.first { $0.name == "Visual Timing" }?.value,
        effectiveOffset == 0 ? nil : String(format: "%+.0f ms", effectiveOffset * 1000))
      XCTAssertEqual(runtime.memory.value(block: 2002, index: 0), speed)
      XCTAssertEqual(runtime.host.timeline.bpm(at: 0), 60 * speed)
      var differences = [Double]()
      var frameSamples = Set<Double>()
      let start = CACurrentMediaTime()
      let chartStart = model.playbackTime
      let frameChartStart = model.currentTime
      for _ in 0..<40 {
        let before = CACurrentMediaTime()
        if !nativePlayfield { model.engineFrame(size: size, touches: []) }
        let after = CACurrentMediaTime()
        let frame = try XCTUnwrap(model.frameTiming)
        frameSamples.insert(frame.sampleHostTime)
        let eventTime = model.inputTime(at: frame.sampleHostTime)
        differences.append(eventTime - model.currentTime)
        if !nativePlayfield {
          XCTAssertGreaterThanOrEqual(frame.sampleHostTime, before)
        }
        XCTAssertLessThanOrEqual(frame.sampleHostTime, after)
        // Delayed delivery must retain the earlier event's media mapping.
        let oldTime = model.inputTime(at: before)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(model.inputTime(at: before), oldTime, accuracy: 0.001)
      }
      let elapsed = CACurrentMediaTime() - start
      XCTAssertEqual(model.playbackTime - chartStart, elapsed, accuracy: 0.025,
        "Chart seconds track wall seconds even at \(speed)× music speed")
      if nativePlayfield {
        XCTAssertGreaterThan(frameSamples.count, 2,
          "Repeatedly reading one stale frame must not pass")
        XCTAssertEqual(model.currentTime - frameChartStart, elapsed, accuracy: 0.075,
          "Display-driven runtime must keep advancing during observation")
      }
      let mean = differences.reduce(0, +) / Double(differences.count)
      let maximum = differences.map(abs).max() ?? 0
      XCTAssertEqual(mean, 0, accuracy: 0.002)
      XCTAssertLessThan(maximum, 0.005)
      let report = try XCTUnwrap(model.timingRecorder?.snapshot())
      XCTAssertGreaterThan(report.metrics[
        PlaybackTimingMetric.clockDifference.rawValue]?.count ?? 0, 0,
        "Must exercise the real player timebase, not a fallback clock")
      if nativePlayfield && !softwareFallback {
        XCTAssertGreaterThan(report.counters[
          PlaybackTimingCounter.submitted.rawValue] ?? 0, 0)
        #if !targetEnvironment(simulator)
        XCTAssertGreaterThan(report.metrics[
          PlaybackTimingMetric.presentation.rawValue]?.count ?? 0, 0)
        XCTAssertGreaterThan(report.metrics[
          PlaybackTimingMetric.deadline.rawValue]?.count ?? 0, 0)
        #endif
        print(report.text)
      }
      if softwareFallback {
        XCTAssertGreaterThan(report.counters[
          PlaybackTimingCounter.software.rawValue] ?? 0, 0)
        XCTAssertNil(report.counters[PlaybackTimingCounter.submitted.rawValue])
      }
      print("Live clocks (native: \(nativePlayfield), software: \(softwareFallback)) \(speed)×: mean difference \(mean * 1000) ms, "
        + "max absolute \(maximum * 1000) ms, \(differences.count) samples")
    }
  }

  func testPreparedMusicLeaseCleansUpAndSilenceUsesItsExactBytes() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.caf")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
    buffer.frameLength = 8000
    for frame in 0..<8000 { buffer.floatChannelData![0][frame] = frame < 4000 ? 0 : 0.1 }
    do {
      let file = try AVAudioFile(forWriting: source, settings: format.settings)
      try file.write(from: buffer)
    }
    var lease: PreparedRuntimeAudio? = try PreparedRuntimeAudio(
      data: Data(contentsOf: source), sourceURL: URL(string: "https://fixture.example/audio.caf")!,
      temporaryDirectory: directory)
    let url = try XCTUnwrap(lease?.url)
    XCTAssertEqual(LeadingAudioSilence.duration(at: url), 0.45, accuracy: 0.001)
    XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: source))
    lease = nil
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertThrowsError(try PreparedRuntimeAudio(data: Data(), sourceURL: source,
      temporaryDirectory: directory))
  }

  func testPlaybackSpeedScalesTempoAndClocksWithoutScalingJudgmentErrors() throws {
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":9,"entities":[
      {"archetype":"#BPM_CHANGE","data":[{"name":"#BEAT","value":0},
       {"name":"#BPM","value":120}]},
      {"archetype":"#BPM_CHANGE","data":[{"name":"#BEAT","value":4},
       {"name":"#BPM","value":60}]}]}
      """#.utf8))
    for speed in [0.5, 1, 1.5, 2] {
      let clock = BGMClockMapping(offset: 9, speed: speed)
      let tempo = BPMTimeline(level: level, speed: speed)
      XCTAssertEqual(tempo.time(at: 6), 4 / speed, accuracy: 1e-9)
      XCTAssertEqual(tempo.bpm(at: 6), 60 * speed)
      XCTAssertEqual(clock.initialChartTime, -9 / speed)
      XCTAssertEqual(clock.mediaTime(chartTime: tempo.time(at: 6)), 13)
      XCTAssertEqual(clock.chartTime(mediaTime: 13), tempo.time(at: 6))
      var events = PlaybackClockHistory()
      events.record(.init(hostTime: 100, mediaTime: 13, rate: speed))
      let late = try XCTUnwrap(events.mediaTime(at: 100.02))
      XCTAssertEqual(clock.chartTime(mediaTime: late) - tempo.time(at: 6),
        0.02, accuracy: 1e-9, "20 ms remains 20 ms in the engine's judgment window")
      XCTAssertEqual(BPMTimeline(level: LevelData(bgmOffset: 0, entities: []),
        speed: speed).bpm(at: 0), 60 * speed)
    }
  }

  func testRuntimeSpeedFeedsBothBPMImportsAndBuiltInTempoFunctions() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},"particle":{"effects":[]},
      "nodes":[],"buckets":[],"archetypes":[{"name":"#BPM_CHANGE",
      "hasInput":false,"imports":[{"name":"#BPM","index":0}],"exports":[]}]}
      """#.utf8))
    let level = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[{"archetype":"#BPM_CHANGE",
      "data":[{"name":"#BEAT","value":0},{"name":"#BPM","value":120}]}]}
      """#.utf8))
    let runtime = try EnginePlayRuntime(engine: engine, level: level, options: [1.5],
      aspectRatio: 1.8, skinSpriteIDs: [], effectClipIDs: [], particleEffectIDs: [],
      playbackSpeed: 1.5)
    XCTAssertEqual(runtime.host.timeline.bpm(at: 0), 180)
    XCTAssertEqual(runtime.host.timeline.time(at: 6), 2)
    XCTAssertEqual(runtime.memory.value(block: 4001, index: 0), 180)
    XCTAssertEqual(runtime.memory.value(block: 2002, index: 0), 1.5)
  }

  func testIntroAdvanceStopsAtAudioAndCannotHangOnExtremeOffsets() {
    XCTAssertEqual(IntroAdvance.nextTime(current: -3, limit: 0,
      nextAudio: -2.99, steps: 1), -2.99)
    XCTAssertEqual(IntroAdvance.nextTime(current: -0.01, limit: 0,
      nextAudio: nil, steps: 1), 0)
    XCTAssertNil(IntroAdvance.nextTime(current: -1e15, limit: -1e15 + 1,
      nextAudio: nil, steps: 1))
    XCTAssertNil(IntroAdvance.nextTime(current: 0, limit: 100,
      nextAudio: nil, steps: 1801))
  }
  func testLeadingSilenceRetainsAudioOnsetAndDoesNotFetchStreams() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("intro-\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000,
      channels: 2))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
    buffer.frameLength = 8000
    for channel in 0..<2 {
      for frame in 0..<8000 {
        buffer.floatChannelData![channel][frame] = channel == 1 && frame >= 4000
          ? 0.01 : 0
      }
    }
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }
    XCTAssertEqual(LeadingAudioSilence.duration(at: url), 0.45, accuracy: 0.001)
    XCTAssertEqual(LeadingAudioSilence.duration(at:
      URL(string: "https://example.com/do-not-fetch.mp3")!), 0)
    XCTAssertEqual(LeadingAudioSilence.duration(at:
      url.appendingPathExtension("missing")), 0)
  }
  func testEventClockPreservesQueuedTouchesAcrossStallAndResume() throws {
    var history = PlaybackClockHistory()
    history.record(.init(hostTime: 100, mediaTime: 10, rate: 1))
    history.record(.init(hostTime: 101, mediaTime: 11, rate: 0))
    history.record(.init(hostTime: 102, mediaTime: 11, rate: 1))
    for (host, media) in [(100.988, 10.988), (101.012, 11),
      (101.988, 11), (102.012, 11.012)] {
      XCTAssertEqual(try XCTUnwrap(history.mediaTime(at: host)), media, accuracy: 1e-9)
    }
    history.record(.init(hostTime: 103, mediaTime: 12, rate: 2))
    XCTAssertEqual(try XCTUnwrap(history.mediaTime(at: 103.1)), 12.2, accuracy: 1e-9)
  }

  func testEventClockUsesCoreMediaRateAndAnchorRatherThanDeliveryAge() throws {
    let host = CMClockGetHostTimeClock()
    var base: CMTimebase?
    XCTAssertEqual(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
      sourceClock: host, timebaseOut: &base), noErr)
    let timebase = try XCTUnwrap(base)
    let anchor = CMClockGetTime(host)
    XCTAssertEqual(CMTimebaseSetRateAndAnchorTime(timebase, rate: 0,
      anchorTime: CMTime(seconds: 10, preferredTimescale: 60000),
      immediateSourceTime: anchor), noErr)
    let clock = PlaybackEventClock(timebase: timebase)
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds - 0.012)),
      10, accuracy: 1e-9, "A frozen clock must not turn delivery delay into Early")
    XCTAssertEqual(CMTimebaseSetRateAndAnchorTime(timebase, rate: 1,
      anchorTime: CMTime(seconds: 10, preferredTimescale: 60000),
      immediateSourceTime: CMTimeAdd(anchor, CMTime(value: 1, timescale: 1))), noErr)
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds + 0.5)),
      10, accuracy: 1e-8, "Queued pre-resume events keep the paused mapping")
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds + 1.012)),
      10.012, accuracy: 1e-8)
  }

  @MainActor
  func testFallbackInputUsesEventTimeRatherThanLastObserverSample() throws {
    let engine = try JSONDecoder().decode(EnginePlayData.self, from: Data(#"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"archetypes":[],"nodes":[],"buckets":[]}
      """#.utf8))
    let chart = try JSONDecoder().decode(LevelData.self, from: Data(#"""
      {"bgmOffset":0,"entities":[
        {"name":"head","archetype":"TapNote","data":[
          {"name":"#BEAT","value":1},{"name":"lane","value":0}]},
        {"name":"tail","archetype":"HoldNote","data":[
          {"name":"#BEAT","value":2}]},
        {"archetype":"HoldConnector","data":[
          {"name":"head","ref":"head"},{"name":"tail","ref":"tail"}]}]}
      """#.utf8))
    let resource = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "clock", source: nil, version: 1, rating: 1,
      title: LocalizedText("Clock"), artists: LocalizedText("Fixture"),
      author: "Fixture", tags: [], cover: resource, bgm: resource, data: resource)
    let model = GameplayModel()
    model.prepare(bundle: RuntimeBundle(engine: engine, level: chart,
      bgmURL: URL(fileURLWithPath: "/nonexistent-clock-fixture.wav"), isOffline: true),
      level: level, server: ServerDescriptor(id: "clock", name: "Clock",
        baseURL: URL(string: "https://example.com")!), title: "Clock")
    model.start()
    defer { model.stop() }
    model.update(mediaTime: 0.99)
    model.press(lane: 0, at: 1)
    XCTAssertEqual(model.noteTimings.last?.accuracy, 0)
    model.update(mediaTime: 1.99)
    model.release(lane: 0, at: 2)
    XCTAssertEqual(model.noteTimings.last?.accuracy, 0)
    XCTAssertEqual(model.noteTimings.count, 2)
  }
}
