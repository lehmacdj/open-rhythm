import UIKit

typealias EngineExpression = [String: Double]
typealias EngineQuadTransform = [String: EngineExpression]

struct EngineConfiguration: Decodable {
  struct Option: Decodable { let def: Double }
  let options: [Option]
}

struct SkinData: Decodable {
  struct Sprite: Decodable {
    let name: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let transform: EngineQuadTransform
  }
  let width: Int
  let height: Int
  let interpolation: Bool
  let sprites: [Sprite]
}

struct ParticleData: Decodable {
  struct Sprite: Decodable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
  }
  struct Effect: Decodable {
    let name: String
    let transform: EngineQuadTransform
    let groups: [Group]
  }
  struct Group: Decodable {
    let count: Int
    let particles: [Particle]
  }
  struct Particle: Decodable {
    let sprite: Int
    let color: String
    let start: Double
    let duration: Double
    let x: Property
    let y: Property
    let w: Property
    let h: Property
    let r: Property
    let a: Property
  }
  struct Property: Decodable {
    let from: EngineExpression?
    let to: EngineExpression?
    let ease: String?

    func value(at time: Double, variables: EngineExpression) -> Double {
      let start = EngineGeometry.evaluate(from ?? [:], variables)
      let end = EngineGeometry.evaluate(to ?? [:], variables)
      return start + (end - start) * EngineEasing.value(ease ?? "linear", time)
    }
  }
  let width: Int
  let height: Int
  let interpolation: Bool
  let sprites: [Sprite]
  let effects: [Effect]
}

enum EngineGeometry {
  static func evaluate(_ expression: EngineExpression, _ values: EngineExpression)
    -> Double {
    expression.reduce(0) { $0 + $1.value * values[$1.key, default: 0] }
  }

  static func transformed(
    _ points: [EnginePoint], by transform: EngineQuadTransform,
    variables: EngineExpression = [:]
  ) -> [EnginePoint] {
    var values = variables
    for (index, point) in points.enumerated() {
      values["x\(index + 1)"] = point.x
      values["y\(index + 1)"] = point.y
    }
    return (1...4).map {
      EnginePoint(
        x: evaluate(transform["x\($0)"] ?? [:], values),
        y: evaluate(transform["y\($0)"] ?? [:], values)
      )
    }
  }

  static func screenPoint(
    _ point: EnginePoint, matrix: [Double], size: CGSize
  ) -> CGPoint {
    let x = matrix[0] * point.x + matrix[1] * point.y + matrix[3]
    let y = matrix[4] * point.x + matrix[5] * point.y + matrix[7]
    let w = matrix[12] * point.x + matrix[13] * point.y + matrix[15]
    return CGPoint(
      x: size.width / 2 + x / w * size.height / 2,
      y: size.height / 2 - y / w * size.height / 2
    )
  }

  static func bilinear(_ points: [EnginePoint], u: Double, v: Double)
    -> EnginePoint {
    let weights = [(1-u)*(1-v), (1-u)*v, u*v, u*(1-v)]
    return EnginePoint(
      x: zip(points, weights).reduce(0) { $0 + $1.0.x * $1.1 },
      y: zip(points, weights).reduce(0) { $0 + $1.0.y * $1.1 }
    )
  }

  static func randomVariables(seed: UInt64) -> EngineExpression {
    var state = seed
    var values: EngineExpression = ["c": 1]
    for index in 1...8 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let value = Double(state >> 11) / 9_007_199_254_740_992
      values["r\(index)"] = value
      values["sinr\(index)"] = sin(2 * .pi * value)
      values["cosr\(index)"] = cos(2 * .pi * value)
    }
    return values
  }
}

enum EngineEasing {
  static func value(_ name: String, _ time: Double) -> Double {
    let t = min(1, max(0, time))
    if name == "none" { return 0 }
    if name == "linear" { return t }
    for mode in ["inOut", "outIn", "in", "out"] where name.hasPrefix(mode) {
      let curve = String(name.dropFirst(mode.count))
      switch mode {
      case "in": return inward(curve, t)
      case "out": return 1 - inward(curve, 1 - t)
      case "inOut":
        return t < 0.5 ? inward(curve, t * 2) / 2
          : 1 - inward(curve, 2 - t * 2) / 2
      default:
        return t < 0.5 ? (1 - inward(curve, 1 - t * 2)) / 2
          : (1 + inward(curve, t * 2 - 1)) / 2
      }
    }
    return t
  }

