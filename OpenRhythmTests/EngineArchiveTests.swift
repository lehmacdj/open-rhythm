import XCTest
import zlib
@testable import OpenRhythm

final class EngineArchiveTests: EngineHostTestCase {
  func testEffectArchiveHonorsZIPFilenameEncodings() throws {
    let legacy = Data([0x63, 0x61, 0x66, 0x82, 0x2e, 0x77, 0x61, 0x76])
    let unicode = Data("音.wav".utf8)
    let payload = Data("hello".utf8)
    let cp437 = try EffectAudioArchive(data: namedEffectArchive([
      (legacy, 0, Data())]))
    XCTAssertEqual(cp437.files["café.wav"], payload)
    let ambiguous = try EffectAudioArchive(data: namedEffectArchive([
      (Data([0xc3, 0xa9]), 0, Data())]))
    XCTAssertEqual(ambiguous.files["├⌐"], payload,
      "Do not guess UTF-8 merely because legacy bytes are valid UTF-8")
    let utf8 = try EffectAudioArchive(data: namedEffectArchive([
      (unicode, 1 << 11, Data())]))
    XCTAssertEqual(utf8.files["音.wav"], payload)
    XCTAssertThrowsError(try EffectAudioArchive(data: namedEffectArchive([
      (legacy, 1 << 11, Data())])), "Flagged UTF-8 must be valid")
    XCTAssertThrowsError(try EffectAudioArchive(data: namedEffectArchive([
      (legacy, 0, Data()), (Data("café.wav".utf8), 1 << 11, Data())])),
      "Different byte encodings must not bypass duplicate-name rejection")
  }

  func testEffectArchiveHonorsValidatedUnicodePathExtraFields() throws {
    let name = Data("tone.wav".utf8)
    let unicode = Data("音.wav".utf8)
    let checksum = name.withUnsafeBytes {
      crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
    }
    // Unicode Path tag 0x7075, size, version, CRC of the original filename.
    let extra = Data([0x75, 0x70, UInt8(5 + unicode.count), 0, 1]
      + (0..<4).map { UInt8(truncatingIfNeeded: checksum >> ($0 * 8)) })
      + unicode
    let archive = try EffectAudioArchive(data: namedEffectArchive([(name, 0, extra)]))
    XCTAssertEqual(archive.files["音.wav"], Data("hello".utf8))
    XCTAssertNil(archive.files["tone.wav"])
    let unknown = Data([0xfe, 0xca, 1, 0, 0xa5])
    XCTAssertEqual(try EffectAudioArchive(data: namedEffectArchive([
      (name, 0, unknown + extra + extra)])).files["音.wav"], Data("hello".utf8))
    XCTAssertEqual(try EffectAudioArchive(data: namedEffectArchive([
      (name, 1 << 11, extra)])).files["tone.wav"], Data("hello".utf8),
      "The UTF-8 header flag takes precedence over redundant extra names")
    for index in [4, 5] { // Unknown version or stale filename CRC: use header.
      var ignored = extra
      ignored[index] ^= 0xff
      let fallback = try EffectAudioArchive(data:
        namedEffectArchive([(name, 0, ignored)]))
      XCTAssertEqual(fallback.files["tone.wav"], Data("hello".utf8))
    }
    var malformed = extra
    malformed[2] = 255
    XCTAssertThrowsError(try EffectAudioArchive(data:
      namedEffectArchive([(name, 0, malformed)])))
    for length in 1...3 {
      XCTAssertThrowsError(try EffectAudioArchive(data:
        namedEffectArchive([(name, 0, Data(extra.prefix(length)))])))
    }
    var invalidUnicode = extra
    invalidUnicode[9] = 0xff
    XCTAssertThrowsError(try EffectAudioArchive(data:
      namedEffectArchive([(name, 0, invalidUnicode)])))
    invalidUnicode[5] ^= 0xff
    XCTAssertEqual(try EffectAudioArchive(data: namedEffectArchive([
      (name, 0, invalidUnicode)])).files["tone.wav"], Data("hello".utf8),
      "Stale CRC means ignore the Unicode bytes without decoding them")
    var conflicting = extra
    conflicting[conflicting.count - 1] = UInt8(ascii: "x")
    XCTAssertThrowsError(try EffectAudioArchive(data:
      namedEffectArchive([(name, 0, extra + conflicting)])))
    XCTAssertThrowsError(try EffectAudioArchive(data: namedEffectArchive([
      (name, 0, extra), (unicode, 1 << 11, Data())])),
      "Unicode overrides also participate in duplicate-name checks")
  }

