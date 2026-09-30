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

  func testPlainTextIsPreserved() {
    XCTAssertEqual(LocalizedText("μ's").displayValue(), "μ's")
  }
}
