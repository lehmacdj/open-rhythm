import XCTest
import AVFoundation
@testable import OpenRhythm

final class EngineAudioTests: EngineHostTestCase {
  @MainActor
  private func nativeEffectFixture(rate: Double = 48000,
    outputRate: Double = 48000, channels: AVAudioChannelCount = 1,
    constant: Bool = false
  ) throws -> (AVAudioEngine, NativeEffectVoice, AVAudioPCMBuffer) {
    let engine = AVAudioEngine()
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: rate, channels: channels))
    let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: 4096))
    source.frameLength = 4096
    for channel in 0..<Int(channels) {
      for frame in 0..<4096 {
        let value = constant ? 0.25 : Float(frame + 1) / 8192
        source.floatChannelData![channel][frame] = channel == 0 ? value : -value
      }
    }
    let voice = NativeEffectVoice(engine: engine, buffer: source)
    let outputFormat = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: outputRate, channels: channels))
    try engine.enableManualRenderingMode(.offline, format: outputFormat,
      maximumFrameCount: 512)
    let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outputFormat,
      frameCapacity: 512))
    try engine.start()
    return (engine, voice, output)
  }

  @MainActor
  func testNativeVoiceScheduledStartStopAndReplacementAreSampleAccurate() throws {
    let schedules = [0, 1025].flatMap { start in
      [24577, 32769, 40961].map { (start, $0) }
    }
    for (start, replacement) in schedules {
      let (engine, voice, output) = try nativeEffectFixture(channels: 2)
      defer { engine.stop() }
      voice.play(after: Double(start) / 48000, looped: true)
      voice.stop(after: 32769.0 / 48000)
      voice.stop(after: Double(replacement) / 48000)
      for block in stride(from: 0, to: 41984, by: 512) {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        for channel in 0..<2 {
          let pcm = output.floatChannelData![channel]
          let mismatch = (0..<512).first { index in
            let frame = block + index
            let value: Float = frame >= start && frame < replacement
              ? Float((frame - start) % 4096 + 1) / 8192 : 0
            let expected = channel == 0 ? value : -value
            return !pcm[index].isFinite || abs(pcm[index] - expected) > 1e-6
          }
          XCTAssertNil(mismatch,
            "Block \(block), stop \(replacement), channel \(channel)")
          if mismatch != nil { return }
        }
      }
    }
  }

  @MainActor
  func testNativeVoiceRebasesEvenAfterOldStopWithoutResettingPhase() throws {
    for renderPause in [false, true] {
      let (engine, voice, output) = try nativeEffectFixture()
      defer { engine.stop() }
      voice.play(after: 0, looped: true)
      voice.stop(after: 1025.0 / 48000)
      for _ in 0..<3 {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      }
      XCTAssertEqual(output.floatChannelData![0][0], 1025.0 / 8192,
        accuracy: 1e-6)
      XCTAssertEqual(output.floatChannelData![0][1], 0)
      // Native output passed the old deadline before BGM buffering was noticed.
      // Its later chart-relative rebase must also work if pause/resume coalesce.
      voice.pause()
      if renderPause {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        XCTAssertTrue((0..<512).allSatisfy {
          output.floatChannelData![0][$0] == 0
        })
      }
      voice.resume()
      voice.stop(after: 1025.0 / 48000)
      for block in stride(from: 0, to: 1536, by: 512) {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        let pcm = output.floatChannelData![0]
        XCTAssertTrue((0..<512).allSatisfy { index in
          let frame = block + index
          let expected: Float = frame < 1025 ? Float(frame + 1026) / 8192 : 0
          return pcm[index].isFinite && abs(pcm[index] - expected) < 1e-6
        }, "Rebase must retain phase through the expired native stop")
      }
    }
  }

  @MainActor
  func testNativeVoiceReuseDiscardsPriorDeadlineAndCompletion() throws {
    let (engine, voice, output) = try nativeEffectFixture()
    defer { engine.stop() }
    voice.play(after: 0, looped: false)
    for _ in 0..<8 {
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    }
    XCTAssertFalse(voice.isPlaying)
    // Many publications with no render use bounded storage, not queued tasks.
    for _ in 0..<1000 {
      voice.play(after: 0, looped: true)
      voice.stop(after: 1.0 / 48000)
      voice.stop()
    }
    voice.play(after: 0, looped: false)
    XCTAssertTrue(voice.isPlaying, "Old completion cannot retire a reused voice")
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    XCTAssertEqual(output.floatChannelData![0][0], 1.0 / 8192, accuracy: 1e-6)
    XCTAssertEqual(output.floatChannelData![0][511], 512.0 / 8192, accuracy: 1e-6)
    XCTAssertTrue(voice.isPlaying, "No old stop may leak into this generation")
  }

  @MainActor
  func testNativeResumePublishesRebasedStopInSameSnapshot() throws {
    let (engine, voice, output) = try nativeEffectFixture()
    defer { engine.stop() }
    voice.play(after: 0, looped: true)
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    voice.pause()
    voice.stop(after: 1.0 / 48000)
    // An audio callback can run after re-arming but before the main actor resumes.
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    voice.resume()
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    XCTAssertEqual(output.floatChannelData![0][0], 513.0 / 8192, accuracy: 1e-6)
    XCTAssertTrue((1..<512).allSatisfy { output.floatChannelData![0][$0] == 0 },
      "The first resumed callback must already contain the rebased deadline")
  }

  @MainActor
  func testScheduledEffectsExcludeVoiceAllocationTimeFromDelay() throws {
    var now = 0.0
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      // The first eight voices are warmed before playback, not timed work.
      if voices.count >= 8 { now += 0.1 }
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    defer { audio.stop() }
    try audio.update(Array(repeating:
      EngineAudioCommand(clipID: 1, time: 0.5, minimumDistance: 0), count: 10),
      at: 0, currentTime: { now })
    XCTAssertEqual(voices.count, 10)
    XCTAssertEqual(voices[8].delays.first ?? -1, 0.4, accuracy: 1e-12)
    XCTAssertEqual(voices[9].delays.first ?? -1, 0.3, accuracy: 1e-12,
      "A chord must share a deadline, not accumulate voice setup delays")
  }

  @MainActor
  func testScheduledLoopsRecheckTimeAfterAllocationAndBeforeStop() throws {
    var now = 0.0
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      if voices.count >= 8 {
        now += 0.1
        voice.onPlay = { now += 0.05 }
      }
      voices.append(voice)
      return voice
    }
    defer { audio.stop() }
    try audio.update([], at: 0, loopCommands: (1...8).map {
      .start(id: $0, clipID: 1, time: 0)
    })
    try audio.update([], at: 0, loopCommands: [
      .start(id: 9, clipID: 1, time: 0.25), .stop(id: 9, time: 0.45)
    ], currentTime: { now })
    let voice = try XCTUnwrap(voices.last)
    XCTAssertEqual(voice.delays.first ?? -1, 0.15, accuracy: 1e-12)
    XCTAssertEqual(voice.stopDelays.first ?? -1, 0.3, accuracy: 1e-12)
  }

  @MainActor
  func testResumedLoopStopUsesTimeAfterOtherVoicesResume() throws {
    var now = 0.0
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    defer { audio.stop() }
    try audio.update([EngineAudioCommand(clipID: 1, time: 0,
      minimumDistance: 0)], at: 0, loopCommands: [
        .start(id: 1, clipID: 1, time: 0), .stop(id: 1, time: 0.8)
      ], currentTime: { now })
    let loop = try XCTUnwrap(voices.first { $0.looping == [true] })
    let effect = try XCTUnwrap(voices.first { $0.looping == [false] })
    audio.pause(at: 0.4)
    now = 0.4
    effect.onResume = { now += 0.1 }
    loop.events.removeAll()
    try audio.update([], at: 0.4, currentTime: { now })
    XCTAssertEqual(loop.events, ["scheduledStop", "resume"],
      "Publish the current stop deadline before any resumed samples")
    XCTAssertEqual(loop.stopDelays.last ?? -1, 0.3, accuracy: 1e-12)
  }

  @MainActor
  func testLoopExpiredDuringAllocationNeverStartsAndVoiceIsReusable() throws {
    var now = 0.0
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      if voices.count >= 8 { now += 0.6 }
      voices.append(voice)
      return voice
    }
    defer { audio.stop() }
    try audio.update([], at: 0, loopCommands: (1...8).map {
      .start(id: $0, clipID: 1, time: 0)
    })
    try audio.update([], at: 0, loopCommands: [
      .start(id: 9, clipID: 1, time: 0.25), .stop(id: 9, time: 0.5)
    ], currentTime: { now })
    let voice = try XCTUnwrap(voices.last)
    XCTAssertTrue(voice.delays.isEmpty,
      "A loop whose end passed during setup must never publish a start")
    try audio.update([], at: now, loopCommands: [
      .start(id: 10, clipID: 1, time: now)
    ], currentTime: { now })
    XCTAssertEqual(voices.count, 9)
    XCTAssertEqual(voice.delays, [0])
  }

  @MainActor
  func testNativeScheduledEffectDeadlineSurvivesControllerWork() throws {
    let (engine, voice, output) = try nativeEffectFixture()
    defer { engine.stop() }
    var allocations = 0
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      allocations += 1
      if allocations <= 8 { return MockEffectVoice() }
      // Advance the real native render clock during controller work. This is
      // deterministic and does not use sleeps or a relaxed timing tolerance.
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      return voice
    }
    defer { audio.stop() }
    try audio.update([], at: 0, loopCommands: (1...8).map {
      .start(id: $0, clipID: 1, time: 0)
    })
    try audio.update([EngineAudioCommand(clipID: 1,
      time: 1024.0 / 48000, minimumDistance: 0)], at: 0,
      currentTime: { Double(engine.manualRenderingSampleTime) / 48000 })
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    XCTAssertTrue((0..<512).allSatisfy { output.floatChannelData![0][$0] == 0 })
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    XCTAssertEqual(output.floatChannelData![0][511], 512.0 / 8192,
      accuracy: 1e-6, "Audio must start at frame 1024, not setup-delayed frame 1536")
  }

  @MainActor
  func testLoopControllerArmsFutureStopsBeforeResuming() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([], at: 0, loopCommands: [
      .start(id: 1, clipID: 1, time: 0), .stop(id: 1, time: 0.2)])
    let loop = try XCTUnwrap(voices.first { $0.looping == [true] })
    audio.pause(at: 0.1)
    loop.events.removeAll()
    try audio.update([], at: 0.1)
    XCTAssertEqual(loop.events, ["scheduledStop", "resume"])
    audio.stop()
  }

  @MainActor
  func testNativeVoiceAddedDuringPlaybackUsesExistingClockAndPreservesPeers() throws {
    // Keep the graph stereo so AVAudioMixerNode does not introduce mono
    // equal-power panning when it allocates a new input bus during playback.
    let (engine, first, output) = try nativeEffectFixture(channels: 2)
    defer { engine.stop() }
    first.play(after: 0, looped: true)
    for _ in 0..<6 {
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    }
    let before = engine.manualRenderingSampleTime
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 48000, channels: 2))
    let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
      frameCapacity: 97))
    source.frameLength = 97
    for frame in 0..<97 {
      source.floatChannelData![0][frame] = Float(frame + 1) / 8192
      source.floatChannelData![1][frame] = -Float(frame + 1) / 8192
    }
    let added = NativeEffectVoice(engine: engine, buffer: source)
    XCTAssertEqual(engine.manualRenderingSampleTime, before)
    added.play(after: 513.0 / 48000, looped: true)
    added.stop(after: 1537.0 / 48000)
    for block in stride(from: 0, to: 2048, by: 512) {
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      let samples = output.floatChannelData![0]
      XCTAssertTrue((0..<512).allSatisfy { index in
        let frame = block + index
        let peer = Float((Int(before) + frame) % 4096 + 1) / 8192
        let extra: Float = (513..<1537).contains(frame)
          ? Float((frame - 513) % 97 + 1) / 8192 : 0
        return samples[index].isFinite && abs(samples[index] - (peer + extra)) < 1e-6
          && abs(output.floatChannelData![1][index] + peer + extra) < 1e-6
      }, "Adding a voice must not restart its clock or disrupt an existing loop")
    }
  }

  @MainActor
  func testNativeVoiceRetainsPCMThroughNodeLifetimeAndReleasesGraph() throws {
    weak var weakPCM: AVAudioPCMBuffer?
    weak var weakEngine: AVAudioEngine?
    weak var weakVoice: NativeEffectVoice?
    try autoreleasepool {
      let engine = AVAudioEngine()
      weakEngine = engine
      let format = try XCTUnwrap(AVAudioFormat(
        standardFormatWithSampleRate: 48000, channels: 1))
      var voice: NativeEffectVoice? = try autoreleasepool {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
          frameCapacity: 97))
        buffer.frameLength = 97
        for frame in 0..<97 { buffer.floatChannelData![0][frame] = 0.25 }
        weakPCM = buffer
        return NativeEffectVoice(engine: engine, buffer: buffer)
      }
      weakVoice = voice
      XCTAssertNotNil(weakPCM, "The caller need not retain the source buffer")
      try engine.enableManualRenderingMode(.offline, format: format,
        maximumFrameCount: 512)
      let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 512))
      try engine.start()
      voice?.play(after: 0, looped: true)
      voice = nil
      XCTAssertNil(weakVoice)
      XCTAssertNotNil(weakPCM, "An attached node must keep its PCM alive")
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertTrue((0..<512).allSatisfy {
        output.floatChannelData![0][$0] == 0.25
      })
      engine.stop()
    }
    XCTAssertNil(weakVoice)
    XCTAssertNil(weakEngine, "Voice storage must not retain the audio graph")
    XCTAssertNil(weakPCM, "Tearing down the graph must release source PCM")
  }

  @MainActor
  func testNativeVoiceDenseShortLoopOfflineCost() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 48000, channels: 2))
    for length in [1, 97, 4096] {
      for sourceNode in [false, true] {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
          frameCapacity: AVAudioFrameCount(length)))
        source.frameLength = AVAudioFrameCount(length)
        for channel in 0..<2 {
          for frame in 0..<length { source.floatChannelData![channel][frame] = 0.0001 }
        }
        var native = [NativeEffectVoice]()
        var players = [AVAudioPlayerNode]()
        for _ in 0..<256 {
          if sourceNode { native.append(NativeEffectVoice(engine: engine, buffer: source)) }
          else {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
          }
        }
        try engine.enableManualRenderingMode(.offline, format: format,
          maximumFrameCount: 512)
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
          frameCapacity: 512))
        try engine.start()
        for voice in native { voice.play(after: 0, looped: true) }
        for player in players {
          player.scheduleBuffer(source, at: nil, options: .loops)
          player.play()
        }
        var elapsed = [Double]()
        for block in 0..<72 {
          let begin = ProcessInfo.processInfo.systemUptime
          XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
          let duration = ProcessInfo.processInfo.systemUptime - begin
          if block >= 8 { elapsed.append(duration) }
          for channel in 0..<2 {
            XCTAssertTrue((0..<512).allSatisfy {
              let sample = output.floatChannelData![channel][$0]
              return sample.isFinite && abs(sample - 0.0256) < 1e-5
            })
          }
        }
        elapsed.sort()
        print("PCM_COST source=\(sourceNode) length=\(length) voices=256 "
          + "median_ms=\(elapsed[32] * 1000) p95_ms=\(elapsed[60] * 1000)")
      }
    }
  }

  @MainActor
  func testNativeVoiceConcurrentPublicationRemainsFiniteAndReusable() async throws {
    let (engine, voice, output) = try nativeEffectFixture(channels: 2,
      constant: true)
    defer { engine.stop() }
    voice.play(after: 0, looped: true)
    let rendering = Task.detached { () throws -> Int in
      var invalid = 0
      for iteration in 0..<2000 {
        if try engine.renderOffline(512, to: output) != .success { invalid += 1 }
        let left = output.floatChannelData![0]
        let right = output.floatChannelData![1]
        if (0..<512).contains(where: {
          !left[$0].isFinite || !right[$0].isFinite
            || (left[$0] != 0 && left[$0] != 0.25)
            || right[$0] != -left[$0]
        }) { invalid += 1 }
        if iteration.isMultiple(of: 16) { await Task.yield() }
      }
      return invalid
    }
    // Race complete generations/deadlines against native consumption. There
    // must never be partially published stereo PCM or an unbounded work queue.
    for iteration in 0..<4000 {
      voice.play(after: 0, looped: true)
      voice.stop(after: 0.5)
      voice.pause()
      voice.resume()
      if iteration.isMultiple(of: 3) { voice.stop() }
      if iteration.isMultiple(of: 16) { await Task.yield() }
    }
    let invalid = try await rendering.value
    XCTAssertEqual(invalid, 0)
    voice.stop()
    voice.play(after: 0, looped: false)
    XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
    XCTAssertTrue((0..<512).allSatisfy { output.floatChannelData![0][$0] == 0.25 })
    XCTAssertTrue(voice.isPlaying)
  }

  @MainActor
  func testNativeVoiceCrossRateStereoScheduling() throws {
    let (engine, voice, output) = try nativeEffectFixture(rate: 44100,
      outputRate: 48000, channels: 2, constant: true)
    defer { engine.stop() }
    voice.play(after: 0.1, looped: true)
    voice.stop(after: 0.7)
    for block in stride(from: 0, to: 38912, by: 512) {
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      for channel in 0..<2 {
        let pcm = output.floatChannelData![channel]
        // The mixer resampler has filter tails around each transition. Verify
        // the timing domain away from those tails, not falsely sample-exact SRC.
        XCTAssertTrue((0..<512).allSatisfy { index in
          let frame = block + index
          guard frame < 4600 || (5000..<33000).contains(frame)
            || frame > 34200 else { return pcm[index].isFinite }
          let expected: Float = (5000..<33000).contains(frame)
            ? (channel == 0 ? 0.25 : -0.25) : 0
          return pcm[index].isFinite && abs(pcm[index] - expected) < 1e-5
        }, "Source timestamps must use the clip's rate, not the mixer's")
      }
    }
  }

  @MainActor
  func testNativeScheduledBufferInterruptionUsesExactPlayerSample() throws {
    // Native API capability probe, not yet the production stop implementation.
    // No suspension: audible stopping cannot depend on servicing the main actor.
    for replacement: Int? in [nil, 24577, 40961] {
      let engine = AVAudioEngine()
      defer { engine.stop() }
      let format = try XCTUnwrap(AVAudioFormat(
        standardFormatWithSampleRate: 48000, channels: 1))
      let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 4096))
      source.frameLength = 4096
      for frame in 0..<4096 { source.floatChannelData![0][frame] = 0.25 }
      let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 1))
      silence.frameLength = 1
      silence.floatChannelData![0][0] = 0
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: format)
      try engine.enableManualRenderingMode(.offline, format: format,
        maximumFrameCount: 512)
      let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 512))
      try engine.start()
      player.scheduleBuffer(source, at: nil, options: .loops)
      player.play()
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      player.scheduleBuffer(silence,
        at: AVAudioTime(sampleTime: 32769, atRate: 48000), options: .interrupts)
      // A later enqueue does not cancel the original earlier interruption.
      let requestedEnd = replacement ?? 32769
      let end = min(requestedEnd, 32769)
      if replacement != nil {
        player.scheduleBuffer(silence,
          at: AVAudioTime(sampleTime: AVAudioFramePosition(requestedEnd),
            atRate: 48000),
          options: .interrupts)
      }
      for start in stride(from: 512, to: 41984, by: 512) {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        let samples = output.floatChannelData![0]
        let mismatch = (0..<512).first {
          !samples[$0].isFinite
            || abs(samples[$0] - (start + $0 < end ? 0.25 : 0)) > 1e-6
        }
        XCTAssertNil(mismatch,
          "Wrong interrupt sample near \(start), requested end=\(end)")
        if mismatch != nil { break }
      }
      player.stop()
    }
  }

  @MainActor
  func testNativeEffectPauseRetainsSamplePosition() throws {
    for looped in [false, true] {
      let engine = AVAudioEngine()
      defer { engine.stop() }
      let format = try XCTUnwrap(AVAudioFormat(
        standardFormatWithSampleRate: 48000, channels: 1))
      let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 4096))
      source.frameLength = 4096
      for frame in 0..<4096 {
        source.floatChannelData![0][frame] = Float(frame) / 8192
      }
      let voice = NativeEffectVoice(engine: engine, buffer: source)
      try engine.enableManualRenderingMode(.offline, format: format,
        maximumFrameCount: 512)
      let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 512))
      try engine.start()
      voice.play(after: 0, looped: looped)
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][511], Float(511) / 8192,
        accuracy: 1e-6)
      voice.pause()
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertTrue((0..<512).allSatisfy {
        abs(output.floatChannelData![0][$0]) < 1e-6
      })
      engine.pause()
      try engine.start()
      voice.resume()
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][0], Float(512) / 8192,
        accuracy: 1e-6, "Resume continues the sample; it must not replay or skip")
      voice.stop()
    }
  }

  @MainActor
  func testPauseRetainsReservationThatBecameDueBetweenFrames() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.04,
      minimumDistance: 0.1)], at: 0)
    let active = try XCTUnwrap(voices.first { !$0.delays.isEmpty })
    audio.pause(at: 0.05)
    XCTAssertEqual(active.stopCount, 0)
    XCTAssertEqual(active.pauseCount, 1)
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.06,
      minimumDistance: 0.1)], at: 0.05)
    XCTAssertEqual(active.resumeCount, 1)
    XCTAssertEqual(voices.flatMap(\.delays), [0.04],
      "Resume must neither replay a due reservation nor forget minimum distance")
    audio.stop()
  }

  @MainActor
  func testBufferingDoesNotReplayDueReservationsOrActiveLoops() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.04,
      minimumDistance: 0.1)], at: 0, loopCommands: [
        .start(id: 1, clipID: 1, time: 0), .stop(id: 1, time: 0.3)])
    let effect = try XCTUnwrap(voices.first { $0.looping == [false] })
    let loop = try XCTUnwrap(voices.first { $0.looping == [true] })
    for _ in 0..<3 { try audio.update([], at: 0.05, advancing: false) }
    XCTAssertEqual(effect.stopCount, 0)
    XCTAssertEqual(loop.stopCount, 0)
    XCTAssertEqual(effect.pauseCount, 1)
    XCTAssertEqual(loop.pauseCount, 1)
    try audio.update([EngineAudioCommand(clipID: 1, time: 0.06,
      minimumDistance: 0.1)], at: 0.05)
    XCTAssertEqual(effect.resumeCount, 1)
    XCTAssertEqual(loop.resumeCount, 1)
    XCTAssertEqual(effect.delays, [0.04],
      "An already-started reservation must not play again on buffer recovery")
    XCTAssertEqual(loop.delays, [0], "A held effect retains its sample phase")
    XCTAssertEqual(voices.flatMap(\.delays).count, 2,
      "Recovering a due reservation must also preserve minimum-distance state")
    XCTAssertEqual(loop.stopDelays, [0.3, 0.25],
      "The stop deadline must be rebased after the frozen interval")
    audio.stop()
  }

  @MainActor
  func testPausedLoopStopsAreAppliedBeforeResumingVoice() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([], at: 0, loopCommands: [
      .start(id: 1, clipID: 1, time: 0)])
    let loop = try XCTUnwrap(voices.first { $0.looping == [true] })
    audio.pause(at: 0.05)
    try audio.update([], at: 0.05, advancing: false,
      loopCommands: [.stop(id: 1, time: 0.05)])
    try audio.update([], at: 0.05)
    XCTAssertEqual(loop.stopCount, 1)
    XCTAssertEqual(loop.resumeCount, 0,
      "A stopped loop must not briefly restart before its queued stop is applied")
    XCTAssertEqual(loop.delays, [0])
    audio.stop()
  }

  @MainActor
  func testPausedLoopReplacementReclaimsFullVoicePoolBeforeResume() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([], at: 0, loopCommands: (1...256).map {
      .start(id: $0, clipID: 1, time: 0)
    })
    XCTAssertEqual(audio.allocatedVoiceCount, 256)
    audio.pause(at: 0.1)
    try audio.update([], at: 0.1, advancing: false, loopCommands: [
      .stop(id: 1, time: 0.1), .start(id: 257, clipID: 1, time: 0.1)])
    try audio.update([], at: 0.1)
    XCTAssertEqual(audio.allocatedVoiceCount, 256)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 256)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.resumeCount }, 255)
    XCTAssertEqual(voices.flatMap(\.delays).count, 257)
    audio.stop()
  }

  @MainActor
  func testNativeBufferingRetainsActiveEffectSamplePosition() throws {
    for looped in [false, true] {
      let engine = AVAudioEngine()
      defer { engine.stop() }
      let format = try XCTUnwrap(AVAudioFormat(
        standardFormatWithSampleRate: 48000, channels: 1))
      let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 4096))
      source.frameLength = 4096
      for frame in 0..<4096 {
        source.floatChannelData![0][frame] = Float(frame) / 8192
      }
      let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
        NativeEffectVoice(engine: engine, buffer: source)
      }
      defer { audio.stop() }
      try engine.enableManualRenderingMode(.offline, format: format,
        maximumFrameCount: 512)
      let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
        frameCapacity: 512))
      try engine.start()
      try audio.update(looped ? [] : [EngineAudioCommand(clipID: 1,
        time: 0, minimumDistance: 0)], at: 0,
        loopCommands: looped ? [.start(id: 1, clipID: 1, time: 0),
          .stop(id: 1, time: 0.03)] : [])
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][511], Float(511) / 8192,
        accuracy: 1e-6)
      let pausedTime = 512.0 / 48000
      for _ in 0..<3 {
        try audio.update([], at: pausedTime, advancing: false)
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        XCTAssertTrue((0..<512).allSatisfy {
          abs(output.floatChannelData![0][$0]) < 1e-6
        }, "A frozen BGM clock must freeze the active effect too")
      }
      try audio.update([], at: pausedTime)
      XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
      XCTAssertEqual(output.floatChannelData![0][0], Float(512) / 8192,
        accuracy: 1e-6, "Buffer recovery must neither replay nor skip samples")
      if looped {
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        XCTAssertTrue((0..<512).allSatisfy { index in
          let expected: Float = index < 416 ? Float(1024 + index) / 8192 : 0
          let sample = output.floatChannelData![0][index]
          return sample.isFinite && abs(sample - expected) < 1e-6
        }, "The chart owner must rebase its actual native stop after buffering")
      }
    }
  }

  @MainActor
  func testDebugPausePreservesActiveSamplesAndReschedulesFutureAudio() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0, minimumDistance: 0),
      EngineAudioCommand(clipID: 1, time: 0.4, minimumDistance: 0)
    ], at: 0, loopCommands: [
      .start(id: 1, clipID: 1, time: 0), .stop(id: 1, time: 0.5),
      .start(id: 2, clipID: 1, time: 0.4)])
    XCTAssertEqual(voices.flatMap(\.delays).count, 4)
    audio.pause(at: 0.1)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.pauseCount }, 2)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 2)
    try audio.update([], at: 0.1, advancing: false)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.resumeCount }, 0)
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.resumeCount }, 2)
    XCTAssertEqual(voices.flatMap(\.delays).count, 6)
    XCTAssertEqual(voices.flatMap(\.stopDelays).sorted(), [0.4, 0.5])
    audio.pause(at: 0.2)
    audio.stop()
    let starts = voices.flatMap(\.delays).count
    try audio.update([], at: 0.3)
    XCTAssertEqual(voices.flatMap(\.delays).count, starts,
      "Stop discards paused commands; they must not leak into another play")
  }

  func testAudioCalibrationHonorsEnginePreparationAndScheduledSounds() throws {
    let b = RuntimeNodeBuilder()
    func get(_ block: Double, _ index: Double) -> Int {
      b.call("Get", [b.value(block), b.value(index)])
    }
    func set(_ block: Double, _ index: Double, _ value: Int) -> Int {
      b.call("Set", [b.value(block), b.value(index), value])
    }
    let preprocess = b.call("Execute", [
      set(2000, 0, get(1000, 2)),
      set(1000, 2, b.call("Add", [get(1000, 2), b.value(0.02)]))])
    let initialize = b.call("Execute", [
      b.call("Play", [b.value(8), b.value(0)]),
      b.call("PlayScheduled", [b.value(8), b.value(3), b.value(0)]),
      set(4000, 1, b.call("PlayLooped", [b.value(8)])),
      set(4000, 2, b.call("PlayLoopedScheduled", [b.value(8), b.value(4)])),
      b.call("StopLooped", [get(4000, 1)]),
      b.call("StopLoopedScheduled", [get(4000, 2), b.value(5)])])
    let engine = try b.engine(archetypes: [[
      "name": "Audio", "hasInput": false, "imports": [], "exports": [],
      "preprocess": ["index": preprocess], "initialize": ["index": initialize]]])
    let level = LevelData(bgmOffset: 0, entities: [
      LevelEntity(archetype: "Audio", name: nil, data: [])])
    for speed in [0.5, 1, 2] {
      for offset in [-0.25, 0, 0.25] {
        let runtime = try EnginePlayRuntime(engine: engine, level: level,
          options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [8],
          particleEffectIDs: [], playbackSpeed: speed, audioOffset: offset)
        let effective = offset + 0.02
        for _ in 0..<2 {
          XCTAssertEqual(runtime.memory.value(block: 2000, index: 0), offset)
          XCTAssertEqual(try runtime.audioOffset, effective)
          try runtime.update(at: 2)
          XCTAssertEqual(runtime.host.takeAudioCommands().map(\.time),
            [2, 3 - effective])
          XCTAssertEqual(runtime.host.takeLoopCommands(), [
            .start(id: 1, clipID: 8, time: 2),
            .start(id: 2, clipID: 8, time: 4 - effective),
            .stop(id: 1, time: 2), .stop(id: 2, time: 5 - effective)])
          runtime.restart()
        }
        runtime.memory.set(block: 1000, index: 2, value: .nan)
        XCTAssertThrowsError(try runtime.audioOffset)
        XCTAssertThrowsError(try runtime.update(at: 2))
        XCTAssertThrowsError(try runtime.host.call(function: "PlayScheduled",
          arguments: [8, 3, 0]))
      }
    }
    XCTAssertThrowsError(try EnginePlayRuntime(engine: engine, level: level,
      options: [], aspectRatio: 1, skinSpriteIDs: [], effectClipIDs: [8],
      particleEffectIDs: [], audioOffset: .infinity))
  }

  func testLoopedAudioCommandsHaveIndependentHandlesAndScheduledStops() throws {
    let host = makeHost()
    try host.beginFrame(at: 2)
    let first = try host.call(function: "PlayLooped", arguments: [8])
    let second = try host.call(function: "PlayLoopedScheduled", arguments: [8, 5])
    XCTAssertNotEqual(first, second)
    _ = try host.call(function: "StopLoopedScheduled", arguments: [second, 6])
    _ = try host.call(function: "StopLooped", arguments: [first])
    _ = try host.call(function: "StopLooped", arguments: [first])
    XCTAssertEqual(host.takeLoopCommands(), [
      .start(id: Int(first), clipID: 8, time: 2),
      .start(id: Int(second), clipID: 8, time: 5),
      .stop(id: Int(second), time: 6), .stop(id: Int(first), time: 2)
    ])
    XCTAssertTrue(host.takeLoopCommands().isEmpty)
    XCTAssertEqual(try host.call(function: "PlayLooped", arguments: [999]), 0)
    XCTAssertThrowsError(try host.call(function: "PlayLoopedScheduled",
      arguments: [8, .nan]))
    try host.beginFrame(at: 7)
    _ = try host.call(function: "StopLooped", arguments: [second])
    XCTAssertTrue(host.takeLoopCommands().isEmpty)
  }

  @MainActor
  func testStoppedLoopsReleaseCapacityWithinTheSameBatch() throws {
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      MockEffectVoice()
    }
    let commands = (1...257).flatMap { id -> [EngineLoopCommand] in
      [.start(id: id, clipID: 8, time: 0), .stop(id: id, time: 0)]
    }
    XCTAssertNoThrow(try audio.update([], at: 0, loopCommands: commands))
    let scheduled = (300..<556).flatMap { id -> [EngineLoopCommand] in
      [.start(id: id, clipID: 8, time: 10), .stop(id: id, time: 11)]
    }
    try audio.update([], at: 0, loopCommands: scheduled)
    XCTAssertNoThrow(try audio.update([], at: 11, loopCommands: [
      .start(id: 600, clipID: 8, time: 11)
    ]))
    audio.stop()
  }

  @MainActor
  func testLoopedPlaybackSchedulesStopsAndResumesAfterBuffering() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([], at: 0, loopCommands: [
      .start(id: 1, clipID: 8, time: 0),
      .start(id: 2, clipID: 8, time: 1), .stop(id: 2, time: 2)
    ])
    XCTAssertEqual(voices.filter(\.isPlaying).count, 1)
    let first = try XCTUnwrap(voices.first { $0.isPlaying })
    XCTAssertEqual(first.looping, [true])
    try audio.update([], at: 0.6)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 2)
    let second = try XCTUnwrap(voices.first { $0 !== first && $0.isPlaying })
    XCTAssertEqual(second.delays.last ?? -1, 0.4, accuracy: 0.000001)
    try audio.update([], at: 0.7, advancing: false)
    XCTAssertEqual(first.pauseCount, 1)
    XCTAssertEqual(first.stopCount, 0)
    XCTAssertEqual(second.stopCount, 1,
      "Only the not-yet-started loop must cancel its native reservation")
    try audio.update([], at: 0.7)
    XCTAssertEqual(first.resumeCount, 1)
    XCTAssertEqual(first.delays, [0], "An active loop must not restart")
    XCTAssertEqual(voices.filter(\.isPlaying).count, 2)
    try audio.update([], at: 1.6)
    XCTAssertTrue(voices.contains { abs(($0.stopDelays.last ?? -1) - 0.4) < 0.000001 })
    try audio.update([], at: 2.1)
    XCTAssertEqual(voices.filter(\.isPlaying).count, 1)
    try audio.update([], at: 2.1, loopCommands: [.stop(id: 1, time: 2.1)])
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    try audio.update([], at: 3, loopCommands: [
      .start(id: 3, clipID: 8, time: 5), .stop(id: 3, time: 4)
    ])
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    try audio.update([], at: 3, loopCommands: [.start(id: 4, clipID: 8, time: 3)])
    audio.stop()
    XCTAssertTrue(voices.allSatisfy { !$0.isPlaying })
    XCTAssertEqual(audio.allocatedVoiceCount, 8)
  }

  @MainActor
  func testAudioSeparationUsesPlaybackOrderAndClipIdentity() throws {
    let host = makeHost()
    try host.beginFrame(at: 1)
    _ = try host.call(function: "PlayScheduled", arguments: [8, 2, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [8, 0.1])
    _ = try host.call(function: "Play", arguments: [10, 0.1])
    _ = try host.call(function: "Play", arguments: [999, 0.1])
    var played = [EngineResourceID]()
    let audio = try EngineAudioPlayback(clips: [8: Data(), 10: Data()]) {
      id, _ in
      let voice = MockEffectVoice()
      voice.onPlay = { played.append(id) }
      return voice
    }
    try audio.update(host.takeAudioCommands(), at: 1)
    XCTAssertTrue(host.takeAudioCommands().isEmpty)
    XCTAssertEqual(played.sorted(), [8, 10],
      "A future clip must not suppress an earlier hit")
    try audio.update([], at: 1.4)
    XCTAssertEqual(played.count, 2)
    try audio.update([], at: 2)
    XCTAssertEqual(played.sorted(), [8, 8, 10])
    try audio.update([], at: 3)
    XCTAssertEqual(played.count, 3)
  }

  @MainActor
  func testZeroMinimumDistanceAcceptsEarlierTimedPlay() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([EngineAudioCommand(clipID: 1, time: 2,
      minimumDistance: 0)], at: 2)
    try audio.update([EngineAudioCommand(clipID: 1, time: 1.5,
      minimumDistance: 0)], at: 2)
    XCTAssertEqual(voices.flatMap(\.delays), [0, 0])
    // The earlier play must not rewind the history used for later distances.
    try audio.update([EngineAudioCommand(clipID: 1, time: 2.05,
      minimumDistance: 0.1)], at: 2.05)
    XCTAssertEqual(voices.flatMap(\.delays).count, 2)
    audio.stop()
  }

  @MainActor
  func testExhaustedEffectVoicesDropSoundsWithoutEndingPlay() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update(Array(repeating: EngineAudioCommand(clipID: 1,
      time: 0, minimumDistance: 0), count: 300), at: 0)
    XCTAssertEqual(audio.allocatedVoiceCount, 256)
    XCTAssertEqual(voices.flatMap(\.delays).count, 256)
    try audio.update([], at: 0,
      loopCommands: [.start(id: 1, clipID: 1, time: 0)])
    XCTAssertFalse(voices.flatMap(\.looping).contains(true),
      "A loop that finds no voice is dropped")
    // Finished voices are reused for later hits.
    for voice in voices { voice.isPlaying = false }
    try audio.update([EngineAudioCommand(clipID: 1, time: 1,
      minimumDistance: 0)], at: 1)
    XCTAssertEqual(voices.flatMap(\.delays).count, 257)
    XCTAssertEqual(audio.allocatedVoiceCount, 256)
    audio.stop()
  }

  @MainActor
  func testAudioPrewarmsAndReusesVoicesAcrossHitsAndRestart() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    XCTAssertEqual(voices.count, 8)
    for time in 0..<30 {
      try audio.update([EngineAudioCommand(clipID: 1,
        time: Double(time), minimumDistance: 0)], at: Double(time))
      for voice in voices { voice.isPlaying = false }
    }
    XCTAssertEqual(voices.count, 8, "Hits must reuse prewarmed decoders")
    XCTAssertEqual(voices.flatMap(\.delays).count, 30)
    audio.stop()
    try audio.update([EngineAudioCommand(clipID: 1,
      time: 0, minimumDistance: 0)], at: 0)
    XCTAssertEqual(voices.count, 8, "Restart must retain the prepared pool")
  }

  @MainActor
  func testSuppressedFutureAudioIsReconsideredAfterEarlierClipIsCancelled() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.25, minimumDistance: 0.25),
      EngineAudioCommand(clipID: 1, time: 0.375, minimumDistance: 0.25)
    ], at: 0)
    XCTAssertEqual(voices.flatMap(\.delays), [0.25])
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.125, minimumDistance: 0.25)
    ], at: 0.125)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 1)
    XCTAssertEqual(voices.flatMap(\.delays).sorted(), [0, 0.25, 0.25],
      "The later clip becomes valid after the middle clip is cancelled")
    try audio.update([], at: 0.375)
    XCTAssertEqual(voices.flatMap(\.delays).count, 3)
    audio.stop()
  }

  @MainActor
  func testScheduledVoicesRemainReservedAndRescheduleAfterBuffering() throws {
    var voices = [MockEffectVoice]()
    let audio = try EngineAudioPlayback(clips: [1: Data()]) { _, _ in
      let voice = MockEffectVoice()
      voices.append(voice)
      return voice
    }
    try audio.update([
      EngineAudioCommand(clipID: 1, time: 0.3, minimumDistance: 0),
      EngineAudioCommand(clipID: 1, time: 0.4, minimumDistance: 0)
    ], at: 0)
    XCTAssertEqual(voices.filter { !$0.delays.isEmpty }.count, 2)
    // A scheduled native player need not report isPlaying before it starts.
    for voice in voices { voice.isPlaying = false }
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.flatMap(\.delays).count, 2)
    try audio.update([], at: 0.1, advancing: false)
    XCTAssertEqual(voices.reduce(0) { $0 + $1.stopCount }, 2)
    try audio.update([], at: 0.1)
    XCTAssertEqual(voices.flatMap(\.delays).count, 4)
    XCTAssertEqual(audio.allocatedVoiceCount, 8)
    audio.stop()
  }

  @MainActor
  func testQueuedAudioCommandLimitIsCumulative() throws {
    let audio = try EngineAudioPlayback(clips: [8: Data()]) { _, _ in
      MockEffectVoice()
    }
    let command = EngineAudioCommand(clipID: 8, time: 100, minimumDistance: 0)
    try audio.update(Array(repeating: command, count: 16_384), at: 0)
    XCTAssertThrowsError(try audio.update([command], at: 0))
    // Due commands leave the queue even when voices run out.
    try audio.update([], at: 100)
    XCTAssertNoThrow(try audio.update([command], at: 100))
    audio.stop()
  }
}