  func testEffectArchiveAcceptsBoundedZIP64DirectoriesAndEntryFields() throws {
    let entries = [(Data("one.wav".utf8), 0, Data()),
      (Data("音.wav".utf8), 1 << 11, Data())]
    // Each size/offset/disk sentinel is independent in the central header.
    for fields in 0...15 {
      for (zip64End, sentinels) in [(false, false), (true, false), (true, true)] {
        let data = namedEffectArchive(entries, zip64Fields: fields,
          zip64End: zip64End, zip64Sentinels: sentinels)
        let archive = try EffectAudioArchive(data: data)
        XCTAssertEqual(archive.files, ["one.wav": Data("hello".utf8),
          "音.wav": Data("hello".utf8)], "fields=\(fields), end=\(zip64End)")
      }
    }
    XCTAssertTrue(try EffectAudioArchive(data: namedEffectArchive([],
      zip64End: true)).files.isEmpty)
  }

  func testEffectArchiveRejectsMalformedZIP64WithoutIntegerOverflow() throws {
    let base = namedEffectArchive([(Data("one.wav".utf8), 0, Data())],
      zip64Fields: 15, zip64End: true)
    let end = base.count - 22
    let locator = end - 20
    let record = locator - 56
    let central = 30 + 7 + 20 + 5
    let extra = central + 46 + 7
    func altered(_ data: Data? = nil, at offset: Int, bytes: [UInt8]) -> Data {
      var changed = data ?? base
      changed.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
      return changed
    }
    // Exercise both unrepresentable UInt64s and Int.max, which is representable
    // but must be bounds-checked before any offset arithmetic or allocation.
    for bytes in [[UInt8](repeating: 0xff, count: 8),
      [UInt8](repeating: 0xff, count: 7) + [0x7f]] {
      for offset in [locator + 8, record + 4, record + 24, record + 32,
        record + 40, record + 48, extra + 4, extra + 12, extra + 20] {
        XCTAssertThrowsError(try EffectAudioArchive(data:
          altered(at: offset, bytes: bytes)), "offset=\(offset)")
      }
    }
    for (offset, bytes) in [
      (locator, [UInt8(0)]), // Missing required locator.
      (locator + 4, [1]), (locator + 16, [2]), // Multiple disks.
      (record + 16, [1]), (record + 20, [1]),
      (record + 4, [43]), (record + 24, [2]), // Bad length/count.
      (record + 48, [0]), // Directory must really contain the claimed entries.
      (extra, [2]), (extra + 2, [7]), // Missing/truncated required extension.
      (extra + 28, [1]) // Entry starts on another disk.
    ] {
      XCTAssertThrowsError(try EffectAudioArchive(data:
        altered(at: offset, bytes: bytes)), "offset=\(offset)")
    }
    let ordinaryFields = namedEffectArchive([
      (Data("one.wav".utf8), 0, Data())], zip64End: true,
      zip64Sentinels: false)
    XCTAssertThrowsError(try EffectAudioArchive(data: altered(ordinaryFields,
      at: ordinaryFields.count - 22 + 10, bytes: [2, 0])),
      "Unsaturated legacy counts cannot contradict ZIP64")
    var tooMany = altered(at: record + 24, bytes: [1, 4])
    tooMany = altered(tooMany, at: record + 32, bytes: [1, 4])
    XCTAssertThrowsError(try EffectAudioArchive(data: tooMany),
      "ZIP64 must not bypass the 1024-entry budget") {
      XCTAssertTrue($0.localizedDescription.contains("audio archive entries"))
      XCTAssertFalse($0.localizedDescription.contains("callback"))
    }
    XCTAssertThrowsError(try EffectAudioArchive(data: altered(
      at: extra + 4, bytes: [1, 0, 0, 1, 0, 0, 0, 0])),
      "ZIP64 must not bypass the 16 MiB per-entry budget")
    // Too-small directory spans, local data inside the directory, and redundant
    // extension fields cannot turn a bounds check into cross-record parsing.
    XCTAssertThrowsError(try EffectAudioArchive(data: altered(
      at: record + 40, bytes: [45, 0, 0, 0, 0, 0, 0, 0])))
    XCTAssertThrowsError(try EffectAudioArchive(data: altered(
      at: extra + 20, bytes: [UInt8(central), 0, 0, 0, 0, 0, 0, 0])))
    let redundant = namedEffectArchive([
      (Data("one.wav".utf8), 0, Data([1, 0, 0, 0]))], zip64Fields: 15)
    XCTAssertThrowsError(try EffectAudioArchive(data: redundant))
    for length in 0..<base.count {
      XCTAssertThrowsError(try EffectAudioArchive(data: Data(base.prefix(length))),
        "truncated at \(length)")
    }
  }

