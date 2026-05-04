import SwiftUI

struct TrendsTabView: View {
    @Bindable var viewModel: TrendsViewModel
    let protocolImpactSummary: ProtocolImpactSummary?

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    TrendWindowPickerView(selection: $viewModel.selectedWindow) { window in
                        Task { await viewModel.selectWindow(window) }
                    }
                    TrendMetricSelectorView(selection: $viewModel.selectedMetric) { metric in
                        viewModel.selectMetric(metric)
                    }
                    TrendLineChartView(points: viewModel.chartPoints, metric: viewModel.selectedMetric)
                    summaryStrip
                    StageStackedBarView(points: viewModel.stageCompositionPoints)
                    BaselineComparisonChartView(baseline: viewModel.baseline, latestSession: viewModel.sessions.last)
                    ProtocolImpactView(summary: protocolImpactSummary)
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.loadData() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Insights")
                .font(BetterTypography.display)
                .foregroundStyle(BetterColors.text)
            Text("Trends from cached sleep sessions")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: BetterSpacing.medium) {
            summaryCell("This", value: currentNightsText, color: BetterColors.brand)
            summaryCell("Change", value: changeText, color: changeColor)
            summaryCell("Previous", value: previousNightsText, color: BetterColors.hrv)
        }
    }

    private func summaryCell(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text(label.uppercased())
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Text(value)
                .font(BetterTypography.title)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    let protocolVM = ProtocolViewModel(localRepository: env.localRepository)
    TrendsTabView(
        viewModel: TrendsViewModel(localRepository: env.localRepository),
        protocolImpactSummary: protocolVM.impactSummary
    )
}
