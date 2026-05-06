import SwiftUI

struct ProtocolComparisonDashboardView: View {
    @Bindable var viewModel: ProtocolComparisonDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            header
            windowPicker
            countsRow

            if viewModel.isLoading {
                ProgressView()
                    .tint(BetterColors.brand)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BetterSpacing.medium)
            } else {
                statusContent
            }

            Text("This shows association, not causation.")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Label("Protocol Comparison", systemImage: "pills.fill")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Spacer()
            Text(viewModel.state.confidence.displayName)
                .font(BetterTypography.caption)
                .foregroundStyle(confidenceColor)
                .padding(.horizontal, BetterSpacing.medium)
                .padding(.vertical, BetterSpacing.xSmall)
                .background(confidenceColor.opacity(0.16), in: Capsule())
        }
    }

    private var windowPicker: some View {
        HStack(spacing: BetterSpacing.xSmall) {
            ForEach(ProtocolComparisonWindow.allCases) { window in
                Button {
                    Task { await viewModel.selectWindow(window) }
                } label: {
                    Text(window.displayName)
                        .font(BetterTypography.caption)
                        .foregroundStyle(viewModel.selectedWindow == window ? Color.black : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.small)
                        .background(
                            viewModel.selectedWindow == window ? BetterColors.brand : BetterColors.cardSecondary,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var countsRow: some View {
        HStack(spacing: BetterSpacing.small) {
            countCell("Taken", count: viewModel.state.takenNightCount, color: BetterColors.success)
            countCell("Not Taken", count: viewModel.state.notTakenNightCount, color: BetterColors.warning)
            countCell("Unknown", count: viewModel.state.unknownNightCount, color: BetterColors.subtext)
        }
    }

    private func countCell(_ label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Text("\(count)")
                .font(BetterTypography.title)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.state.status {
        case .loading:
            EmptyView()
        case .enoughData:
            comparisonRows
            insights
        case .notEnoughData:
            message("Log more taken and not-taken nights to compare protocol and non-protocol sleep.")
            comparisonRows
        case .unknownProtocolData:
            message("Protocol status is unknown for these nights. Mark nights as taken or not taken to compare patterns.")
        case .baselineBuilding:
            message("Your baseline is still building. Protocol comparison can still be shown, but more valid nights will make it easier to interpret.")
            comparisonRows
        case .error(let message):
            self.message(message)
        }

        if !viewModel.state.stageDataAvailable {
            message("Stage insights are hidden because detailed stage data is not available for both groups.")
        }
    }

    private var comparisonRows: some View {
        VStack(spacing: BetterSpacing.small) {
            ForEach(viewModel.state.metricRows) { row in
                metricRow(row)
            }
        }
    }

    private func metricRow(_ row: ProtocolComparisonMetricRow) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack {
                Text(row.title)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                if let delta = row.deltaText {
                    Text(delta)
                        .font(BetterTypography.caption)
                        .foregroundStyle(row.isMeaningful ? BetterColors.brand : BetterColors.subtext)
                }
            }
            HStack(spacing: BetterSpacing.small) {
                valuePill("Taken", row.takenValue, color: BetterColors.success)
                valuePill("Not taken", row.notTakenValue, color: BetterColors.warning)
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func valuePill(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text(value)
                .font(BetterTypography.caption)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            ForEach(viewModel.state.insights.prefix(2)) { insight in
                HStack(alignment: .top, spacing: BetterSpacing.small) {
                    Circle()
                        .fill(color(for: insight.displayStyle))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.text)
                        Text(insight.body)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.subtext)
            .fixedSize(horizontal: false, vertical: true)
            .padding(BetterSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var confidenceColor: Color {
        switch viewModel.state.confidence {
        case .unavailable:
            BetterColors.subtext
        case .low:
            BetterColors.warning
        case .medium:
            BetterColors.brand
        case .high:
            BetterColors.success
        }
    }

    private func color(for style: SleepInsightDisplayStyle?) -> Color {
        switch style {
        case .positive:
            BetterColors.success
        case .caution:
            BetterColors.warning
        case .informational:
            BetterColors.brand
        case .neutral, nil:
            BetterColors.subtext
        }
    }
}

#Preview("Protocol Comparison") {
    ProtocolComparisonDashboardView(
        viewModel: ProtocolComparisonDashboardViewModel(localRepository: AppEnvironment.preview().localRepository)
    )
}

