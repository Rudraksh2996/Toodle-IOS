import XCTest
final class ToodleUITests: XCTestCase {
    func testLaunchShowsTabs() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
