import Foundation
import Observation

@MainActor
@Observable
final class RedLightFilterSetupViewModel {
    @ObservationIgnored let service: RedLightFilterService

    private(set) var lastToggleResult: RedLightFilterToggleResult?
    var showRecoveryMessage: Bool { lastToggleResult == .shortcutsUnavailable || lastToggleResult == .invalidURL }

    init(service: RedLightFilterService) {
        self.service = service
    }

    var step: RedLightFilterSetupStep { service.setupStep }

    func confirmColorTintConfigured() {
        service.advance(to: .colorTintConfiguredByUser)
    }

    func openShortcutInstall() {
        service.openShortcutInstallPage()
    }

    func confirmShortcutAdded() {
        service.advance(to: .shortcutAddedByUser)
    }

    func acknowledgeAccessibilityShortcut() {
        service.advance(to: .accessibilityShortcutExplained)
    }

    func openAppSettings() {
        service.openAppSettings()
    }

    func testToggle() {
        // Advance setup to complete before testing so the service runs the URL.
        if step != .complete {
            service.advance(to: .accessibilityShortcutExplained)
            service.advance(to: .complete)
        }
        lastToggleResult = service.toggleSystemRedFilter()
    }

    var recoveryMessage: String {
        switch lastToggleResult {
        case .shortcutsUnavailable:
            return "Your iPhone could not open the Shortcuts app. Make sure Shortcuts is installed, then try again."
        case .invalidURL:
            return "Better could not build the Shortcut link. Reinstall Better or contact support."
        case .setupIncomplete:
            return "Finish the previous steps, then test the toggle."
        case .openedShortcut, nil:
            return ""
        }
    }
}
