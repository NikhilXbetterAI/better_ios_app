import SwiftUI

enum BetterTypography {
    static let display = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let largeTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let subheadline = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .medium, design: .rounded)
    static let footnote = Font.system(size: 13, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let micro = Font.system(size: 10, weight: .medium, design: .rounded)
    static let metric = Font.system(size: 34, weight: .bold, design: .rounded)
    static let compactMetric = Font.system(size: 25, weight: .bold, design: .rounded)

    // Built-in approximations for the board's type system.
    static let boardDisplay = Font.system(size: 34, weight: .regular, design: .serif)
    static let boardTitle = Font.system(size: 22, weight: .semibold, design: .serif)
    static let boardBody = Font.system(size: 16, weight: .regular, design: .serif)
    static let boardMonoBody = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let boardMonoLabel = Font.system(size: 12, weight: .semibold, design: .monospaced)
}
