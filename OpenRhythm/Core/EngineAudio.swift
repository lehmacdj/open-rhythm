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
final class EngineAudioPlayback {
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
  private var pending = [Pending]()
  private var players = [Int: AVAudioPlayer]()
  private var lastPlayed = [Int: Double]()
  private var nextID = 0

  init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
    let data = try CompressedJSONDecoder.decode(
      EffectData.self, from: presentation.data("effectData")
    )
    let archive = try EffectAudioArchive(data: presentation.data("effectAudio"))
    var clips = [Int: Data]()
    for definition in engine.effect.clips {
      if let clip = data.clips.first(where: { $0.name == definition.name }),
        let bytes = archive.files[clip.filename] {
        // Validate decodability during preparation, not on a hit's critical path.
        _ = try AVAudioPlayer(data: bytes)
        clips[definition.id] = bytes
      }
    }
    self.clips = clips
    clipIDs = Set(clips.keys)
  }

  func update(
    _ commands: [EngineAudioCommand], at time: Double, advancing: Bool = true
  ) throws {
    guard commands.count <= 16_384 - pending.count else {
      throw EngineInterpreterError.operationLimitExceeded
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
      for event in pending { players.removeValue(forKey: event.id)?.stop() }
      return
    }
    var prior = lastPlayed
    var retained = [Pending]()
    for event in pending {
      let command = event.command
      let accepted = prior[command.clipID].map {
        command.time - $0 >= command.minimumDistance
      } ?? true
      guard accepted else {
        players.removeValue(forKey: event.id)?.stop()
        continue
      }
      prior[command.clipID] = command.time
      if players[event.id] == nil, command.time <= time + 0.5,
        let bytes = clips[command.clipID] {
        let player = try AVAudioPlayer(data: bytes)
        player.prepareToPlay()
        player.play(atTime: player.deviceCurrentTime + max(0, command.time - time))
        players[event.id] = player
      }
      if command.time <= time {
        lastPlayed[command.clipID] = command.time
      } else {
        retained.append(event)
      }
    }
    pending = retained
    let scheduled = Set(pending.map(\.id))
    players = players.filter { scheduled.contains($0.key) || $0.value.isPlaying }
  }

  func stop() {
    for player in players.values { player.stop() }
    players.removeAll()
    pending.removeAll()
    lastPlayed.removeAll()
  }
}
