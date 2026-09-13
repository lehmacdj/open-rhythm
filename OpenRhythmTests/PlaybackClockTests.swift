import XCTest
import CoreMedia
import AVFoundation
@testable import OpenRhythm

final class PlaybackClockTests: XCTestCase {
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
