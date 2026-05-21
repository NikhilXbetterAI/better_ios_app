import SwiftUI

struct RedLightFilterToggleRow: View {
    let isSetupComplete: Bool
    @Binding var overlayEnabled: Bool
    let onTapSystemToggle: () -> Void
    let onTapSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: "moon.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(Color.red.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Red Sleep Mode")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(isSetupComplete ? "Tint your whole iPhone red via Shortcuts." : "One-time setup required.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: BetterSpacing.small)
                Button(action: isSetupComplete ? onTapSystemToggle : onTapSetup) {
                    Text(isSetupComplete ? "Tint iPhone" : "Set up")
                        .font(BetterTypography.caption.bold())
                        .foregroundStyle(BetterColors.text)
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, BetterSpacing.small)
                        .background(Color.red.opacity(0.32), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $overlayEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tint in Better only")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.text)
                    Text("Adds a red overlay inside Sleep Mode without touching system settings.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.red.opacity(0.7))
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.card.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }
}
