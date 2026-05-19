import SwiftUI
@preconcurrency import UserNotifications

@MainActor
@Observable
final class SleepModeCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var activePresentation: SleepModePresentation?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func present(reason: SleepModeLaunchReason) {
        activePresentation = SleepModePresentation(reason: reason, startedAt: Date())
    }

    func dismiss() {
        activePresentation = nil
    }

    nonisolated static func launchReason(for actionIdentifier: String) -> SleepModeLaunchReason {
        actionIdentifier == SleepModeNotificationService.startActionIdentifier ? .notificationAction : .scheduled
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier.hasPrefix(SleepModeNotificationService.reminderIdentifierPrefix) else {
            return
        }

        await MainActor.run {
            activePresentation = SleepModePresentation(
                reason: Self.launchReason(for: response.actionIdentifier),
                startedAt: Date()
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
