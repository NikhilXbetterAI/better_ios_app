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

                        // Overview — score sparkline + period summary
                        InsightsOverviewCard(
                            sessions: viewModel.sessions,
                            scoreSparklineValues: viewModel.scoreSparklineValues,
                            avgScore: viewModel.avgScoreInPeriod,
                            avgDurationHours: viewModel.avgDurationHours,
                            bestScore: viewModel.bestSleepSession.map { Int(viewModel.healthScore(for: $0).rounded()) },
                            comparisonSummary: viewModel.comparisonSummary
                        )

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
                        if !viewModel.stageCompositionPoints.isEmpty {
                            stageSectionCard
                        }

                        // Baseline comparison chart
                        BaselineComparisonChartView(
                            baseline: viewModel.baseline,
                            latestSession: viewModel.sessions.last
                        )

                        Spacer(minLength: 110)
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
        .padding(.top, 52)
    }

    // MARK: - Trend Chart Section

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

    private var stageSectionCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                HStack(spacing: BetterSpacing.small) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(BetterColors.stageDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Sleep Stage Composition")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                }
                StageStackedBarView(points: viewModel.stageCompositionPoints)
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
}

#Preview("Trends") {
    let env = AppEnvironment.preview()
    NavigationStack {
        TrendsTabView(viewModel: TrendsViewModel(localRepository: env.localRepository))
    }
    .preferredColorScheme(.dark)
}
