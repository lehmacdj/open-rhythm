import XCTest
@testable import OpenRhythm

final class LocalizedTextTests: XCTestCase {
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

