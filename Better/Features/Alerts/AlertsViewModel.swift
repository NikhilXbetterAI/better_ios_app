import Foundation
import Observation

struct DailyReminderSettings: Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    static let `default` = DailyReminderSettings(isEnabled: false, hour: 21, minute: 0)
}

struct SmartAlertSettings: Sendable {
    var lowScoreEnabled: Bool
    var lowDeepSleepEnabled: Bool
    var lowRemSleepEnabled: Bool
    var missedProtocolEnabled: Bool

    static let `default` = SmartAlertSettings(
        lowScoreEnabled: true,
        lowDeepSleepEnabled: true,
        lowRemSleepEnabled: true,
        missedProtocolEnabled: false
    )
}

@MainActor
@Observable
final class AlertsViewModel {
    private static let alertDisplayLimit = 100

    private let localRepository: LocalDataRepositoryProtocol

    var alerts: [SleepAlert] = []
    var unreadCount: Int = 0
    var groupedAlerts: [SleepAlertKind: [SleepAlert]] = [:]
    var dailyReminderSettings: DailyReminderSettings = .default
    var smartAlertSettings: SmartAlertSettings = .default
    var isLoading = false
    var errorMessage: String?

    init(localRepository: LocalDataRepositoryProtocol) {
        self.localRepository = localRepository
    }

    func onAppear() async {
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
}
