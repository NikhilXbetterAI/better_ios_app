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
        for tab in ["Sleep", "Insights", "Protocol", "Biology", "Activity"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 5),
                "Expected root tab '\(tab)' to exist"
            )
        }

        // Sleep tab shows the real dashboard (BETTER SLEEP header label)
        XCTAssertTrue(app.staticTexts["BETTER SLEEP"].waitForExistence(timeout: 5))

        // Root tabs render their real headers.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Protocol"].tap()
        XCTAssertTrue(app.staticTexts["Protocol"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Biology"].tap()
        XCTAssertTrue(app.staticTexts["Biology"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 3))
    }
}
