import SwiftUI

enum ProtocolImpactMetric: String, CaseIterable, Identifiable {
    case score
    case duration
    case deep
    case rem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .score:    "Score"
        case .duration: "Duration"
        case .deep:     "Deep"
        case .rem:      "REM"
        }
    }

    var title: String {
        switch self {
        case .score:    "Sleep Score"
        case .duration: "Sleep Duration"
        case .deep:     "Deep Sleep"
        case .rem:      "REM Sleep"
        }
    }

    var storyTitle: String {
        switch self {
        case .score:
            "Sleep score since starting"
        case .duration:
            "Sleep duration since starting"
        case .deep:
            "Deep sleep since starting"
        case .rem:
            "REM sleep since starting"
        }
    }

    func value(from point: ProtocolChartPoint) -> Double? {
        switch self {
        case .score:
            point.sleepScore
        case .duration:
            point.sleepDuration / 3_600
        case .deep:
            point.deepSleep.map { $0 / 3_600 }
        case .rem:
            point.remSleep.map { $0 / 3_600 }
        }
    }

    func baseline(from summary: SleepPeriodSummary?) -> Double? {
        switch self {
        case .score:
            summary?.averageSleepScore
        case .duration:
            summary?.averageSleepDuration.map { $0 / 3_600 }
        case .deep:
            summary?.averageDeepSleep.map { $0 / 3_600 }
        case .rem:
            summary?.averageREMSleep.map { $0 / 3_600 }
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .score:
            "\(Int(value.rounded()))"
        case .duration, .deep, .rem:
            String(format: "%.1fh", value)
        }
    }

    func formattedDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(formatted(value))"
    }
}

struct ProtocolResearchDashboard: View {
    @Bindable var comparisonViewModel: ProtocolComparisonDashboardViewModel
    let points: [ProtocolChartPoint]
    let baselineSummary: SleepPeriodSummary?

    @State private var selectedMetric: ProtocolImpactMetric = .deep

    private let minimumProtocolNights = 3
    private let minimumOffNights = 2

    private var windows: [ProtocolComparisonWindow] {
        [.last7Days, .last15Days, .last30Days]
    }

