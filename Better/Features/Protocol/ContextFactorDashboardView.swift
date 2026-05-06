import SwiftUI

struct ContextFactorDashboardView: View {
    @Bindable var viewModel: ContextFactorDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            header
            windowPicker
            logButton

            if viewModel.isLoading {
                ProgressView()
                    .tint(BetterColors.brand)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BetterSpacing.medium)
            } else {
                content
            }

            disclaimer
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $viewModel.showCheckIn) {
            ContextCheckInView(
                sleepDateKey: viewModel.lastNightDateKey,
                existingEntry: viewModel.lastNightEntry,
                onSave: { entry in
                    Task { await viewModel.saveEntry(entry) }
                },
                onClear: {
                    Task { await viewModel.clearEntry(forDateKey: viewModel.lastNightDateKey) }
                }
            )
        }
        .task { await viewModel.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Label("Sleep Factors", systemImage: "chart.bar.fill")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Spacer()
            completionBadge
        }
    }

    @ViewBuilder
    private var completionBadge: some View {
        let status = viewModel.lastNightEntry?.completionStatus ?? .notFilled
        let (label, color): (String, Color) = {
            switch status {
            case .complete:  return ("Complete",  BetterColors.success)
            case .partial:   return ("Partial",   BetterColors.warning)
            case .notFilled: return ("Not filled", BetterColors.subtext)
            }
        }()
        Text(label)
            .font(BetterTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, BetterSpacing.medium)
            .padding(.vertical, BetterSpacing.xSmall)
            .background(color.opacity(0.16), in: Capsule())
    }

    // MARK: - Window picker

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

    // MARK: - Log button

    private var logButton: some View {
        Button {
            viewModel.openCheckIn()
        } label: {
            let hasEntry = viewModel.lastNightEntry != nil
            Label(
                hasEntry ? "Edit last night's check-in" : "Log last night",
                systemImage: hasEntry ? "pencil.circle.fill" : "plus.circle.fill"
            )
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BetterSpacing.medium)
            .background(BetterColors.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.allResults.isEmpty {
            emptyState(
                message: "Log a few nights to start comparing sleep against lifestyle factors."
            )
        } else {
            if !viewModel.topResults.isEmpty {
                // High impact summary section
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    Text("Highest Impact")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .textCase(.uppercase)

                    VStack(spacing: BetterSpacing.small) {
                        ForEach(viewModel.topResults, id: \.factor) { result in
                            highImpactCard(result)
                        }
                    }
                }
                .padding(.bottom, BetterSpacing.medium)
            } else if !viewModel.allResults.isEmpty {
                emptyState(
                    message: "No meaningful differences found yet. Keep logging nights to build the comparison."
                )
                .padding(.bottom, BetterSpacing.medium)
            }

            allFactorsGrid
        }
    }

    private func highImpactCard(_ result: ContextComparisonResult) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            ZStack {
                Circle()
                    .fill(BetterColors.brand.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: result.factor.systemImageName)
                    .foregroundStyle(BetterColors.brand)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.factor.displayName)
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                
                if let delta = result.durationDelta {
                    Text("\(formatSignedMinutes(delta)) average sleep duration")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            Spacer()

            confidenceBadge(result.confidence)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Factor rows

    private func factorRow(_ result: ContextComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(result.factor.displayName, systemImage: result.factor.systemImageName)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                confidenceBadge(result.confidence)
            }

            HStack(spacing: BetterSpacing.small) {
                if let yesAvg = result.averageSleepDurationYes,
                   let noAvg  = result.averageSleepDurationNo {
                    metricPill("Yes", formatDuration(yesAvg), color: BetterColors.success)
                    metricPill("No",  formatDuration(noAvg),  color: BetterColors.warning)
                    if let delta = result.durationDelta {
                        Text(formatSignedMinutes(delta))
                            .font(BetterTypography.caption)
                            .foregroundStyle(abs(delta) >= ContextComparisonService.meaningfulDurationDelta
                                             ? BetterColors.brand : BetterColors.subtext)
                    }
                } else {
                    Text("Not enough data")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var allFactorsGrid: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("All Lifestyle Factors")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(viewModel.allResults, id: \.factor) { result in
                    factorGridCard(result)
                }
            }
        }
    }

    private func factorGridCard(_ result: ContextComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: result.factor.systemImageName)
                    .font(.system(size: 14))
                    .foregroundStyle(BetterColors.brand)
                Spacer()
                nightCountText(result)
            }

            Text(result.factor.displayName)
                .font(BetterTypography.caption)
                .bold()
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)

            HStack {
                confidenceBadge(result.confidence)
                Spacer()
                if result.hasMeaningfulDifference, let delta = result.durationDelta {
                    Text(formatSignedMinutes(delta))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(BetterColors.brand)
                }
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(result.hasMeaningfulDifference ? BetterColors.brand.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Empty state

    private func emptyState(message: String) -> some View {
        Text(message)
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.subtext)
            .fixedSize(horizontal: false, vertical: true)
            .padding(BetterSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("These are associations in your own data, not causes. No data leaves this device.")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
    }

    // MARK: - Sub-components

    private func confidenceBadge(_ confidence: ComparisonConfidence) -> some View {
        let (label, color): (String, Color) = {
            switch confidence {
            case .high:        return ("High",   BetterColors.success)
            case .medium:      return ("Medium", BetterColors.brand)
            case .low:         return ("Low",    BetterColors.warning)
            case .unavailable: return ("—",      BetterColors.subtext)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
    }

    private func nightCountText(_ result: ContextComparisonResult) -> some View {
        Text("\(result.yesNightCount)y · \(result.noNightCount)n")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(BetterColors.subtext)
    }

    private func metricPill(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Text(value)
                .font(BetterTypography.caption)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatters

    private func formatDuration(_ ti: TimeInterval) -> String {
        let m = max(0, Int((ti / 60).rounded()))
        let h = m / 60; let min = m % 60
        return h > 0 ? "\(h)h \(min)m" : "\(min)m"
    }

    private func formatSignedMinutes(_ ti: TimeInterval) -> String {
        let m = Int((ti / 60).rounded())
        return "\(m >= 0 ? "+" : "")\(m)m"
    }
}

#Preview("Context Factor Dashboard") {
    let env = AppEnvironment.preview()
    ScrollView {
        ContextFactorDashboardView(
            viewModel: ContextFactorDashboardViewModel(localRepository: env.localRepository)
        )
        .padding()
    }
    .background(BetterColors.background)
}