  func testEffectArchiveReadsIndependentPythonZIP64DeflateFixture() throws {
    // Python stdlib zipfile, ZIP64_LIMIT=0, ZIP_DEFLATED, 2020-01-01 timestamp;
    // independently reopened with zipfile and verified to contain b'hello'.
    let encoded = "UEsDBC0AAAgIAAAAIVCGphA2//////////8HABQA6Z+zLndhdgEAEAAFAAAAAAAA"
      + "AAcAAAAAAAAAy0jNyckHAFBLAQItAy0AAAgIAAAAIVCGphA2//////////8HABQAAAAAAAAA"
      + "AACAAQAAAADpn7Mud2F2AQAQAAUAAAAAAAAABwAAAAAAAABQSwYGLAAAAAAAAAAtAC0AAAAA"
      + "AAAAAAABAAAAAAAAAAEAAAAAAAAASQAAAAAAAABAAAAAAAAAAFBLBgcAAAAAiQAAAAAAAAAB"
      + "AAAAUEsFBgAAAAABAAEASQAAAEAAAAAAAA=="
    let data = try XCTUnwrap(Data(base64Encoded: encoded))
    XCTAssertEqual(data.count, 235)
    XCTAssertEqual(try EffectAudioArchive(data: data).files,
      ["音.wav": Data("hello".utf8)])
    // The same writer on a nonseekable stream uses bit 3 and a ZIP64 data
    // descriptor after the compressed payload, instead of patching its header.
    let streamed = "UEsDBC0ACAgIAAAAIVAAAAAA//////////8HABQA6Z+zLndhdgEAEAAAAAAAAAAA"
      + "AAAAAAAAAAAAy0jNyckHAFBLBwiGphA2BwAAAAAAAAAFAAAAAAAAAFBLAQItAy0ACAgIAAAA"
      + "IVCGphA2//////////8HABQAAAAAAAAAAACAAQAAAADpn7Mud2F2AQAQAAUAAAAAAAAABwAA"
      + "AAAAAABQSwYGLAAAAAAAAAAtAC0AAAAAAAAAAAABAAAAAAAAAAEAAAAAAAAASQAAAAAAAABY"
      + "AAAAAAAAAFBLBgcAAAAAoQAAAAAAAAABAAAAUEsFBgAAAAABAAEASQAAAFgAAAAAAA=="
    let streamedData = try XCTUnwrap(Data(base64Encoded: streamed))
    XCTAssertEqual(streamedData.count, 259)
    XCTAssertEqual(try EffectAudioArchive(data: streamedData).files,
      ["音.wav": Data("hello".utf8)])
  }

