import Foundation
import zlib

enum GzipDecoderError: LocalizedError {
  case initializationFailed(Int32)
  case decompressionFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .initializationFailed(let status):
      "Couldn’t initialize the gzip decoder (zlib status \(status))."
    case .decompressionFailed(let status):
      "Couldn’t decompress the resource (zlib status \(status))."
    }
  }
}

enum GzipDecoder {
  static func decompressIfNeeded(_ data: Data) throws -> Data {
    guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
      return data
    }
    return try decompress(data)
  }

  private static func decompress(_ data: Data) throws -> Data {
    var stream = z_stream()
    let initialization = inflateInit2_(
      &stream,
      MAX_WBITS + 16,
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
      repeat {
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        let written = try chunk.withUnsafeMutableBytes { output in
          stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(output.count)
          status = inflate(&stream, Z_NO_FLUSH)
          guard status == Z_OK || status == Z_STREAM_END else {
            throw GzipDecoderError.decompressionFailed(status)
          }
          return output.count - Int(stream.avail_out)
        }
        result.append(contentsOf: chunk.prefix(written))
      } while status != Z_STREAM_END

      return result
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