  private static func inward(_ name: String, _ t: Double) -> Double {
    switch name {
    case "Sine": return 1 - cos(t * .pi / 2)
    case "Quad": return pow(t, 2)
    case "Cubic": return pow(t, 3)
    case "Quart": return pow(t, 4)
    case "Quint": return pow(t, 5)
    case "Expo": return t == 0 ? 0 : pow(2, 10 * t - 10)
    case "Circ": return 1 - sqrt(1 - t * t)
    case "Back": return 2.70158 * t * t * t - 1.70158 * t * t
    case "Elastic":
      if t == 0 || t == 1 { return t }
      return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * 2 * .pi / 3)
    default: return t
    }
  }
}

@MainActor
final class EnginePresentationAssets {
  struct Sprite {
    let image: UIImage
    let transform: EngineQuadTransform
  }
  let options: [Double]
  let skin: [Int: Sprite]
  let particles: [Int: ParticleData.Effect]
  let particleImages: [UIImage]
  let interpolation: Bool
  let particleInterpolation: Bool
  private var tintedParticles = [String: UIImage]()

  init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
    options = try CompressedJSONDecoder.decode(
      EngineConfiguration.self, from: presentation.data("configuration")
    ).options.map(\.def)
    let skinData = try CompressedJSONDecoder.decode(
      SkinData.self, from: presentation.data("skinData")
    )
    guard let texture = UIImage(data: try presentation.data("skinTexture"))?.cgImage
    else { throw RuntimeBundleError.missingResource("valid skin texture") }
    interpolation = skinData.interpolation
    var sprites = [Int: Sprite]()
    for definition in engine.skin.sprites {
      guard let sprite = skinData.sprites.first(where: { $0.name == definition.name })
      else { continue }
      let image = try Self.crop(texture, x: sprite.x, y: sprite.y,
        w: sprite.w, h: sprite.h)
      sprites[definition.id] = Sprite(image: image, transform: sprite.transform)
    }
    skin = sprites
    let particleData = try CompressedJSONDecoder.decode(
      ParticleData.self, from: presentation.data("particleData")
    )
    particleInterpolation = particleData.interpolation
    guard let texture = UIImage(
      data: try presentation.data("particleTexture")
    )?.cgImage else {
      throw RuntimeBundleError.missingResource("valid particle texture")
    }
    particleImages = try particleData.sprites.map {
      try Self.crop(texture, x: $0.x, y: $0.y, w: $0.w, h: $0.h)
    }
    var effects = [Int: ParticleData.Effect]()
    for definition in engine.particle.effects {
      guard let effect = particleData.effects.first(where: {
        $0.name == definition.name
      }) else { continue }
      guard effect.groups.allSatisfy({
        (0...1024).contains($0.count) && $0.particles.count <= 1024
      }), effect.groups.reduce(0, { $0 + $1.count * $1.particles.count }) <= 4096
      else { throw EngineInterpreterError.operationLimitExceeded }
      effects[definition.id] = effect
    }
    particles = effects
    // Build color variants while preparing the chart, not during a first hit.
    for effect in effects.values {
      for group in effect.groups {
        for particle in group.particles where particleImages.indices.contains(particle.sprite) {
          _ = particleImage(index: particle.sprite,
            color: EngineRenderer.color(particle.color), key: particle.color)
        }
      }
    }
  }

  var preparedImages: [UIImage] {
    skin.values.map(\.image) + Array(tintedParticles.values)
  }

  func particleImage(index: Int, color: UIColor, key: String) -> UIImage {
    let cacheKey = "\(index):\(key)"
    if let image = tintedParticles[cacheKey] { return image }
    let original = particleImages[index]
    let image = Self.tinted(original, color: color)
    tintedParticles[cacheKey] = image
    return image
  }

  static func tinted(_ original: UIImage, color: UIColor) -> UIImage {
    guard let source = original.cgImage else { return original }
    var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
      let context = CGContext(data: nil, width: source.width,
        height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
          CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue),
      let buffer = context.data else { return original }
    context.draw(source, in: CGRect(x: 0, y: 0,
      width: source.width, height: source.height))
    // Multiply premultiplied RGB directly, leaving alpha unchanged. Compositing
    // an opaque tint then masking it bleaches semitransparent colored pixels.
    let bytes = buffer.bindMemory(to: UInt8.self,
      capacity: context.bytesPerRow * source.height)
    let multipliers = [red, green, blue].map { min(1, max(0, $0)) }
    for offset in stride(from: 0, to: context.bytesPerRow * source.height, by: 4) {
      for (channel, multiplier) in multipliers.enumerated() {
        bytes[offset + channel] = UInt8(
          (CGFloat(bytes[offset + channel]) * multiplier).rounded())
      }
    }
    guard let result = context.makeImage() else { return original }
    return UIImage(cgImage: result, scale: original.scale,
      orientation: original.imageOrientation)
  }

  private static func crop(
    _ texture: CGImage, x: Double, y: Double, w: Double, h: Double
  ) throws -> UIImage {
    guard [x, y, w, h].allSatisfy(\.isFinite), x >= 0, y >= 0,
      w > 0, h > 0, x + w <= Double(texture.width),
      y + h <= Double(texture.height),
      let cropped = texture.cropping(to: CGRect(x: x, y: y, width: w, height: h))
    else { throw EngineInterpreterError.invalidArguments("sprite bounds") }
    return UIImage(cgImage: cropped)
  }
}

