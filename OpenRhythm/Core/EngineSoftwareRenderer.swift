import UIKit

/// The fallback shares Metal's mesh, but owns coverage explicitly. Quartz
/// triangle clips include shared edges twice, which is wrong for alpha sprites.
/// Half-open coverage follows the standard top-left rasterization rule:
/// https://learn.microsoft.com/windows/win32/direct3d11/d3d10-graphics-programming-guide-rasterizer-stage-rules
@MainActor
enum EngineSoftwareRenderer {
  private struct Texture {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
      width = image.width
      height = image.height
      let width = width, height = height
      guard width > 0, height > 0, width <= 8192, height <= 8192,
        width * height <= 8_000_000 else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      var bytes = [UInt8](repeating: 0, count: width * height * 4)
      let decoded = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress,
          width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }
      guard decoded else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      self.bytes = bytes
    }

    func sample(u: Double, v: Double, linear: Bool) -> SIMD4<Double> {
      func texel(_ x: Int, _ y: Int) -> SIMD4<Double> {
        let index = (min(height - 1, max(0, y)) * width
          + min(width - 1, max(0, x))) * 4
        return SIMD4(Double(bytes[index]), Double(bytes[index + 1]),
          Double(bytes[index + 2]), Double(bytes[index + 3]))
      }
      let x = min(1, max(0, u)) * Double(width)
      let y = min(1, max(0, v)) * Double(height)
      if !linear { return texel(Int(x), Int(y)) }
      let left = Int(floor(x - 0.5))
      let top = Int(floor(y - 0.5))
      let a = x - 0.5 - Double(left)
      let b = y - 0.5 - Double(top)
      return (texel(left, top) * (1 - a) + texel(left + 1, top) * a) * (1 - b)
        + (texel(left, top + 1) * (1 - a) + texel(left + 1, top + 1) * a) * b
    }
  }

  private struct Vertex {
    let x: Double
    let y: Double
    let u: Double
    let v: Double
  }

  static func render(_ sprites: [EngineRenderSprite], size: CGSize,
    scale: Double = 1, pixelBudget: Int = 64_000_000) throws -> CGImage {
    let w = ceil(size.width * scale)
    let h = ceil(size.height * scale)
    guard w.isFinite, h.isFinite, w > 0, h > 0, w <= 16384, h <= 16384,
      w * h <= 8_000_000 else { throw EngineInterpreterError.operationLimitExceeded }
    let width = Int(w), height = Int(h)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    var textures = [ObjectIdentifier: Texture]()
    var textureBytes = 0
    var remaining = pixelBudget
    var vertexCount = 0
    for sprite in sprites {
      let mesh = EngineMetalRenderer.vertices(for: sprite, size: size)
      guard !mesh.isEmpty, let image = sprite.image.cgImage else { continue }
      guard mesh.count <= 1_000_000 - vertexCount else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      vertexCount += mesh.count
      let key = ObjectIdentifier(sprite.image)
      let texture: Texture
      if let cached = textures[key] { texture = cached }
      else {
        texture = try Texture(image)
        guard texture.bytes.count <= 128_000_000 - textureBytes else {
          throw EngineInterpreterError.operationLimitExceeded
        }
        textureBytes += texture.bytes.count
        textures[key] = texture
      }
      let vertices = mesh.map {
        // Shared endpoints snap identically onto a subpixel coverage grid.
        Vertex(x: ((Double($0.position.x) + 1) * w / 2 * 256).rounded() / 256,
          y: ((1 - Double($0.position.y)) * h / 2 * 256).rounded() / 256,
          u: Double($0.uv.x), v: Double($0.uv.y))
      }
      for index in stride(from: 0, to: vertices.count, by: 3) {
        let a = vertices[index]
        var b = vertices[index + 1], c = vertices[index + 2]
        func edge(_ a: Vertex, _ b: Vertex, _ x: Double, _ y: Double) -> Double {
          (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
        }
        var area = edge(a, b, c.x, c.y)
        guard area.isFinite, area != 0 else { continue }
        if area < 0 { swap(&b, &c); area = -area }
        let left = Int(max(0, min(w, floor(min(a.x, b.x, c.x)))))
        let right = Int(max(0, min(w, ceil(max(a.x, b.x, c.x)))))
        let top = Int(max(0, min(h, floor(min(a.y, b.y, c.y)))))
        let bottom = Int(max(0, min(h, ceil(max(a.y, b.y, c.y)))))
        let examined = (right - left) * (bottom - top)
        guard examined <= remaining else { throw EngineInterpreterError.operationLimitExceeded }
        remaining -= examined
        func includes(_ value: Double, from a: Vertex, to b: Vertex) -> Bool {
          value > 0 || (value == 0 && (b.y < a.y || (b.y == a.y && b.x > a.x)))
        }
        for y in top..<bottom {
          for x in left..<right {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let ea = edge(b, c, px, py), eb = edge(c, a, px, py), ec = edge(a, b, px, py)
            guard includes(ea, from: b, to: c), includes(eb, from: c, to: a),
              includes(ec, from: a, to: b) else { continue }
            let u = (ea * a.u + eb * b.u + ec * c.u) / area
            let v = (ea * a.v + eb * b.v + ec * c.v) / area
            let source = texture.sample(u: u, v: v, linear: sprite.interpolation)
              * min(1, max(0, sprite.alpha))
            let keep = 1 - source.w / 255
            let offset = (y * width + x) * 4
            for channel in 0..<4 {
              pixels[offset + channel] = UInt8(min(255, max(0,
                (source[channel] + Double(pixels[offset + channel]) * keep).rounded())))
            }
          }
        }
      }
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue:
          CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw EngineInterpreterError.operationLimitExceeded }
    return image
  }

  static func draw(_ sprites: [EngineRenderSprite], context: CGContext,
    size: CGSize, pixelBudget: Int = 64_000_000) throws {
    let scale = max(hypot(context.ctm.a, context.ctm.b), hypot(context.ctm.c, context.ctm.d))
    let image = try render(sprites, size: size, scale: scale, pixelBudget: pixelBudget)
    context.saveGState()
    defer { context.restoreGState() }
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: size))
  }
}
