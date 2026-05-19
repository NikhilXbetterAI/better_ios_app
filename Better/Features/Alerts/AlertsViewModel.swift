import Foundation
import Observation

nonisolated struct DailyReminderSettings: Codable, Sendable, Hashable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    static let `default` = DailyReminderSettings(isEnabled: false, hour: 21, minute: 0)
}

nonisolated struct SmartAlertSettings: Codable, Sendable, Hashable {
    var analysisReadyEnabled: Bool
    var lowScoreEnabled: Bool
    var lowDeepSleepEnabled: Bool
    var lowRemSleepEnabled: Bool
    var missedProtocolEnabled: Bool

    static let `default` = SmartAlertSettings(
        analysisReadyEnabled: true,
        lowScoreEnabled: true,
        lowDeepSleepEnabled: true,
        lowRemSleepEnabled: true,
        missedProtocolEnabled: false
    )

    var enabledKinds: Set<SleepAlertKind> {
        var kinds: Set<SleepAlertKind> = []
        if analysisReadyEnabled { kinds.insert(.analysisReady) }
        if lowScoreEnabled { kinds.insert(.lowScore) }
        if lowDeepSleepEnabled { kinds.insert(.lowDeepSleep) }
        if lowRemSleepEnabled { kinds.insert(.lowRemSleep) }
        if missedProtocolEnabled { kinds.insert(.missedProtocol) }
        return kinds
    }
}

@MainActor
@Observable
final class AlertsViewModel {
    private static let alertDisplayLimit = 100

    private let localRepository: LocalDataRepositoryProtocol
    private let notificationPreferencesStore: AlertNotificationPreferencesStoring

    var alerts: [SleepAlert] = []
    var unreadCount: Int = 0
    var groupedAlerts: [SleepAlertKind: [SleepAlert]] = [:]
    var dailyReminderSettings: DailyReminderSettings = .default {
        didSet { saveNotificationPreferencesIfNeeded() }
    }
    var smartAlertSettings: SmartAlertSettings = .default {
        didSet { saveNotificationPreferencesIfNeeded() }
    }
    var isLoading = false
    var errorMessage: String?
    private var isApplyingNotificationPreferences = false

    init(
        localRepository: LocalDataRepositoryProtocol,
        notificationPreferencesStore: AlertNotificationPreferencesStoring = UserDefaultsAlertNotificationPreferencesStore()
    ) {
        self.localRepository = localRepository
        self.notificationPreferencesStore = notificationPreferencesStore
    }

    func onAppear() async {
        loadNotificationPreferences()
        await loadAlerts()
    }

    func markRead(_ alert: SleepAlert) async {
        do {
            try await localRepository.markAlertRead(id: alert.id)
            await loadAlerts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead() async {
        do {
            for alert in alerts where !alert.isRead {
                try await localRepository.markAlertRead(id: alert.id)
            }
            await loadAlerts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAlerts() async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await localRepository.fetchProfile()
            let appStartKey = SleepDateKey.calendarDateKey(for: profile.createdAt)
            alerts = try await localRepository.fetchAlerts(
                unreadOnly: false,
                fromSleepDateKey: appStartKey,
                limit: Self.alertDisplayLimit
            )
            let unreadAlerts = try await localRepository.fetchAlerts(
                unreadOnly: true,
                fromSleepDateKey: appStartKey,
                limit: nil
            )
            unreadCount = unreadAlerts.count
            groupedAlerts = Dictionary(grouping: alerts, by: \.kind)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadNotificationPreferences() {
        isApplyingNotificationPreferences = true
        let preferences = notificationPreferencesStore.load()
        dailyReminderSettings = preferences.dailyReminderSettings
        smartAlertSettings = preferences.smartAlertSettings
        isApplyingNotificationPreferences = false
    }

    private func saveNotificationPreferencesIfNeeded() {
        guard !isApplyingNotificationPreferences else { return }
        notificationPreferencesStore.save(
            AlertNotificationPreferences(
                dailyReminderSettings: dailyReminderSettings,
                smartAlertSettings: smartAlertSettings
            )
        )
    }
}
