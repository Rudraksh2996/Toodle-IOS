import XCTest
@testable import ToodleCore
final class ToodleCoreTests: XCTestCase {
    func testVersion() { XCTAssertEqual(ToodleVersion.current, "1.0") }
}
