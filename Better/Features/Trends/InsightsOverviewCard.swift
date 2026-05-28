import SwiftUI

struct InsightsOverviewCard: View {
    let sessions: [SleepSession]
    let scoreSparklineValues: [Double]
    let avgScore: Double?
    let avgDurationHours: Double?
    let comparisonSummary: TrendComparisonSummary?

    @State private var ringProgress: Double = 0
    @State private var hasAnimatedRing = false

    var body: some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.medium) {
                mainRow
                Divider().background(BetterColors.border.opacity(0.45))
                statsRow
            }
        }
        .onAppear {
            if !hasAnimatedRing { animateRing() }
        }
        .onChange(of: avgScore) { _, _ in
            // Snap to new value without re-animating from zero on every reload.
            let target = min(max((avgScore ?? 0) / 100.0, 0), 1)
            withAnimation(.easeOut(duration: 0.35)) {
                ringProgress = target
            }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            sparklineSection
            Spacer()
            scoreRingSection
        }
    }

    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack(spacing: 5) {
                Text("SLEEP SCORE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .tracking(1.0)
                Text("TREND")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brandLight)
                    .tracking(1.0)
            }

            if scoreSparklineValues.count >= 2 {
                SparklineView(values: scoreSparklineValues, color: BetterColors.brand)
                    .frame(height: 52)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BetterColors.cardSecondary)
                    .frame(height: 52)
                    .overlay(
                        Text("More nights needed")
                            .font(BetterTypography.micro)
                            .foregroundStyle(BetterColors.subtext)
                    )
            }

            if let summary = comparisonSummary {
                periodLabel(summary)
            }
        }
    }

    private func periodLabel(_ summary: TrendComparisonSummary) -> some View {
        HStack(spacing: 5) {
            Text("\(summary.currentValidNights) nights tracked")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            if summary.previousValidNights > 0 {
                Text("·")
                    .foregroundStyle(BetterColors.subtext)
                changeChip(summary.percentChange)
            }
        }
    }

    private var scoreRingSection: some View {
        VStack(alignment: .center, spacing: BetterSpacing.small) {
            ZStack {
                // Track
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(BetterColors.brand.opacity(0.10), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(90))

                // Fill
                Circle()
                    .trim(from: 0.12, to: 0.12 + 0.76 * ringProgress)
                    .stroke(
                        AngularGradient(
                            colors: [BetterColors.brand, BetterColors.brandLight],
                            center: .center,
                            startAngle: .degrees(-90 + 43),
                            endAngle: .degrees(270 - 43)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.easeOut(duration: 0.85), value: ringProgress)

                // Center label
                if let score = avgScore {
                    VStack(spacing: 1) {
                        Text("\(Int(score.rounded()))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                            .contentTransition(.numericText())
                        Text("avg")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            .frame(width: 72, height: 72)

            Text("Sleep Score")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                label: "Avg Duration",
                value: avgDurationHours.map { formatHours($0) } ?? "--",
                color: BetterColors.brand
            )
            if let score = avgScore {
                statDivider
                statCell(
                    label: "Avg Sleep Score",
                    value: "\(Int(score.rounded()))",
                    color: BetterColors.success
                )
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(BetterColors.border)
            .frame(width: 1, height: 28)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func changeChip(_ change: Double) -> some View {
        let color: Color = abs(change) < 0.02 ? BetterColors.subtext : (change >= 0 ? BetterColors.success : BetterColors.warning)
        let icon = abs(change) < 0.02 ? "minus" : (change >= 0 ? "arrow.up" : "arrow.down")
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.0f%%", abs(change * 100)))
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private func animateRing() {
        hasAnimatedRing = true
        ringProgress = 0
        let target = min(max((avgScore ?? 0) / 100.0, 0), 1)
        withAnimation(.easeOut(duration: 0.85)) {
            ringProgress = target
        }
    }
}
