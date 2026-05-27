import SwiftUI

struct TrendsTabView: View {
    @Bindable var viewModel: TrendsViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer(screenHeight: geometry.size.height)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: BetterSpacing.section) {
                        header

                        TrendWindowPickerView(selection: $viewModel.selectedWindow) { window in
                            Task { await viewModel.selectWindow(window) }
                        }

                        insightFramingCard

                        // Overview — score sparkline + period summary
                        InsightsOverviewCard(
                            sessions: viewModel.sessions,
                            scoreSparklineValues: viewModel.scoreSparklineValues,
                            avgScore: viewModel.avgScoreInPeriod,
                            avgDurationHours: viewModel.avgDurationHours,
                            bestScore: viewModel.bestSleepSession.map { Int(viewModel.healthScore(for: $0).rounded()) },
                            comparisonSummary: viewModel.comparisonSummary
                        )

                        if let chronotypeResult = viewModel.chronotypeResult {
                            ChronotypeInsightCardView(result: chronotypeResult)
                        }

                        // Sleep insights (moved from Sleep dashboard)
                        InsightsSleepInsightsCard(insights: viewModel.latestSessionInsights)

                        // Trend chart section
                        trendChartSection

                        // Bedtime pattern (requires baseline)
                        if let baseline = viewModel.baseline, baseline.validNights >= 7 {
                            InsightsBedtimeCard(baseline: baseline)
                        }

                        // Best night card
                        if let best = viewModel.bestSleepSession {
                            InsightsBestSleepCard(
                                session: best,
                                score: Int(viewModel.healthScore(for: best).rounded()),
                                windowLabel: viewModel.selectedWindow.displayName
                            )
                        }

                        // Weekday vs weekend
                        if viewModel.weekdaySessionCount + viewModel.weekendSessionCount >= 4 {
                            InsightsWeekdayWeekendCard(
                                weekdayAvgHours: viewModel.weekdayAvgHours,
                                weekendAvgHours: viewModel.weekendAvgHours,
                                weekdayCount: viewModel.weekdaySessionCount,
                                weekendCount: viewModel.weekendSessionCount
                            )
                        }

                        // Stage composition over time
                        stageSection

                        // Baseline comparison chart
                        BaselineComparisonChartView(
                            baseline: viewModel.baseline,
                            latestSession: viewModel.sessions.last
                        )

                        Spacer(minLength: 140)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BetterSpacing.screen)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
        }
        .refreshable {
            await viewModel.loadData()
        }
    }

    // MARK: - Background

    private func backgroundLayer(screenHeight: CGFloat) -> some View {
        ZStack {
            BetterColors.background
            RadialGradient(
                colors: [BetterColors.brand.opacity(0.08), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: screenHeight * 0.5
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("BETTER SLEEP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.brandLight)
                .tracking(1.6)
            Text("Sleep Insights")
                .font(BetterTypography.display)
                .foregroundStyle(BetterColors.text)
            Text("Patterns and trends from your sleep history")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(.top, 58)
    }

    // MARK: - Trend Chart Section

    private var insightFramingCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("What changed")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)

                HStack(alignment: .top, spacing: BetterSpacing.small) {
                    framingCell(
                        title: "Changed",
                        value: changedValueText,
                        detail: changedDetailText,
                        color: changeColor
                    )
                    framingCell(
                        title: "Usual",
                        value: usualValueText,
                        detail: usualDetailText,
                        color: BetterColors.hrv
                    )
                    framingCell(
                        title: "Data",
                        value: dataValueText,
                        detail: dataDetailText,
                        color: BetterColors.brand
                    )
                }
            }
        }
    }

    private func framingCell(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text(detail)
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trendChartSection: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                // Section header
                HStack(spacing: BetterSpacing.small) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(BetterColors.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Sleep Trends")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                }

                TrendMetricSelectorView(selection: $viewModel.selectedMetric) { metric in
                    viewModel.selectMetric(metric)
                }

                TrendLineChartView(
                    points: viewModel.chartPoints,
                    metric: viewModel.selectedMetric,
                    protocolStatus: viewModel.adherenceByDateKey,
                    protocolStartDate: viewModel.protocolStartDate
                )

                if hasTakenNights || hasNotTakenNights {
                    ProtocolChartLegend(hasTaken: hasTakenNights, hasNotTaken: hasNotTakenNights)
                }

                summaryStrip
            }
        }
    }

    // MARK: - Stage Section Card

    private var stageSection: some View {
        StageDurationCompositionView(
            points: viewModel.stageCompositionPoints,
            selectedWindow: viewModel.selectedWindow
        ) { window in
            Task {
                await viewModel.selectWindow(window)
            }
        }
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: BetterSpacing.small) {
            summaryCell("This Period", value: currentNightsText, color: BetterColors.brand)
            summaryCell("Change", value: changeText, color: changeColor)
            summaryCell("Previous", value: previousNightsText, color: BetterColors.hrv)
        }
    }

    private func summaryCell(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Computed Helpers

    private var hasTakenNights: Bool {
        viewModel.adherenceByDateKey.values.contains(true)
    }
    private var hasNotTakenNights: Bool {
        viewModel.adherenceByDateKey.values.contains(false)
    }

    private var changeText: String {
        guard let change = viewModel.weekOverWeekChange else { return "--" }
        return String(format: "%+.0f%%", change * 100)
    }
    private var changeColor: Color {
        guard let change = viewModel.weekOverWeekChange else { return BetterColors.subtext }
        return change >= 0 ? BetterColors.success : BetterColors.warning
    }
    private var currentNightsText: String {
        viewModel.comparisonSummary.map { "\($0.currentValidNights)n" } ?? "\(viewModel.sessions.count)n"
    }
    private var previousNightsText: String {
        viewModel.comparisonSummary.map { "\($0.previousValidNights)n" } ?? "--"
    }

    private var changedValueText: String {
        guard let summary = viewModel.comparisonSummary else { return "Needs prior data" }
        return "\(formatSignedMetricDelta(summary.currentAverage - summary.previousAverage))"
    }

    private var changedDetailText: String {
        guard let summary = viewModel.comparisonSummary else {
            return "Compare to a previous \(viewModel.selectedWindow.displayName) window"
        }
        return "\(formatMetricValue(summary.currentAverage)) now vs \(formatMetricValue(summary.previousAverage)) prior"
    }

    private var usualValueText: String {
        guard let latest = viewModel.sessions.last,
              let baseline = viewModel.baseline,
              let latestValue = metricValue(for: latest),
              let baselineValue = baselineMetricValue(baseline)
        else { return "Usual not ready" }

        return formatSignedMetricDelta(latestValue - baselineValue)
    }

    private var usualDetailText: String {
        guard let baseline = viewModel.baseline, baseline.validNights >= 7 else {
            return "Usual needs 7+ baseline nights"
        }
        guard baselineMetricValue(baseline) != nil else {
            return "Usual unavailable for this metric"
        }
        return "Latest night vs \(baseline.validNights)-night usual"
    }

    private var dataValueText: String {
        "\(viewModel.sessions.count)n"
    }

    private var dataDetailText: String {
        if let summary = viewModel.comparisonSummary {
            return "\(summary.currentValidNights) current / \(summary.previousValidNights) prior"
        }
        if let baseline = viewModel.baseline {
            return "\(baseline.validNights) usual baseline nights"
        }
        return "\(viewModel.selectedWindow.displayName) window"
    }

    private func metricValue(for session: SleepSession) -> Double? {
        switch viewModel.selectedMetric {
        case .totalSleep:
            session.totalSleepTime / 3_600
        case .longestRestorativeBlock:
            session.continuitySummary.blocks.isEmpty ? nil : session.continuitySummary.longestBlockDuration / 3_600
        case .score:
            viewModel.healthScore(for: session)
        case .deepSleep:
            session.dataQuality == .detailedStages ? session.deepDuration / 3_600 : nil
        case .remSleep:
            session.dataQuality == .detailedStages ? session.remDuration / 3_600 : nil
        case .hrv:
            session.biometrics?.hrvAverage
        case .waso:
            session.waso / 60
        case .latency:
            session.sleepLatency / 60
        case .respiratoryRate:
            session.biometrics?.respiratoryRateAverage
        case .oxygenSaturation:
            session.biometrics?.oxygenSaturationAverage.map { $0 * 100 }
        }
    }

    private func baselineMetricValue(_ baseline: SleepBaseline) -> Double? {
        switch viewModel.selectedMetric {
        case .totalSleep:
            baseline.totalSleepAverage / 3_600
        case .longestRestorativeBlock, .score:
            nil
        case .deepSleep:
            baseline.deepAverage / 3_600
        case .remSleep:
            baseline.remAverage / 3_600
        case .hrv:
            baseline.hrvAverage
        case .waso:
            baseline.wasoAverage / 60
        case .latency:
            baseline.latencyAverage / 60
        case .respiratoryRate:
            baseline.respiratoryRateAverage
        case .oxygenSaturation:
            baseline.oxygenSaturationAverage * 100
        }
    }

    private func formatMetricValue(_ value: Double) -> String {
        switch viewModel.selectedMetric {
        case .totalSleep, .longestRestorativeBlock, .deepSleep, .remSleep:
            String(format: "%.1fh", value)
        case .score:
            String(format: "%.0f pts", value)
        case .hrv:
            String(format: "%.0f ms", value)
        case .waso, .latency:
            String(format: "%.0f min", value)
        case .respiratoryRate:
            String(format: "%.1f br/min", value)
        case .oxygenSaturation:
            String(format: "%.0f%%", value)
        }
    }

    private func formatSignedMetricDelta(_ delta: Double) -> String {
        switch viewModel.selectedMetric {
        case .totalSleep, .longestRestorativeBlock, .deepSleep, .remSleep:
            return String(format: "%+.1fh", delta)
        case .score:
            return String(format: "%+.0f pts", delta)
        case .hrv:
            return String(format: "%+.0f ms", delta)
        case .waso, .latency:
            return String(format: "%+.0f min", delta)
        case .respiratoryRate:
            return String(format: "%+.1f br/min", delta)
        case .oxygenSaturation:
            return String(format: "%+.0f%%", delta)
        }
    }
}

#if DEBUG
#Preview("Trends") {
    let env = AppEnvironment.preview()
    NavigationStack {
        TrendsTabView(viewModel: TrendsViewModel(localRepository: env.localRepository))
    }
    .preferredColorScheme(.dark)
}
#endif
