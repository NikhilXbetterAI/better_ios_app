import SwiftUI

struct SleepAssessmentIntroStepView: View {
    @State private var pulse: CGFloat = 0.96
    @State private var glowOpacity: Double = 0.55

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(BetterColors.stageDeep.opacity(0.14))
                        .frame(width: 188, height: 188)
                        .scaleEffect(pulse)
                        .opacity(glowOpacity)

                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 62, weight: .semibold))
                        .foregroundStyle(BetterColors.stageDeep)
                }
                .frame(height: screenHeight * 0.38)

                VStack(spacing: BetterSpacing.small) {
                    Text("A few quick sleep questions")
                        .font(BetterTypography.title)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("These answers help Better give you more useful sleep insights and show patterns that match your routine. You can skip for now and come back later.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                BetterHealthCard {
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        introRow(
                            title: "Personalized insights",
                            body: "We use the answers to explain why your sleep score or recovery changed.",
                            icon: "chart.line.uptrend.xyaxis",
                            color: BetterColors.brand
                        )
                        Divider().overlay(BetterColors.border)
                        introRow(
                            title: "Better follow-up",
                            body: "The questions help us keep the advice focused on what matters to your sleep.",
                            icon: "bubble.left.and.text.bubble.right.fill",
                            color: BetterColors.stageDeep
                        )
                    }
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { animate() }
    }

    private func introRow(title: String, body: String, icon: String, color: Color) -> some View {
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
                Text(body)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func animate() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            pulse = 1.04
            glowOpacity = 0.8
        }
    }
}

#if DEBUG
#Preview("Assessment Intro") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepAssessmentIntroStepView()
    }
}
#endif
