import SwiftUI

struct PrivacyDisclosureStepView: View {
    @State private var shieldScale: CGFloat = 0.6
    @State private var shieldOpacity: Double = 0
    @State private var rowOpacities: [Double] = [0, 0, 0, 0]
    @State private var rowOffsets: [CGFloat] = [18, 18, 18, 18]

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero: Shield with lock ─────────────────────────────────────
                heroArea
                    .frame(height: screenHeight * 0.36)
                    .accessibilityHidden(true)

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.small) {
                    Text("Your data, your device")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Better uses your health data to generate insights. Everything stays on this device — encrypted and private.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Data categories card ───────────────────────────────────────
                BetterHealthCard {
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        dataRow("Sleep & Biometrics", "Sleep stages, heart rate, HRV, oxygen, respiratory rate", "moon.zzz.fill", BetterColors.stageDeep, 0)
                        Divider().overlay(BetterColors.border)
                        dataRow("Activity", "Steps, calories, exercise minutes, stand hours", "figure.walk", BetterColors.success, 1)
                        Divider().overlay(BetterColors.border)
                        dataRow("Body & Fitness", "Weight, body fat, wrist temperature, VO₂ Max", "heart.circle.fill", BetterColors.heartRate, 2)
                        Divider().overlay(BetterColors.border)
                        dataRow("Your check-ins", "Protocols, context logs, questionnaire answers", "checkmark.circle.fill", BetterColors.brand, 3)
                    }
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                // ── Privacy assurance banner ───────────────────────────────────
                HStack(spacing: BetterSpacing.small) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BetterColors.brand)
                    Text("Never uploaded to any server · AES-256 encrypted · Delete anytime")
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.medium)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { startAnimations() }
    }

    // MARK: - Hero

    private var heroArea: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(BetterColors.brand.opacity(0.12), lineWidth: 28)
                .frame(width: 130, height: 130)
                .scaleEffect(shieldScale * 1.1)
                .opacity(shieldOpacity * 0.7)

            // Inner ring
            Circle()
                .stroke(BetterColors.brand.opacity(0.22), lineWidth: 14)
                .frame(width: 96, height: 96)
                .scaleEffect(shieldScale)
                .opacity(shieldOpacity)

            // Shield icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BetterColors.brand, Color(hex: "#818CF8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(shieldScale)
                .opacity(shieldOpacity)
        }
    }

    // MARK: - Data row

    private func dataRow(_ title: String, _ description: String, _ icon: String, _ color: Color, _ index: Int) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(description)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
        }
        .opacity(rowOpacities[index])
        .offset(y: rowOffsets[index])
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            shieldScale = 1.0
            shieldOpacity = 1.0
        }
        for i in 0..<4 {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.1 + 0.35)) {
                rowOpacities[i] = 1
                rowOffsets[i] = 0
            }
        }
    }
}

#if DEBUG
#Preview("Privacy Disclosure") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        PrivacyDisclosureStepView()
    }
}
#endif
