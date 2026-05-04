import SwiftUI

// MARK: - Score ring matching ScoreRing in SleepTab.tsx

struct SleepQualityRingView: View {
    let score: Int
    let isPartial: Bool

    private var ringColor: Color {
        switch score {
        case 90...: BetterColors.success
        case 80...: BetterColors.brand
        case 70...: BetterColors.warning
        default:    BetterColors.danger
        }
    }

    private var label: String {
        switch score {
        case 90...: "Excellent"
        case 80...: "Good"
        case 70...: "Fair"
        default:    "Poor"
        }
    }

    var body: some View {
        VStack(spacing: BetterSpacing.xSmall) {
            ZStack {
                // Track
                Circle()
                    .stroke(BetterColors.cardTertiary, lineWidth: 10)

                // Fill
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: score)

                // Score text
                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("/ 100")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            .frame(width: 120, height: 120)

            HStack(spacing: BetterSpacing.xSmall) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ringColor)
                if isPartial {
                    Text("(partial)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
    }
}

// MARK: - Compact inline score badge

struct SleepScoreBadge: View {
    let score: Int

    private var color: Color {
        switch score {
        case 90...: BetterColors.success
        case 80...: BetterColors.brand
        case 70...: BetterColors.warning
        default:    BetterColors.danger
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(score)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Text(scoreLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private var scoreLabel: String {
        switch score {
        case 90...: "Excellent"
        case 80...: "Good"
        case 70...: "Fair"
        default:    "Poor"
        }
    }
}

#Preview("Score Ring") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        VStack(spacing: 24) {
            SleepQualityRingView(score: 82, isPartial: false)
            SleepQualityRingView(score: 64, isPartial: true)
        }
    }
}
