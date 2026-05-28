import SwiftUI

/// Protocol Formula V1 design tokens — derived from `protocol-v3-core.jsx`'s `PV` and
/// `VERSIONS` constants. We layer these on top of `BetterColors` rather than replace it,
/// since the rest of the app uses the indigo brand. Hex parsing uses the existing
/// `Color(hex:)` initializer from `Core/DesignSystem/Color+Hex.swift`.
enum ProtocolPalette {
    static func versionColor(hex: String) -> Color { Color(hex: hex) }

    /// JSX `PV.addin` — amber, used for add-in chips and notes.
    static let addinColor = Color(hex: "#FBBF24")
    static let goodColor = Color(hex: "#4ADE80")
    static let badColor = Color(hex: "#F87171")
    static let baselineColor = Color.white.opacity(0.38)
    static let mutedText = Color.white.opacity(0.58)
    static let dimText = Color.white.opacity(0.36)
    static let faintText = Color.white.opacity(0.18)
    
    static let backgroundColor = Color(hex: "#0C0A09")
    static let surfaceColor = Color.white.opacity(0.04)
    static let borderColor = Color.white.opacity(0.09)
    static let borderStrColor = Color.white.opacity(0.16)
    static let brandColor = Color(hex: "#67E8F9")

    // Unified sleep stage colors — used everywhere stages appear
    static let deepColor   = Color(hex: "#818CF8")  // Indigo
    static let remColor    = Color(hex: "#F472B6")  // Pink
    static let lightColor  = Color(hex: "#60A5FA")  // Blue
    static let awakeColor  = Color(hex: "#FB923C")  // Orange
}