@MainActor
struct EngineRenderSprite {
  let image: UIImage
  let points: [EnginePoint]
  let matrix: [Double]
  let alpha: Double
  let interpolation: Bool
}

@MainActor
enum EngineRenderer {
  static func draw(
    host: CommandEngineRuntimeHost, assets: EnginePresentationAssets,
    context: CGContext, size: CGSize
  ) {
    for sprite in sprites(host: host, assets: assets) {
      context.interpolationQuality = sprite.interpolation ? .medium : .none
      drawImage(sprite.image, points: sprite.points, matrix: sprite.matrix,
        alpha: sprite.alpha, context: context, size: size)
    }
  }

  static func sprites(
    host: CommandEngineRuntimeHost, assets: EnginePresentationAssets
  ) -> [EngineRenderSprite] {
    var result = [EngineRenderSprite]()
    let ordered = host.draws.enumerated().sorted {
      if $0.element.zValues == $1.element.zValues { return $0.offset < $1.offset }
      return $0.element.zValues.lexicographicallyPrecedes($1.element.zValues)
    }
    for (_, command) in ordered {
      guard let sprite = assets.skin[command.spriteID] else { continue }
      let points = EngineGeometry.transformed(command.points, by: sprite.transform)
      result.append(EngineRenderSprite(image: sprite.image, points: points,
        matrix: command.transform, alpha: command.alpha,
        interpolation: assets.interpolation))
    }
    for instance in host.particles.values.sorted(by: { $0.id < $1.id }) {
      guard let effect = assets.particles[instance.effectID] else { continue }
      let elapsed = (host.time - instance.startTime) / instance.duration
      let progress = instance.isLooped ? elapsed - floor(elapsed) : elapsed
      let seed = UInt64(instance.id)
      let variables = EngineGeometry.randomVariables(seed: seed)
      let quad = EngineGeometry.transformed(
        instance.points, by: effect.transform, variables: variables
      )
      for (groupIndex, group) in effect.groups.enumerated() {
        for repetition in 0..<group.count {
          let variables = EngineGeometry.randomVariables(
            seed: seed &* 65_537 &+ UInt64(groupIndex * 1024 + repetition)
          )
          for particle in group.particles {
            guard particle.duration > 0, progress >= particle.start,
              progress < particle.start + particle.duration,
              assets.particleImages.indices.contains(particle.sprite)
            else { continue }
            let time = (progress - particle.start) / particle.duration
            let x = particle.x.value(at: time, variables: variables)
            let y = particle.y.value(at: time, variables: variables)
            let w = particle.w.value(at: time, variables: variables)
            let h = particle.h.value(at: time, variables: variables)
            let rotation = particle.r.value(at: time, variables: variables)
            let alpha = particle.a.value(at: time, variables: variables)
            let points = [(-1.0,-1.0),(-1,1),(1,1),(1,-1)].map { sx, sy in
              let dx = sx * w / 2
              let dy = sy * h / 2
              return EngineGeometry.bilinear(quad,
                u: (x + dx * cos(rotation) - dy * sin(rotation) + 1) / 2,
                v: (y + dx * sin(rotation) + dy * cos(rotation) + 1) / 2)
            }
            let image = assets.particleImage(index: particle.sprite,
              color: color(particle.color), key: particle.color)
            let matrix = (0..<16).map { host.memory.value(block: 1004, index: $0) }
            result.append(EngineRenderSprite(image: image, points: points,
              matrix: matrix, alpha: alpha,
              interpolation: assets.particleInterpolation))
          }
        }
      }
    }
    return result
  }

