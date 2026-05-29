import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case insights
    case chronotype
    case `protocol`
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            "Sleep"
        case .insights:
            "Insights"
        case .chronotype:
            "Chronotype"
        case .protocol:
            "Formula"
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
        case .chronotype:
            "sun.horizon.fill"
        case .protocol:
            "pills.fill"
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
        case .chronotype:
            BetterColors.cyan
        case .protocol:
            BetterColors.brand
        case .settings:
            BetterColors.subtext
        }
    }
}