  func testEffectArchiveAcceptsZIP64ExtensibleRecordsAndMixedSentinels() throws {
    let base = namedEffectArchive([(Data("tone.wav".utf8), 0, Data())],
      zip64End: true, zip64Sentinels: false,
      zip64Extensible: Data([0x34, 0x12, 1, 0, 0, 0, 0xab]),
      directorySignature: Data([0x12, 0x34]), comment: Data("comment".utf8))
    let end = base.count - 22 - 7
    let fields = [(4, 2), (6, 2), (8, 2), (10, 2), (12, 4), (16, 4)]
    for mask in 0..<64 {
      var data = base
      for (index, field) in fields.enumerated() where mask & (1 << index) != 0 {
        data.replaceSubrange((end + field.0)..<(end + field.0 + field.1),
          with: [UInt8](repeating: 0xff, count: field.1))
      }
      XCTAssertEqual(try EffectAudioArchive(data: data).files,
        ["tone.wav": Data("hello".utf8)], "mask=\(mask)")
    }
  }

  /// A stored ZIP with independent local/central records and raw name bytes.
  private func namedEffectArchive(_ entries: [(Data, Int, Data)],
    zip64Fields: Int = 0, zip64End: Bool = false,
    zip64Sentinels: Bool = true, zip64Extensible: Data = Data(),
    directorySignature: Data? = nil, comment: Data = Data()) -> Data {
    var result = Data()
    var directory = Data()
    func append(_ value: Int, bytes: Int, to data: inout Data) {
      data.append(contentsOf: (0..<bytes).map {
        UInt8(truncatingIfNeeded: value >> ($0 * 8))
      })
    }
    let payload = Data("hello".utf8)
    let checksum = payload.withUnsafeBytes {
      crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
    }
    for (name, flags, extra) in entries {
      let local = result.count
      var localExtra = extra
      if zip64Fields & 3 != 0 {
        append(1, bytes: 2, to: &localExtra)
        append(16, bytes: 2, to: &localExtra)
        append(payload.count, bytes: 8, to: &localExtra)
        append(payload.count, bytes: 8, to: &localExtra)
      }
      var centralExtra = extra
      if zip64Fields != 0 {
        var extended = Data()
        for (bit, value, length) in [(1, payload.count, 8),
          (2, payload.count, 8), (4, local, 8), (8, 0, 4)]
          where zip64Fields & bit != 0 {
          append(value, bytes: length, to: &extended)
        }
        append(1, bytes: 2, to: &centralExtra)
        append(extended.count, bytes: 2, to: &centralExtra)
        centralExtra.append(extended)
      }
      append(0x04034b50, bytes: 4, to: &result)
      for value in [zip64Fields == 0 ? 20 : 45, flags, 0, 0, 0] {
        append(value, bytes: 2, to: &result)
      }
      let localSize = zip64Fields & 3 == 0 ? payload.count : 0xffff_ffff
      for value in [Int(checksum), localSize, localSize] {
        append(value, bytes: 4, to: &result)
      }
      append(name.count, bytes: 2, to: &result)
      append(localExtra.count, bytes: 2, to: &result)
      result.append(name)
      result.append(localExtra)
      result.append(payload)
      append(0x02014b50, bytes: 4, to: &directory)
      let version = zip64Fields == 0 ? 20 : 45
      for value in [version, version, flags, 0, 0, 0] {
        append(value, bytes: 2, to: &directory)
      }
      for value in [Int(checksum),
        zip64Fields & 2 == 0 ? payload.count : 0xffff_ffff,
        zip64Fields & 1 == 0 ? payload.count : 0xffff_ffff] {
        append(value, bytes: 4, to: &directory)
      }
      for value in [name.count, centralExtra.count, 0,
        zip64Fields & 8 == 0 ? 0 : 0xffff, 0] {
        append(value, bytes: 2, to: &directory)
      }
      append(0, bytes: 4, to: &directory)
      append(zip64Fields & 4 == 0 ? local : 0xffff_ffff,
        bytes: 4, to: &directory)
      directory.append(name)
      directory.append(centralExtra)
    }
    if let directorySignature {
      append(0x05054b50, bytes: 4, to: &directory)
      append(directorySignature.count, bytes: 2, to: &directory)
      directory.append(directorySignature)
    }
    let directoryStart = result.count
    result.append(directory)
    if zip64End {
      let end = result.count
      append(0x06064b50, bytes: 4, to: &result)
      append(44 + zip64Extensible.count, bytes: 8, to: &result)
      for value in [45, 45] { append(value, bytes: 2, to: &result) }
      for value in [0, 0] { append(value, bytes: 4, to: &result) }
      for value in [entries.count, entries.count, directory.count, directoryStart] {
        append(value, bytes: 8, to: &result)
      }
      result.append(zip64Extensible)
      append(0x07064b50, bytes: 4, to: &result)
      append(0, bytes: 4, to: &result)
      append(end, bytes: 8, to: &result)
      append(1, bytes: 4, to: &result)
    }
    append(0x06054b50, bytes: 4, to: &result)
    let count = zip64End && zip64Sentinels ? 0xffff : entries.count
    for value in [0, 0, count, count] {
      append(value, bytes: 2, to: &result)
    }
    append(zip64End && zip64Sentinels ? 0xffff_ffff : directory.count,
      bytes: 4, to: &result)
    append(zip64End && zip64Sentinels ? 0xffff_ffff : directoryStart,
      bytes: 4, to: &result)
    append(comment.count, bytes: 2, to: &result)
    result.append(comment)
    return result
  }

