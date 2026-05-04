import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case insights
    case `protocol`
    case alerts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            "Sleep"
        case .insights:
            "Insights"
        case .protocol:
            "Protocol"
        case .alerts:
            "Alerts"
        case .settings:
            "Settings"
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
        case .alerts:
            "bell.fill"
        case .settings:
            "gearshape.fill"
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
        case .alerts:
            BetterColors.stageREM
        case .settings:
            BetterColors.stageAwake
        }
    }
}
