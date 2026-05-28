import XCTest
@testable import Better

final class AppleHealthReviewComplianceTests: XCTestCase {
    func testHealthKitPlistMatchesReadOnlyRepositoryBehavior() throws {
        let plist = try Self.infoPlist()

        let sharePurpose = try XCTUnwrap(plist["NSHealthShareUsageDescription"] as? String)
        let updatePurpose = try XCTUnwrap(
            plist["NSHealthUpdateUsageDescription"] as? String,
            "App Store validation requires the Health update purpose string when HealthKit capability is present, even though Better requests no write types."
        )
        XCTAssertFalse(sharePurpose.isEmpty)
        XCTAssertTrue(updatePurpose.contains("does not save data to Apple Health"))

        let backgroundModes = try XCTUnwrap(plist["UIBackgroundModes"] as? [String])
        let validIOSBackgroundModes: Set<String> = [
            "audio",
            "bluetooth-central",
            "bluetooth-peripheral",
            "external-accessory",
            "fetch",
            "location",
            "nearby-interaction",
            "network-authentication",
            "newsstand-content",
            "processing",
            "push-to-talk",
            "remote-notification",
            "voip"
        ]
        XCTAssertTrue(backgroundModes.contains("fetch"))
        XCTAssertTrue(Set(backgroundModes).isSubset(of: validIOSBackgroundModes))
        XCTAssertFalse(
            backgroundModes.contains("healthkit"),
            "healthkit is not a valid iOS UIBackgroundModes value; HealthKit observer delivery is controlled by the HealthKit background-delivery entitlement."
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
        // The shared "Skip for now" / "Continue" CTAs now live in OnboardingFlowView's bottom chrome,
        // gated by step.canSkip / resolvedPrimaryTitle, so the strings appear there rather than in
        // SleepAssessmentIntroStepView itself.
        XCTAssertTrue(onboardingFlow.contains("Skip for now"))
        XCTAssertTrue(onboardingFlow.contains("\"Continue\""))
        XCTAssertTrue(onboardingFlow.contains(".assessmentIntro, .notifications: true"))
        XCTAssertFalse(onboardingFlow.contains("case .health, .notifications: true"))
        XCTAssertFalse(onboardingFlow.contains("case .health, .assessmentIntro, .notifications: true"))
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