    private var filteredPoints: [ProtocolChartPoint] {
        guard let dayCount = comparisonViewModel.selectedWindow.dayCount else { return points }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -dayCount + 1, to: end) ?? end
        return points.filter { point in
            let day = calendar.startOfDay(for: point.date)
            return day >= start && day <= end
        }
    }

    private var baselineAverage: Double? {
        selectedMetric.baseline(from: baselineSummary)
    }

    private var protocolValues: [Double] {
        filteredPoints.filter { $0.status == .taken }.compactMap { selectedMetric.value(from: $0) }
    }

    private var offValues: [Double] {
        filteredPoints.filter { $0.status == .notTaken }.compactMap { selectedMetric.value(from: $0) }
    }

    private var protocolAverage: Double? {
        average(protocolValues)
    }

    private var offAverage: Double? {
        average(offValues)
    }

    private var baselineDelta: Double? {
        protocolAverage.flatMap { protocolAverage in baselineAverage.map { protocolAverage - $0 } }
    }

    private var maxBandValue: Double {
        max([baselineAverage, protocolAverage, offAverage].compactMap { $0 }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            header
            windowPicker
            metricPicker
            storySummary
            ProtocolBeforeAfterImprovementChart(
                metric: selectedMetric,
                baselineValue: baselineAverage,
                protocolValue: protocolAverage,
                protocolNightCount: protocolValues.count,
                minimumProtocolNights: minimumProtocolNights
            )
            comparisonBands
            ProtocolNightHistoryStrip(
                points: filteredPoints,
                metric: selectedMetric,
                baselineValue: baselineAverage
            )
            lowDataMessage
        }
        .padding(BetterSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BetterColors.cardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(BetterColors.glassStroke, lineWidth: 1)
                }
        }
    }

    private var header: some View {
        HStack {
            Label("Protocol Impact", systemImage: "chart.line.uptrend.xyaxis")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Spacer()
            confidenceBadge
        }
    }

    private var confidenceBadge: some View {
        let label: String = switch comparisonViewModel.state.confidence {
        case .high:
            "Strong"
        case .medium:
            "Moderate"
        case .low:
            "Early"
        case .unavailable:
            "Building"
        }
        let color: Color = switch comparisonViewModel.state.confidence {
        case .high:
            BetterColors.success
        case .medium:
            BetterColors.hrv
        case .low:
            BetterColors.warning
        case .unavailable:
            BetterColors.subtext
        }
        return Text(label)
            .font(BetterTypography.micro.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var windowPicker: some View {
        HStack(spacing: BetterSpacing.xSmall) {
            ForEach(windows) { window in
                Button {
                    Task { await comparisonViewModel.selectWindow(window) }
                } label: {
                    Text(window.shortLabel)
                        .font(BetterTypography.caption.weight(.semibold))
                        .foregroundStyle(comparisonViewModel.selectedWindow == window ? Color.black : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.small)
                        .background(
                            comparisonViewModel.selectedWindow == window ? BetterColors.brand : BetterColors.cardSecondary,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 6) {
            ForEach(ProtocolImpactMetric.allCases) { metric in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedMetric = metric
                    }
                } label: {
                    Text(metric.displayName)
                        .font(BetterTypography.caption.weight(.semibold))
                        .foregroundStyle(selectedMetric == metric ? Color.black : BetterColors.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedMetric == metric ? BetterColors.brand : BetterColors.cardSecondary.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var storySummary: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text(selectedMetric.storyTitle)
                .font(BetterTypography.caption.weight(.semibold))
                .foregroundStyle(BetterColors.subtext)
                .textCase(.uppercase)

            Text(summaryHeadline)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(summaryColor)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(summaryDetail)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(BetterColors.cardSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var summaryHeadline: String {
        guard protocolValues.count >= minimumProtocolNights, let baselineDelta else {
            return "Building baseline comparison"
        }
        return "\(selectedMetric.formattedDelta(baselineDelta)) vs baseline"
    }

    private var summaryDetail: String {
        guard protocolValues.count >= minimumProtocolNights else {
            let remaining = max(minimumProtocolNights - protocolValues.count, 0)
            return "Need \(remaining) more protocol night\(remaining == 1 ? "" : "s") before showing a protocol change."
        }
        guard baselineAverage != nil else {
            return "Baseline is still building for this metric."
        }
        return "Comparing your protocol nights with your pre-protocol baseline."
    }

    private var summaryColor: Color {
        guard protocolValues.count >= minimumProtocolNights, let baselineDelta else {
            return BetterColors.text
        }
        return baselineDelta >= 0 ? BetterColors.success : BetterColors.danger
    }

    private var comparisonBands: some View {
        VStack(spacing: BetterSpacing.medium) {
            impactBand(
                label: "Baseline",
                detail: "\(baselineSummary?.nightCount ?? 0) pre-protocol nights",
                value: baselineAverage,
                barValue: baselineAverage,
                color: BetterColors.subtext,
                pendingText: "Building baseline"
            )
            impactBand(
                label: "After protocol",
                detail: "\(protocolValues.count) protocol night\(protocolValues.count == 1 ? "" : "s")",
                value: protocolAverage,
                barValue: protocolAverage,
                color: BetterColors.success,
                pendingText: "Need \(max(minimumProtocolNights - protocolValues.count, 0)) more"
            )
            impactBand(
                label: "Off nights",
                detail: offValues.isEmpty ? "Not enough off nights yet" : "\(offValues.count) off night\(offValues.count == 1 ? "" : "s")",
                value: offValues.count >= minimumOffNights ? offAverage : nil,
                barValue: offValues.count >= minimumOffNights ? offAverage : nil,
                color: BetterColors.warning,
                pendingText: "Appears after missed/off nights"
            )
        }
    }

    private func impactBand(
        label: String,
        detail: String,
        value: Double?,
        barValue: Double?,
        color: Color,
        pendingText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(BetterTypography.footnote.weight(.semibold))
                        .foregroundStyle(BetterColors.text)
                    Text(detail)
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.mutedText)
                }
                Spacer()
                Text(value.map(selectedMetric.formatted) ?? pendingText)
                    .font(BetterTypography.caption.weight(.bold))
                    .foregroundStyle(value == nil ? BetterColors.mutedText : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(BetterColors.background.opacity(0.55))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * barFraction(for: barValue))
                    }
            }
            .frame(height: 10)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.54), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var lowDataMessage: some View {
        let message: String? = if protocolValues.count < minimumProtocolNights {
            "Need \(max(minimumProtocolNights - protocolValues.count, 0)) more protocol night\(max(minimumProtocolNights - protocolValues.count, 0) == 1 ? "" : "s") before comparing protocol sleep patterns."
        } else if offValues.count < minimumOffNights {
            "Off-night comparison will appear after missed/off nights."
        } else {
            nil
        }

        return Group {
            if let message {
                Text(message)
                    .font(BetterTypography.footnote.weight(.semibold))
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BetterSpacing.medium)
                    .background(BetterColors.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func barFraction(for value: Double?) -> CGFloat {
        guard let value, maxBandValue > 0 else { return 0 }
        return min(max(CGFloat(value / maxBandValue), 0), 1)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct ProtocolBeforeAfterImprovementChart: View {
    let metric: ProtocolImpactMetric
    let baselineValue: Double?
    let protocolValue: Double?
    let protocolNightCount: Int
    let minimumProtocolNights: Int

    private var hasEnoughProtocol: Bool {
        protocolNightCount >= minimumProtocolNights
    }

    private var delta: Double? {
        guard hasEnoughProtocol, let baselineValue, let protocolValue else { return nil }
        return protocolValue - baselineValue
    }

    private var values: [Double] {
        [baselineValue, protocolValue].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Change visual")
                        .font(BetterTypography.footnote.weight(.semibold))
                        .foregroundStyle(BetterColors.text)
                    Text("Baseline to after protocol")
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.mutedText)
                }
                Spacer()
                deltaPill
            }

            chart

            HStack {
                endpointLabel(title: "Baseline", value: baselineValue, alignment: .leading)
                Spacer()
                endpointLabel(title: "After protocol", value: hasEnoughProtocol ? protocolValue : nil, alignment: .trailing)
            }
        }
        .padding(BetterSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BetterColors.cardSecondary.opacity(0.56))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(BetterColors.glassStroke.opacity(0.7), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var deltaPill: some View {
        if let delta {
            let color = delta >= 0 ? BetterColors.success : BetterColors.danger
            Text("\(metric.formattedDelta(delta))")
                .font(BetterTypography.caption.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.15), in: Capsule())
        } else {
            Text("Building")
                .font(BetterTypography.caption.weight(.semibold))
                .foregroundStyle(BetterColors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BetterColors.cardSecondary, in: Capsule())
        }
    }

    private var chart: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let baselinePoint = point(for: baselineValue, x: 18, size: size)
            let protocolPoint = point(for: hasEnoughProtocol ? protocolValue : nil, x: size.width - 18, size: size)

            ZStack {
                backgroundGrid(size: size)

                Path { path in
                    path.move(to: baselinePoint)
                    path.addLine(to: protocolPoint)
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                if !hasEnoughProtocol || protocolValue == nil {
                    Path { path in
                        path.move(to: baselinePoint)
                        path.addLine(to: protocolPoint)
                    }
                    .stroke(BetterColors.mutedText.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 7]))
                }

                deltaBadgeBetween(start: baselinePoint, end: protocolPoint)

                endpointDot(at: baselinePoint, color: BetterColors.subtext, fill: false)
                endpointDot(at: protocolPoint, color: hasEnoughProtocol ? BetterColors.success : BetterColors.mutedText, fill: hasEnoughProtocol && protocolValue != nil)
            }
        }
        .frame(height: 150)
    }

    private func backgroundGrid(size: CGSize) -> some View {
        Path { path in
            for index in 0..<4 {
                let y = CGFloat(index) / 3 * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(BetterColors.border.opacity(0.32), lineWidth: 1)
    }

    private func endpointDot(at point: CGPoint, color: Color, fill: Bool) -> some View {
        Circle()
            .fill(fill ? color : BetterColors.card)
            .overlay(Circle().stroke(color, lineWidth: 3))
            .frame(width: 22, height: 22)
            .shadow(color: fill ? color.opacity(0.35) : .clear, radius: 8)
            .position(point)
    }

    @ViewBuilder
    private func deltaBadgeBetween(start: CGPoint, end: CGPoint) -> some View {
        if let delta {
            let color = delta >= 0 ? BetterColors.success : BetterColors.danger
            HStack(spacing: 5) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text(metric.formattedDelta(delta))
                    .font(BetterTypography.micro.weight(.bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(BetterColors.card, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
            .position(CGPoint(x: (start.x + end.x) / 2, y: min(max((start.y + end.y) / 2 - 14, 22), 128)))
        }
    }

    private func endpointLabel(title: String, value: Double?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(BetterTypography.micro.weight(.semibold))
                .foregroundStyle(BetterColors.mutedText)
            Text(value.map(metric.formatted) ?? "Pending")
                .font(BetterTypography.footnote.weight(.bold))
                .foregroundStyle(value == nil ? BetterColors.mutedText : BetterColors.text)
        }
    }

    private var lineColor: Color {
        guard let delta else { return BetterColors.mutedText.opacity(0.45) }
        return delta >= 0 ? BetterColors.success : BetterColors.danger
    }

    private func point(for value: Double?, x: CGFloat, size: CGSize) -> CGPoint {
        guard let value else {
            return CGPoint(x: x, y: size.height * 0.52)
        }
        let range = valueRange
        let normalized = range.upperBound == range.lowerBound ? 0.5 : (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let y = (1 - CGFloat(normalized)) * (size.height - 28) + 14
        return CGPoint(x: x, y: y)
    }

    private var valueRange: ClosedRange<Double> {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * 0.25, metric == .score ? 5 : 0.3)
        return (minValue - padding)...(maxValue + padding)
    }
}

struct ProtocolNightHistoryStrip: View {
    let points: [ProtocolChartPoint]
    let metric: ProtocolImpactMetric
    let baselineValue: Double?

    @State private var selectedDateKey: String?

    private var visiblePoints: [(point: ProtocolChartPoint, value: Double)] {
        points.compactMap { point in
            metric.value(from: point).map { (point, $0) }
        }
    }

    private var selectedPoint: (point: ProtocolChartPoint, value: Double)? {
        guard let selectedDateKey else { return nil }
        return visiblePoints.first { $0.point.dateKey == selectedDateKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent nights")
                    .font(BetterTypography.footnote.weight(.semibold))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                if let baselineValue {
                    Text("Baseline \(metric.formatted(baselineValue))")
                        .font(BetterTypography.micro.weight(.semibold))
                        .foregroundStyle(BetterColors.mutedText)
                }
            }

            if visiblePoints.isEmpty {
                emptyState
            } else {
                nightStrip
                legend
                if let selectedPoint {
                    tooltip(for: selectedPoint)
                }
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var nightStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 9) {
                ForEach(visiblePoints, id: \.point.id) { item in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            selectedDateKey = selectedDateKey == item.point.dateKey ? nil : item.point.dateKey
                        }
                    } label: {
                        VStack(spacing: 8) {
                            dot(for: item.point, isSelected: selectedDateKey == item.point.dateKey)
                            Text(dayLabel(for: item.point.date))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedDateKey == item.point.dateKey ? BetterColors.text : BetterColors.mutedText)
                        }
                        .frame(width: 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func dot(for point: ProtocolChartPoint, isSelected: Bool) -> some View {
        let color: Color = switch point.status {
        case .taken:
            BetterColors.success
        case .notTaken:
            BetterColors.subtext
        case .unknown:
            BetterColors.mutedText
        }

        return Circle()
            .fill(point.status == .taken ? color : point.status == .unknown ? color.opacity(0.22) : BetterColors.card)
            .overlay {
                Circle()
                    .stroke(color, lineWidth: point.status == .taken ? 0 : 1.8)
            }
            .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
            .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 6)
    }

    private var legend: some View {
        HStack(spacing: BetterSpacing.medium) {
            legendItem(color: BetterColors.success, fill: true, label: "Protocol")
            legendItem(color: BetterColors.subtext, fill: false, label: "Off")
            legendItem(color: BetterColors.mutedText, fill: true, label: "Unknown")
            Spacer()
        }
    }

    private func legendItem(color: Color, fill: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(fill ? color.opacity(label == "Unknown" ? 0.22 : 1) : BetterColors.card)
                .overlay(Circle().stroke(color, lineWidth: fill && label != "Unknown" ? 0 : 1.4))
                .frame(width: 8, height: 8)
            Text(label)
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func tooltip(for item: (point: ProtocolChartPoint, value: Double)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.point.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(BetterTypography.micro.weight(.semibold))
                    .foregroundStyle(BetterColors.mutedText)
                Text(statusLabel(for: item.point.status))
                    .font(BetterTypography.caption.weight(.semibold))
                    .foregroundStyle(item.point.status == .taken ? BetterColors.success : BetterColors.subtext)
            }
            Spacer()
            Text(metric.formatted(item.value))
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        Text("Recent nights will appear after sleep data is available.")
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BetterSpacing.medium)
            .background(BetterColors.cardSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusLabel(for status: ProtocolNightStatus) -> String {
        switch status {
        case .taken:
            "Protocol night"
        case .notTaken:
            "Off night"
        case .unknown:
            "Unknown"
        }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

private extension ProtocolComparisonWindow {
    var shortLabel: String {
        switch self {
        case .last7Days:
            "7d"
        case .last15Days:
            "15d"
        case .last30Days:
            "30d"
        case .all:
            "All"
        }
    }
}
