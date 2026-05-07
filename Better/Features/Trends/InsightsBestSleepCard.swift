import SwiftUI

struct InsightsBestSleepCard: View {
    let session: SleepSession
    let score: Int          // pre-computed via HealthSleepScoreEstimator — matches dashboard
    let windowLabel: String

    @State private var ringProgress: Double = 0
    private var scoreColor: Color {
        switch score {
        case 85...: BetterColors.success
        case 70...: BetterColors.brand
        case 55...: BetterColors.warning
        default:    BetterColors.danger
        }
    }
    private var scoreLabel: String {
        switch score {
        case 85...: "Excellent"
        case 70...: "Good"
        case 55...: "Fair"
        default:    "Poor"
        }
    }
    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: session.startDate)
    }

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                headerRow
                contentRow
            }
        }
        .onAppear { animateRing() }
        .onChange(of: score) { _, _ in animateRing() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(scoreColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Best Night")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("in the last \(windowLabel)")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    // MARK: - Content Row

    private var contentRow: some View {
        HStack(spacing: BetterSpacing.large) {
            scoreRing
            metricsColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scoreRing: some View {
        return ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(scoreColor.opacity(0.10), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * ringProgress)
                .stroke(
                    AngularGradient(
                        colors: [scoreColor, scoreColor.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(-90 + 43),
                        endAngle: .degrees(270 - 43)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.85), value: ringProgress)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .contentTransition(.numericText())
                Text(scoreLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }
        }
        .frame(width: 84, height: 84)
    }

    private var metricsColumn: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text(dateLabel)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)

            HStack(spacing: BetterSpacing.medium) {
                metricBadge(
                    icon: "clock.fill",
                    value: formatDuration(session.totalSleepTime),
                    label: "Total",
                    color: BetterColors.brand
                )
                metricBadge(
                    icon: "gauge.with.dots.needle.67percent",
                    value: "\(Int(session.efficiency * 100))%",
                    label: "Efficiency",
                    color: BetterColors.success
                )
            }

            if session.deepDuration > 0 {
                HStack(spacing: BetterSpacing.medium) {
                    metricBadge(
                        icon: "moon.stars.fill",
                        value: formatDuration(session.deepDuration),
                        label: "Deep",
                        color: BetterColors.stageDeep
                    )
                    if session.remDuration > 0 {
                        metricBadge(
                            icon: "waveform.path.ecg",
                            value: formatDuration(session.remDuration),
                            label: "REM",
                            color: BetterColors.stageREM
                        )
                    }
                }
            }
        }
    }

    private func metricBadge(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3_600
        let m = (Int(interval) % 3_600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func animateRing() {
        ringProgress = 0
        let target = min(max(Double(score) / 100.0, 0), 1)
        withAnimation(.easeOut(duration: 0.85)) {
            ringProgress = target
        }
    }
}
