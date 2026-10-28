import XCTest
@testable import OpenRhythm

final class LocalizedTextTests: XCTestCase {
  func testBundledStandardTextTableIsCompleteAndUsedVerbatim() {
    // Pin the resource count so a missing/partial copied-resource build cannot
    // silently substitute identifier title-casing for arbitrary engine labels.
    XCTAssertEqual(EngineStandardText.english.count, 596)
    for (identifier, expected) in EngineStandardText.english {
      XCTAssertTrue(identifier.hasPrefix("#"))
      XCTAssertEqual(EngineStandardText.label(identifier), expected)
    }
    XCTAssertEqual(EngineStandardText.label("#SPEED"), "Level Speed")
    XCTAssertEqual(EngineStandardText.label("#ON"), "ON")
    XCTAssertEqual(EngineStandardText.label(""), "")
    XCTAssertEqual(EngineStandardText.label("not #STAGE_ALPHA"),
      "not #STAGE_ALPHA")
  }

  func testParsesAndSelectsLocalizedValue() {
    let text = LocalizedText(
      #"##LOCALIZE:{"ja":"僕らのLIVE 君とのLIFE","en":"Bokura no LIVE Kimi to no LIFE"}"#
    )

    XCTAssertEqual(
      text.displayValue(locale: Locale(identifier: "ja")),
      "僕らのLIVE 君とのLIFE"
    )
    XCTAssertEqual(
      text.displayValue(locale: Locale(identifier: "en_US")),
      "Bokura no LIVE Kimi to no LIFE"
    )
  }

  func testDeviceLocalesMapToSonolusCodes() {
    let expected = [
      "zh-Hans_CN": "zhs", "zh-Hant_TW": "zht", "zh-Hant_US": "zht",
      "zh-Hans_HK": "zhs", "zh_TW": "zht", "zh_HK": "zht", "zh_MO": "zht",
      "zh_CN": "zhs", "zh_SG": "zhs", "zh": "zhs", "ja_JP": "ja",
      "en_US": "en", "ko": "ko", "pt_BR": "pt"
    ]
    for (identifier, code) in expected {
      XCTAssertEqual(Locale(identifier: identifier).sonolusLocalization, code,
        identifier)
    }
    let text = LocalizedText(#"##LOCALIZE:{"zhs":"简体","zht":"繁體"}"#)
    XCTAssertEqual(text.displayValue(locale: Locale(identifier: "zh-Hant_HK")),
      "繁體")
    XCTAssertEqual(text.displayValue(locale: Locale(identifier: "zh-Hans_CN")),
      "简体")
  }

  func testMissingLanguageShowsTheFirstLanguageAsWritten() {
    let french = Locale(identifier: "fr_FR")
    // Many keys make an accidental pass through hash order unlikely.
    let codes = ["el", "en", "es", "id", "it", "ja", "ko", "ru", "tr", "zhs"]
    for first in codes {
      let rest = codes.filter { $0 != first }
      let json = ([first] + rest).map { #""\#($0)":"\#($0) value""# }
        .joined(separator: ",")
      XCTAssertEqual(
        LocalizedText("##LOCALIZE:{\(json)}").displayValue(locale: french),
        "\(first) value")
    }
    // Escaped quotes and non-ASCII keys don't disturb the order.
    let escaped = LocalizedText(
      #"##LOCALIZE:{ "x\"y" : "a \"quoted\" \\ value", "日本" :"b"}"#)
    XCTAssertEqual(escaped.displayValue(locale: french), #"a "quoted" \ value"#)
    XCTAssertEqual(LocalizedText(#"##LOCALIZE:{"en":"x"}"#)
      .displayValue(locale: Locale(identifier: "en_GB")), "x")
    XCTAssertEqual(LocalizedText("##LOCALIZE:{not json").displayValue(),
      "##LOCALIZE:{not json")
  }

  func testSearchValuesAreDeterministic() {
    let text = LocalizedText(
      #"##LOCALIZE:{"ja":"b","en":"a","ko":"c","fr":"a"}"#)
    XCTAssertEqual(text.searchValues, ["a", "b", "c"])
  }

  func testPlainTextIsPreserved() {
    XCTAssertEqual(LocalizedText("μ's").displayValue(), "μ's")
  }
}