  func testArchiveValidatesBoundsChecksumAndCompressionLimits() throws {
    let encoded = "UEsDBBQAAAAAAAAAAACGphA2BQAAAAUAAAAIAAAAdG9uZS50eHRoZWxs"
      + "b1BLAQIUABQAAAAAAAAAAACGphA2BQAAAAUAAAAIAAAAAAAAAAAAAAAAAAAAAAB0"
      + "b25lLnR4dFBLBQYAAAAAAQABADYAAAArAAAAAAA="
    let data = try XCTUnwrap(Data(base64Encoded: encoded))
    let archive = try EffectAudioArchive(data: data)
    XCTAssertEqual(archive.files["tone.txt"], Data("hello".utf8))
    for length in [0, 10, 21, data.count - 1] {
      XCTAssertThrowsError(try EffectAudioArchive(data: data.prefix(length)))
    }
    var corrupt = data
    corrupt[38] ^= 0xff
    XCTAssertThrowsError(try EffectAudioArchive(data: corrupt))
    let compressed = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAAA8tIzcnJBwCGphA2BQAAAA=="))
    XCTAssertEqual(try GzipDecoder.decompress(compressed), Data("hello".utf8))
    XCTAssertThrowsError(try GzipDecoder.decompress(compressed, maximumSize: 4))
  }

  func testGzipErrorsDescribeTheFailureAndKeepTheZlibStatus() throws {
    let member = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/8tIzcnJBwCGphA2BQAAAA=="))
    func message(_ data: Data, maximumSize: Int = 1024) -> String {
      do {
        _ = try GzipDecoder.decompress(data, maximumSize: maximumSize)
        return "no error"
      } catch { return error.localizedDescription }
    }
    XCTAssertEqual(message(member, maximumSize: 4),
      "The resource is too large to decompress (limit 4 bytes).")
    var corrupt = member
    corrupt[2] ^= 0xff
    XCTAssertEqual(message(corrupt),
      "The compressed resource is corrupt (zlib status \(Z_DATA_ERROR)).")
    XCTAssertEqual(message(member.prefix(member.count - 4)),
      "The compressed resource is truncated (zlib status \(Z_BUF_ERROR)).")
  }

