import UIKit

typealias EngineExpression = [String: Double]
typealias EngineQuadTransform = [String: EngineExpression]

struct EngineConfiguration: Decodable {
  struct OptionCategory: Decodable {
    let name: String
    let title: String
  }

  struct OptionGroup: Identifiable {
    let id: String
    let title: String
    let optionIndices: [Int]
  }

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

    func preferredValue(in preferences: GameplayPreferences) -> Double? {
      if usesNoteSpeedControl, let value = preferences.noteSpeed { return value }
      if usesScoreModeControl, let value = preferences.scoreMode {
        return Double(value)
      }
      return name.flatMap { preferences.engineOptions[$0] }
    }

    func setPreferredValue(_ value: Double?, in preferences: inout GameplayPreferences) {
      if usesNoteSpeedControl { preferences.noteSpeed = value }
      else if usesScoreModeControl { preferences.scoreMode = value.flatMap(Int.init(exactly:)) }
      else if let name { preferences.engineOptions[name] = value }
      // Reset also clears legacy generic overrides of dedicated controls.
      if value == nil, let name { preferences.engineOptions[name] = nil }
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
          try EngineEasing.validate(ease, field: "UI animation easing")
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
    let judgmentErrorStyle: String?
    let judgmentErrorPlacement: String?
    let judgmentErrorMin: Double?

    func validate() throws {
      let metrics: Set<String> = ["arcade", "arcadePercentage", "accuracy",
        "accuracyPercentage", "life", "time", "perfect", "perfectPercentage",
        "greatGoodMiss", "greatGoodMissPercentage", "miss", "missPercentage",
        "errorHeatmap"]
      let styles: Set<String> = ["none", "late", "early", "plus", "minus",
        "arrowUp", "arrowDown", "arrowLeft", "arrowRight", "triangleUp",
        "triangleDown", "triangleLeft", "triangleRight"]
      let placements: Set<String> = ["left", "right", "leftRight", "top",
        "bottom", "topBottom", "center"]
      for (field, value, supported) in [
        ("primary metric", primaryMetric, metrics),
        ("secondary metric", secondaryMetric, metrics),
        ("judgment error style", judgmentErrorStyle, styles),
        ("judgment error placement", judgmentErrorPlacement, placements)
      ] {
        if let value, !supported.contains(value) {
          throw RuntimeBundleError.unsupportedPresentationValue(
            field: field, value: value)
        }
      }
    }

    var runtimeValues: [Double] {
      [menuVisibility, judgmentVisibility, comboVisibility,
       primaryMetricVisibility, secondaryMetricVisibility]
        .flatMap { $0?.values ?? [1, 1] }
    }
  }
  let options: [Option]
  let ui: UI?
  var optionCategories: [OptionCategory]? = nil

  /// Presentation order is independent of the runtime option-memory indices.
  var optionGroups: [OptionGroup] {
    if let optionCategories {
      return optionCategories.compactMap { category in
        let indices = options.indices.filter {
          options[$0].name != nil && options[$0].category == category.name
        }
        guard !indices.isEmpty else { return nil }
        return OptionGroup(id: category.name, title: Option.label(category.title),
          optionIndices: indices)
      }
    }
    // Older configurations have no categories. Keep their dedicated speed
    // and score-mode controls and the existing per-option sections.
    return options.indices.compactMap { index in
      let option = options[index]
      guard option.name != nil, !option.usesNoteSpeedControl,
        !option.usesScoreModeControl else { return nil }
      return OptionGroup(id: String(index), title: option.displayName,
        optionIndices: [index])
    }
  }

