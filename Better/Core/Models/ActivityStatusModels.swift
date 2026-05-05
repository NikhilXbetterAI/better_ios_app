import Foundation
import SwiftUI

nonisolated enum UserActivityStatus: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case active
    case traveling
    case sick
    case jetLagged
    case injured

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .traveling: "Traveling"
        case .sick: "Sick"
        case .jetLagged: "Jet Lagged"
        case .injured: "Injured"
        }
    }

    var subtitle: String {
        switch self {
        case .active: "Training and routine are normal"
        case .traveling: "Away from your normal environment"
        case .sick: "Recovery needs more rest"
        case .jetLagged: "Circadian rhythm is adjusting"
        case .injured: "Recovery load may affect sleep"
        }
    }

    var systemImageName: String {
        switch self {
        case .active: "figure.run"
        case .traveling: "airplane"
        case .sick: "cross.case.fill"
        case .jetLagged: "globe.asia.australia.fill"
        case .injured: "bandage.fill"
        }
    }

    @MainActor
    var accentColor: Color {
        switch self {
        case .active: BetterColors.success
        case .traveling: BetterColors.activity
        case .sick: BetterColors.warning
        case .jetLagged: BetterColors.violet
        case .injured: BetterColors.danger
        }
    }

    var insight: String {
        switch self {
        case .active:
            "Active day logged. Compare deep sleep, HRV, and soreness patterns before changing training load."
        case .traveling:
            "Travel logged. Sleep timing and respiratory changes can be interpreted with environment disruption in mind."
        case .sick:
            "Sick day logged. Prioritize sleep duration and watch HRV or resting heart rate recovery before resuming intensity."
        case .jetLagged:
            "Jet lag logged. Expect schedule drift and lighter sleep while your circadian rhythm stabilizes."
        case .injured:
            "Injury logged. Higher awakenings or lower HRV may reflect tissue repair and discomfort rather than routine failure."
        }
    }
}

nonisolated struct ActivityStatusLog: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var dateKey: String
    var status: UserActivityStatus
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dateKey: String,
        status: UserActivityStatus,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
