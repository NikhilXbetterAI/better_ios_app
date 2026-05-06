import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xxLarge) {
            Spacer(minLength: BetterSpacing.large)

            ZStack {
                Circle()
                    .fill(BetterColors.brand.opacity(0.18))
                    .frame(width: 112, height: 112)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(BetterColors.brand)
            }

            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("Better sleep starts with your baseline")
                    .font(BetterTypography.display)
                    .foregroundStyle(BetterColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Connect Apple Health and log your nights. It takes a few days to build your personal baseline. Once ready, you'll see associations between your habits and your sleep.")
                    .font(BetterTypography.body)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: BetterSpacing.medium) {
                OnboardingValueRow(icon: "heart.text.square.fill", title: "Data stays local", description: "Better reads sleep data securely from Apple Health.")
                OnboardingValueRow(icon: "magnifyingglass", title: "Find associations", description: "Compare your routines to your sleep metrics.")
                OnboardingValueRow(icon: "shield.fill", title: "Not a medical device", description: "Insights highlight trends, not medical causes.")
            }

            Spacer(minLength: BetterSpacing.large)
        }
    }
}

struct OnboardingValueRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 36, height: 36)
                .background(BetterColors.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(description)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
