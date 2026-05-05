import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case insights
    case `protocol`
    case biology
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            "Sleep"
        case .insights:
            "Insights"
        case .protocol:
            "Protocol"
        case .biology:
            "Biology"
        case .activity:
            "Activity"
        }
    }

    var systemImageName: String {
        switch self {
        case .sleep:
            "moon.fill"
        case .insights:
            "chart.bar.xaxis"
        case .protocol:
            "pills.fill"
        case .biology:
            "heart.fill"
        case .activity:
            "figure.run"
        }
    }

    var accentColor: Color {
        switch self {
        case .sleep:
            BetterColors.stageDeep
        case .insights:
            BetterColors.stageCore
        case .protocol:
            BetterColors.brand
        case .biology:
            BetterColors.heartRate
        case .activity:
            BetterColors.activity
        }
    }
}
