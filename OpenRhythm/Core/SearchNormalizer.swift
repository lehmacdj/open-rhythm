import Foundation

enum SearchNormalizer {
  static func normalize(_ value: String) -> String {
    value
      .precomposedStringWithCompatibilityMapping
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .components(separatedBy: .alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  static func searchableForms(of value: String) -> Set<String> {
    var forms = [normalize(value)]
    if let latin = value.applyingTransform(.toLatin, reverse: false) {
      forms.append(normalize(latin))
    }
    return Set(forms.filter { !$0.isEmpty })
  }

  static func tokens(in query: String) -> [String] {
    normalize(query).split(separator: " ").map(String.init)
  }
}

