import SwiftUI

// MARK: - Heart Rate card matching Heart Rate ExpandableCard in SleepTab.tsx

struct HeartRateCardContent: View {
    let biometrics: NightlyBiometricSummary
    let baseline: SleepBaseline?
    let recentSessions: [SleepSession]

    init(
        biometrics: NightlyBiometricSummary,
        baseline: SleepBaseline?,
        recentSessions: [SleepSession] = []
    ) {
        self.biometrics = biometrics
        self.baseline = baseline
        self.recentSessions = recentSessions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            // Avg / Min / Max row
            HStack {
                Spacer()
                ForEach(hrStats, id: \.label) { stat in
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(stat.value)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)
                            Text("BPM")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                        }
                        Text(stat.label)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                    Spacer()
                }
            }

            BiometricTrendChart(
                title: "30-night heart rate",
                points: recentSessions.biometricTrendPoints { $0.heartRateAverage },
                unit: "bpm",
                color: BetterColors.heartRate
            )

            // HRV divider row
            if let hrv = biometrics.hrvAverage {
                Divider().background(BetterColors.border)
                HRVRow(hrv: hrv, baseline: baseline)
            }

            // SpO2 row
            if let spo2 = biometrics.oxygenSaturationAverage {
                Divider().background(BetterColors.border)
                SpO2Row(spo2: spo2)
            }
        }
    }

    private var hrStats: [(label: String, value: String)] {
        [
            ("Avg", biometrics.heartRateAverage.map { String(format: "%.0f", $0) } ?? "–"),
            ("Min", biometrics.heartRateMinimum.map { String(format: "%.0f", $0) } ?? "–"),
            ("Max", biometrics.heartRateMaximum.map { String(format: "%.0f", $0) } ?? "–"),
        ]
    }
}

// MARK: - HRV inline row

struct HRVRow: View {
    let hrv: Double
    let baseline: SleepBaseline?

    var body: some View {
        HStack {
            Text("Overnight HRV")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", hrv))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.hrv)
                Text("ms")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                if let baselineHRV = baseline?.hrvAverage {
                    let diff = hrv - baselineHRV
                    Text("\(diff >= 0 ? "↑ +" : "↓ ")\(String(format: "%.0f", diff))ms avg")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(diff >= 0 ? BetterColors.success : BetterColors.warning)
                }
            }
        }
    }
}

// MARK: - SpO2 inline row

private struct SpO2Row: View {
    let spo2: Double
    private var percentage: Int { Int(spo2 * 100) }

    var body: some View {
        HStack {
            Text("Blood Oxygen")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percentage)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(percentage >= 95 ? BetterColors.success : BetterColors.warning)
                Text("%")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }
}

// MARK: - Summary row for card header

struct HeartRateSummary: View {
    let biometrics: NightlyBiometricSummary

    var body: some View {
        if let avg = biometrics.heartRateAverage {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", avg))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("BPM avg")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        } else {
            Text("–")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }
}

struct BiometricTrendPoint: Identifiable, Hashable {
    var id: String { dateKey }
    let dateKey: String
    let value: Double
}

private struct BiometricTrendChart: View {
    let title: String
    let points: [BiometricTrendPoint]
    let unit: String
    let color: Color
    var normalRange: ClosedRange<Double>?

    private var values: [Double] { points.map(\.value) }
    private var average: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    private var lowerBound: Double {
        let candidates = values + rangeValues + averageValues
        return (candidates.min() ?? 0) - verticalPadding
    }
    private var upperBound: Double {
        let candidates = values + rangeValues + averageValues
        return (candidates.max() ?? 1) + verticalPadding
    }
    private var rangeValues: [Double] {
        guard let normalRange else { return [] }
        return [normalRange.lowerBound, normalRange.upperBound]
    }
    private var averageValues: [Double] {
        average.map { [$0] } ?? []
    }
    private var verticalPadding: Double {
        max(0.5, ((values.max() ?? 1) - (values.min() ?? 0)) * 0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                if let average {
                    Text("avg \(format(average)) \(unit)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            if points.isEmpty {
                Text("No 30-night history yet")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                GeometryReader { proxy in
                    ZStack {
                        chartBackground(size: proxy.size)
                        if let normalRange {
                            rangeBand(normalRange, size: proxy.size)
                        }
                        if let average {
                            averageRule(average, size: proxy.size)
                        }
                        linePath(size: proxy.size)
                            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            Circle()
                                .fill(color)
                                .frame(width: 5, height: 5)
                                .position(position(for: point.value, at: index, size: proxy.size))
                        }
                    }
                }
                .frame(height: 112)
                .padding(.top, 2)
            }
        }
    }

    private func chartBackground(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BetterColors.cardSecondary)
            horizontalGrid(size: size)
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

    private func rangeBand(_ range: ClosedRange<Double>, size: CGSize) -> some View {
        let top = yPosition(for: range.upperBound, size: size)
        let bottom = yPosition(for: range.lowerBound, size: size)
        return Rectangle()
            .fill(BetterColors.hrv.opacity(0.12))
            .frame(height: max(2, bottom - top))
            .position(x: size.width / 2, y: top + max(2, bottom - top) / 2)
    }

    private func averageRule(_ average: Double, size: CGSize) -> some View {
        Path { path in
            let y = yPosition(for: average, size: size)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func linePath(size: CGSize) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            for index in points.indices {
                let point = position(for: points[index].value, at: index, size: size)
                index == points.startIndex ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    private func position(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        let x = points.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(points.count - 1)
        return CGPoint(x: x, y: yPosition(for: value, size: size))
    }

    private func yPosition(for value: Double, size: CGSize) -> CGFloat {
        let spread = max(0.1, upperBound - lowerBound)
        let normalized = (value - lowerBound) / spread
        let y = size.height - (size.height * CGFloat(normalized))
        return min(max(12, y), size.height - 12)
    }

    private func format(_ value: Double) -> String {
        unit == "br/min" ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}

extension Array where Element == SleepSession {
    func biometricTrendPoints(_ value: (NightlyBiometricSummary) -> Double?) -> [BiometricTrendPoint] {
        suffix(30).compactMap { session in
            guard let biometrics = session.biometrics,
                  let metricValue = value(biometrics) else {
                return nil
            }
            return BiometricTrendPoint(dateKey: session.sleepDateKey, value: metricValue)
        }
    }
}
