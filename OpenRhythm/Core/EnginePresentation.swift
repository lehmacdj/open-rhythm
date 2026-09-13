import UIKit

typealias EngineExpression = [String: Double]
typealias EngineQuadTransform = [String: EngineExpression]

struct EngineConfiguration: Decodable {
  struct Option: Decodable {
    let def: Double
    let name: String?
    let min: Double?
    let max: Double?
    let step: Double?
    var values: [LocalizedText]? = nil
    var type: String? = nil
    var title: String? = nil
    var description: String? = nil
    var category: String? = nil
    var unit: String? = nil
    var standard: Bool? = nil
    var advanced: Bool? = nil

    var controlType: String? {
      switch type {
      case "toggle": return "toggle"
      case "select": return values?.isEmpty == false ? "select" : nil
      case "slider": return sliderRange != nil ? "slider" : nil
      case nil:
        if values?.isEmpty == false { return "select" }
        return sliderRange != nil ? "slider" : nil
      default: return nil
      }
    }

    static func label(_ text: String) -> String {
      text.hasPrefix("#")
        ? text.dropFirst().replacingOccurrences(of: "_", with: " ").capitalized
        : text
    }

    var displayName: String { Self.label(title ?? name ?? "Option") }
    var usesNoteSpeedControl: Bool {
      name == "#NOTE_SPEED" && controlType == "slider"
    }
    var usesScoreModeControl: Bool {
      name == "Score Mode" && controlType == "select"
    }

    func value(_ preferred: Double?) -> Double {
      guard let preferred, preferred.isFinite else { return def }
      switch controlType {
      case "toggle": return preferred == 0 || preferred == 1 ? preferred : def
      case "select": return Double(selectedIndex(Int(exactly: preferred)) ?? 0)
      case "slider": return clamped(preferred)
      default: return def
      }
    }

    func valueLabel(_ value: Double) -> String {
      if controlType == "toggle" { return value == 0 ? "Off" : "On" }
      if controlType == "select", let values,
        let index = Int(exactly: value), values.indices.contains(index) {
        return Self.label(values[index].displayValue())
      }
      if unit == "#PERCENTAGE_UNIT" {
        return (value * 100).formatted(.number.precision(.fractionLength(0...2))) + "%"
      }
      let suffix = unit.map { " " + Self.label($0) } ?? ""
      return value.formatted(.number.precision(.fractionLength(0...3))) + suffix
    }

    func selectedIndex(_ preferred: Int?) -> Int? {
      guard let values, !values.isEmpty else { return nil }
      if let preferred, values.indices.contains(preferred) { return preferred }
      if let index = Int(exactly: def), values.indices.contains(index) { return index }
      return 0
    }

    var sliderRange: ClosedRange<Double>? {
      guard let min, let max, min.isFinite, max.isFinite, max > min,
        (max - min).isFinite else { return nil }
      return min...max
    }

    func clamped(_ value: Double) -> Double {
      guard value.isFinite, let range = sliderRange else { return def }
      let bounded = Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
      guard let step, step.isFinite, step > 0 else { return bounded }
      let rounded = range.lowerBound + ((bounded - range.lowerBound) / step).rounded() * step
      guard rounded.isFinite else { return bounded }
      return Swift.min(range.upperBound, Swift.max(range.lowerBound, rounded))
    }
  }
  struct UI: Decodable {
    struct Animation: Decodable {
      struct Tween: Decodable {
        let from: Double
        let to: Double
        let duration: Double
        let ease: String

        private enum CodingKeys: String, CodingKey { case from, to, duration, ease }

        init(from decoder: Decoder) throws {
          let values = try decoder.container(keyedBy: CodingKeys.self)
          from = try values.decode(Double.self, forKey: .from)
          to = try values.decode(Double.self, forKey: .to)
          duration = try values.decode(Double.self, forKey: .duration)
          ease = try values.decode(String.self, forKey: .ease)
          guard from.isFinite, to.isFinite, abs(from) <= 1024, abs(to) <= 1024,
            duration.isFinite, (0...3600).contains(duration) else {
            throw DecodingError.dataCorruptedError(forKey: .duration, in: values,
              debugDescription: "Engine UI animation exceeds supported numeric bounds.")
          }
        }

