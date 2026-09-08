import CoreFoundation
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

  static func searchableForms(
    of value: String,
    languageCode: String? = nil
  ) -> Set<String> {
    var forms = [normalize(value)]
    let japanese = isJapanese(value, languageCode: languageCode)
    if !japanese,
      let latin = value.applyingTransform(.toLatin, reverse: false)
    {
      forms.append(normalize(latin))
    }
    if japanese,
      let transcription = japaneseLatinTranscription(of: value)
    {
      let normalized = normalize(transcription)
      forms.append(normalized)
      forms.append(normalized.replacingOccurrences(of: " ", with: ""))
    }
    return Set(forms.filter { !$0.isEmpty })
  }

  static func tokens(in query: String) -> [String] {
    normalize(query).split(separator: " ").map(String.init)
  }

  private static func isJapanese(
    _ value: String,
    languageCode: String?
  ) -> Bool {
    if languageCode?.lowercased().hasPrefix("ja") == true {
      return true
    }
    guard languageCode == nil || languageCode == "und" else {
      return false
    }

    let string = value as CFString
    let range = CFRange(location: 0, length: CFStringGetLength(string))
    let detected = CFStringTokenizerCopyBestStringLanguage(string, range)
    return (detected as String?)?.hasPrefix("ja") == true
  }

  private static func japaneseLatinTranscription(
    of value: String
  ) -> String? {
    let string = value as CFString
    let range = CFRange(location: 0, length: CFStringGetLength(string))
    let locale = NSLocale(localeIdentifier: "ja_JP") as CFLocale
    let options = kCFStringTokenizerUnitWord
      | kCFStringTokenizerAttributeLatinTranscription
    guard let tokenizer = CFStringTokenizerCreate(
      kCFAllocatorDefault,
      string,
      range,
      options,
      locale
    ) else { return nil }

    var tokens = [String]()
    while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
      if let transcription = CFStringTokenizerCopyCurrentTokenAttribute(
        tokenizer,
        kCFStringTokenizerAttributeLatinTranscription
      ) as? String {
        tokens.append(transcription)
      } else {
        let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let start = String.Index(
          utf16Offset: tokenRange.location,
          in: value
        )
        let end = String.Index(
          utf16Offset: tokenRange.location + tokenRange.length,
          in: value
        )
        tokens.append(String(value[start..<end]))
      }
    }
    return tokens.isEmpty ? nil : tokens.joined(separator: " ")
  }
}
