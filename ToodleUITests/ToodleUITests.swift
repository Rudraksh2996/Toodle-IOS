import XCTest
final class ToodleUITests: XCTestCase {
    func testLoginGateValidation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        guard app.staticTexts["Welcome to Toodle"].waitForExistence(timeout:10) else {
            throw XCTSkip("An authenticated Clerk session is already active")
        }
        let email = app.textFields["Email address"]
        XCTAssertTrue(email.exists)
        email.tap(); email.typeText("invalid-email")
        XCTAssertTrue(app.staticTexts["emailError"].exists)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
    }

    func testOfflineWalkthrough() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        if app.staticTexts["Welcome to Toodle"].waitForExistence(timeout:3) {
            throw XCTSkip("Offline walkthrough requires an authenticated Clerk test session")
        }
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
