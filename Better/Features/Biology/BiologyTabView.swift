import SwiftUI

struct BiologyTabView: View {
    @Bindable var viewModel: BiologyViewModel
    @State private var activeManualKind: BiologyMetricKind?

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header

                    if viewModel.isLoading, viewModel.metrics.isEmpty {
                        ProgressView()
                            .tint(BetterColors.brand)
                            .frame(maxWidth: .infinity)
                    } else {
                        content
                    }
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xxLarge)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.load() }
        .sheet(item: $activeManualKind) { kind in
            ManualBiologyEntrySheet(kind: kind) { value in
                Task { await viewModel.saveManualEntry(kind: kind, value: value) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Biology")
                    .font(BetterTypography.largeTitle)
                    .foregroundStyle(BetterColors.text)
                Text("Apple Health baselines and body metrics")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            syncBadge
        }
    }

    private var syncBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.errorMessage == nil ? BetterColors.success : BetterColors.warning)
                .frame(width: 7, height: 7)
            Text(viewModel.errorMessage == nil ? "Synced" : "Partial")
                .font(BetterTypography.caption)
                .foregroundStyle(viewModel.errorMessage == nil ? BetterColors.success : BetterColors.warning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BetterColors.cardSecondary, in: Capsule())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            if let vo2 = metric(.vo2Max) {
                Vo2MaxCard(metric: vo2)
                    .manualOverlay(metric: vo2, onAdd: { activeManualKind = .vo2Max })
            }

            LazyVGrid(columns: twoColumns, spacing: BetterSpacing.medium) {
                if let hrv = metric(.hrvBaseline) {
                    CompactBiologyMetricCard(metric: hrv, iconName: "waveform.path.ecg", color: BetterColors.hrv)
                        .manualOverlay(metric: hrv, onAdd: { activeManualKind = .hrvBaseline })
                }
                if let rhr = metric(.restingHeartRateBaseline) {
                    CompactBiologyMetricCard(metric: rhr, iconName: "heart.fill", color: BetterColors.heartRate, usesGauge: true)
                        .manualOverlay(metric: rhr, onAdd: { activeManualKind = .restingHeartRateBaseline })
                }
            }

            if let weight = metric(.weight) {
                WideBiologyMetricCard(metric: weight, iconName: "scalemass.fill", color: BetterColors.violet)
                    .manualOverlay(metric: weight, onAdd: { activeManualKind = .weight })
            }

            LazyVGrid(columns: twoColumns, spacing: BetterSpacing.medium) {
                if let lean = metric(.leanBodyMass) {
                    CompactBiologyMetricCard(metric: lean, iconName: "figure.strengthtraining.traditional", color: BetterColors.activity)
                        .manualOverlay(metric: lean, onAdd: { activeManualKind = .leanBodyMass })
                }
                if let bodyFat = metric(.bodyFatPercentage) {
                    CompactBiologyMetricCard(metric: bodyFat, iconName: "percent", color: BetterColors.success, usesGauge: true)
                        .manualOverlay(metric: bodyFat, onAdd: { activeManualKind = .bodyFatPercentage })
                }
            }

            VitalsRow(
                metrics: [
                    metric(.bloodOxygen),
                    metric(.bodyTemperature),
                    metric(.respiratoryRate)
                ].compactMap { $0 },
                onAdd: { activeManualKind = $0 }
            )

            BiologyInsightsCard(metrics: metricsByKind)
        }
    }

    private var twoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: BetterSpacing.medium),
            GridItem(.flexible(), spacing: BetterSpacing.medium)
        ]
    }

    private var metricsByKind: [BiologyMetricKind: BiologyMetric] {
        Dictionary(uniqueKeysWithValues: viewModel.metrics.map { ($0.kind, $0) })
    }

    private func metric(_ kind: BiologyMetricKind) -> BiologyMetric? {
        metricsByKind[kind]
    }
}

private struct Vo2MaxCard: View {
    let metric: BiologyMetric

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                metricHeader(iconName: "lungs.fill", title: metric.title, color: BetterColors.warning)
                HStack(alignment: .bottom, spacing: BetterSpacing.large) {
                    metricValue(metric)
                    Spacer()
                    VStack(alignment: .trailing, spacing: BetterSpacing.small) {
                        RangeBandView(value: metric.value, bounds: 30...65, color: BetterColors.warning)
                            .frame(width: 160)
                        HStack {
                            Text("Low")
                            Spacer()
                            Text("Excellent")
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                    }
                }
            }
        }
    }
}

private struct WideBiologyMetricCard: View {
    let metric: BiologyMetric
    let iconName: String
    let color: Color

    var body: some View {
        BetterHealthCard {
            HStack(alignment: .bottom, spacing: BetterSpacing.large) {
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    metricHeader(iconName: iconName, title: metric.title, color: color)
                    metricValue(metric)
                }
                Spacer()
                SparklineView(values: metric.history, color: color)
                    .frame(width: 170)
            }
        }
    }
}

private struct CompactBiologyMetricCard: View {
    let metric: BiologyMetric
    let iconName: String
    let color: Color
    var usesGauge = false

