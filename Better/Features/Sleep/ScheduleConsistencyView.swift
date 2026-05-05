import SwiftUI

// MARK: - Schedule consistency matching ScheduleConsistencyView in SleepTab.tsx

struct ScheduleConsistencyView: View {
    let session: SleepSession
    let baseline: SleepBaseline
    let recentSessions: [SleepSession]

    init(
        session: SleepSession,
        baseline: SleepBaseline,
        recentSessions: [SleepSession] = []
    ) {
        self.session = session
        self.baseline = baseline
        self.recentSessions = recentSessions
    }

    private var metrics: SleepScheduleChartMetrics {
        let sessions = recentSessions.isEmpty ? [session] : recentSessions
        return SleepScheduleChartMetrics(sessions: sessions)
    }

    var body: some View {
        VStack(spacing: BetterSpacing.large) {
            scheduleChartSection(
                title: "Sleep time",
                timeLabel: Self.formatMinuteOfDay(metrics.bedtimeAverageMinute),
                spreadLabel: "±\(Int(metrics.bedtimeVariationMinutes.rounded())) min",
                chart: ScheduleDotChart(
                    points: metrics.bedtimePoints,
                    averageMinute: metrics.bedtimeAverageMinute,
                    color: BetterColors.brand
                )
            )

            scheduleChartSection(
                title: "Wake time",
                timeLabel: Self.formatMinuteOfDay(metrics.wakeAverageMinute),
                spreadLabel: "±\(Int(metrics.wakeVariationMinutes.rounded())) min",
                chart: ScheduleDotChart(
                    points: metrics.wakePoints,
                    averageMinute: metrics.wakeAverageMinute,
                    color: BetterColors.warning
                )
            )
        }
    }

    private func scheduleChartSection<ChartContent: View>(
        title: String,
        timeLabel: String,
        spreadLabel: String,
        chart: ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                HStack(spacing: 4) {
                    Text(timeLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(spreadLabel)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            chart
        }
    }

    static func formatMinuteOfDay(_ minuteOfDay: Double) -> String {
        let totalMinutes = Int(minuteOfDay.rounded())
        let normalizedMinutes = (totalMinutes % 1_440 + 1_440) % 1_440
        let hour = normalizedMinutes / 60
        let minute = normalizedMinutes % 60
        let ampm = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, ampm)
    }
}

private struct ScheduleDotChart: View {
    let points: [SleepScheduleChartPoint]
    let averageMinute: Double
    let color: Color

    private var spread: Double {
        max(45, points.map { abs(SleepScheduleChartMetrics.signedMinuteDistance($0.minuteOfDay, averageMinute)) }.max() ?? 45)
    }

    var body: some View {
        if points.isEmpty {
            Text("No 30-night history yet")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BetterColors.cardSecondary)
                    horizontalGrid(size: proxy.size)
                    averageRule(size: proxy.size)
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .position(position(for: point, at: index, size: proxy.size))
                    }
                }
            }
            .frame(height: 104)
        }
    }

    private func horizontalGrid(size: CGSize) -> some View {
        Path { path in
            for step in 1...2 {
                let y = size.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(BetterColors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func averageRule(size: CGSize) -> some View {
        Path { path in
            let y = size.height / 2
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func position(for point: SleepScheduleChartPoint, at index: Int, size: CGSize) -> CGPoint {
        let x = points.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(points.count - 1)
        let offset = SleepScheduleChartMetrics.signedMinuteDistance(point.minuteOfDay, averageMinute)
        let normalized = min(1, max(-1, offset / spread))
        let y = size.height / 2 - CGFloat(normalized) * (size.height / 2 - 12)
        return CGPoint(x: x, y: min(max(12, y), size.height - 12))
    }
}

struct SleepScheduleChartPoint: Identifiable, Hashable {
    var id: String { dateKey }
    let dateKey: String
    let minuteOfDay: Double
}

struct SleepScheduleChartMetrics: Hashable {
    let bedtimePoints: [SleepScheduleChartPoint]
    let wakePoints: [SleepScheduleChartPoint]
    let bedtimeAverageMinute: Double
    let wakeAverageMinute: Double
    let bedtimeVariationMinutes: Double
    let wakeVariationMinutes: Double

    init(sessions: [SleepSession], calendar: Calendar = .current) {
        let validSessions = sessions
            .filter { $0.totalSleepTime >= SleepDataProcessor.minimumSleepDuration }
            .filter { $0.dataQuality != .inBedOnly && $0.dataQuality != .noData }
            .sorted { $0.sleepDateKey < $1.sleepDateKey }
            .suffix(30)

        bedtimePoints = validSessions.map {
            SleepScheduleChartPoint(
                dateKey: $0.sleepDateKey,
                minuteOfDay: Self.minuteOfDay(for: $0.inBedStartDate ?? $0.startDate, calendar: calendar)
            )
        }
        wakePoints = validSessions.map {
            SleepScheduleChartPoint(
                dateKey: $0.sleepDateKey,
                minuteOfDay: Self.minuteOfDay(for: $0.inBedEndDate ?? $0.endDate, calendar: calendar)
            )
        }
        bedtimeAverageMinute = Self.circularAverage(bedtimePoints.map(\.minuteOfDay))
        wakeAverageMinute = Self.circularAverage(wakePoints.map(\.minuteOfDay))
        bedtimeVariationMinutes = Self.circularVariation(points: bedtimePoints, averageMinute: bedtimeAverageMinute)
        wakeVariationMinutes = Self.circularVariation(points: wakePoints, averageMinute: wakeAverageMinute)
    }

    static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    static func signedMinuteDistance(_ minute: Double, _ reference: Double) -> Double {
        var difference = (minute - reference).truncatingRemainder(dividingBy: 1_440)
        if difference > 720 { difference -= 1_440 }
        if difference < -720 { difference += 1_440 }
        return difference
    }

    static func circularAverage(_ minutes: [Double]) -> Double {
        guard !minutes.isEmpty else { return 0 }
        let vectors = minutes.reduce((sin: 0.0, cos: 0.0)) { result, minute in
            let angle = minute / 1_440 * 2 * Double.pi
            return (result.sin + sin(angle), result.cos + cos(angle))
        }
        let angle = atan2(vectors.sin / Double(minutes.count), vectors.cos / Double(minutes.count))
        let normalized = angle < 0 ? angle + 2 * Double.pi : angle
        return normalized / (2 * Double.pi) * 1_440
    }

    private static func circularVariation(points: [SleepScheduleChartPoint], averageMinute: Double) -> Double {
        guard !points.isEmpty else { return 0 }
        let meanSquare = points
            .map { signedMinuteDistance($0.minuteOfDay, averageMinute) }
            .map { $0 * $0 }
            .reduce(0, +) / Double(points.count)
        return sqrt(meanSquare)
    }
}

// MARK: - Compact summary for card header

struct ScheduleConsistencySummary: View {
    let baseline: SleepBaseline

    private var worstSD: Double {
        max(baseline.bedtimeMinuteStandardDeviation, baseline.wakeMinuteStandardDeviation)
    }

    var body: some View {
        Text("±\(Int(worstSD)) min variation")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(BetterColors.text)
    }
}
