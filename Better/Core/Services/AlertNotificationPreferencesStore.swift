import Foundation

nonisolated protocol AlertNotificationPreferencesStoring: Sendable {
    func load() -> AlertNotificationPreferences
    func save(_ preferences: AlertNotificationPreferences)
    func clear()
}

nonisolated struct AlertNotificationPreferences: Codable, Hashable, Sendable {
    var dailyReminderSettings: DailyReminderSettings
    var smartAlertSettings: SmartAlertSettings

    static let `default` = AlertNotificationPreferences(
        dailyReminderSettings: .default,
        smartAlertSettings: .default
    )

    var enabledKinds: Set<SleepAlertKind> {
        smartAlertSettings.enabledKinds
    }

    var alertGenerationSettings: AlertGenerationSettings {
        var settings = AlertGenerationSettings.default
        settings.localNotificationsEnabled = dailyReminderSettings.isEnabled || !enabledKinds.isEmpty
        settings.notificationEnabledKinds = enabledKinds.union([.baselineAvailable, .protocolPattern])
        return settings
    }
}

nonisolated final class UserDefaultsAlertNotificationPreferencesStore: AlertNotificationPreferencesStoring, @unchecked Sendable {
    private static let storageKey = "better.alertNotificationPreferences.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> AlertNotificationPreferences {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? decoder.decode(AlertNotificationPreferences.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func save(_ preferences: AlertNotificationPreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
