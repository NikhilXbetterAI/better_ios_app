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

    @MainActor
    func testOnboardingHealthPermissionFlowUsesCompliantPrePromptControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-onboarding"]
        app.launch()

        let primaryButton = app.buttons["onboarding.primary"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 5))
        XCTAssertEqual(primaryButton.label, "Get Started")
        primaryButton.tap()

        let privacyPolicyButton = app.buttons["onboarding.privacyPolicy"]
        XCTAssertTrue(privacyPolicyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(privacyPolicyButton.isHittable)
        XCTAssertEqual(primaryButton.label, "Continue")
        primaryButton.tap()

        XCTAssertTrue(app.staticTexts["Apple Health Access"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        XCTAssertFalse(app.buttons["Skip for now"].exists)
        XCTAssertFalse(app.buttons["onboarding.back"].exists)
        XCTAssertEqual(primaryButton.label, "Continue")

        primaryButton.tap()
        XCTAssertTrue(app.staticTexts["Set your sleep goal"].waitForExistence(timeout: 3))
        XCTAssertEqual(primaryButton.label, "Continue")
        primaryButton.tap()

        XCTAssertTrue(app.staticTexts["A few quick sleep questions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        XCTAssertEqual(primaryButton.label, "Continue")
    }
}
