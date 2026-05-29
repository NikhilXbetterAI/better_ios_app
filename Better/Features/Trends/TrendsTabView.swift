import SwiftUI

struct TrendsTabView: View {
    @Bindable var viewModel: TrendsViewModel
    var onOpenChronotype: () -> Void = {}

    var body: some View {
        ZStack {
            backgroundLayer
            ScrollView(.vertical, showsIndicators: false) {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    TrendsDashboardSkeletonView()
                        .padding(.horizontal, BetterSpacing.screen)
                } else {
                LazyVStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header

                    comparisonBanner

                    InsightsOverviewCard(
                        sessions: viewModel.sessions,
                        scoreSparklineValues: viewModel.scoreSparklineValues,
                        avgScore: viewModel.avgScoreInPeriod,
                        avgDurationHours: viewModel.avgDurationHours,
                        comparisonSummary: viewModel.comparisonSummary
                    )

                    if let chronotypeResult = viewModel.chronotypeResult,
                       chronotypeResult.estimate != nil {
                        ChronotypeInsightsPreviewCard(
                            result: chronotypeResult,
                            onOpenChronotype: onOpenChronotype
                        )
                    }

                    SleepRhythmCard(
                        chronotypeResult: nil,
                        baseline: viewModel.baseline
                    )

                    if viewModel.weekdaySessionCount + viewModel.weekendSessionCount >= 4 {
                        InsightsWeekdayWeekendCard(
                            weekdayAvgHours: viewModel.weekdayAvgHours,
                            weekendAvgHours: viewModel.weekendAvgHours,
                            weekdayCount: viewModel.weekdaySessionCount,
                            weekendCount: viewModel.weekendSessionCount
                        )
                    }

                    InsightsExplorerView(viewModel: viewModel)

                    stageSection

                    InsightsSleepInsightsCard(insights: viewModel.latestSessionInsights)

                    Spacer(minLength: 140)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BetterSpacing.screen)
                } // end else (skeleton guard)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                windowPickerToolbarItem
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .refreshable {
            await viewModel.loadData()
        }
    }

    // MARK: - Navigation Bar Window Picker

    private var windowPickerToolbarItem: some View {
        HStack(spacing: 2) {
            ForEach(TrendWindow.allCases) { window in
                let isSelected = viewModel.selectedWindow == window
                Button {
                    Task { await viewModel.selectWindow(window) }
                } label: {
                    Text(window.displayName)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? BetterColors.brand : BetterColors.subtext)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? BetterColors.brand.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            BetterColors.background
            RadialGradient(
                colors: [BetterColors.brand.opacity(0.08), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 400
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
        .padding(.top, 24)
    }

    // MARK: - Comparison Banner

    @ViewBuilder
    private var comparisonBanner: some View {
        if let summary = viewModel.comparisonSummary {
            let delta = summary.currentAverage - summary.previousAverage
            let isZero = abs(delta) < 0.01
            let iconName: String = isZero ? "minus" : (delta > 0 ? "arrow.up" : "arrow.down")
            let iconColor: Color = isZero ? BetterColors.subtext : (delta > 0 ? BetterColors.success : BetterColors.warning)
            let formattedDelta = formatSignedMetricDelta(delta)
            let formattedUsual = formatMetricValue(summary.previousAverage)

            BetterHealthCard {
                HStack(alignment: .center, spacing: BetterSpacing.medium) {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(iconColor)
                        .frame(width: 36, height: 36)
                        .background(iconColor.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("You slept \(formattedDelta) \(delta >= 0 ? "more" : "less") than your \(viewModel.selectedWindow.displayName) average (\(formattedUsual) usual).")
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(summary.currentValidNights) nights tracked")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Stage Section Card

    private var stageSection: some View {
        StageDurationCompositionView(
            points: viewModel.stageCompositionPoints,
            selectedWindow: viewModel.selectedWindow
        )
    }

    // MARK: - Computed Helpers

    private var changeColor: Color {
        guard let change = viewModel.weekOverWeekChange else { return BetterColors.subtext }
        return change >= 0 ? BetterColors.success : BetterColors.warning
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