  func validateOptions() throws {
    if let optionCategories {
      let names = Set(optionCategories.map(\.name))
      guard names.count == optionCategories.count else {
        throw EngineInterpreterError.invalidArguments("duplicate engine option category")
      }
      for option in options {
        guard let category = option.category, names.contains(category) else {
          throw EngineInterpreterError.invalidArguments(
            "category for engine option: \(option.displayName)")
        }
      }
    }
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
    options.map { $0.value($0.preferredValue(in: preferences)) }
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
    struct Endpoints {
      let from: Double
      let to: Double
    }

    let from: EngineExpression?
    let to: EngineExpression?
    let ease: String?

    func value(at time: Double, variables: EngineExpression) -> Double {
      value(at: time, endpoints: endpoints(variables: variables))
    }

    func endpoints(variables: EngineExpression) -> Endpoints {
      Endpoints(from: EngineGeometry.evaluate(from ?? [:], variables),
        to: EngineGeometry.evaluate(to ?? [:], variables))
    }

    func value(at time: Double, endpoints: Endpoints) -> Double {
      endpoints.from + (endpoints.to - endpoints.from)
        * EngineEasing.particleValue(ease ?? "linear", time)
    }
  }
  let width: Int
  let height: Int
  let interpolation: Bool
  let sprites: [Sprite]
  let effects: [Effect]
}

/// Only expression endpoints are time-independent. Never cache eased values,
/// transformed quads, or particle visibility, all of which can change per frame.
struct EngineParticlePropertyCache {
  struct Key: Hashable {
    let seed: UInt64
    let effect: Int
    let group: Int
    let particle: Int
  }

  struct Properties {
    let x, y, w, h, r, a: ParticleData.Property.Endpoints

    init(_ particle: ParticleData.Particle, variables: EngineExpression) {
      x = particle.x.endpoints(variables: variables)
      y = particle.y.endpoints(variables: variables)
      w = particle.w.endpoints(variables: variables)
      h = particle.h.endpoints(variables: variables)
      r = particle.r.endpoints(variables: variables)
      a = particle.a.endpoints(variables: variables)
    }
  }

  private var previous = [Key: Properties]()
  private var current = [Key: Properties]()
  let capacity: Int

  init(capacity: Int = 1024) { self.capacity = max(0, capacity) }
  var count: Int { previous.count + current.count }

  mutating func beginFrame() {
    previous = current
    current = [:]
  }

  mutating func properties(for particle: ParticleData.Particle, key: Key,
    variables: EngineExpression) -> Properties {
    // Definitions belong to one immutable asset bundle. Include their identity
    // as well as the seed: reused handles after restart can name another effect.
    // Admit a bounded prefix. Once full, do no more hashing for this frame's
    // overflow: sparse/large effects must not pay two failed lookups per sprite.
    guard current.count < capacity else { return Properties(particle, variables: variables) }
    let result = previous[key] ?? Properties(particle, variables: variables)
    current[key] = result
    return result
  }
}

/// Random expressions depend only on the seed, not on animation time or the
/// current quad. Bound storage so long plays cannot retain every past effect.
struct EngineParticleRandomCache {
  private var previous = [UInt64: EngineExpression]()
  private var current = [UInt64: EngineExpression]()
  let capacity: Int

  init(capacity: Int = 512) {
    self.capacity = max(0, capacity)
  }

  var count: Int { previous.count + current.count }

  mutating func beginFrame() {
    previous = current
    current = [:]
  }

  mutating func variables(seed: UInt64) -> EngineExpression {
    if let cached = current[seed] { return cached }
    let result = previous[seed] ?? EngineGeometry.randomVariables(seed: seed)
    // Retain the first bounded subset of each frame. Evicting on every miss
    // would give zero hits when a repeated frame exceeds the cache capacity.
    if current.count < capacity { current[seed] = result }
    return result
  }
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
  static let supportedNames = Set(["linear", "none"] +
    ["in", "out", "inOut", "outIn"].flatMap { mode in
      ["Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Back",
        "Elastic"].map { mode + $0 }
    })

  static func validate(_ name: String?, field: String) throws {
    if let name, !supportedNames.contains(name) {
      throw RuntimeBundleError.unsupportedPresentationValue(field: field, value: name)
    }
  }

