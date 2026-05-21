import Foundation
import Observation
import UIKit

enum RedLightFilterSetupStep: String, Codable, CaseIterable {
    case notStarted
    case colorTintConfiguredByUser
    case shortcutAddedByUser
    case accessibilityShortcutExplained
    case complete

    var order: Int {
        switch self {
        case .notStarted: return 0
        case .colorTintConfiguredByUser: return 1
        case .shortcutAddedByUser: return 2
        case .accessibilityShortcutExplained: return 3
        case .complete: return 4
        }
    }
}

enum RedLightFilterToggleResult: Equatable {
    case openedShortcut
    case shortcutsUnavailable
    case setupIncomplete
    case invalidURL
}

@MainActor
@Observable
final class RedLightFilterService {
    // Update this constant whenever the published iCloud Shortcut link changes.
    // The shortcut must contain a single `Set Color Filters` action with mode `Toggle`.
    static let shortcutName = "Better Red Sleep Mode"
    static let shortcutInstallURLString = "https://www.icloud.com/shortcuts/REPLACE_WITH_REAL_ID"

    private static let setupKey = "better.redLightFilter.setupStep.v1"
    private static let lastRequestedKey = "better.redLightFilter.lastRequestedOn.v1"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let opener: @MainActor (URL) -> Bool
    @ObservationIgnored private let canOpen: @MainActor (URL) -> Bool

    private(set) var setupStep: RedLightFilterSetupStep
    /// Optimistic local belief about whether the user wants the system tint on.
    /// iOS does not expose actual Color Filter state — never present this as truth.
    private(set) var lastRequestedState: Bool

    init(
        defaults: UserDefaults = .standard,
        opener: @escaping @MainActor (URL) -> Bool = { @MainActor url in
            UIApplication.shared.open(url)
            return true
        },
        canOpen: @escaping @MainActor (URL) -> Bool = { @MainActor url in
            UIApplication.shared.canOpenURL(url)
        }
    ) {
        self.defaults = defaults
        self.opener = opener
        self.canOpen = canOpen
        let raw = defaults.string(forKey: Self.setupKey) ?? RedLightFilterSetupStep.notStarted.rawValue
        self.setupStep = RedLightFilterSetupStep(rawValue: raw) ?? .notStarted
        self.lastRequestedState = defaults.bool(forKey: Self.lastRequestedKey)
    }

    var isSetupComplete: Bool { setupStep == .complete }

    func advance(to step: RedLightFilterSetupStep) {
        guard step.order >= setupStep.order else { return }
        setupStep = step
        defaults.set(step.rawValue, forKey: Self.setupKey)
    }

    func resetSetup() {
        setupStep = .notStarted
        defaults.set(RedLightFilterSetupStep.notStarted.rawValue, forKey: Self.setupKey)
    }

    @discardableResult
    func toggleSystemRedFilter() -> RedLightFilterToggleResult {
        guard isSetupComplete else { return .setupIncomplete }
        guard let url = runShortcutURL() else { return .invalidURL }
        if !canOpen(url) { return .shortcutsUnavailable }
        _ = opener(url)
        lastRequestedState.toggle()
        defaults.set(lastRequestedState, forKey: Self.lastRequestedKey)
        return .openedShortcut
    }

    func openShortcutInstallPage() {
        guard let url = URL(string: Self.shortcutInstallURLString) else { return }
        _ = opener(url)
    }

    /// Opens Better's own app settings page. Per Apple's docs `openSettingsURLString`
    /// does NOT deep-link into Settings > Accessibility. The wizard copy must reflect that.
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        _ = opener(url)
    }

    func runShortcutURL() -> URL? {
        let encoded = Self.shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.shortcutName
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    }
}
