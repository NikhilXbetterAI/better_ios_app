import SwiftUI

enum BetterColors {
    static let background = Color(hex: "#07070F")
    static let backgroundElevated = Color(hex: "#10111B")
    static let card = Color(hex: "#1C1E2E")
    static let cardSecondary = Color(hex: "#232538")
    static let cardTertiary = Color(hex: "#2B3042")
    static let brand = Color(hex: "#6366F1")
    static let brandLight = Color(hex: "#818CF8")
    static let text = Color.white
    static let subtext = Color(hex: "#9A9AA7")
    static let mutedText = Color(hex: "#666979")
    static let border = Color.white.opacity(0.08)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [card, cardSecondary.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var glassStroke: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }
    static let stageDeep = Color(hex: "#7C3AED")
    static let stageCore = Color(hex: "#2F80ED")
    static let stageREM = Color(hex: "#8FD3FF")
    static let stageAwake = Color(hex: "#FF8A4C")
    // Semantic metric colors
    static let success = Color(hex: "#32D74B")
    static let warning = Color(hex: "#FF9F0A")
    static let danger = Color(hex: "#FF453A")
    static let heartRate = Color(hex: "#FF4F9A")
    static let hrv = Color(hex: "#2DD4BF")
    static let activity = Color(hex: "#0A84FF")
    static let violet = Color(hex: "#BF5AF2")
    static let cyan = Color(hex: "#64D2FF")
}

extension SleepStageType {
    var color: Color {
        switch self {
        case .deep: BetterColors.stageDeep
        case .core: BetterColors.stageCore
        case .rem: BetterColors.stageREM
        case .awake: BetterColors.stageAwake
        case .unspecified: BetterColors.brand.opacity(0.6)
        case .inBed: BetterColors.subtext.opacity(0.4)
        }
    }
}