  /// Resource curves follow the public Studio renderer. Keep its variants
  /// separate from numerical engine functions and HUD animation curves.
  static func particleValue(_ name: String, _ time: Double) -> Double {
    let t = min(1, max(0, time))
    switch name {
    case "inOutBack", "inOutElastic":
      let curve = name == "inOutBack" ? "Back" : "Elastic"
      return t < 0.5 ? inward(curve, 2 * t) / 2
        : 1 - inward(curve, 2 - 2 * t) / 2
    case "outInExpo":
      if t == 0 || t == 1 { return t }
      return t < 0.5 ? (1 - pow(2, -20 * t)) / 2
        : (1 + pow(2, 20 * t - 20)) / 2
    case "outInElastic":
      if t == 0 || t == 1 { return t }
      if t < 0.5 { return value(name, t) }
      // Studio preserves the inward curve's exponential term at this
      // midpoint rather than applying the numerical function's zero guard.
      return (1 - pow(2, 20 * t - 20)
        * sin((20 * t - 20.75) * 2 * .pi / 3)) / 2
    default:
      return value(name, t)
    }
  }

  static func value(_ name: String, _ time: Double, clamped: Bool = true) -> Double {
    let t = clamped ? min(1, max(0, time)) : time
    if name == "none" { return t == 1 ? 1 : 0 }
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
  let background: EngineBackgroundAssets?
  let forcedSkinRenderMode: EngineSkinRenderMode?
  private(set) var skinRenderMode: EngineSkinRenderMode
  private var tintedParticles = [String: UIImage]()
  private var particleRandomCache = EngineParticleRandomCache()
  private var particlePropertyCache = EngineParticlePropertyCache()

  func beginParticleFrame() {
    particleRandomCache.beginFrame()
    particlePropertyCache.beginFrame()
  }

  func particleVariables(seed: UInt64, cached: Bool) -> EngineExpression {
    cached ? particleRandomCache.variables(seed: seed)
      : EngineGeometry.randomVariables(seed: seed)
  }

  func particleProperties(_ particle: ParticleData.Particle,
    key: EngineParticlePropertyCache.Key, variables: EngineExpression)
    -> EngineParticlePropertyCache.Properties {
    particlePropertyCache.properties(for: particle, key: key, variables: variables)
  }

  init(engine: EnginePlayData, presentation: RuntimePresentation) throws {
    forcedSkinRenderMode = try engine.skin.forcedRenderMode
    skinRenderMode = forcedSkinRenderMode ?? .standard
    let configuration = try CompressedJSONDecoder.decode(
      EngineConfiguration.self, from: presentation.data("configuration")
    )
    self.configuration = configuration
    background = presentation.resources.keys.contains(where: { $0.hasPrefix("background") })
      ? try EngineBackgroundAssets(presentation: presentation) : nil
    try configuration.validateOptions()
    try configuration.ui?.validate()
    options = configuration.options.map(\.def)
    ui = configuration.ui
    noteSpeedIndex = configuration.options.firstIndex(where: \.usesNoteSpeedControl)
    noteSpeedOption = noteSpeedIndex.map { configuration.options[$0] }
    judgementErrorMinimum = configuration.ui?.judgmentErrorMin.flatMap {
      $0.isFinite && $0 >= 0 ? $0 / 1000 : nil
    }
    scoreModeIndex = configuration.options.firstIndex(where: \.usesScoreModeControl)
    scoreModeOption = scoreModeIndex.map { configuration.options[$0] }
    var sprites = [Int: Sprite]()
    if engine.skin.sprites.isEmpty {
      interpolation = false
    } else {
      let skinData = try CompressedJSONDecoder.decode(
        SkinData.self, from: presentation.data("skinData")
      )
      guard let texture = UIImage(data: try presentation.data("skinTexture"))?.cgImage
      else { throw RuntimeBundleError.missingResource("valid skin texture") }
      interpolation = skinData.interpolation
      for definition in engine.skin.sprites {
        guard let sprite = skinData.sprites.first(where: { $0.name == definition.name })
        else { continue }
        let image = try Self.crop(texture, x: sprite.x, y: sprite.y,
          w: sprite.w, h: sprite.h)
        sprites[definition.id] = Sprite(image: image, transform: sprite.transform)
      }
    }
    skin = sprites
    // Engines can omit entire presentation families they do not use. Do not
    // require a particle texture merely because a skin or configuration exists.
    guard !engine.particle.effects.isEmpty else {
      particleInterpolation = false
      particleImages = []
      particles = [:]
      return
    }
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
      for group in effect.groups {
        for particle in group.particles {
          for (name, property) in [("x", particle.x), ("y", particle.y),
            ("w", particle.w), ("h", particle.h), ("r", particle.r),
            ("a", particle.a)] {
            try EngineEasing.validate(property.ease,
              field: "particle \(definition.name) \(name) easing")
          }
        }
      }
      effects[definition.id] = effect
    }
    particles = effects
    // Build color variants while preparing the chart, not during a first hit.
    for effect in effects.values {
      for group in effect.groups {
        for particle in group.particles where particleImages.indices.contains(particle.sprite) {
          _ = particleImage(index: particle.sprite, key: particle.color)
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

  func particleImage(index: Int, key: String) -> UIImage {
    let cacheKey = "\(index):\(key)"
    if let image = tintedParticles[cacheKey] { return image }
    let original = particleImages[index]
    let image = Self.tinted(original, color: EngineRenderer.color(key))
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

  func configureRenderMode(preferred: EngineSkinRenderMode) {
    skinRenderMode = forcedSkinRenderMode ?? preferred
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
  var renderMode: EngineSkinRenderMode = .standard
  var isStaticIntroDecoration = false
}

/// Compare visible presentation, not entity activation or offscreen commands.
/// Static stage graphics can remain on screen throughout a skippable lead-in.
@MainActor
struct EngineIntroVisualFrame: Equatable {
  struct Sprite: Equatable {
    let image: ObjectIdentifier
    let points: [CGPoint]
    let alpha: Double
    let region: EngineTextureRegion
    let interpolation: Bool
    let isStaticDecoration: Bool
  }
  let sprites: [Sprite]
  let background: [Double]
  let ui: [[Double]]

  init(sprites: [EngineRenderSprite], aspect: Double,
    background: [Double] = [], ui: [[Double]] = []) {
    let size = CGSize(width: aspect * 2, height: 2)
    let screen = CGRect(origin: .zero, size: size)
    self.sprites = sprites.compactMap { sprite in
      guard sprite.alpha > 0, sprite.matrix.count == 16,
        sprite.points.count == 4 else { return nil }
      let points = sprite.points.map {
        EngineGeometry.screenPoint($0, matrix: sprite.matrix, size: size)
      }
      guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
      let xs = points.map(\.x), ys = points.map(\.y)
      let bounds = CGRect(x: xs.min()!, y: ys.min()!,
        width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
      guard !bounds.isEmpty, bounds.intersects(screen) else { return nil }
      return Sprite(image: ObjectIdentifier(sprite.image), points: points,
        alpha: sprite.alpha, region: sprite.textureRegion,
        interpolation: sprite.interpolation,
        isStaticDecoration: sprite.isStaticIntroDecoration)
    }
    self.background = background
    self.ui = ui
  }
}

@MainActor
struct EngineIntroVisualGuard {
  enum Decision { case advance, stop, rewind }
  private var initial: EngineIntroVisualFrame?

  mutating func observe(_ frame: EngineIntroVisualFrame,
    hasParticles: Bool) -> Decision {
    // Particle effects already have an explicit lifetime. Preserve that start
    // even when their first frame is transparent or outside the viewport.
    guard let initial else {
      self.initial = frame
      if hasParticles || frame.sprites.contains(where: { !$0.isStaticDecoration }) {
        return .stop
      }
      return .advance
    }
    guard frame != initial else { return hasParticles ? .stop : .advance }
    // A newly appearing graphic starts here. If an initial graphic changes or
    // disappears, retain its held first state too (e.g. the "3" of a count-in),
    // rather than starting at its first transition to "2".
    guard frame.background == initial.background, frame.ui == initial.ui else {
      return .rewind
    }
    var next = frame.sprites.startIndex
    for sprite in initial.sprites {
      guard let index = frame.sprites[next...].firstIndex(of: sprite) else {
        return .rewind
      }
      next = index + 1
    }
    return .stop
  }
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
    host: CommandEngineRuntimeHost, assets: EnginePresentationAssets,
    cacheParticleRandomVariables: Bool = true,
    cacheParticleProperties: Bool = true
  ) -> [EngineRenderSprite] {
    if cacheParticleRandomVariables || cacheParticleProperties {
      assets.beginParticleFrame()
    }
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
            interpolation: assets.interpolation, textureRegion: patch.region,
            renderMode: assets.skinRenderMode,
            isStaticIntroDecoration: command.isStaticIntroDecoration))
        }
      } else {
        result.append(EngineRenderSprite(image: sprite.image, points: points,
          matrix: command.transform, alpha: command.alpha,
          interpolation: assets.interpolation, renderMode: assets.skinRenderMode,
          isStaticIntroDecoration: command.isStaticIntroDecoration))
      }
    }
    // The particle transform is frame-wide. Reading its sixteen values for
    // every emitted particle duplicates thousands of VM reads on busy hits.
    let particleMatrix = host.particles.isEmpty ? []
      : (0..<16).map { host.memory.value(block: 1004, index: $0) }
    for instance in host.particles.values.sorted(by: { $0.id < $1.id }) {
      guard let effect = assets.particles[instance.effectID] else { continue }
      let elapsed = (host.time - instance.startTime) / instance.duration
      let progress = instance.isLooped ? elapsed - floor(elapsed) : elapsed
      let seed = UInt64(instance.id)
      let variables = assets.particleVariables(seed: seed,
        cached: cacheParticleRandomVariables)
      let quad = EngineGeometry.transformed(
        instance.points, by: effect.transform, variables: variables
      )
      for (groupIndex, group) in effect.groups.enumerated() {
        for repetition in 0..<group.count {
          let groupSeed = seed &* 65_537 &+ UInt64(groupIndex * 1024 + repetition)
          let variables = assets.particleVariables(
            seed: groupSeed,
            cached: cacheParticleRandomVariables
          )
          for (particleIndex, particle) in group.particles.enumerated() {
            // A subparticle can straddle the parent effect's cycle boundary.
            // Keep its tail in the same animation interval after wrapping.
            let particleProgress = instance.isLooped && progress < particle.start
              ? progress + 1 : progress
            guard particle.duration > 0, particleProgress >= particle.start,
              particleProgress <= particle.start + particle.duration,
              assets.particleImages.indices.contains(particle.sprite)
            else { continue }
            let time = (particleProgress - particle.start) / particle.duration
            let properties = cacheParticleProperties
              ? assets.particleProperties(particle, key: .init(seed: groupSeed,
                effect: instance.effectID, group: groupIndex, particle: particleIndex),
                variables: variables)
              : EngineParticlePropertyCache.Properties(particle, variables: variables)
            let x = particle.x.value(at: time, endpoints: properties.x)
            let y = particle.y.value(at: time, endpoints: properties.y)
            let w = particle.w.value(at: time, endpoints: properties.w)
            let h = particle.h.value(at: time, endpoints: properties.h)
            let rotation = particle.r.value(at: time, endpoints: properties.r)
            let alpha = particle.a.value(at: time, endpoints: properties.a)
            let cosine = cos(rotation), sine = sin(rotation)
            let points = [(-1.0,-1.0),(-1,1),(1,1),(1,-1)].map { sx, sy in
              // Resource dimensions are local half-extents. The bilinear map
              // below already converts the -1...1 coordinate space to 0...1.
              let dx = sx * w
              let dy = sy * h
              return EngineGeometry.bilinear(quad,
                u: (x + dx * cosine - dy * sine + 1) / 2,
                v: (y + dx * sine + dy * cosine + 1) / 2)
            }
            let image = assets.particleImage(index: particle.sprite, key: particle.color)
            result.append(EngineRenderSprite(image: image, points: points,
              matrix: particleMatrix, alpha: alpha,
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
