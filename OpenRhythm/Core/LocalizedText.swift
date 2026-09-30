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

  init(_ rawValue: String) {
    self.rawValue = rawValue

    guard rawValue.hasPrefix(Self.prefix) else {
      values = ["und": rawValue]
      return
    }

    let json = String(rawValue.dropFirst(Self.prefix.count))
    values = (try? JSONDecoder().decode(
      [String: String].self,
      from: Data(json.utf8)
    )) ?? ["und": rawValue]
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  func displayValue(locale: Locale = .current) -> String {
    let languageCode = locale.language.languageCode?.identifier
    let identifiers: [String] = [
      locale.identifier,
      languageCode,
      "en",
      "ja",
      "und"
    ].compactMap { $0 }

    for identifier in identifiers {
      if let value = values[identifier] {
        return value
      }
    }

    return values.values.first ?? rawValue
  }

  var searchValues: [String] {
    Array(Set(values.values))
  }
}
