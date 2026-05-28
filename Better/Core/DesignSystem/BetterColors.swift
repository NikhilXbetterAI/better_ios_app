import SwiftUI

enum BetterColors {
    static let background = Color(hex: "#000000")
    static let backgroundElevated = Color(hex: "#080808")
    static let card = Color(hex: "#0C0C0C")
    static let cardSecondary = Color(hex: "#141414")
    static let cardTertiary = Color(hex: "#1C1C1C")
    static let brand = Color(hex: "#6366F1")
    static let brandLight = Color(hex: "#818CF8")
    static let text = Color.white
    static let subtext = Color(hex: "#B6B7C4")
    static let mutedText = Color(hex: "#8E92A4")
    static let border = Color.white.opacity(0.08)

    // Style board tokens from the designer export.
    static let boardDeepCobaltBlue = Color(hex: "#02154A")
    static let boardGrey0 = Color(hex: "#F0F0F0")
    static let boardGrey1 = Color(hex: "#BFBFBF")
    static let boardGrey2 = Color(hex: "#878787")
    static let boardGrey3 = Color(hex: "#0A0A0A")
    static let boardLimeMist = Color(hex: "#F3FFC9")
    static let boardBackgroundPrimary = Color(hex: "#FFFFFF")
    static let boardBackgroundSecondary = Color(hex: "#011969")
    static let boardTextPrimary = Color(hex: "#000000")
    static let boardTextSecondary = Color(hex: "#666666")
    static let boardTextTertiary = Color(hex: "#767676")
    static let boardTextInvert = Color(hex: "#FFFFFF")
    static let boardBrand03 = Color(hex: "#9C73FF")
    static let boardDanger = Color(hex: "#CF1B42")

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [card, cardSecondary.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var boardHeroGradient: LinearGradient {
        LinearGradient(
            colors: [boardDeepCobaltBlue, boardBackgroundSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var boardHighlightGradient: LinearGradient {
        LinearGradient(
            colors: [boardBrand03, boardDeepCobaltBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassStroke: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }
    static let stageDeep = Color(hex: "#7C3AED")
    static let stageCore = Color(hex: "#007AFF")
    static let stageREM = Color(hex: "#38C7FF")
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