  static func color(_ hex: String) -> UIColor {
    var text = String(hex.dropFirst())
    if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
    guard let value = UInt32(text, radix: 16) else { return .white }
    return UIColor(red: Double((value >> 16) & 255) / 255,
      green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255, alpha: 1)
  }

  static func drawImage(
    _ image: UIImage, points: [EnginePoint], matrix: [Double],
    alpha: Double, context: CGContext, size: CGSize
  ) {
    guard alpha.isFinite, alpha > 0 else { return }
    let quad = points.map { EngineGeometry.screenPoint($0, matrix: matrix, size: size) }
    guard quad.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
    let error = hypot(quad[0].x + quad[2].x - quad[1].x - quad[3].x,
      quad[0].y + quad[2].y - quad[1].y - quad[3].y)
    guard error.isFinite else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.setAlpha(min(1, alpha))
    // Most sprites are parallelograms; avoid tessellating that common case.
    if error < 0.01 {
      context.concatenate(CGAffineTransform(
        a: (quad[2].x - quad[1].x) / image.size.width,
        b: (quad[2].y - quad[1].y) / image.size.width,
        c: (quad[0].x - quad[1].x) / image.size.height,
        d: (quad[0].y - quad[1].y) / image.size.height,
        tx: quad[1].x, ty: quad[1].y
      ))
      drawUpright(image, context: context)
      return
    }
    // A bilinear patch's triangle error is at most warp / (4 * divisions²).
    // Target 0.25 points, capped at the previous 8x8 quality/budget. Mildly
    // warped hold connectors do not need 128 clipped image draws each frame.
    let divisions = tessellationDivisions(warp: error)
    let converted = quad.map { EnginePoint(x: $0.x, y: $0.y) }
    context.setShouldAntialias(false)
    for row in 0..<divisions {
      for column in 0..<divisions {
        let uv = [(column,row), (column,row+1), (column+1,row+1), (column+1,row)]
          .map { (Double($0.0) / Double(divisions), Double($0.1) / Double(divisions)) }
        let destination = uv.map {
          EngineGeometry.bilinear(converted, u: $0.0, v: $0.1)
        }.map { CGPoint(x: $0.x, y: $0.y) }
        let source = uv.map {
          CGPoint(x: $0.0 * image.size.width, y: (1 - $0.1) * image.size.height)
        }
        for indices in [[0,1,2], [0,2,3]] {
          triangle(image, source: indices.map { source[$0] },
            destination: indices.map { destination[$0] }, context: context)
        }
      }
    }
  }

  static func tessellationDivisions(warp: Double) -> Int {
    guard warp.isFinite else { return 8 }
    return max(1, Int(ceil(sqrt(min(64, max(0, warp))))))
  }

  private static func triangle(
    _ image: UIImage, source: [CGPoint], destination: [CGPoint], context: CGContext
  ) {
    func basis(_ p: [CGPoint]) -> CGAffineTransform {
      CGAffineTransform(a: p[1].x-p[0].x, b: p[1].y-p[0].y,
        c: p[2].x-p[0].x, d: p[2].y-p[0].y, tx: p[0].x, ty: p[0].y)
    }
    context.saveGState()
    defer { context.restoreGState() }
    context.beginPath()
    context.addLines(between: destination)
    context.closePath()
    context.clip()
    context.concatenate(basis(source).inverted().concatenating(basis(destination)))
    drawUpright(image, context: context)
  }

  private static func drawUpright(_ image: UIImage, context: CGContext) {
    guard let cgImage = image.cgImage else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.translateBy(x: 0, y: image.size.height)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
  }
}