  func testGzipConcatenatedMembersPreserveAllResourceData() throws {
    // Independent fixtures generated with Python's gzip.compress(mtime=0).
    let hello = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/8tIzcnJBwCGphA2BQAAAA=="))
    let world = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/yvPL8pJAQBDEXc6BQAAAA=="))
    let empty = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/wMAAAAAAAAAAAA="))
    XCTAssertEqual(try GzipDecoder.decompress(empty + hello + empty + world),
      Data("helloworld".utf8))
    let start = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/6tWSkrP9U9LK04tUbIy0AEA4bCqmw8AAAA="))
    let end = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/1NKzSvJLMlMLVayio6tBQAuowsfDgAAAA=="))
    let level = try CompressedJSONDecoder.decode(LevelData.self,
      from: start + end)
    XCTAssertEqual(level.bgmOffset, 0)
    XCTAssertTrue(level.entities.isEmpty)
  }

  func testGzipValidatesEveryMemberAndRejectsTrailingGarbage() throws {
    let member = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/8tIzcnJBwCGphA2BQAAAA=="))
    for length in 1..<member.count {
      XCTAssertThrowsError(try GzipDecoder.decompress(member + member.prefix(length)),
        "Truncated second member at \(length)")
    }
    for offset in [2, 3, member.count - 8, member.count - 4] {
      var corrupt = member
      corrupt[offset] ^= 0xff
      XCTAssertThrowsError(try GzipDecoder.decompress(member + corrupt),
        "Invalid second member at \(offset)")
    }
    XCTAssertThrowsError(try GzipDecoder.decompress(member + Data([0xff])))
  }

  func testGzipMembersPreserveROMAndWrapperBoundaries() throws {
    let first = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/2NgWGAPAMhOJTkEAAAA"))
    let second = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/2NgUDgAAA45pC8EAAAA"))
    let memory = EngineMemory()
    try memory.loadROM(first + second)
    XCTAssertEqual(memory.value(block: 3000, index: 0), 1.25)
    XCTAssertEqual(memory.value(block: 3000, index: 1), -2.5)
    let expanded = try GzipDecoder.decompress(first + second)
    XCTAssertEqual(try GzipDecoder.decompress(first + second,
      windowBits: MAX_WBITS + 32), expanded)
    // Data slices can retain a nonzero startIndex; magic detection must not
    // subscript absolute indices 0 and 1.
    let slice = (Data([0xff]) + first + second).dropFirst()
    XCTAssertEqual(try GzipDecoder.decompressIfNeeded(slice), expanded)
    XCTAssertEqual(try GzipDecoder.decompressIfNeeded(Data("plain".utf8)),
      Data("plain".utf8))
    let raw = try XCTUnwrap(Data(base64Encoded: "y0jNyckHAA=="))
    XCTAssertEqual(try GzipDecoder.decompress(raw, windowBits: -MAX_WBITS),
      Data("hello".utf8))
    let empty = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/wMAAAAAAAAAAAA="))
    XCTAssertEqual(try GzipDecoder.decompress(empty + empty, maximumSize: 0), Data())
    XCTAssertThrowsError(try GzipDecoder.decompress(empty, maximumSize: -1))
    // Auto-detection must not permit a non-gzip wrapper as the next member.
    XCTAssertThrowsError(try GzipDecoder.decompress(first + raw,
      windowBits: MAX_WBITS + 32))
  }

  func testGzipSizeBudgetAppliesAcrossMembersAndOutputChunks() throws {
    let member = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/8tIzcnJBwCGphA2BQAAAA=="))
    XCTAssertEqual(try GzipDecoder.decompress(member + member, maximumSize: 10),
      Data("hellohello".utf8))
    XCTAssertThrowsError(try GzipDecoder.decompress(member + member, maximumSize: 9))
    let chunk = try XCTUnwrap(Data(base64Encoded:
      "H4sIAAAAAAAC/+3BAQEAAACAkNvN7wgKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      + "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAappYtCwAAAEA"))
    XCTAssertEqual(try GzipDecoder.decompress(chunk + member,
      maximumSize: 65_541), Data(repeating: 120, count: 65_536) + Data("hello".utf8))
    XCTAssertThrowsError(try GzipDecoder.decompress(chunk + member,
      maximumSize: 65_540))
  }
}
