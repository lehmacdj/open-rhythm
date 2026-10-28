import Foundation

/// Public Sonolus Text identifiers, in the app's current UI language (English).
/// This is a pinned offline protocol-label table, not a dependency on the
/// Sonolus app. Its source revision and MIT notice travel with the resource.
enum EngineStandardText {
  private final class ResourceMarker {}
  private struct Table: Decodable {
    let texts: [String: String]
  }

  static let english: [String: String] = {
    guard let url = Bundle(for: ResourceMarker.self).url(
      forResource: "EngineStandardText", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let table = try? JSONDecoder().decode(Table.self, from: data) else {
      assertionFailure("The bundled engine text table is missing or invalid.")
      return [:]
    }
    return table.texts
  }()

  static func label(_ text: String) -> String {
    guard text.hasPrefix("#") else { return text }
    return english[text]
      ?? text.dropFirst().replacingOccurrences(of: "_", with: " ").capitalized
  }
}

struct LocalizedText: Codable, Hashable, Sendable {
  private static let prefix = "##LOCALIZE:"

  let rawValue: String
  let values: [String: String]
  /// The keys of `values` in the order the server wrote them.
  private let keys: [String]

  init(_ rawValue: String) {
    self.rawValue = rawValue
    let json = Data(rawValue.dropFirst(Self.prefix.count).utf8)
    guard rawValue.hasPrefix(Self.prefix),
      let values = try? JSONDecoder().decode([String: String].self, from: json)
    else {
      values = ["und": rawValue]
      keys = ["und"]
      return
    }
    self.values = values
    // Decoders don't keep object order, so recover it from the text.
    let ordered = Self.orderedKeys(in: json)
    keys = Set(ordered) == Set(values.keys) ? ordered : values.keys.sorted()
  }

  /// A flat object of strings lists its string literals as key, value, key,
  /// value, …; one decode of those literals as an array yields its keys.
  private static func orderedKeys(in json: Data) -> [String] {
    let bytes = [UInt8](json)
    var literals = [ArraySlice<UInt8>]()
    var index = 0
    while index < bytes.count {
      guard bytes[index] == UInt8(ascii: "\"") else { index += 1; continue }
      let start = index
      index += 1
      while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
        index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
      }
      index += 1
      literals.append(bytes[start..<min(index, bytes.count)])
    }
    let array = Data("[".utf8)
      + Data(literals.joined(separator: Array(",".utf8))) + Data("]".utf8)
    guard let strings = try? JSONDecoder().decode([String].self, from: array)
    else { return [] }
    var seen = Set<String>()
    return stride(from: 0, to: strings.count, by: 2)
      .map { strings[$0] }.filter { seen.insert($0).inserted }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Sonolus shows the first language written when the player's is absent.
  func displayValue(locale: Locale = .current) -> String {
    values[locale.sonolusLocalization]
      ?? keys.first.flatMap { values[$0] } ?? rawValue
  }

  var searchValues: [String] {
    Set(values.values).sorted()
  }
}

extension Locale {
  /// The Sonolus `localization` code for this locale. Sonolus names Chinese
  /// by script (zhs, zht); other languages use their language code.
  var sonolusLocalization: String {
    let code = language.languageCode?.identifier ?? "en"
    guard code == "zh" else { return code }
    switch language.script?.identifier {
    case "Hans": return "zhs"
    case "Hant": return "zht"
    default:
      return ["TW", "HK", "MO"].contains(region?.identifier ?? "")
        ? "zht" : "zhs"
    }
  }
}
