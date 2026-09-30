import XCTest
import CoreMedia
import AVFoundation
import UIKit
@testable import OpenRhythm

final class PlaybackClockTests: XCTestCase {
  @MainActor
  func testAudioSessionLeaseReleaseCannotStopAnotherModel() async throws {
    let probe = AudioSessionProbe()
    let ended = expectation(description: "Both final-owner releases complete")
    ended.expectedFulfillmentCount = 2
    let session = PlaybackAudioSession { active in
      probe.record(active)
      if !active { ended.fulfill() }
    }
    let first = UUID(), second = UUID(), third = UUID()
    try await session.activate(owner: first)
    try await session.activate(owner: second)
    session.release(owner: first)
    session.release(owner: first)
    session.release(owner: UUID())
    // Reactivation is also a queue barrier for preceding cleanup operations.
    try await session.activate(owner: second)
    XCTAssertEqual(probe.values, [true, true, true])
    session.release(owner: second)
    try await session.activate(owner: third)
    XCTAssertEqual(probe.values, [true, true, true, false, true])
    session.release(owner: third)
    await fulfillment(of: [ended], timeout: 2)
    XCTAssertEqual(probe.values, [true, true, true, false, true, false])
    XCTAssertFalse(probe.usedMainThread)
  }

  @MainActor
  func testAudioSessionOrdersReleaseDuringPendingActivation() async throws {
    let probe = AudioSessionProbe()
    let entered = expectation(description: "Activation is pending off-main")
    let ended = expectation(description: "Both leases released")
    ended.expectedFulfillmentCount = 2
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    let session = PlaybackAudioSession { active in
      let count = probe.record(active)
      if count == 1 {
        entered.fulfill()
        guard gate.wait(timeout: .now() + 2) == .success else {
          throw NSError(domain: "AudioSessionProbe", code: 1)
        }
      }
      if !active { ended.fulfill() }
    }
    let first = UUID(), second = UUID()
    let activation = Task { try await session.activate(owner: first) }
    await fulfillment(of: [entered], timeout: 2)
    session.release(owner: first)
    let replacement = Task { try await session.activate(owner: second) }
    gate.signal()
    try await activation.value
    try await replacement.value
    XCTAssertEqual(probe.values, [true, false, true])
    session.release(owner: first)
    session.release(owner: second)
    await fulfillment(of: [ended], timeout: 2)
    XCTAssertEqual(probe.values, [true, false, true, false])
    XCTAssertFalse(probe.usedMainThread)
  }

  @MainActor
  func testAudioSessionActivationFailureDoesNotAcquireLease() async throws {
    let probe = AudioSessionProbe()
    let ended = expectation(description: "Successful lease released")
    let session = PlaybackAudioSession { active in
      if probe.record(active) == 1 {
        throw NSError(domain: "AudioSessionProbe", code: 7,
          userInfo: [NSLocalizedDescriptionKey: "Injected activation failure"])
      }
      if !active { ended.fulfill() }
    }
    let first = UUID(), second = UUID()
    do {
      try await session.activate(owner: first)
      XCTFail("Activation failures must propagate")
    } catch {
      XCTAssertEqual((error as NSError).domain, "AudioSessionProbe")
      XCTAssertEqual((error as NSError).code, 7)
    }
    session.release(owner: first)
    try await session.activate(owner: second)
    XCTAssertEqual(probe.values, [true, true])
    session.release(owner: second)
    await fulfillment(of: [ended], timeout: 2)
  }

