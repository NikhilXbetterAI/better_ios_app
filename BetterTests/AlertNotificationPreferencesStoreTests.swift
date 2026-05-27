import Foundation
import XCTest
@testable import Better

@MainActor
final class AlertNotificationPreferencesStoreTests: XCTestCase {
    func testDefaultPreferencesLoadWhenStoreIsEmpty() {
        let suiteName = "better.alertPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAlertNotificationPreferencesStore(defaults: defaults)
        let loaded = store.load()

        XCTAssertEqual(loaded, .default)
        XCTAssertTrue(loaded.alertGenerationSettings.localNotificationsEnabled)
        XCTAssertEqual(
            loaded.alertGenerationSettings.notificationEnabledKinds,
            loaded.smartAlertSettings.enabledKinds.union([.baselineAvailable, .protocolPattern])
        )
    }

    func testPreferencesRoundTripIntoAlertGenerationSettings() {
        let suiteName = "better.alertPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAlertNotificationPreferencesStore(defaults: defaults)
        var preferences = AlertNotificationPreferences(
            dailyReminderSettings: DailyReminderSettings(isEnabled: true, hour: 7, minute: 30),
            smartAlertSettings: SmartAlertSettings(
                analysisReadyEnabled: true,
                lowScoreEnabled: false,
                lowDeepSleepEnabled: true,
                lowRemSleepEnabled: false,
                missedProtocolEnabled: true
            )
        )

        store.save(preferences)
        let loaded = store.load()

        XCTAssertEqual(loaded, preferences)
        XCTAssertTrue(loaded.alertGenerationSettings.localNotificationsEnabled)
        XCTAssertTrue(
            loaded.alertGenerationSettings.notificationEnabledKinds.isSuperset(
                of: [.analysisReady, .lowDeepSleep, .missedProtocol]
            )
        )

        preferences.smartAlertSettings.analysisReadyEnabled = false
        store.save(preferences)
        let reloaded = store.load()
        XCTAssertFalse(reloaded.smartAlertSettings.analysisReadyEnabled)
    }
}
