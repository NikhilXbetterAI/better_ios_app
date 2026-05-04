import SwiftUI

struct ResearchModeStepView: View {
    @Binding var isResearchMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xxLarge) {
            OnboardingStepHeader(
                icon: "doc.text.magnifyingglass",
                title: "Research mode",
                body: "Research mode unlocks CSV export and deeper protocol impact views. It is opt-in and can be changed later."
            )

            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                Toggle(isOn: $isResearchMode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable research mode")
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.text)
                        Text("Show export tools and protocol analytics for structured sleep experiments.")
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                    }
                }
                .tint(BetterColors.brand)

                Divider().overlay(BetterColors.border)

                OnboardingValueRow(icon: "square.and.arrow.up", title: "Export on demand", description: "Data stays local unless you explicitly export it.")
                OnboardingValueRow(icon: "chart.bar.xaxis", title: "Protocol context", description: "Compare adherent and non-adherent nights as correlation.")
            }
            .padding(BetterSpacing.large)
            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer()
        }
    }
}
