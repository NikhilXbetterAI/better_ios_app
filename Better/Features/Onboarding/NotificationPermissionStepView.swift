import SwiftUI

struct NotificationPermissionStepView: View {
    let isRequested: Bool
    let isGranted: Bool
    let onRequest: () -> Void

    @State private var cardOffsets: [CGFloat] = [100, 100, 100]
    @State private var cardOpacities: [Double] = [0, 0, 0]

    private let mockNotifications: [(title: String, body: String, delay: Double)] = [
        ("Better", "Your sleep analysis for last night is ready.", 0.10),
        ("Better", "3-night sleep debt alert: you're 2.4h behind your goal.", 0.22),
        ("Better", "Protocol reminder: wind-down routine starts in 30 min.", 0.34),
    ]

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero: mock notification cards ─────────────────────────────
                heroArea
                    .frame(height: screenHeight * 0.40)
                    .clipped()

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.small) {
                    Text("Choose sleep reminders")
                        .font(BetterTypography.boardDisplay)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Notifications are optional. Better nudges you when analysis is ready or when a sleep trend needs attention.")
                        .font(BetterTypography.boardBody)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Reminder type rows ────────────────────────────────────────
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    reminderRow("chart.line.uptrend.xyaxis", "Analysis ready", "Know when a new night has been processed.", BetterColors.brand)
                    Divider().overlay(BetterColors.border)
                    reminderRow("moon.fill", "Sleep debt", "Catch short-sleep streaks before they compound.", BetterColors.stageDeep)
                    Divider().overlay(BetterColors.border)
                    reminderRow("pills.fill", "Protocol reminders", "Support consistency when research mode is enabled.", BetterColors.stageAwake)
                }
                .padding(BetterSpacing.large)
                .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                // ── Status ────────────────────────────────────────────────────
                if isRequested {
                    OnboardingNoticeView(
                        icon: isGranted ? "checkmark.circle.fill" : "bell.slash.fill",
                        title: isGranted
                            ? "Notifications enabled."
                            : "Notifications not enabled. You can turn them on later in Settings.",
                        color: isGranted ? BetterColors.success : BetterColors.subtext
                    )
                    .padding(.horizontal, BetterSpacing.screen)
                    .padding(.top, BetterSpacing.medium)
                }

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { animateCards() }
    }

    // MARK: - Hero

    private var heroArea: some View {
        ZStack {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(BetterColors.boardHighlightGradient)
                .opacity(0.20)
                .offset(y: -30)

            VStack(spacing: 10) {
                ForEach(Array(mockNotifications.enumerated()), id: \.offset) { i, notif in
                    MockNotificationCard(title: notif.title, message: notif.body)
                        .offset(y: cardOffsets[i])
                        .opacity(cardOpacities[i])
                }
            }
            .padding(.horizontal, BetterSpacing.screen)
            .offset(y: 36)
        }
    }

    // MARK: - Reminder row

    private func reminderRow(_ icon: String, _ title: String, _ body: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BetterTypography.subheadline).foregroundStyle(BetterColors.text)
                Text(body).font(BetterTypography.footnote).foregroundStyle(BetterColors.subtext)
            }
            Spacer(minLength: 0)
        }
    }

    private func animateCards() {
        for (i, notif) in mockNotifications.enumerated() {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(notif.delay)) {
                cardOffsets[i] = 0
                cardOpacities[i] = 1
            }
        }
    }
}

// MARK: - Mock Notification Card

private struct MockNotificationCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BetterColors.boardHeroGradient)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BetterColors.boardTextInvert)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.boardMonoBody)
                    .foregroundStyle(BetterColors.boardGrey1)
                Text(message)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(BetterSpacing.medium)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    }
}