    var body: some View {
        BetterHealthCard(padding: BetterSpacing.medium) {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                metricHeader(iconName: iconName, title: metric.title, color: color)
                if usesGauge {
                    HStack(alignment: .bottom) {
                        metricValue(metric, compact: true)
                        Spacer()
                        MetricGaugeView(progress: progress, color: color)
                    }
                } else {
                    SparklineView(values: metric.history, color: color)
                    metricValue(metric, compact: true)
                }
            }
            .frame(minHeight: 148, alignment: .top)
        }
    }

    private var progress: Double {
        guard let value = metric.value else { return 0 }
        switch metric.kind {
        case .bodyFatPercentage:
            return min(max(value / 35, 0.08), 0.92)
        case .restingHeartRateBaseline:
            return min(max((90 - value) / 45, 0.08), 0.92)
        default:
            return min(max(value / 100, 0.08), 0.92)
        }
    }
}

private struct VitalsRow: View {
    let metrics: [BiologyMetric]
    let onAdd: (BiologyMetricKind) -> Void

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            ForEach(metrics) { metric in
                BetterHealthCard(cornerRadius: 18, padding: BetterSpacing.medium) {
                    VStack(alignment: .leading, spacing: BetterSpacing.small) {
                        HStack {
                            Image(systemName: icon(for: metric.kind))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(color(for: metric.kind))
                            Spacer()
                            if metric.isManualEntry {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(BetterColors.subtext)
                            }
                        }
                        if metric.value != nil {
                            Text(displayValue(metric))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Button {
                                onAdd(metric.kind)
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(BetterColors.brand)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(metric.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                        Text(metric.rating)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(color(for: metric.kind))
                    }
                }
            }
        }
    }

    private func icon(for kind: BiologyMetricKind) -> String {
        switch kind {
        case .bloodOxygen: "drop.fill"
        case .bodyTemperature: "thermometer.medium"
        default: "wind"
        }
    }

    private func color(for kind: BiologyMetricKind) -> Color {
        switch kind {
        case .bloodOxygen: BetterColors.cyan
        case .bodyTemperature: BetterColors.warning
        default: BetterColors.hrv
        }
    }
}

private struct BiologyInsightsCard: View {
    let metrics: [BiologyMetricKind: BiologyMetric]

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("Research Connections")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .textCase(.uppercase)
                insight("HRV baseline", body: hrvInsight, color: BetterColors.hrv, iconName: "waveform.path.ecg")
                insight("Oxygenation", body: oxygenInsight, color: BetterColors.cyan, iconName: "drop.fill")
                insight("Body composition", body: bodyInsight, color: BetterColors.warning, iconName: "scalemass.fill")
            }
        }
    }

    private var hrvInsight: String {
        if let value = metrics[.hrvBaseline]?.value {
            return "Current HRV baseline is \(Int(value)) ms. Use this alongside sleep stages before changing recovery protocols."
        }
        return "HRV baseline will appear after enough Apple Health samples are available."
    }

    private var oxygenInsight: String {
        if let value = metrics[.bloodOxygen]?.value {
            return "Average SpO2 is \(Int(value))%. Stable oxygenation supports clearer deep-sleep interpretation."
        }
        return "Blood oxygen data is not available yet."
    }

    private var bodyInsight: String {
        if let value = metrics[.weight]?.value {
            return "Weight is \(String(format: "%.1f", value)) kg. Track changes with RHR and sleep fragmentation over time."
        }
        return "Body composition cards are ready for Apple Health body metrics."
    }

    private func insight(_ title: String, body: String, color: Color, iconName: String) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.text)
                Text(body)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.medium)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func metricHeader(iconName: String, title: String, color: Color) -> some View {
    HStack(spacing: 8) {
        Image(systemName: iconName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
        Text(title)
            .font(BetterTypography.subheadline)
            .foregroundStyle(BetterColors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

private func metricValue(_ metric: BiologyMetric, compact: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(displayValue(metric, includeUnit: false))
                .font(compact ? BetterTypography.compactMetric : BetterTypography.metric)
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if metric.value != nil {
                Text(metric.unit)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        Text(metric.rating)
            .font(BetterTypography.subheadline)
            .foregroundStyle(ratingColor(metric.rating))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Manual entry overlay modifier

private extension View {
    /// Overlays a "+" add button (when value is nil) and a pencil badge (when manually entered).
    @ViewBuilder
    func manualOverlay(metric: BiologyMetric, onAdd: @escaping () -> Void) -> some View {
        self
            .overlay(alignment: .topTrailing) {
                if metric.isManualEntry {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BetterColors.subtext.opacity(0.7))
                        .padding(BetterSpacing.medium)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if metric.value == nil {
                    Button(action: onAdd) {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.brand)
                    }
                    .buttonStyle(.plain)
                    .padding(BetterSpacing.medium)
                }
            }
    }
}

private func displayValue(_ metric: BiologyMetric, includeUnit: Bool = true) -> String {
    guard let value = metric.value else { return "--" }
    let formatted: String
    switch metric.kind {
    case .bloodOxygen, .bodyFatPercentage:
        formatted = String(format: "%.0f", value)
    case .respiratoryRate, .bodyTemperature, .weight, .vo2Max:
        formatted = String(format: "%.1f", value)
    default:
        formatted = String(format: "%.0f", value)
    }
    return includeUnit ? "\(formatted) \(metric.unit)" : formatted
}

private func ratingColor(_ rating: String) -> Color {
    switch rating {
    case "Good", "Excellent", "Strong", "Acceptable", "Normal":
        BetterColors.success
    case "Fair", "Stabilizing", "Tracking":
        BetterColors.warning
    case "Elevated", "Low", "Watch":
        BetterColors.danger
    default:
        BetterColors.subtext
    }
}

#Preview("Biology") {
    BiologyTabView(
        viewModel: BiologyViewModel(
            localRepository: AppEnvironment.preview().localRepository,
            healthRepository: AppEnvironment.preview().healthRepository
        )
    )
}