  @MainActor
  func testGameplayReportsActivationFailureAndStopsPendingStartup() async throws {
    let session = PlaybackAudioSession { _ in
      throw NSError(domain: "AudioSessionProbe", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Injected activation failure"])
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-failure-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = try makeSessionModel(session, directory: directory)
    defer { model.stop() }
    model.start()
    for _ in 0..<200 where model.phase == .playing {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(model.phase, .failed("Audio playback could not start. "
      + "Injected activation failure (AudioSessionProbe, 7)"))
    XCTAssertFalse(model.isStartingPlayback)
    XCTAssertEqual(model.currentTime, 0)
  }

  @MainActor
  func testAbandonedRestartReleasesSessionWhenModelDeallocates() async throws {
    let probe = AudioSessionProbe()
    let entered = expectation(description: "Model owns a pending activation")
    let ended = expectation(description: "Deallocation releases the lease")
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    let session = PlaybackAudioSession { active in
      probe.record(active)
      if active {
        entered.fulfill()
        guard gate.wait(timeout: .now() + 2) == .success else {
          throw NSError(domain: "AudioSessionProbe", code: 1)
        }
      } else { ended.fulfill() }
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-lifetime-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var model: GameplayModel? = try makeSessionModel(session, directory: directory)
    weak var weakModel = model
    model?.start()
    await fulfillment(of: [entered], timeout: 2)
    // Preserve ownership as restart does, then abandon that restart. The
    // pending activation holds the model until its stale-generation guard.
    model?.stop(deactivateAudio: false)
    model = nil
    gate.signal()
    await fulfillment(of: [ended], timeout: 2)
    XCTAssertNil(weakModel)
    XCTAssertEqual(probe.values, [true, false])
  }

  @MainActor
  func testAudioInterruptionStopsActiveEngineWithoutSceneChange() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("session-interruption-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let notifications = NotificationCenter()
    let model = try makeSessionModel(PlaybackAudioSession { _ in },
      directory: directory, nativeEngine: true, audioNotifications: notifications)
    defer { model.stop() }
    model.start()
    let size = CGSize(width: 800, height: 400)
    for _ in 0..<200 {
      model.engineFrame(size: size, touches: [])
      if !model.isStartingPlayback && model.playbackTime > 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(model.phase, .playing)
    XCTAssertFalse(model.isStartingPlayback)
    let runtime = try XCTUnwrap(model.engineRuntime)
    let p = EnginePoint(x: 0, y: 0)
    let touch = EngineTouch(id: 1, started: true, ended: false,
      time: model.playbackTime, startTime: model.playbackTime,
      position: p, startPosition: p, delta: p)
    model.engineFrame(size: size, touches: [touch])
    XCTAssertEqual(runtime.memory.value(block: 1001, index: 3), 1)
    let generation = model.playbackGeneration
    notifications.post(
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(), userInfo: [
        AVAudioSessionInterruptionTypeKey:
          AVAudioSession.InterruptionType.began.rawValue
      ])
    await Task.yield()
    XCTAssertEqual(model.phase, .ready)
    XCTAssertNotNil(model.playbackNotice)
    XCTAssertGreaterThan(model.playbackGeneration, generation)
    model.engineFrame(size: size, touches: [])
    XCTAssertEqual(runtime.memory.value(block: 1001, index: 3), 1,
      "An interrupted play must no longer interpret input frames")
    XCTAssertNil(model.resultSaveTask, "An interrupted play is not a result")
    model.start()
    for _ in 0..<200 {
      model.engineFrame(size: size, touches: [])
      if !model.isStartingPlayback && model.playbackTime > 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(model.phase, .playing)
    XCTAssertFalse(model.isStartingPlayback)
    XCTAssertNil(model.playbackNotice)
    let restartedTime = model.playbackTime
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertGreaterThan(model.playbackTime, restartedTime,
      "An explicit restart must reach advancing audio, not only change phase")
  }

  @MainActor
  func testAudioInterruptionCancelsPendingActivationAndAllowsExplicitRestart()
    async throws {
    let entered = expectation(description: "Activation pending")
    let released = expectation(description: "Interrupted activation released")
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    let session = PlaybackAudioSession { active in
      if active {
        entered.fulfill()
        guard gate.wait(timeout: .now() + 2) == .success else {
          throw NSError(domain: "AudioSessionProbe", code: 1)
        }
      } else { released.fulfill() }
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pending-interruption-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let notifications = NotificationCenter()
    let model = try makeSessionModel(session, directory: directory,
      audioNotifications: notifications)
    defer { model.stop() }
    model.start()
    await fulfillment(of: [entered], timeout: 2)
    let generation = model.playbackGeneration
    let inputGeneration = model.inputGeneration
    // Malformed and ended notifications must not stop a live attempt.
    for raw: UInt? in [nil, 99, AVAudioSession.InterruptionType.ended.rawValue] {
      notifications.post(name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(), userInfo: raw.map {
          [AVAudioSessionInterruptionTypeKey: $0]
        })
    }
    XCTAssertEqual(model.phase, .playing)
    XCTAssertEqual(model.playbackGeneration, generation)
    XCTAssertNil(model.playbackNotice)
    // Also exercise background delivery through the observer's main queue.
    await Task.detached {
      notifications.post(name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(), userInfo: [
          AVAudioSessionInterruptionTypeKey:
            AVAudioSession.InterruptionType.began.rawValue
        ])
    }.value
    XCTAssertEqual(model.phase, .ready)
    XCTAssertFalse(model.isStartingPlayback)
    XCTAssertGreaterThan(model.playbackGeneration, generation)
    XCTAssertGreaterThan(model.inputGeneration, inputGeneration)
    XCTAssertNotNil(model.playbackNotice)
    gate.signal()
    await fulfillment(of: [released], timeout: 2)
    XCTAssertEqual(model.phase, .ready,
      "A completed stale activation must not restart interrupted playback")
    XCTAssertNil(model.resultSaveTask)
    notifications.post(name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(), userInfo: [
        AVAudioSessionInterruptionTypeKey:
          AVAudioSession.InterruptionType.ended.rawValue,
        AVAudioSessionInterruptionOptionKey:
          AVAudioSession.InterruptionOptions.shouldResume.rawValue
      ])
    XCTAssertEqual(model.phase, .ready, "Do not restart without the player")
    model.start()
    XCTAssertEqual(model.phase, .playing)
    XCTAssertNil(model.playbackNotice)
    model.stop()
    notifications.post(name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(), userInfo: [
        AVAudioSessionInterruptionTypeKey:
          AVAudioSession.InterruptionType.began.rawValue
      ])
    XCTAssertNil(model.playbackNotice, "Stopped models no longer observe audio")
  }

  @MainActor
  func testStoppedPlayerDoesNotJudgeUntilMusicResumes() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("stopped-input-\(UUID())")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var capturedPlayer: AVPlayer?
    let model = try makeSessionModel(PlaybackAudioSession { _ in },
      directory: directory, nativeEngine: true, inputProbe: true,
      makePlayer: { url in
        let player = AVPlayer(url: url)
        capturedPlayer = player
        return player
      })
    defer { model.stop() }
    model.start()
    let size = CGSize(width: 800, height: 400)
    for _ in 0..<200 {
      model.engineFrame(size: size, touches: [])
      if !model.isStartingPlayback && model.playbackTime > 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertFalse(model.isStartingPlayback)
    XCTAssertGreaterThan(model.playbackTime, 0)
    let player = try XCTUnwrap(capturedPlayer)
    let runtime = try XCTUnwrap(model.engineRuntime)
    XCTAssertEqual(runtime.inputCount, 1)
    XCTAssertEqual(runtime.resolvedInputCount, 0)
    player.pause()
    XCTAssertEqual(player.timeControlStatus, .paused)
    let frozenTime = model.playbackTime
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(model.playbackTime, frozenTime, accuracy: 0.001)
    let p = EnginePoint(x: 0, y: 0)
    let touch = EngineTouch(id: 1, started: true, ended: false,
      time: frozenTime, startTime: frozenTime,
      position: p, startPosition: p, delta: p)
    for _ in 0..<3 {
      XCTAssertFalse(model.engineFrame(size: size, touches: [touch]))
    }
    XCTAssertEqual(runtime.resolvedInputCount, 0,
      "Stopped music must not give an unlimited window to judge a note")
    XCTAssertEqual(model.phase, .playing,
      "An ordinary wait must not abort the attempt as an interruption")
    player.play()
    for _ in 0..<200 {
      if player.timeControlStatus == .playing,
        model.playbackTime > frozenTime { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertGreaterThan(model.playbackTime, frozenTime)
    XCTAssertTrue(model.engineFrame(size: size, touches: [touch]))
    XCTAssertEqual(runtime.resolvedInputCount, 1)

    // Normal EOF must keep the monotonic chart tail alive even though the
    // same media player is stopped. Restart to leave an unresolved input.
    model.stop()
    model.start()
    for _ in 0..<200 {
      model.engineFrame(size: size, touches: [])
      if !model.isStartingPlayback && model.playbackTime > 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertFalse(model.isStartingPlayback)
    let tailRuntime = try XCTUnwrap(model.engineRuntime)
    XCTAssertEqual(tailRuntime.resolvedInputCount, 0)
    player.pause()
    model.playbackEnded()
    XCTAssertTrue(model.isPlaybackAdvancing)
    XCTAssertTrue(model.engineFrame(size: size, touches: [touch]))
    XCTAssertEqual(tailRuntime.resolvedInputCount, 1)
  }

  func testStoppedInputPreservesHoldsAndPendingTapWithoutAdmittingNewPresses() {
    var pool = EngineTouchPool<Int>()
    pool.beginPlayback(generation: 1)
    func sample(_ x: Double, _ time: Double) -> [EngineTouchSample] {
      [EngineTouchSample(position: EnginePoint(x: x, y: 0),
        time: time, timestamp: time + 10)]
    }
    pool.receive(key: 1, samples: sample(0, 1), started: true, ended: false)
    pool.nextFrame(at: 1)
    // A short tap starts before the stopped frame; do not consume it until
    // the engine has actually processed its batch.
    pool.receive(key: 2, samples: sample(1, 1.1), started: true, ended: false)
    let ids = pool.touches.map(\.id)
    pool.receive(key: 1, samples: sample(0.2, 1.1), started: false, ended: true,
      acceptingNewContacts: false)
    pool.receive(key: 2, samples: sample(1, 1.1), started: false, ended: true,
      acceptingNewContacts: false)
    for key in 3...100 {
      pool.receive(key: key, samples: sample(0, 1.1), started: true, ended: false,
        acceptingNewContacts: false)
    }
    XCTAssertEqual(pool.touches.map(\.id), ids)
    XCTAssertEqual(pool.touches.map(\.started), [false, true])
    XCTAssertEqual(pool.touches.map(\.ended), [true, true])
    XCTAssertEqual(pool.touches[0].position.x, 0.2)
    // A reused identity for an ended contact cannot overwrite its release.
    pool.receive(key: 1, samples: sample(2, 1.1), started: true, ended: false,
      acceptingNewContacts: false)
    pool.receive(key: 1, samples: sample(2, 1.2), started: false, ended: true)
    XCTAssertEqual(pool.touches[0].position.x, 0.2)
    pool.nextFrame(at: 1.2)
    XCTAssertTrue(pool.touches.isEmpty)
    // Rejected presses do not become new contacts from later move/end events.
    pool.receive(key: 3, samples: sample(0.5, 1.2), started: false, ended: false)
    pool.receive(key: 3, samples: sample(0.5, 1.3), started: false, ended: true)
    XCTAssertTrue(pool.touches.isEmpty)
    pool.receive(key: 3, samples: sample(0.5, 1.4), started: true, ended: false)
    XCTAssertEqual(pool.touches.count, 1)
    XCTAssertTrue(pool.touches[0].started)
  }

  @MainActor
  private func makeSessionModel(_ session: PlaybackAudioSession,
    directory: URL, nativeEngine: Bool = false,
    audioNotifications: NotificationCenter = .default,
    inputProbe: Bool = false,
    makePlayer: @escaping (URL) -> AVPlayer = { AVPlayer(url: $0) }
  ) throws -> GameplayModel {
    let audio = directory.appendingPathComponent("tone.caf")
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 48000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: nativeEngine ? 48000 * 4 : 480))
    buffer.frameLength = buffer.frameCapacity
    for frame in 0..<Int(buffer.frameLength) {
      buffer.floatChannelData![0][frame] = nativeEngine
        ? Float(sin(Double(frame) * 2 * .pi * 440 / 48000) * 0.0002) : 0
    }
    do {
      let file = try AVAudioFile(forWriting: audio, settings: format.settings)
      try file.write(from: buffer)
    }
    let engineJSON = inputProbe ? #"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[{"name":"Probe","hasInput":true,"imports":[],
         "exports":[],"touch":{"index":6}}],
       "nodes":[{"value":4005},{"value":0},{"value":1},
         {"func":"Set","args":[0,1,2]},{"value":4004},
         {"func":"Set","args":[4,1,2]},
         {"func":"Execute","args":[3,5]}]}
      """# : #"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"archetypes":[],"nodes":[],"buckets":[]}
      """#
    let engine = try JSONDecoder().decode(EnginePlayData.self,
      from: Data(engineJSON.utf8))
    let resource = ResourceLocator(hash: nil, url: nil)
    let level = SonolusLevelItem(name: "session-failure", source: nil,
      version: 1, rating: 1, title: LocalizedText("Session failure"),
      artists: LocalizedText("Generated"), author: "Fixture", tags: [],
      cover: resource, bgm: resource, data: resource)
    let model = GameplayModel(audioSession: session,
      audioNotifications: audioNotifications, makePlayer: makePlayer)
    model.prepare(bundle: RuntimeBundle(engine: engine,
      level: LevelData(bgmOffset: 0, entities: inputProbe
        ? [LevelEntity(archetype: "Probe", name: nil, data: [])] : []),
      bgmURL: audio,
      isOffline: true, presentation: nativeEngine
        ? RuntimePresentation(resources: [
          "configuration": Data(#"{"options":[]}"#.utf8)]) : nil,
      playbackMode: nativeEngine ? .engine : .basicLanes), level: level,
      server: ServerDescriptor(id: "session-failure", name: "Fixture",
        baseURL: URL(string: "https://example.com")!), title: "Session failure")
    return model
  }

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
  func testDebugPauseFreezesStartupPlayerAndTailClocksAcrossRestarts() async throws {
    for _ in 0..<3 {
      try await checkLiveClocks(nativePlayfield: false, debugPauseCheck: true)
    }
  }

  @MainActor
  private func checkLiveClocks(nativePlayfield: Bool,
    softwareFallback: Bool = false, calibrateVisuals: Bool = false,
    engineAdjustsAudioOffset: Bool = false,
    debugPauseCheck: Bool = false) async throws {
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
      """# : debugPauseCheck ? #"""
      {"skin":{"sprites":[]},"effect":{"clips":[]},
       "particle":{"effects":[]},"buckets":[],
       "archetypes":[{"name":"Debug","hasInput":true,
         "imports":[],"exports":[],"preprocess":{"index":7}}],
       "nodes":[{"value":1000},{"value":0},
         {"func":"Get","args":[0,1]},{"value":42},
         {"func":"DebugLog","args":[3]},
         {"func":"DebugPause","args":[]},
         {"func":"Execute","args":[4,5]},
         {"func":"If","args":[2,6,1]}]}
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
        ? [LevelEntity(archetype: "Offset", name: nil, data: [])]
        : debugPauseCheck
          ? [LevelEntity(archetype: "Debug", name: nil, data: [])] : []), bgmURL: audio,
      isOffline: true, presentation: presentation), level: level,
      server: ServerDescriptor(id: "live-clock", name: "Fixture",
        baseURL: URL(string: "https://example.com")!), title: "Live clock fixture")
    let original = model.settings
    defer { model.stop(); model.settings = original }
    model.settings = GameplayPreferences(recordTimingDiagnostics: true,
      engineDebugMode: debugPauseCheck)
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
      if debugPauseCheck {
        model.engineFrame(size: size, touches: [])
        XCTAssertTrue(model.isDebugPaused)
        XCTAssertTrue(model.isStartingPlayback)
        XCTAssertEqual(model.debugLog.map(\.value), ["42.0"])
        XCTAssertEqual(model.modifiedOptions.first {
          $0.name == "Engine Debug Mode"
        }?.value, "On")
        try await checkPaused(model, size: size)
        model.resumeFromDebugPause()
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
      if debugPauseCheck {
        let generation = model.playbackGeneration
        let inputGeneration = model.inputGeneration
        _ = try runtime.host.call(function: "DebugPause", arguments: [])
        model.engineFrame(size: size, touches: [])
        XCTAssertTrue(model.isDebugPaused)
        XCTAssertEqual(model.playbackGeneration, generation,
          "Pause must not invalidate playback observers or restart the runtime")
        XCTAssertGreaterThan(model.inputGeneration, inputGeneration)
        try await checkPaused(model, size: size)
        model.resumeFromDebugPause()
        let resumeTime = model.playbackTime
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertLessThan(model.playbackTime - resumeTime, 0.1,
          "Paused wall time must never count as chart time")
        XCTAssertTrue(model.engineRuntime === runtime)
        XCTAssertFalse(model.isDebugPaused)
      }
      var differences = [Double]()
      var frameSamples = Set<Double>()
      let start = CACurrentMediaTime()
      let chartStart = model.playbackTime
      let startSampleEnd = CACurrentMediaTime()
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
        XCTAssertEqual(model.inputTime(at: before), oldTime, accuracy: 0.001,
          "Queried host time=\(before); \(model.eventClockDiagnostics)")
      }
      let endSampleStart = CACurrentMediaTime()
      let chartEnd = model.playbackTime
      let endSampleEnd = CACurrentMediaTime()
      let elapsed = endSampleStart - start
      // Drift updates must not hide a wrong playback speed by taking the
      // transition-aware branch below. Check the native effective rate at
      // every moving observation independently of input/player agreement.
      let movingRates = model.eventClockDiagnosticObservations.filter {
        $0.segment.rate != 0
      }.map { $0.segment.rate }
      XCTAssertFalse(movingRates.isEmpty, model.eventClockDiagnostics)
      for rate in movingRates {
        XCTAssertEqual(rate, speed, accuracy: 0.001,
          "Native clock must run at the selected speed, apart from drift")
      }
      let clockChanged = model.eventClockDiagnosticObservations.contains {
        guard let transition = $0.transition else { return false }
        return transition.latestHostTime >= start
          && transition.earliestHostTime <= endSampleEnd
      }
      if clockChanged {
        // Buffering/re-anchoring can legitimately stop or jump the player.
        // Do not mistake that for input disagreement or compensate its rate.
        // Check against the captured piecewise player mapping instead.
        let mappedStart = model.inputTime(at: (start + startSampleEnd) / 2)
        let mappedEnd = model.inputTime(at: (endSampleStart + endSampleEnd) / 2)
        XCTAssertEqual(chartStart, mappedStart, accuracy: 0.002,
          model.eventClockDiagnostics)
        XCTAssertEqual(chartEnd, mappedEnd, accuracy: 0.002,
          model.eventClockDiagnostics)
        print("Player transitioned during wall-progression check: "
          + "chart delta=\(chartEnd - chartStart), wall delta=\(elapsed); "
          + "native rates checked=\(movingRates.count)")
      } else {
        XCTAssertEqual(chartEnd - chartStart, elapsed, accuracy: 0.025,
          "Uninterrupted chart seconds track wall seconds at \(speed)×; "
            + "read widths=\(startSampleEnd - start), "
            + "\(endSampleEnd - endSampleStart); \(model.eventClockDiagnostics)")
      }
      if nativePlayfield {
        XCTAssertGreaterThan(frameSamples.count, 2,
          "Repeatedly reading one stale frame must not pass")
        XCTAssertEqual(model.currentTime - frameChartStart,
          chartEnd - chartStart, accuracy: 0.075,
          "Display-driven runtime must track the player, including its stalls")
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
      if debugPauseCheck {
        model.playbackEnded()
        model.pauseForDebug()
        let tailTime = model.playbackTime
        try await checkPaused(model, size: size)
        model.resumeFromDebugPause()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(model.playbackTime - tailTime, 0.04, accuracy: 0.03,
          "The post-audio clock must exclude the paused interval too")
      }
    }
    if debugPauseCheck {
      let oldRuntime = model.engineRuntime
      model.settings.engineDebugMode = false
      model.restart()
      model.engineFrame(size: size, touches: [])
      XCTAssertFalse(model.engineRuntime === oldRuntime,
        "Debug mode is part of the prepared-runtime cache key")
      XCTAssertFalse(model.isEngineDebugMode)
      XCTAssertFalse(model.isDebugPaused)
      XCTAssertTrue(model.debugLog.isEmpty)
      model.pauseForDebug()
      XCTAssertFalse(model.isDebugPaused)
    }
  }

  @MainActor
  private func checkPaused(_ model: GameplayModel, size: CGSize) async throws {
    let clock = model.playbackTime
    let frameTime = model.currentTime
    let inputCount = model.engineRuntime?.resolvedInputCount
    for _ in 0..<3 {
      try await Task.sleep(for: .milliseconds(50))
      model.engineFrame(size: size, touches: [])
      XCTAssertEqual(model.phase, .playing)
      XCTAssertEqual(model.playbackTime, clock)
      XCTAssertEqual(model.inputTime(at: CACurrentMediaTime()), clock)
      XCTAssertEqual(model.currentTime, frameTime)
      XCTAssertEqual(model.engineRuntime?.resolvedInputCount, inputCount)
      XCTAssertNil(model.frameTiming)
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

  func testZeroOriginClockMappingsDoNotRewriteObservedTouches() throws {
    var history = PlaybackClockHistory()
    let moving = PlaybackClockHistory.Segment(hostTime: 0,
      mediaTime: -85153.621562, rate: 1)
    history.observe(moving, at: 85153.781923625)
    let queuedHost = 85153.98802570836
    history.observe(moving, at: queuedHost)
    let queuedMedia = try XCTUnwrap(history.mediaTime(at: queuedHost))
    let stop = history.observe(.init(hostTime: 0,
      mediaTime: 0.375681291, rate: 0), at: 85153.997367333)
    XCTAssertEqual(stop?.earliestHostTime, queuedHost)
    XCTAssertEqual(stop?.usedNotificationTime, false)
    XCTAssertEqual(history.mediaTime(at: queuedHost), queuedMedia)
    XCTAssertEqual(history.mediaTime(at: 85153.998), 0.375681291)
    let resumed = PlaybackClockHistory.Segment(hostTime: 0,
      mediaTime: -85153.587163209, rate: 1)
    let resumeHost = 85154.008091208
    history.observe(resumed, at: 85154.008772041,
      transitionHostTime: resumeHost)
    XCTAssertEqual(history.mediaTime(at: resumeHost - 0.0001), 0.375681291)
    XCTAssertEqual(try XCTUnwrap(history.mediaTime(at: resumeHost + 0.0001)),
      0.421027999, accuracy: 1e-8)
    for index in 0..<200 {
      history.observe(resumed, at: 85154.009 + Double(index) / 1000)
    }
    XCTAssertEqual(history.segments.count, 3)
    XCTAssertEqual(history.mediaTime(at: queuedHost), queuedMedia)
    // A discontinuity whose conversion origin is still zero must begin now,
    // not replace the earlier stopped or running intervals.
    history.observe(.init(hostTime: 0, mediaTime: 99, rate: 0), at: 85155)
    XCTAssertEqual(history.mediaTime(at: queuedHost), queuedMedia)
    XCTAssertEqual(history.mediaTime(at: 85155), 99)
  }

  func testClockObservationFallbacksPreservePastAndBoundStorage() throws {
    var history = PlaybackClockHistory()
    history.observe(.init(hostTime: 0, mediaTime: 10, rate: 0), at: 100)
    let candidates: [Double] = [.nan, -.infinity, 0, 1000]
    for (index, candidate) in candidates.enumerated() {
      let now = 101 + Double(index)
      let change = history.observe(.init(hostTime: 0,
        mediaTime: Double(index), rate: 0), at: now,
        transitionHostTime: candidate)
      XCTAssertEqual(change?.appliedHostTime, now)
      XCTAssertEqual(change?.usedNotificationTime, false)
      XCTAssertEqual(history.mediaTime(at: 100), 10)
    }
    let count = history.segments.count
    history.observe(.init(hostTime: 0, mediaTime: 99, rate: 1), at: 99)
    history.observe(.init(hostTime: 0, mediaTime: .nan, rate: 1), at: 105)
    XCTAssertEqual(history.segments.count, count)
    for index in 105..<300 {
      history.observe(.init(hostTime: 0, mediaTime: Double(index), rate: 0),
        at: Double(index))
    }
    XCTAssertEqual(history.segments.count, 128)
    XCTAssertEqual(history.mediaTime(at: 299), 299)
  }

  func testTransitionAtPreviousObservationCannotReplaceThatObservation() {
    var history = PlaybackClockHistory()
    let old = PlaybackClockHistory.Segment(hostTime: 0, mediaTime: 10, rate: 0)
    let new = PlaybackClockHistory.Segment(hostTime: 0, mediaTime: 20, rate: 0)
    history.observe(old, at: 100)
    XCTAssertNil(history.observe(new, at: 100, transitionHostTime: 100),
      "Equal-resolution snapshots cannot order two different mappings")
    let transition = history.observe(new, at: 101, transitionHostTime: 100)
    XCTAssertEqual(transition?.usedNotificationTime, false)
    XCTAssertEqual(transition?.appliedHostTime, 101)
    XCTAssertEqual(history.mediaTime(at: 99), 10)
    XCTAssertEqual(history.mediaTime(at: 100), 10)
    XCTAssertEqual(history.mediaTime(at: 101), 20)
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
    let now = CMClockGetTime(host).seconds
    let nativeNow = CMTimebaseGetTime(timebase).seconds
    let afterNative = CMClockGetTime(host).seconds
    XCTAssertGreaterThanOrEqual(nativeNow, now - anchor.seconds + 9 - 1e-8)
    XCTAssertLessThanOrEqual(nativeNow, afterNative - anchor.seconds + 9 + 1e-8)
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: now)),
      now - anchor.seconds + 9, accuracy: 1e-8,
      "A future reference anchor does not schedule a future rate change")
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds + 0.5)),
      9.5, accuracy: 1e-8, "The new mapping already applies before its anchor")
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds - 0.012)),
      10, accuracy: 1e-8, "Actual pre-transition events keep the paused mapping")
    XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: anchor.seconds + 1.012)),
      10.012, accuracy: 1e-8)
  }

  func testClockTransitionDiagnosticsAreOptInBoundedAndDoNotChangeMapping() throws {
    let host = CMClockGetHostTimeClock()
    var base: CMTimebase?
    XCTAssertEqual(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
      sourceClock: host, timebaseOut: &base), noErr)
    let timebase = try XCTUnwrap(base)
    let plain = PlaybackEventClock(timebase: timebase)
    let traced = PlaybackEventClock(timebase: timebase, recordTransitions: true)
    for value in 1...80 {
      XCTAssertEqual(CMTimebaseSetTime(timebase,
        time: CMTime(value: Int64(value), timescale: 1)), noErr)
      let timestamp = CMClockGetTime(host).seconds
      XCTAssertEqual(try XCTUnwrap(traced.mediaTime(at: timestamp)),
        Double(value), accuracy: 1e-9)
      XCTAssertEqual(plain.mediaTime(at: timestamp), traced.mediaTime(at: timestamp))
    }
    XCTAssertTrue(plain.diagnosticObservations.isEmpty)
    XCTAssertEqual(traced.diagnosticObservations.count, 64)
    let snapshot = traced.diagnosticObservations
    XCTAssertEqual(snapshot.last?.segment.mediaTime, 80)
    XCTAssertTrue(snapshot.allSatisfy { $0.observedHostTime.isFinite })
    XCTAssertEqual(CMTimebaseSetTime(timebase,
      time: CMTime(value: 81, timescale: 1)), noErr)
    _ = traced.mediaTime(at: CMClockGetTime(host).seconds)
    XCTAssertEqual(snapshot.last?.segment.mediaTime, 80)
    XCTAssertEqual(traced.diagnosticObservations.last?.segment.mediaTime, 81)
  }

  func testNestedClockChangesAndSourceReplacementPreserveQueuedEvents() throws {
    let host = CMClockGetHostTimeClock()
    var parent: CMTimebase?
    XCTAssertEqual(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
      sourceClock: host, timebaseOut: &parent), noErr)
    let source = try XCTUnwrap(parent)
    XCTAssertEqual(CMTimebaseSetTime(source,
      time: CMTime(value: 10, timescale: 1)), noErr)
    XCTAssertEqual(CMTimebaseSetRate(source, rate: 1), noErr)
    var child: CMTimebase?
    XCTAssertEqual(CMTimebaseCreateWithSourceTimebase(
      allocator: kCFAllocatorDefault, sourceTimebase: source,
      timebaseOut: &child), noErr)
    let timebase = try XCTUnwrap(child)
    XCTAssertEqual(CMTimebaseSetRate(timebase, rate: 2), noErr)
    let clock = PlaybackEventClock(timebase: timebase)
    var queued = [(Double, Double)]()
    func checkAndQueue() throws {
      // Compare a timestamp after capture, avoiding uncertainty inside the
      // just-observed transition bracket. No wall-time sleeps are needed.
      _ = clock.mediaTime(at: CMClockGetTime(host).seconds)
      let now = CMClockGetTime(host)
      let expected = CMSyncConvertTime(now, from: host, to: timebase).seconds
      let actual = try XCTUnwrap(clock.mediaTime(at: now.seconds))
      XCTAssertEqual(actual, expected, accuracy: 1e-7)
      for (timestamp, media) in queued {
        XCTAssertEqual(try XCTUnwrap(clock.mediaTime(at: timestamp)), media,
          accuracy: 1e-7)
      }
      queued.append((now.seconds, actual))
    }
    try checkAndQueue()
    XCTAssertEqual(CMTimebaseSetRate(source, rate: 0), noErr)
    try checkAndQueue()
    XCTAssertEqual(CMTimebaseSetTime(source,
      time: CMTime(value: 50, timescale: 1)), noErr)
    try checkAndQueue()
    XCTAssertEqual(CMTimebaseSetRate(source, rate: -1), noErr)
    try checkAndQueue()
    XCTAssertEqual(CMTimebaseSetSourceClock(timebase, host), noErr)
    try checkAndQueue()
    XCTAssertEqual(CMTimebaseSetSourceTimebase(timebase, source), noErr)
    try checkAndQueue()
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
      bgmURL: URL(fileURLWithPath: "/nonexistent-clock-fixture.wav"), isOffline: true,
      playbackMode: .basicLanes),
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

private final class AudioSessionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var transitions = [Bool]()
  private var mainThread = false

  @discardableResult
  func record(_ active: Bool) -> Int {
    lock.lock()
    defer { lock.unlock() }
    transitions.append(active)
    mainThread = mainThread || Thread.isMainThread
    return transitions.count
  }

  var values: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return transitions
  }

  var usedMainThread: Bool {
    lock.lock()
    defer { lock.unlock() }
    return mainThread
  }
}
