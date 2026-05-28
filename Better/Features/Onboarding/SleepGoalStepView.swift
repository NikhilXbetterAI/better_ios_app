import SwiftUI

struct SleepGoalStepView: View {
    @Binding var sleepGoalHours: Double

    private var arcColor: Color {
        sleepGoalHours >= 7 && sleepGoalHours <= 9 ? BetterColors.success : BetterColors.warning
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero ──────────────────────────────────────────────────────
                ZStack {
                    SleepArcView(value: sleepGoalHours, range: 6...10)
                }
                .frame(height: screenHeight * 0.38)

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.small) {
                    Text("Set your sleep goal")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Better uses this target for sleep debt, score context, and alerts. You can change it later.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Slider card ───────────────────────────────────────────────
                VStack(spacing: BetterSpacing.medium) {
                    Slider(value: $sleepGoalHours, in: 6...10, step: 0.25)
                        .tint(arcColor)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: arcColor == BetterColors.success)
                        .accessibilityLabel("Sleep goal")
                        .accessibilityValue("\(String(format: "%.1f", sleepGoalHours)) hours")

                    HStack {
                        Text("6h")
                        Spacer()
                        Text("8h")
                        Spacer()
                        Text("10h")
                    }
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                }
                .padding(BetterSpacing.xLarge)
                .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}
