import XCTest
final class ToodleUITests: XCTestCase {
    func testOfflineWalkthrough() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["Open Command Center"].waitForExistence(timeout:10)); app.buttons["Open Command Center"].tap()
        XCTAssertTrue(app.buttons["playStorm"].waitForExistence(timeout:10))
        app.swipeUp()
        let node = app.buttons["node-4"]
        if !node.isHittable { app.swipeUp() }
        XCTAssertTrue(node.waitForExistence(timeout:5)); node.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5)); app.buttons["Done"].tap()
        app.swipeDown(); app.buttons["playStorm"].tap()
        let hazard = app.buttons["Critical hazard · Preview dispatch"]
        app.swipeDown(); XCTAssertTrue(hazard.waitForExistence(timeout:15)); hazard.tap()
        app.buttons["Simulate dispatch"].tap(); XCTAssertTrue(app.staticTexts["dispatchResult"].waitForExistence(timeout:5)); app.buttons["Done"].tap()
        app.tabBars.buttons["Capture"].tap(); XCTAssertTrue(app.buttons["Analyze image"].exists)
        app.tabBars.buttons["Settings"].tap(); XCTAssertTrue(app.switches["offlineMode"].exists)
    }
}
