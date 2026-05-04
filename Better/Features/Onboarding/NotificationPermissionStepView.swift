import SwiftUI

struct NotificationPermissionStepView: View {
    let isRequested: Bool
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xxLarge) {
            OnboardingStepHeader(
                icon: "bell.badge.fill",
                title: "Choose sleep reminders",
                body: "Notifications are optional. Better can nudge you when analysis is ready or when a sleep trend needs attention."
            )

            VStack(spacing: BetterSpacing.medium) {
                reminderRow(icon: "chart.line.uptrend.xyaxis", title: "Analysis ready", body: "Know when a new night has been processed.")
                reminderRow(icon: "moon.fill", title: "Sleep debt", body: "Catch short-sleep streaks before they compound.")
                reminderRow(icon: "pills.fill", title: "Protocol reminders", body: "Support consistency when research mode is enabled.")
            }
            .padding(BetterSpacing.large)
            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if isRequested {
                OnboardingNoticeView(
                    icon: isGranted ? "checkmark.circle.fill" : "bell.slash.fill",
                    title: isGranted ? "Notifications are enabled." : "Notifications were not enabled. You can turn them on later in Settings.",
                    color: isGranted ? BetterColors.success : BetterColors.warning
                )
            }

            Button(action: onRequest) {
                Label("Enable Notifications", systemImage: "bell.fill")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BetterColors.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func reminderRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 34, height: 34)
                .background(BetterColors.brand.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BetterTypography.subheadline).foregroundStyle(BetterColors.text)
                Text(body).font(BetterTypography.footnote).foregroundStyle(BetterColors.subtext)
            }
            Spacer()
        }
    }
}