        func value(at elapsed: Double) -> Double {
          guard duration > 0, elapsed < duration else { return to }
          let result = from + (to - from) * EngineEasing.value(ease, elapsed / duration)
          return result.isFinite ? Swift.min(1024, Swift.max(-1024, result)) : to
        }
      }
      let scale: Tween
      let alpha: Tween
      var duration: Double { Swift.max(scale.duration, alpha.duration) }
    }
    struct Visibility: Decodable {
      let scale: Double
      let alpha: Double

      var values: [Double] {
        [scale.isFinite ? Swift.max(0, scale) : 1,
         alpha.isFinite ? Swift.min(1, Swift.max(0, alpha)) : 1]
      }
    }
    let menuVisibility: Visibility?
    let judgmentVisibility: Visibility?
    let comboVisibility: Visibility?
    let primaryMetricVisibility: Visibility?
    let secondaryMetricVisibility: Visibility?
    let primaryMetric: String?
    let secondaryMetric: String?
    let judgmentAnimation: Animation?
    let comboAnimation: Animation?
    let judgmentErrorPlacement: String?
    let judgmentErrorMin: Double?

    var runtimeValues: [Double] {
      [menuVisibility, judgmentVisibility, comboVisibility,
       primaryMetricVisibility, secondaryMetricVisibility]
        .flatMap { $0?.values ?? [1, 1] }
    }
  }
  let options: [Option]
  let ui: UI?

  func validateOptions() throws {
    var names = Set<String>()
    for option in options {
      if let name = option.name, !names.insert(name).inserted {
        throw EngineInterpreterError.invalidArguments("duplicate engine option: \(name)")
      }
      var valid = option.def.isFinite
      switch option.controlType {
      case "slider":
        valid = valid && option.sliderRange?.contains(option.def) == true
          && (option.step == nil || (option.step!.isFinite && option.step! > 0))
      case "select":
        valid = valid && Int(exactly: option.def).map {
          option.values?.indices.contains($0) == true
        } == true
      case "toggle": valid = valid && (option.def == 0 || option.def == 1)
      default:
        // Unknown future kinds retain their numeric default and an explicit
        // unavailable control. Malformed known kinds must not reach SwiftUI.
        valid = valid && !["slider", "select"].contains(option.type ?? "")
      }
      guard valid else {
        throw EngineInterpreterError.invalidArguments("engine option: \(option.displayName)")
      }
    }
  }

  func runtimeOptions(preferences: GameplayPreferences) -> [Double] {
    options.map { option in
      if option.usesNoteSpeedControl, let speed = preferences.noteSpeed {
        return option.value(speed)
      }
      if option.usesScoreModeControl, let score = preferences.scoreMode {
        return option.value(Double(score))
      }
      return option.value(option.name.flatMap { preferences.engineOptions[$0] })
    }
  }

  func playbackSpeed(preferences: GameplayPreferences) -> Double {
    guard let index = options.firstIndex(where: { $0.name == "#SPEED" })
    else { return 1 }
    return runtimeOptions(preferences: preferences)[index]
  }

  func modifiedStandardOptions(preferences: GameplayPreferences)
    -> [EngineOptionOverride] {
    zip(options, runtimeOptions(preferences: preferences)).compactMap { option, value in
      guard option.standard == true, value != option.def else { return nil }
      return EngineOptionOverride(name: option.displayName,
        value: option.valueLabel(value))
    }
  }
}

