import AVFoundation
import CoreFoundation
import CoreHaptics
import zlib

/// Serializes the process-wide session without blocking the main actor. Each
/// model owns one lease; an old model's cleanup cannot stop a newer model.
@MainActor
final class PlaybackAudioSession {
  static let shared = PlaybackAudioSession { active in
    let session = AVAudioSession.sharedInstance()
    if active { try session.setCategory(.playback) }
    try session.setActive(active)
  }

  private let queue = DispatchQueue(label: "OpenRhythm.AudioSession",
    qos: .userInitiated)
  private let worker: PlaybackAudioSessionWorker

  init(setActive: @escaping @Sendable (Bool) throws -> Void) {
    worker = PlaybackAudioSessionWorker(setActive: setActive)
  }

  func activate(owner: UUID) async throws {
    // Submission happens on the main actor before suspending. stop() submits
    // release synchronously to the same queue, so it cannot overtake this.
    try await withCheckedThrowingContinuation { continuation in
      let worker = worker
      queue.async {
        do {
          try worker.activate(owner: owner)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  nonisolated func release(owner: UUID) {
    let worker = worker
    queue.async { worker.release(owner: owner) }
  }
}

// All mutable state is confined to PlaybackAudioSession's serial queue.
private final class PlaybackAudioSessionWorker: @unchecked Sendable {
  private let setActive: @Sendable (Bool) throws -> Void
  private var owners = Set<UUID>()

  init(setActive: @escaping @Sendable (Bool) throws -> Void) {
    self.setActive = setActive
  }

  func activate(owner: UUID) throws {
    // Reassert activation even for an existing owner after an interruption.
    // A failed activation must not create a new lease.
    try setActive(true)
    owners.insert(owner)
  }

  func release(owner: UUID) {
    guard owners.remove(owner) != nil, owners.isEmpty else { return }
    do { try setActive(false) }
    catch {
      // Cleanup cannot restart playback. Preserve diagnostics rather than
      // swallowing a failure or retaining a dead owner's lease forever.
      NSLog("Audio session deactivation failed: %@", String(describing: error))
    }
  }
}

extension EngineHaptic {
  // The engine contract names strengths, not platform-specific waveforms.
  // Use short transients for impacts and a bounded continuous event for Long.
  var parameters: (intensity: Float, sharpness: Float, duration: Double)? {
    switch self {
    case .none: nil
    case .light: (0.35, 0.6, 0)
    case .medium: (0.65, 0.5, 0)
    case .heavy: (1, 0.4, 0)
    case .long: (0.65, 0.4, 0.15)
    }
  }
}

@MainActor
protocol EngineHapticBackend: AnyObject {
  var interrupted: (() -> Void)? { get set }
  func start() throws
  func play(_ type: EngineHaptic) throws
  func stop()
}

@MainActor
private final class NativeHapticBackend: EngineHapticBackend {
  var interrupted: (() -> Void)?
  private let engine: CHHapticEngine
  private var players = [EngineHaptic: any CHHapticPatternPlayer]()

  init() throws {
    engine = try CHHapticEngine()
    engine.playsHapticsOnly = true
    engine.isAutoShutdownEnabled = false
    engine.resetHandler = { [weak self] in
      Task { @MainActor in self?.interrupted?() }
    }
    engine.stoppedHandler = { [weak self] _ in
      Task { @MainActor in self?.interrupted?() }
    }
  }

  func start() throws {
    players.removeAll()
    try engine.start()
    for type in EngineHaptic.allCases {
      guard let values = type.parameters else { continue }
      let event = CHHapticEvent(eventType: values.duration > 0
        ? .hapticContinuous : .hapticTransient, parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: values.intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: values.sharpness)
        ], relativeTime: 0, duration: values.duration)
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      players[type] = try engine.makePlayer(with: pattern)
    }
  }

  func play(_ type: EngineHaptic) throws {
    // Prebuilt players bound work and allocation when a dense chord resolves.
    try players[type]?.start(atTime: CHHapticTimeImmediate)
  }

  func stop() {
    interrupted = nil
    players.removeAll()
    engine.resetHandler = {}
    engine.stoppedHandler = { _ in }
    engine.stop(completionHandler: nil)
  }
}

@MainActor
final class EngineHapticPlayback {
  private let makeBackend: @MainActor () -> (any EngineHapticBackend)?
  private let now: () -> Double
  private var backend: (any EngineHapticBackend)?
  private var needsRecovery = false
  private var lastRecovery = -Double.infinity
  var isPrepared: Bool { backend != nil && !needsRecovery }

  init(makeBackend: @escaping @MainActor () -> (any EngineHapticBackend)? = {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
    return try? NativeHapticBackend()
  }, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.makeBackend = makeBackend
    self.now = now
  }

  convenience init(hardwareAvailable: Bool) {
    self.init(makeBackend: { hardwareAvailable ? try? NativeHapticBackend() : nil })
  }

  func start() {
    stop()
    guard let backend = makeBackend() else { return }
    self.backend = backend
    backend.interrupted = { [weak self, weak backend] in
      guard let self, let backend, self.backend === backend else { return }
      self.needsRecovery = true
    }
    do { try backend.start() } catch {
      needsRecovery = true
      lastRecovery = now()
    }
  }

  func play(_ type: EngineHaptic) {
    guard type != .none, let backend else { return }
    if needsRecovery {
      let time = now()
      guard time.isFinite, time - lastRecovery >= 1 else { return }
      lastRecovery = time
      do {
        try backend.start()
        needsRecovery = false
      } catch { return }
    }
    do { try backend.play(type) } catch { needsRecovery = true }
  }

  func stop() {
    let previous = backend
    backend = nil
    needsRecovery = false
    lastRecovery = -.infinity
    previous?.interrupted = nil
    previous?.stop()
  }
}

/// Reads only named files into memory. Archive paths are never written to disk.
struct EffectAudioArchive {
  let files: [String: Data]

  init(data: Data) throws {
    let bytes = [UInt8](data)
    func integer(_ offset: Int, _ length: Int) throws -> Int {
      guard offset >= 0, offset <= bytes.count - length else {
        throw EngineInterpreterError.invalidArguments("audio archive bounds")
      }
      return (0..<length).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
    }
    guard bytes.count >= 22, bytes.count <= 64 * 1024 * 1024 else {
      throw EngineInterpreterError.invalidArguments("audio archive size")
    }
    guard let end = stride(
      from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1
    ).first(where: { offset in
      (try? integer(offset, 4)) == 0x06054b50
        && (try? integer(offset + 20, 2)) == bytes.count - offset - 22
    }), try integer(end + 4, 2) == 0, try integer(end + 6, 2) == 0 else {
      throw EngineInterpreterError.invalidArguments("audio archive directory")
    }
    let count = try integer(end + 10, 2)
    guard count <= 1024 else { throw EngineInterpreterError.operationLimitExceeded }
    var offset = try integer(end + 16, 4)
    var files = [String: Data]()
    var totalSize = 0
    for _ in 0..<count {
      guard try integer(offset, 4) == 0x02014b50,
        try integer(offset + 8, 2) & 1 == 0 else {
        throw EngineInterpreterError.invalidArguments("audio archive entry")
      }
      let flags = try integer(offset + 8, 2)
      let method = try integer(offset + 10, 2)
      let checksum = try integer(offset + 16, 4)
      let compressedSize = try integer(offset + 20, 4)
      let size = try integer(offset + 24, 4)
      let nameLength = try integer(offset + 28, 2)
      let extraLength = try integer(offset + 30, 2)
      let commentLength = try integer(offset + 32, 2)
      let local = try integer(offset + 42, 4)
      let nameStart = offset + 46
      let extraStart = nameStart + nameLength
      let extraEnd = extraStart + extraLength
      guard extraEnd + commentLength <= bytes.count,
        try integer(local, 4) == 0x04034b50,
        size <= 16 * 1024 * 1024, totalSize + size <= 64 * 1024 * 1024 else {
        throw EngineInterpreterError.invalidArguments("audio archive file")
      }
      let name = try Self.filename(bytes[nameStart..<extraStart], flags: flags,
        extra: bytes[extraStart..<extraEnd])
      guard files[name] == nil else {
        throw EngineInterpreterError.invalidArguments("duplicate audio filename")
      }
      let start = try local + 30 + integer(local + 26, 2) + integer(local + 28, 2)
      guard start <= bytes.count, compressedSize <= bytes.count - start else {
        throw EngineInterpreterError.invalidArguments("audio archive data")
      }
      let compressed = Data(bytes[start..<(start + compressedSize)])
      let decoded: Data
      switch method {
      case 0: decoded = compressed
      case 8:
        decoded = try GzipDecoder.decompress(
          compressed, windowBits: -MAX_WBITS, maximumSize: size
        )
      default:
        throw EngineInterpreterError.invalidArguments("audio archive compression")
      }
      let crc = decoded.withUnsafeBytes {
        crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
      }
      guard decoded.count == size, Int(crc) == checksum else {
        throw EngineInterpreterError.invalidArguments("audio archive checksum")
      }
      files[name] = decoded
      totalSize += size
      offset += 46 + nameLength + extraLength + commentLength
    }
    self.files = files
  }

  /// ZIP APPNOTE Appendix D and 4.6.9: the encoding flag and CRC-validated
  /// Unicode Path field determine names, independently of audio content.
  private static func filename(_ bytes: ArraySlice<UInt8>, flags: Int,
    extra: ArraySlice<UInt8>) throws -> String {
    let isUTF8 = flags & (1 << 11) != 0
    let cp437 = String.Encoding(rawValue:
      CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
    guard let headerName = String(bytes: bytes,
      encoding: isUTF8 ? .utf8 : cp437) else {
      throw EngineInterpreterError.invalidArguments("audio filename encoding")
    }
    let checksum = bytes.withUnsafeBufferPointer {
      crc32(0, $0.baseAddress, uInt($0.count))
    }
    var unicodeName: String?
    var offset = extra.startIndex
    while offset < extra.endIndex {
      guard extra.endIndex - offset >= 4 else {
        throw EngineInterpreterError.invalidArguments("audio ZIP extra field")
      }
      let tag = Int(extra[offset]) | Int(extra[offset + 1]) << 8
      let length = Int(extra[offset + 2]) | Int(extra[offset + 3]) << 8
      offset += 4
      guard length <= extra.endIndex - offset else {
        throw EngineInterpreterError.invalidArguments("audio ZIP extra bounds")
      }
      if tag == 0x7075, !isUTF8, length > 0, extra[offset] == 1 {
        guard length >= 5 else {
          throw EngineInterpreterError.invalidArguments("audio Unicode path")
        }
        let nameCRC = (0..<4).reduce(UInt32(0)) {
          $0 | UInt32(extra[offset + 1 + $1]) << ($1 * 8)
        }
        // A stale field belongs to an older name. Unknown versions are also
        // ignored, as required by the ZIP extension's compatibility rule.
        if nameCRC == checksum {
          guard let name = String(bytes: extra[(offset + 5)..<(offset + length)],
            encoding: .utf8), unicodeName == nil || unicodeName == name else {
            throw EngineInterpreterError.invalidArguments("audio Unicode path")
          }
          unicodeName = name
        }
      }
      offset += length
    }
    return unicodeName ?? headerName
  }
}

@MainActor
protocol EngineEffectVoice: AnyObject {
  var isPlaying: Bool { get }
  func play(after delay: Double, looped: Bool)
  func stop(after delay: Double)
  func stop()
  func pause()
  func resume()
}

@MainActor
final class NativeEffectVoice: EngineEffectVoice {
  private let native: ORPCMVoice
  var isPlaying: Bool { native.playing }

  init(engine: AVAudioEngine, buffer: AVAudioPCMBuffer) {
    native = ORPCMVoice(engine: engine, buffer: buffer)
  }

  func play(after delay: Double, looped: Bool) {
    native.play(after: delay, looped: looped)
  }

  func pause() { native.pause() }
  func resume() { native.resume() }
  func stop(after delay: Double) { native.stop(after: delay) }
  func stop() { native.stop() }
}

@MainActor
private final class NativeEffectBank {
  let engine = AVAudioEngine()
  private var buffers = [Int: AVAudioPCMBuffer]()
  private var voices = [NativeEffectVoice]()

  init(clips: [Int: Data]) throws {
    guard clips.count <= 256 else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenRhythmEffects-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var decodedBytes: UInt64 = 0
    for (id, data) in clips {
      // AVAudioFile decodes from a file, but gameplay retains only PCM memory.
      // Archive-supplied paths are never used, and staging files are removed.
      let url = directory.appendingPathComponent("\(id).audio")
      try data.write(to: url)
      let file = try AVAudioFile(forReading: url)
      guard file.length > 0, file.length <= 8_000_000,
        (1...2).contains(file.processingFormat.channelCount) else {
        throw EngineInterpreterError.invalidArguments("effect audio format")
      }
      decodedBytes += UInt64(file.length)
        * UInt64(file.processingFormat.channelCount) * 4
      guard decodedBytes <= 128 * 1024 * 1024,
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
          frameCapacity: AVAudioFrameCount(file.length)) else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      try file.read(into: buffer)
      buffers[id] = buffer
    }
  }

  func voice(for id: Int) throws -> any EngineEffectVoice {
    guard let buffer = buffers[id] else {
      throw EngineInterpreterError.invalidArguments("effect clip")
    }
    let voice = NativeEffectVoice(engine: engine, buffer: buffer)
    voices.append(voice)
    return voice
  }

  func start() throws {
    guard !buffers.isEmpty, !engine.isRunning else { return }
    engine.prepare()
    try engine.start()
  }
}

@MainActor
final class EngineAudioPlayback {
  private struct Loop {
    let clipID: Int
    let start: Double
    var end = Double.infinity
    var voice: (any EngineEffectVoice)?
    var scheduledEnd: Double?
  }
  private var loops = [Int: Loop]()
  private struct EffectData: Decodable {
    struct Clip: Decodable { let name: String; let filename: String }
    let clips: [Clip]
  }
  private struct Pending {
    let id: Int
    let command: EngineAudioCommand
  }
  let clipIDs: Set<Int>
  private let clips: [Int: Data]
  private let makeVoice: @MainActor (Int, Data) throws -> any EngineEffectVoice
  private var nativeBank: NativeEffectBank?
  private var available = [Int: [any EngineEffectVoice]]()
  private(set) var allocatedVoiceCount = 0
  private var pending = [Pending]()
  private var players = [Int: (clipID: Int, voice: any EngineEffectVoice)]()
  private var lastPlayed = [Int: Double]()
  private var nextID = 0
  private var isPaused = false
  private var pausedLoopCommands = [EngineLoopCommand]()

  convenience init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
    guard !engine.effect.clips.isEmpty else {
      try self.init(clips: [:])
      return
    }
    let data = try CompressedJSONDecoder.decode(
      EffectData.self, from: presentation.data("effectData")
    )
    let archive = try EffectAudioArchive(data: presentation.data("effectAudio"))
    var clips = [Int: Data]()
    for definition in engine.effect.clips {
      if let clip = data.clips.first(where: { $0.name == definition.name }),
        let bytes = archive.files[clip.filename] {
        clips[definition.id] = bytes
      }
    }
    try self.init(clips: clips)
  }

  init(clips: [Int: Data],
    makeVoice: @escaping @MainActor (Int, Data) throws -> any EngineEffectVoice
  ) throws {
    guard clips.count <= 256 else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    self.clips = clips
    self.makeVoice = makeVoice
    clipIDs = Set(clips.keys)
    // Warm overlapping voices before gameplay. Bound total allocation for
    // untrusted engines, while allowing a larger pool for unusual busy charts.
    let voicesPerClip = min(8, 256 / max(1, clips.count))
    for (id, bytes) in clips {
      available[id] = try (0..<voicesPerClip).map { _ in try makeVoice(id, bytes) }
      allocatedVoiceCount += voicesPerClip
    }
  }

  convenience init(clips: [Int: Data]) throws {
    let bank = try NativeEffectBank(clips: clips)
    try self.init(clips: clips, makeVoice: { id, _ in try bank.voice(for: id) })
    nativeBank = bank
  }

  func start() throws { try nativeBank?.start() }

  /// Freeze active samples, cancel wall-clock reservations, and retain the
  /// logical schedule. Resume only once the BGM clock is advancing again.
  func pause(at time: Double) {
    guard !isPaused else { return }
    isPaused = true
    var retained = [Pending]()
    for event in pending {
      if event.command.time <= time, players[event.id] != nil {
        // A reserved voice may have started since the last display update.
        // Promote it to active ownership instead of replaying its beginning.
        lastPlayed[event.command.clipID] = event.command.time
      } else {
        recycle(event.id, stop: true)
        retained.append(event)
      }
    }
    pending = retained
    for player in players.values { player.voice.pause() }
    for id in Array(loops.keys) {
      guard let loop = loops[id] else { continue }
      if loop.start > time { releaseLoopVoice(id) }
      else {
        loop.voice?.pause()
        loops[id]?.scheduledEnd = nil
      }
    }
    nativeBank?.engine.pause()
  }

  func update(
    _ commands: [EngineAudioCommand], at time: Double, advancing: Bool = true,
    loopCommands: [EngineLoopCommand] = [], currentTime: (() -> Double)? = nil
  ) throws {
    // Voice allocation, graph changes and earlier commands can take time.
    // Translate each deadline at publication, not from the batch's old sample.
    // Deterministic callers without a moving clock retain the supplied time.
    let readTime = { () throws -> Double in
      let value = currentTime?() ?? time
      guard value.isFinite else {
        throw EngineInterpreterError.invalidArguments("effect playback clock")
      }
      return value
    }
    guard loopCommands.count <= 16_384 - pausedLoopCommands.count else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    guard commands.count <= 16_384 - pending.count else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    // Buffering is a pause in the BGM timeline, not a fresh playback. Promote
    // reservations that already became due and freeze their sample positions;
    // only future reservations need cancellation and re-scheduling.
    if !advancing { pause(at: time) }
    let scheduled = Set(pending.map(\.id))
    for (id, player) in players where !scheduled.contains(id) && !player.voice.isPlaying {
      recycle(id)
    }
    for command in commands {
      pending.append(Pending(id: nextID, command: command))
      nextID += 1
    }
    pending.sort {
      $0.command.time == $1.command.time ? $0.id < $1.id
        : $0.command.time < $1.command.time
    }
    var effectiveLoopCommands = loopCommands
    if isPaused {
      pausedLoopCommands.append(contentsOf: loopCommands)
      guard advancing else { return }
      // Apply stopped/expired handles while voices are still silent. Resuming
      // first could briefly replay a loop whose stop arrived during the pause.
      try updateLoops(pausedLoopCommands, at: time, advancing: false,
        currentTime: readTime)
      pausedLoopCommands.removeAll(keepingCapacity: true)
      effectiveLoopCommands = []
      try nativeBank?.start()
      for player in players.values { player.voice.resume() }
      for id in Array(loops.keys) {
        guard let loop = loops[id], let voice = loop.voice else { continue }
        let now = try readTime()
        if loop.end <= now {
          removeFinishedLoop(id, at: now)
          continue
        }
        // Re-arm only after graph startup and other voices' resume work, but
        // before this voice can publish any unpaused samples.
        if loop.end <= now + 0.5 {
          voice.stop(after: loop.end - now)
          loops[id]?.scheduledEnd = loop.end
        }
        voice.resume()
      }
      isPaused = false
    }
    if let nativeBank, !nativeBank.engine.isRunning {
      // A route-format change can stop AVAudioEngine independently of BGM.
      // Reconcile native reservations and reschedule future commands after
      // restarting. An unavailable output throws into gameplay's error state.
      for id in Array(players.keys) { recycle(id, stop: true) }
      for id in Array(loops.keys) { releaseLoopVoice(id) }
      try nativeBank.start()
    }
    try updateLoops(effectiveLoopCommands, at: time, advancing: true,
      currentTime: readTime)
    var prior = lastPlayed
    var retained = [Pending]()
    for event in pending {
      let command = event.command
      let accepted = prior[command.clipID].map {
        command.time - $0 >= command.minimumDistance
      } ?? true
      guard accepted else {
        recycle(event.id, stop: true)
        if command.time > time { retained.append(event) }
        continue
      }
      prior[command.clipID] = command.time
      if players[event.id] == nil, command.time <= time + 0.5,
        let bytes = clips[command.clipID] {
        let voice: any EngineEffectVoice
        if let ready = available[command.clipID]?.popLast() {
          voice = ready
        } else {
          guard allocatedVoiceCount < 256 else {
            throw EngineInterpreterError.operationLimitExceeded
          }
          voice = try makeVoice(command.clipID, bytes)
          allocatedVoiceCount += 1
        }
        voice.play(after: max(0, command.time - (try readTime())), looped: false)
        players[event.id] = (command.clipID, voice)
      }
      if command.time <= time {
        lastPlayed[command.clipID] = command.time
      } else {
        retained.append(event)
      }
    }
    pending = retained
  }

  private func updateLoops(_ commands: [EngineLoopCommand], at time: Double,
    advancing: Bool, currentTime: () throws -> Double) throws {
    guard commands.count <= 16_384 else {
      throw EngineInterpreterError.operationLimitExceeded
    }
    // The host can reuse capacity as soon as a scheduled stop is reached.
    for id in Array(loops.keys) { removeFinishedLoop(id, at: time) }
    for command in commands {
      switch command {
      case .start(let id, let clipID, let start):
        guard clips[clipID] != nil else { continue }
        guard loops[id] == nil, loops.count < 256, start.isFinite else {
          throw EngineInterpreterError.invalidArguments("looped audio start")
        }
        loops[id] = Loop(clipID: clipID, start: start)
      case .stop(let id, let end):
        guard end.isFinite else {
          throw EngineInterpreterError.invalidArguments("looped audio stop")
        }
        guard let loop = loops[id], end < loop.end else { continue }
        loops[id]?.end = end
        removeFinishedLoop(id, at: time)
      }
    }
    for id in Array(loops.keys) {
      guard let loop = loops[id] else { continue }
      if loop.end <= time || loop.end <= loop.start {
        releaseLoopVoice(id)
        loops[id] = nil
        continue
      }
      if !advancing { continue }
      let now = try currentTime()
      if loop.end <= now {
        removeFinishedLoop(id, at: now)
        continue
      }
      if let voice = loop.voice, loop.end <= now + 0.5,
        loop.scheduledEnd != loop.end {
        voice.stop(after: loop.end - now)
        loops[id]?.scheduledEnd = loop.end
      }
      guard loop.voice == nil, loop.start <= now + 0.5,
        let bytes = clips[loop.clipID] else { continue }
      let voice: any EngineEffectVoice
      if let ready = available[loop.clipID]?.popLast() { voice = ready }
      else {
        guard allocatedVoiceCount < 256 else {
          throw EngineInterpreterError.operationLimitExceeded
        }
        voice = try makeVoice(loop.clipID, bytes)
        allocatedVoiceCount += 1
      }
      let startTime = try currentTime()
      guard loop.end > startTime else {
        available[loop.clipID, default: []].append(voice)
        loops[id] = nil
        continue
      }
      loops[id]?.voice = voice
      voice.play(after: max(0, loop.start - startTime), looped: true)
      let stopTime = try currentTime()
      if loop.end <= stopTime + 0.5 {
        voice.stop(after: max(0, loop.end - stopTime))
        loops[id]?.scheduledEnd = loop.end
      }
    }
  }

  private func removeFinishedLoop(_ id: Int, at time: Double) {
    guard let loop = loops[id],
      loop.end <= time || loop.end <= loop.start else { return }
    releaseLoopVoice(id)
    loops[id] = nil
  }

  private func releaseLoopVoice(_ id: Int) {
    guard let loop = loops[id], let voice = loop.voice else { return }
    voice.stop()
    available[loop.clipID, default: []].append(voice)
    loops[id]?.voice = nil
    loops[id]?.scheduledEnd = nil
  }

  private func recycle(_ id: Int, stop: Bool = false) {
    guard let player = players.removeValue(forKey: id) else { return }
    if stop { player.voice.stop() }
    available[player.clipID, default: []].append(player.voice)
  }

  func stop() {
    isPaused = false
    pausedLoopCommands.removeAll()
    for id in Array(loops.keys) { releaseLoopVoice(id) }
    loops.removeAll()
    for id in Array(players.keys) { recycle(id, stop: true) }
    pending.removeAll()
    lastPlayed.removeAll()
    nativeBank?.engine.pause()
  }
}
