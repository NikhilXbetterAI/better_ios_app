import XCTest

final class BetterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testShellRendersPrimaryTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Primary tabs are present
        for tab in ["Sleep", "Insights", "Chronotype", "Formula", "Settings"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 5),
                "Expected root tab '\(tab)' to exist"
            )
        }
        XCTAssertFalse(app.tabBars.buttons["Biology"].exists)
        XCTAssertFalse(app.tabBars.buttons["Activity"].exists)

        // Sleep tab shows the real dashboard (BETTER SLEEP header label)
        XCTAssertTrue(app.staticTexts["BETTER SLEEP"].waitForExistence(timeout: 5))

        // Root tabs render their real headers. The Formula tab can render either its
        // dashboard ("Formula") or its onboarding ("Sleep Formula Tracking") depending
        // on whether any formula versions exist in the preview store.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Formula"].tap()
        let protocolHeader = app.staticTexts["Formula"]
        let protocolOnboardingHeader = app.staticTexts["Sleep Formula Tracking"]
        XCTAssertTrue(
            protocolHeader.waitForExistence(timeout: 3) || protocolOnboardingHeader.waitForExistence(timeout: 3),
            "Expected either the Formula dashboard or its onboarding screen to appear"
        )
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

        // The first tap on .health triggers connectHealth() but stays on the step;
        // the user must tap a second time to advance once authorization completes.
        primaryButton.tap()
        primaryButton.tap()
        XCTAssertTrue(app.staticTexts["Set your sleep goal"].waitForExistence(timeout: 5))
        XCTAssertEqual(primaryButton.label, "Continue")
        primaryButton.tap()

        XCTAssertTrue(app.staticTexts["A few quick sleep questions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        XCTAssertEqual(primaryButton.label, "Continue")
    }
}