struct EngineUIElement: Equatable {
  let values: [Double]
  init(memory: EngineMemory, index: Int) {
    values = (0..<10).map { memory.value(block: 1006, index: index * 10 + $0) }
  }
  var isVisible: Bool {
    values.allSatisfy(\.isFinite) && values[5] > 0 && values[7] > 0
  }
  var pivot: CGPoint { CGPoint(x: values[2], y: 1 - values[3]) }
  func anchor(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width / 2 + values[0] * size.height / 2,
      y: size.height / 2 - values[1] * size.height / 2)
  }
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

  static func curvedPatches(_ quad: [EnginePoint], curve: EngineCurve)
    -> [(points: [EnginePoint], region: EngineTextureRegion)] {
    guard quad.count == 4, (1...1024).contains(curve.segments),
      curve.controls.count == (curve.edge == .bottomTop || curve.edge == .leftRight ? 2 : 1)
    else { return [] }
    let controls = curve.controls.map {
      bilinear(quad, u: ($0.x + 1) / 2, v: ($0.y + 1) / 2)
    }
    let vertical = [.left, .right, .leftRight].contains(curve.edge)
    let firstControl: EnginePoint? = [.left, .bottom, .leftRight, .bottomTop]
      .contains(curve.edge) ? controls[0] : nil
    let secondControl: EnginePoint? = [.right, .top].contains(curve.edge)
      ? controls[0] : controls.count == 2 ? controls[1] : nil
    func edge(_ start: EnginePoint, _ end: EnginePoint,
      control: EnginePoint?, at t: Double) -> EnginePoint {
      guard let control else {
        return EnginePoint(x: start.x * (1 - t) + end.x * t,
          y: start.y * (1 - t) + end.y * t)
      }
      let a = (1 - t) * (1 - t)
      let b = 2 * t * (1 - t)
      let c = t * t
      return EnginePoint(x: a * start.x + b * control.x + c * end.x,
        y: a * start.y + b * control.y + c * end.y)
    }
    // Compute shared boundaries once to prevent tiny cracks between strips.
    let first = (0...curve.segments).map {
      edge(quad[0], quad[vertical ? 1 : 3], control: firstControl,
        at: Double($0) / Double(curve.segments))
    }
    let second = (0...curve.segments).map {
      edge(quad[vertical ? 3 : 1], quad[2], control: secondControl,
        at: Double($0) / Double(curve.segments))
    }
    return (0..<curve.segments).map { index in
      let lower = Double(index) / Double(curve.segments)
      let upper = Double(index + 1) / Double(curve.segments)
      if vertical {
        return ([first[index], first[index + 1], second[index + 1], second[index]],
          EngineTextureRegion(minU: 0, minV: lower, maxU: 1, maxV: upper))
      }
      return ([first[index], second[index], second[index + 1], first[index + 1]],
        EngineTextureRegion(minU: lower, minV: 0, maxU: upper, maxV: 1))
    }
  }
}

