import XCTest
@testable import OpenRhythm

final class EngineHapticTests: EngineHostTestCase {
  @MainActor
  func testHapticPlayFailureRecoversWithoutAnOSCallback() {
    let backend = MockHapticBackend()
    var time = 10.0
    let playback = EngineHapticPlayback(makeBackend: { backend }, now: { time })
    playback.start()
    backend.failsPlay = true
    playback.play(.medium)
    XCTAssertFalse(playback.isPrepared)
    playback.play(.medium)
    XCTAssertEqual(backend.starts, 2)
    for _ in 0..<100 { playback.play(.medium) }
    XCTAssertEqual(backend.starts, 2)
    time = 11
    backend.failsPlay = false
    playback.play(.medium)
    XCTAssertEqual(backend.starts, 3)
    XCTAssertTrue(playback.isPrepared)
    XCTAssertEqual(backend.played, [.medium])
  }

  @MainActor
  func testHapticRecoveryIsBoundedAndRejectsPreviousSessionCallbacks() {
    let first = MockHapticBackend()
    let second = MockHapticBackend()
    var time = 10.0
    var session = 0
    let playback = EngineHapticPlayback(makeBackend: {
      session += 1
      return session == 1 ? first : second
    }, now: { time })
    playback.start()
    let staleCallback = first.interrupted
    XCTAssertEqual(first.starts, 1)
    first.interrupted?()
    XCTAssertFalse(playback.isPrepared)
    playback.play(.none)
    XCTAssertEqual(first.starts, 1, "No work for an engine's None request")
    playback.play(.heavy)
    XCTAssertEqual(first.starts, 2)
    XCTAssertEqual(first.played, [.heavy])
    XCTAssertTrue(playback.isPrepared)
    first.interrupted?()
    first.failsStart = true
    time = 11
    for _ in 0..<100 { playback.play(.long) }
    XCTAssertEqual(first.starts, 3, "Repeated failure must not retry every frame")
    time = 12
    first.failsStart = false
    playback.play(.long)
    XCTAssertEqual(first.starts, 4)
    XCTAssertEqual(first.played, [.heavy, .long])
    playback.start()
    XCTAssertEqual(first.stops, 1)
    staleCallback?()
    XCTAssertTrue(playback.isPrepared)
    playback.play(.light)
    XCTAssertEqual(second.starts, 1)
    XCTAssertEqual(second.played, [.light])
    playback.stop()
    staleCallback?()
    playback.play(.heavy)
    XCTAssertFalse(playback.isPrepared)
    XCTAssertEqual(second.stops, 1)
    XCTAssertEqual(second.played, [.light])
  }

  func testHapticContractAndChordCoalescing() {
    XCTAssertEqual((0...4).map { EngineHaptic(runtimeValue: Double($0)) },
      [.none, .light, .medium, .heavy, .long])
    for value in [-1.0, 1.5, 5, .nan, .infinity, 1e100] {
      XCTAssertEqual(EngineHaptic(runtimeValue: value), .none)
    }
    XCTAssertEqual(EngineHaptic.combined([]), .none)
    XCTAssertEqual(EngineHaptic.combined([.light, .medium, .heavy, .none]), .heavy)
    XCTAssertEqual(EngineHaptic.combined([.long, .heavy, .long]), .long)
    XCTAssertNil(EngineHaptic.none.parameters)
    XCTAssertLessThan(EngineHaptic.light.parameters!.intensity,
      EngineHaptic.medium.parameters!.intensity)
    XCTAssertLessThan(EngineHaptic.medium.parameters!.intensity,
      EngineHaptic.heavy.parameters!.intensity)
    XCTAssertEqual(EngineHaptic.heavy.parameters!.duration, 0)
    XCTAssertGreaterThan(EngineHaptic.long.parameters!.duration, 0)
  }

  @MainActor
  func testUnavailableHapticHardwareIsSafeAcrossRestart() {
    let playback = EngineHapticPlayback(hardwareAvailable: false)
    for _ in 0..<3 {
      playback.start()
      XCTAssertFalse(playback.isPrepared)
      for type in EngineHaptic.allCases { playback.play(type) }
      playback.stop()
      XCTAssertFalse(playback.isPrepared)
    }
  }
}

@MainActor
private final class MockHapticBackend: EngineHapticBackend {
  var interrupted: (() -> Void)?
  var starts = 0
  var stops = 0
  var played = [EngineHaptic]()
  var failsStart = false
  var failsPlay = false

  func start() throws {
    starts += 1
    if failsStart { throw EngineInterpreterError.operationLimitExceeded }
  }
  func play(_ type: EngineHaptic) throws {
    if failsPlay { throw EngineInterpreterError.operationLimitExceeded }
    played.append(type)
  }
  func stop() { stops += 1 }
}
