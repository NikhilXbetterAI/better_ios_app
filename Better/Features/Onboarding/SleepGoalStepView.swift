import SwiftUI

struct SleepGoalStepView: View {
    @Binding var sleepGoalHours: Double

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xxLarge) {
            OnboardingStepHeader(
                icon: "target",
                title: "Set your sleep goal",
                body: "Better uses this target for sleep debt, score context, and alerts. You can change it later."
            )

            VStack(spacing: BetterSpacing.large) {
                Text(String(format: "%.1f hours", sleepGoalHours))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .frame(maxWidth: .infinity)

                Slider(value: $sleepGoalHours, in: 6...10, step: 0.25)
                    .tint(BetterColors.brand)

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
            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer()
        }
    }
}