enum EngineEasing {
  static func value(_ name: String, _ time: Double, clamped: Bool = true) -> Double {
    let t = clamped ? min(1, max(0, time)) : time
    if name == "none" { return 0 }
    if name == "linear" { return t }
    for mode in ["inOut", "outIn", "in", "out"] where name.hasPrefix(mode) {
      let curve = String(name.dropFirst(mode.count))
      switch mode {
      case "in": return inward(curve, t)
      case "out": return 1 - inward(curve, 1 - t)
      case "inOut":
        if curve == "Back" {
          let c = 1.70158 * 1.525
          return t < 0.5 ? pow(2 * t, 2) * ((c + 1) * 2 * t - c) / 2
            : (pow(2 * t - 2, 2) * ((c + 1) * (2 * t - 2) + c) + 2) / 2
        }
        if curve == "Elastic" {
          if t == 0 || t == 1 { return t }
          let wave = sin((20 * t - 11.125) * (2 * .pi / 4.5))
          return t < 0.5 ? -pow(2, 20 * t - 10) * wave / 2
            : pow(2, -20 * t + 10) * wave / 2 + 1
        }
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
  let configuration: EngineConfiguration
  let ui: EngineConfiguration.UI?
  let noteSpeedOption: EngineConfiguration.Option?
  let judgementErrorMinimum: Double?
  let scoreModeOption: EngineConfiguration.Option?
  private let scoreModeIndex: Int?
  private let noteSpeedIndex: Int?
  let skin: [Int: Sprite]
  let particles: [Int: ParticleData.Effect]
  let particleImages: [UIImage]
  let interpolation: Bool
  let particleInterpolation: Bool
  private var tintedParticles = [String: UIImage]()

  init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
    let configuration = try CompressedJSONDecoder.decode(
      EngineConfiguration.self, from: presentation.data("configuration")
    )
    self.configuration = configuration
    try configuration.validateOptions()
    options = configuration.options.map(\.def)
    ui = configuration.ui
    noteSpeedIndex = configuration.options.firstIndex(where: \.usesNoteSpeedControl)
    noteSpeedOption = noteSpeedIndex.map { configuration.options[$0] }
    judgementErrorMinimum = configuration.ui?.judgmentErrorMin.flatMap {
      $0.isFinite && $0 >= 0 ? $0 / 1000 : nil
    }
    scoreModeIndex = configuration.options.firstIndex(where: \.usesScoreModeControl)
    scoreModeOption = scoreModeIndex.map { configuration.options[$0] }
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

  func runtimeOptions(noteSpeed: Double?, scoreMode: Int? = nil) -> [Double] {
    configuration.runtimeOptions(preferences:
      GameplayPreferences(noteSpeed: noteSpeed, scoreMode: scoreMode))
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
  var textureRegion: EngineTextureRegion = .full
}

@MainActor
enum EngineRenderer {
  static func draw(
    host: CommandEngineRuntimeHost, assets: EnginePresentationAssets,
    context: CGContext, size: CGSize
  ) throws {
    try draw(sprites(host: host, assets: assets), context: context, size: size)
  }

  static func draw(_ sprites: [EngineRenderSprite], context: CGContext,
    size: CGSize, pixelBudget: Int = 64_000_000) throws {
    if sprites.contains(where: { sprite in
      guard sprite.textureRegion == .full, sprite.points.count == 4,
        sprite.matrix.count == 16 else { return true }
      let quad = sprite.points.map {
        EngineGeometry.screenPoint($0, matrix: sprite.matrix, size: size)
      }
      let warp = hypot(quad[0].x + quad[2].x - quad[1].x - quad[3].x,
        quad[0].y + quad[2].y - quad[1].y - quad[3].y)
      return !warp.isFinite || warp >= 0.01
    }) {
      // One frame, one scratch surface/cache/budget, including ordinary Draw
      // connectors. Otherwise each warped sprite would reset the limits.
      try EngineSoftwareRenderer.draw(sprites, context: context, size: size,
        pixelBudget: pixelBudget)
      return
    }
    for sprite in sprites {
      context.interpolationQuality = sprite.interpolation ? .medium : .none
      try drawImage(sprite.image, points: sprite.points, matrix: sprite.matrix,
        alpha: sprite.alpha, context: context, size: size,
        textureRegion: sprite.textureRegion)
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
      guard command.alpha > 0, let sprite = assets.skin[command.spriteID] else { continue }
      let points = EngineGeometry.transformed(command.points, by: sprite.transform)
      if let curve = command.curve {
        for patch in EngineGeometry.curvedPatches(points, curve: curve) {
          result.append(EngineRenderSprite(image: sprite.image, points: patch.points,
            matrix: command.transform, alpha: command.alpha,
            interpolation: assets.interpolation, textureRegion: patch.region))
        }
      } else {
        result.append(EngineRenderSprite(image: sprite.image, points: points,
          matrix: command.transform, alpha: command.alpha,
          interpolation: assets.interpolation))
      }
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
    alpha: Double, context: CGContext, size: CGSize,
    textureRegion: EngineTextureRegion = .full
  ) throws {
    guard alpha.isFinite, alpha > 0, points.count == 4, matrix.count == 16,
      textureRegion.isValid else { return }
    let quad = points.map { EngineGeometry.screenPoint($0, matrix: matrix, size: size) }
    guard quad.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
    let error = hypot(quad[0].x + quad[2].x - quad[1].x - quad[3].x,
      quad[0].y + quad[2].y - quad[1].y - quad[3].y)
    guard error.isFinite else { return }
    if error >= 0.01 || textureRegion != .full {
      try EngineSoftwareRenderer.draw([EngineRenderSprite(image: image,
        points: points, matrix: matrix, alpha: alpha,
        interpolation: context.interpolationQuality != .none,
        textureRegion: textureRegion)], context: context, size: size)
      return
    }
    // Retain Quartz's efficient affine path for ordinary rectangular sprites.
    context.saveGState()
    defer { context.restoreGState() }
    context.setAlpha(min(1, alpha))
    context.concatenate(CGAffineTransform(
      a: (quad[2].x - quad[1].x) / image.size.width,
      b: (quad[2].y - quad[1].y) / image.size.width,
      c: (quad[0].x - quad[1].x) / image.size.height,
      d: (quad[0].y - quad[1].y) / image.size.height,
      tx: quad[1].x, ty: quad[1].y
    ))
    drawUpright(image, context: context)
  }

  static func tessellationDivisions(warp: Double) -> Int {
    guard warp.isFinite else { return 8 }
    return max(1, Int(ceil(sqrt(min(64, max(0, warp))))))
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
