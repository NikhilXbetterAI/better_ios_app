import XCTest

final class BetterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testShellRendersFiveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // All five tabs are present
        XCTAssertTrue(app.tabBars.buttons["Sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Insights"].exists)
        XCTAssertTrue(app.tabBars.buttons["Protocol"].exists)
        XCTAssertTrue(app.tabBars.buttons["Alerts"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)

        // Sleep tab shows the real dashboard (BETTER SLEEP header label)
        XCTAssertTrue(app.staticTexts["BETTER SLEEP"].waitForExistence(timeout: 5))

        // Phase 6 tabs render their real headers.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Protocol"].tap()
        XCTAssertTrue(app.staticTexts["Protocol"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Alerts"].tap()
        XCTAssertTrue(app.staticTexts["Alerts"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }
}
