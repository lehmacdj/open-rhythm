import Foundation
import zlib

enum GzipDecoderError: LocalizedError {
  case initializationFailed(Int32)
  case decompressionFailed(Int32)
  /// Input or output exceeds this many bytes.
  case sizeLimitExceeded(Int)

  var errorDescription: String? {
    switch self {
    case .initializationFailed(let status):
      let reason = status == Z_MEM_ERROR ? " because memory ran out" : ""
      return "Couldn’t initialize the gzip decoder\(reason) "
        + "(zlib status \(status))."
    case .decompressionFailed(let status):
      let summary = switch status {
      case Z_DATA_ERROR: "The compressed resource is corrupt"
      case Z_BUF_ERROR: "The compressed resource is truncated"
      case Z_MEM_ERROR: "Memory ran out while decompressing the resource"
      default: "Couldn’t decompress the resource"
      }
      return "\(summary) (zlib status \(status))."
    case .sizeLimitExceeded(let limit):
      return "The resource is too large to decompress "
        + "(limit \(limit) bytes)."
    }
  }
}

enum GzipDecoder {
  static func decompressIfNeeded(_ data: Data) throws -> Data {
    guard data.starts(with: [0x1f, 0x8b]) else {
      return data
    }
    return try decompress(data)
  }

  static func decompress(
    _ data: Data, windowBits: Int32 = MAX_WBITS + 16,
    maximumSize: Int = 64 * 1024 * 1024
  ) throws -> Data {
    guard data.count <= Int(UInt32.max) else {
      throw GzipDecoderError.sizeLimitExceeded(Int(UInt32.max))
    }
    guard maximumSize >= 0 else {
      throw GzipDecoderError.sizeLimitExceeded(maximumSize)
    }
    var stream = z_stream()
    let initialization = inflateInit2_(
      &stream,
      windowBits,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initialization == Z_OK else {
      throw GzipDecoderError.initializationFailed(initialization)
    }
    defer { inflateEnd(&stream) }

    return try data.withUnsafeBytes { input in
      stream.next_in = UnsafeMutablePointer<Bytef>(
        mutating: input.bindMemory(to: Bytef.self).baseAddress
      )
      stream.avail_in = uInt(input.count)

      var result = Data()
      var status = Z_OK
      let chunkSize = 64 * 1024
      var chunk = [UInt8](repeating: 0, count: chunkSize)
      // RFC 1952 permits a series of gzip members. inflate stops after one;
      // reset its member state while retaining the cumulative output budget.
      // ZIP entries use raw DEFLATE and must not take this gzip-only path.
      let concatenated = windowBits > MAX_WBITS
        && data.starts(with: [0x1f, 0x8b])
      while true {
        let written = try chunk.withUnsafeMutableBytes { output in
          stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(output.count)
          status = inflate(&stream, Z_NO_FLUSH)
          guard status == Z_OK || status == Z_STREAM_END else {
            throw GzipDecoderError.decompressionFailed(status)
          }
          return output.count - Int(stream.avail_out)
        }
        guard written <= maximumSize - result.count else {
          throw GzipDecoderError.sizeLimitExceeded(maximumSize)
        }
        result.append(contentsOf: chunk.prefix(written))
        guard status == Z_STREAM_END else { continue }
        guard concatenated, stream.avail_in > 0 else { return result }
        // Do not silently accept a truncated member, garbage, or a zlib
        // wrapper following a valid gzip member (even in auto-detect mode).
        guard stream.avail_in >= 2, let next = stream.next_in,
          next[0] == 0x1f, next[1] == 0x8b else {
          throw GzipDecoderError.decompressionFailed(Z_DATA_ERROR)
        }
        let remaining = stream.avail_in
        let reset = inflateReset(&stream)
        guard reset == Z_OK else {
          throw GzipDecoderError.decompressionFailed(reset)
        }
        stream.next_in = next
        stream.avail_in = remaining
      }
    }
  }
}

enum CompressedJSONDecoder {
  static func decode<Value: Decodable>(
    _ type: Value.Type,
    from data: Data,
    decoder: JSONDecoder = JSONDecoder()
  ) throws -> Value {
    try decoder.decode(type, from: GzipDecoder.decompressIfNeeded(data))
  }
}
