import XCTest
@testable import PrismKit

final class PrismKitTests: XCTestCase {
  func testHealth() {
    XCTAssertEqual(PrismKit.health(), "ok:PrismKit")
  }
}
