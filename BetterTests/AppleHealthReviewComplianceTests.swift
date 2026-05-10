import XCTest
@testable import Better

final class AppleHealthReviewComplianceTests: XCTestCase {
    func testHealthKitPlistMatchesReadOnlyRepositoryBehavior() throws {
        let plist = try Self.infoPlist()

        XCTAssertNotNil(plist["NSHealthShareUsageDescription"])
        XCTAssertNil(
            plist["NSHealthUpdateUsageDescription"],
            "HealthKitRepository requests no share/write types, so the app must not declare a Health update usage description."
        )

        let backgroundModes = try XCTUnwrap(plist["UIBackgroundModes"] as? [String])
        XCTAssertTrue(backgroundModes.contains("fetch"))
        XCTAssertTrue(
            backgroundModes.contains("healthkit"),
            "The app enables HealthKit background delivery and has the entitlement, so UIBackgroundModes must include healthkit."
        )
    }

    func testHealthKitRepositoryRequestsReadOnlyAuthorization() throws {
        let source = try Self.source(named: "Better/Core/Repositories/HealthKitRepository.swift")

        XCTAssertTrue(source.contains("requestAuthorization(toShare: [], read: readTypes)"))
        XCTAssertFalse(source.contains("toShare: readTypes"))
    }

    func testNoDisallowedHealthPrePermissionCopyRemains() throws {
        let onboardingFlow = try Self.source(named: "Better/Features/Onboarding/OnboardingFlowView.swift")
        let healthStep = try Self.source(named: "Better/Features/Onboarding/HealthPermissionStepView.swift")
        let assessmentIntro = try Self.source(named: "Better/Features/Onboarding/SleepAssessmentIntroStepView.swift")
        let sleepBanner = try Self.source(named: "Better/Features/Sleep/HealthKitPermissionBannerView.swift")
        let welcome = try Self.source(named: "Better/Features/Onboarding/WelcomeStepView.swift")
        let combined = [onboardingFlow, healthStep, assessmentIntro, sleepBanner, welcome].joined(separator: "\n")

        XCTAssertFalse(combined.contains("Connect Apple Health"))
        XCTAssertFalse(combined.contains("buttonLabel: \"Connect\""))
        XCTAssertFalse(healthStep.contains("Skip for now"))
        XCTAssertFalse(healthStep.contains("Settings"))
        XCTAssertTrue(assessmentIntro.contains("Skip for now"))
        XCTAssertTrue(assessmentIntro.contains("Continue"))
        XCTAssertTrue(onboardingFlow.contains("case .notifications: true"))
        XCTAssertFalse(onboardingFlow.contains("case .health, .notifications: true"))
    }

    func testPrivacyPolicyAffordancesAreVisibleOutsideCrowdedCopyRows() throws {
        let onboardingFlow = try Self.source(named: "Better/Features/Onboarding/OnboardingFlowView.swift")
        let assessmentIntro = try Self.source(named: "Better/Features/Onboarding/SleepAssessmentIntroStepView.swift")
        let privacyDisclosure = try Self.source(named: "Better/Features/Onboarding/PrivacyDisclosureStepView.swift")
        let privacyControls = try Self.source(named: "Better/Features/Settings/PrivacyControlsView.swift")

        XCTAssertTrue(onboardingFlow.contains("accessibilityIdentifier(\"onboarding.privacyPolicy\")"))
        XCTAssertTrue(assessmentIntro.contains(".font(BetterTypography.title)"))
        XCTAssertTrue(assessmentIntro.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(privacyDisclosure.contains("Button(\"Privacy Policy\")"))
        XCTAssertTrue(privacyControls.contains("Label(\"Privacy Policy\", systemImage: \"lock.shield\")"))
        XCTAssertTrue(privacyControls.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }
}

private extension AppleHealthReviewComplianceTests {
    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func source(named relativePath: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent("Better/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }
}
