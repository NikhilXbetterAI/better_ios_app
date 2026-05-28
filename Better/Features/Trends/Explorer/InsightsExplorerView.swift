import SwiftUI

struct InsightsExplorerView: View {
    @Bindable var viewModel: TrendsViewModel
    @State private var isExpanded = false

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                header
                metricPickerRows
                ExplorerChartView(
                    points: viewModel.chartPoints,
                    secondaryPoints: viewModel.secondaryChartPoints,
                    tertiaryPoints: viewModel.tertiaryChartPoints,
                    primaryMetric: viewModel.selectedMetric,
                    secondaryMetric: viewModel.secondaryMetric,
                    tertiaryMetric: viewModel.tertiaryMetric
                )
                PeriodComparisonTableView(
                    averages: viewModel.periodAverages,
                    primaryMetric: viewModel.selectedMetric,
                    secondaryMetric: viewModel.secondaryMetric
                )
            }
        }
        .fullScreenCover(isPresented: $isExpanded) {
            ExplorerFullScreenView(viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "rectangle.split.2x1.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BetterColors.cyan, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Explore Metrics")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Select metrics to compare")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer()

            Button {
                isExpanded = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BetterColors.subtext)
                    .frame(width: 32, height: 32)
                    .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Metric Picker Rows

    private var metricPickerRows: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            // Row 1: Primary
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BetterColors.brand)
                        .frame(width: 8, height: 8)
                    Text("Primary")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .tracking(0.8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BetterSpacing.small) {
                        ForEach(TrendMetric.allCases) { metric in
                            let isSelected = viewModel.selectedMetric == metric
                            Button {
                                viewModel.selectMetric(metric)
                            } label: {
                                Text(metric.displayName)
                                    .font(BetterTypography.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundStyle(isSelected ? BetterColors.text : BetterColors.subtext)
                                    .padding(.horizontal, BetterSpacing.medium)
                                    .padding(.vertical, BetterSpacing.small)
                                    .background(
                                        isSelected ? BetterColors.brand.opacity(0.28) : BetterColors.cardSecondary,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                isSelected ? BetterColors.brand : BetterColors.border,
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollClipDisabled(false)
            }

            // Row 2: Compare 1
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BetterColors.success)
                        .frame(width: 8, height: 8)
                    Text("Compare 1")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .tracking(0.8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BetterSpacing.small) {
                        // None chip
                        let noneSelected = viewModel.secondaryMetric == nil
                        Button {
                            viewModel.selectSecondaryMetric(nil)
                        } label: {
                            Text("None")
                                .font(BetterTypography.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundStyle(noneSelected ? BetterColors.text : BetterColors.subtext)
                                .padding(.horizontal, BetterSpacing.medium)
                                .padding(.vertical, BetterSpacing.small)
                                .background(
                                    noneSelected ? BetterColors.success.opacity(0.25) : BetterColors.cardSecondary,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            noneSelected ? BetterColors.success : BetterColors.border,
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)

                        ForEach(TrendMetric.allCases) { metric in
                            if metric != viewModel.selectedMetric {
                                let isSelected = viewModel.secondaryMetric == metric
                                Button {
                                    viewModel.selectSecondaryMetric(metric)
                                } label: {
                                    Text(metric.displayName)
                                        .font(BetterTypography.caption)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .foregroundStyle(isSelected ? BetterColors.text : BetterColors.subtext)
                                        .padding(.horizontal, BetterSpacing.medium)
                                        .padding(.vertical, BetterSpacing.small)
                                        .background(
                                            isSelected ? BetterColors.success.opacity(0.25) : BetterColors.cardSecondary,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(
                                                    isSelected ? BetterColors.success : BetterColors.border,
                                                    lineWidth: 1
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollClipDisabled(false)
            }

            // Row 3: Compare 2 — only shown when a secondary metric is selected
            if viewModel.secondaryMetric != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(BetterColors.warning)
                            .frame(width: 8, height: 8)
                        Text("Compare 2")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .tracking(0.8)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BetterSpacing.small) {
                            // None chip
                            let noneSelected = viewModel.tertiaryMetric == nil
                            Button {
                                viewModel.selectTertiaryMetric(nil)
                            } label: {
                                Text("None")
                                    .font(BetterTypography.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundStyle(noneSelected ? BetterColors.text : BetterColors.subtext)
                                    .padding(.horizontal, BetterSpacing.medium)
                                    .padding(.vertical, BetterSpacing.small)
                                    .background(
                                        noneSelected ? BetterColors.warning.opacity(0.25) : BetterColors.cardSecondary,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                noneSelected ? BetterColors.warning : BetterColors.border,
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)

                            ForEach(TrendMetric.allCases) { metric in
                                if metric != viewModel.selectedMetric && metric != viewModel.secondaryMetric {
                                    let isSelected = viewModel.tertiaryMetric == metric
                                    Button {
                                        viewModel.selectTertiaryMetric(metric)
                                    } label: {
                                        Text(metric.displayName)
                                            .font(BetterTypography.caption)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                            .foregroundStyle(isSelected ? BetterColors.text : BetterColors.subtext)
                                            .padding(.horizontal, BetterSpacing.medium)
                                            .padding(.vertical, BetterSpacing.small)
                                            .background(
                                                isSelected ? BetterColors.warning.opacity(0.25) : BetterColors.cardSecondary,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(
                                                        isSelected ? BetterColors.warning : BetterColors.border,
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .scrollClipDisabled(false)
                }
            }
        }
    }
}
