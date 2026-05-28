import SwiftUI

struct WelcomeStepView: View {
    @State private var floatOffset: CGFloat = 0
    @State private var orbitAngle: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero ──────────────────────────────────────────────────────
                heroArea
                    .frame(height: screenHeight * 0.42)
                    .accessibilityHidden(true)

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.medium) {
                    Text("Better sleep starts\nwith your baseline")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Use Apple Health data and log your nights. Once your baseline is ready, you'll see exactly how your habits affect your sleep.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Mini feature cards ────────────────────────────────────────
                HStack(spacing: BetterSpacing.medium) {
                    OnboardingMiniCard(
                        icon: "heart.text.square.fill",
                        label: "Stays\nlocal",
                        accessibilityLabel: "Data stays on this device"
                    )
                    OnboardingMiniCard(
                        icon: "magnifyingglass",
                        label: "Finds\nlinks",
                        accessibilityLabel: "Finds links between habits and sleep"
                    )
                    OnboardingMiniCard(
                        icon: "shield.fill",
                        label: "Not\nmedical",
                        accessibilityLabel: "Not medical advice"
                    )
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                Spacer(minLength: 0)
                // Space for footer pill
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { startAnimations() }
    }

    // MARK: - Hero

    private var heroArea: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(BetterColors.brand.opacity(0.18), lineWidth: 1.5)
                .frame(width: 220, height: 220)

            // Medium ring
            Circle()
                .stroke(BetterColors.brandLight.opacity(0.18), lineWidth: 1)
                .frame(width: 160, height: 160)

            // Inner filled circle
            Circle()
                .fill(BetterColors.card)
                .frame(width: 112, height: 112)

            // Orbiting dots
            ForEach([0.0, 120.0, 240.0], id: \.self) { startDeg in
                let angle = Angle.degrees(startDeg + orbitAngle)
                let radius: CGFloat = 72
                Circle()
                    .fill(BetterColors.brand)
                    .frame(width: 8, height: 8)
                    .offset(
                        x: radius * cos(angle.radians),
                        y: radius * sin(angle.radians)
                    )
            }

            // Moon symbol
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(BetterColors.brandGradient)
        }
        .offset(y: floatOffset)
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            floatOffset = -10
        }
        withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
            orbitAngle = 360
        }
    }
}

// MARK: - Mini Card

private struct OnboardingMiniCard: View {
    let icon: String
    let label: String
    let accessibilityLabel: String

    var body: some View {
        VStack(spacing: BetterSpacing.small) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BetterColors.brandGradient)
                .frame(width: 44, height: 44)
                .background(BetterColors.brand.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(label)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BetterSpacing.medium)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

// Keeping OnboardingValueRow for external use
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
