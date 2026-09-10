import AVFoundation
import zlib

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
      let method = try integer(offset + 10, 2)
      let checksum = try integer(offset + 16, 4)
      let compressedSize = try integer(offset + 20, 4)
      let size = try integer(offset + 24, 4)
      let nameLength = try integer(offset + 28, 2)
      let extraLength = try integer(offset + 30, 2)
      let commentLength = try integer(offset + 32, 2)
      let local = try integer(offset + 42, 4)
      guard offset + 46 + nameLength <= bytes.count,
        let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + nameLength)],
          encoding: .utf8), files[name] == nil,
        try integer(local, 4) == 0x04034b50,
        size <= 16 * 1024 * 1024, totalSize + size <= 64 * 1024 * 1024 else {
        throw EngineInterpreterError.invalidArguments("audio archive file")
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
}

@MainActor
protocol EngineEffectVoice: AnyObject {
  var isPlaying: Bool { get }
  func play(after delay: Double, looped: Bool)
  func stop(after delay: Double)
  func stop()
}

@MainActor
private final class NativeEffectVoice: EngineEffectVoice {
  private let player = AVAudioPlayerNode()
  private let buffer: AVAudioPCMBuffer
  private var generation = 0
  private var stopTask: Task<Void, Never>?
  private(set) var isPlaying = false

  init(engine: AVAudioEngine, buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
  }

  func play(after delay: Double, looped: Bool) {
    stopTask?.cancel()
    generation += 1
    let current = generation
    isPlaying = true
    let time = delay > 0 ? AVAudioTime(hostTime: mach_absolute_time()
      + AVAudioTime.hostTime(forSeconds: delay)) : nil
    player.scheduleBuffer(buffer, at: time, options: looped ? [.loops] : [],
      completionCallbackType: .dataPlayedBack) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.generation == current, !looped else { return }
        self.isPlaying = false
      }
    }
    start()
  }

  func start() { if !player.isPlaying { player.play() } }

  func stop(after delay: Double) {
    stopTask?.cancel()
    if delay <= 0 { stop(); return }
    let current = generation
    stopTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self, self.generation == current else { return }
      self.stop()
    }
  }

  func stop() {
    stopTask?.cancel()
    stopTask = nil
    generation += 1
    isPlaying = false
    player.stop()
  }
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
    for voice in voices { voice.start() }
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

  convenience init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
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

  func update(
    _ commands: [EngineAudioCommand], at time: Double, advancing: Bool = true,
    loopCommands: [EngineLoopCommand] = []
  ) throws {
    guard commands.count <= 16_384 - pending.count else {
      throw EngineInterpreterError.operationLimitExceeded
    }
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
    if !advancing {
      // Native audio clocks do not pause when AVPlayer buffers. Cancel future
      // starts and retain their commands until the BGM clock resumes.
      for event in pending { recycle(event.id, stop: true) }
      try updateLoops(loopCommands, at: time, advancing: false)
      return
    }
    if let nativeBank, !nativeBank.engine.isRunning {
      // A route-format change can stop AVAudioEngine independently of BGM.
      // Reconcile native reservations and reschedule future commands after
      // restarting. An unavailable output throws into gameplay's error state.
      for id in Array(players.keys) { recycle(id, stop: true) }
      for id in Array(loops.keys) { releaseLoopVoice(id) }
      try nativeBank.start()
    }
    try updateLoops(loopCommands, at: time, advancing: true)
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
        voice.play(after: max(0, command.time - time), looped: false)
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
    advancing: Bool) throws {
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
      if !advancing { releaseLoopVoice(id); continue }
      if let voice = loop.voice, loop.end <= time + 0.5,
        loop.scheduledEnd != loop.end {
        voice.stop(after: max(0, loop.end - time))
        loops[id]?.scheduledEnd = loop.end
      }
      guard loop.voice == nil, loop.start <= time + 0.5,
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
      voice.play(after: max(0, loop.start - time), looped: true)
      if loop.end <= time + 0.5 {
        voice.stop(after: max(0, loop.end - time))
        loops[id]?.scheduledEnd = loop.end
      }
      loops[id]?.voice = voice
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
    for id in Array(loops.keys) { releaseLoopVoice(id) }
    loops.removeAll()
    for id in Array(players.keys) { recycle(id, stop: true) }
    pending.removeAll()
    lastPlayed.removeAll()
    nativeBank?.engine.pause()
  }
}
