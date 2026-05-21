import SwiftUI

struct ProtocolCaveatFooter: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(ProtocolPalette.dimText)
            Text(ProtocolImpactSummary.causalityCaveat)
                .font(.caption2)
                .foregroundStyle(ProtocolPalette.dimText)
                .accessibilityLabel("Disclaimer: \(ProtocolImpactSummary.causalityCaveat)")
        }
        .padding(.top, 4)
    }
}
