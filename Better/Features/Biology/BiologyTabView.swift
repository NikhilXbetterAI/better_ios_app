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

            BiomarkerModuleCard(
                summaries: viewModel.biomarkerSummaries,
                isLoading: viewModel.isLoadingBiomarkers,
                errorMessage: viewModel.biomarkerErrorMessage
            )

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
        }
    }

    private var twoColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var metricsByKind: [BiologyMetricKind: BiologyMetric] {
        Dictionary(uniqueKeysWithValues: viewModel.metrics.map { ($0.kind, $0) })
    }

    private func metric(_ kind: BiologyMetricKind) -> BiologyMetric? {
        metricsByKind[kind]
    }
}

// MARK: - Biomarker Module

private struct BiomarkerZone {
    let label: String
    let range: ClosedRange<Double>
    let color: Color
}

private struct BiomarkerModuleCard: View {
    let summaries: [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]]
    let isLoading: Bool
    let errorMessage: String?

    @State private var selectedKind: BiomarkerKind = .hrv
    @State private var selectedTimeline: BiomarkerTimeline = .thirtyDays
    @State private var selectedPointID: String?
    @Namespace private var pillNS

    private var summary: BiomarkerSummary? {
        summaries[selectedKind]?[selectedTimeline]
    }

    private var selectedPoint: BiomarkerDailyPoint? {
        guard let summary else { return nil }
        if let selectedPointID, let point = summary.points.first(where: { $0.id == selectedPointID }) {
            return point
        }
        return summary.points.last
    }

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                headerRow
                kindSelector
                timelineSelector

                if isLoading, summaries.isEmpty {
                    loadingState
                } else if let summary {
                    valueSection(summary)
                    educationSection(summary)
                    chartSection(summary)
                    selectedPointSection(summary)
                    footerStats(summary)
                } else {
                    emptyState
                }
            }
        }
        .onAppear { resetSelectedPoint() }
        .onChange(of: selectedKind) { _, _ in resetSelectedPoint() }
        .onChange(of: selectedTimeline) { _, _ in resetSelectedPoint() }
        .onChange(of: summary?.id) { _, _ in resetSelectedPoint() }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Biomarkers")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .textCase(.uppercase)
                Text(selectedKind.fullName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
            }
            Spacer()
            if let errorMessage {
                Text(errorMessage.isEmpty ? "Partial" : "Partial")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BetterColors.warning.opacity(0.13), in: Capsule())
            }
        }
    }

    private var kindSelector: some View {
        HStack(spacing: 4) {
            ForEach(BiomarkerKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedKind = kind
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kind.iconName)
                            .font(.system(size: 11, weight: .bold))
                        Text(kind.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        if selectedKind == kind {
                            Capsule()
                                .fill(kind.color.opacity(0.18))
                                .overlay(Capsule().stroke(kind.color.opacity(0.35), lineWidth: 1))
                                .matchedGeometryEffect(id: "biomarkerPill", in: pillNS)
                        }
                    }
                    .foregroundStyle(selectedKind == kind ? kind.color : BetterColors.subtext)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.displayName), \(selectedKind == kind ? "selected" : "not selected")")
            }
            Spacer()
        }
    }

    private var timelineSelector: some View {
        HStack(spacing: 4) {
            ForEach(BiomarkerTimeline.allCases) { timeline in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedTimeline = timeline
                    }
                } label: {
                    Text(timeline.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedTimeline == timeline ? BetterColors.background : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedTimeline == timeline ? selectedKind.color : BetterColors.cardSecondary,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(timeline.rawValue) days, \(selectedTimeline == timeline ? "selected" : "not selected")")
            }
        }
        .padding(4)
        .background(BetterColors.cardSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func valueSection(_ summary: BiomarkerSummary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(format(summary.currentValue))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .contentTransition(.numericText())
                    Text(selectedKind.unit)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.bottom, 8)
                }
                HStack(spacing: 5) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selectedKind.color)
                    Text(deltaText(value: summary.currentValue, average: summary.average))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    Text("·")
                        .foregroundStyle(BetterColors.mutedText)
                    Text("\(summary.validSampleCount)/\(summary.expectedDayCount) days")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                statusBadge(selectedPoint?.status ?? summary.points.last?.status)
                Text(selectedTimeline.description)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.mutedText)
            }
        }
    }

    private func statusBadge(_ status: String?) -> some View {
        let label = status ?? "No Data"
        let color = statusColor(label)
        return Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }

    private func educationSection(_ summary: BiomarkerSummary) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selectedKind.color)
                .frame(width: 26, height: 26)
                .background(selectedKind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(summary.education)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.medium)
        .background(selectedKind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chartSection(_ summary: BiomarkerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BiomarkerInteractiveChart(
                points: summary.points,
                selectedPointID: selectedPointID ?? summary.points.last?.id,
                zones: selectedKind.chartZones,
                chartMin: selectedKind.chartMin,
                chartMax: selectedKind.chartMax,
                color: selectedKind.color,
                onSelect: { point in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        selectedPointID = point.id
                    }
                }
            )
            .id(summary.id)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(chartAccessibility(summary))

            legendRow
        }
    }

    private var legendRow: some View {
        HStack(spacing: 10) {
            ForEach(["Optimal", "Normal", "Fair", "Needs Attention"], id: \.self) { label in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(legendColor(label))
                        .frame(width: 12, height: 4)
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                }
            }
            Spacer()
            Text("\(selectedTimeline.rawValue) days")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.mutedText)
        }
    }

    private func legendColor(_ label: String) -> Color {
        switch label {
        case "Optimal": BetterColors.success
        case "Normal":  BetterColors.hrv
        case "Fair":    BetterColors.warning
        default:        BetterColors.danger
        }
    }

    private func selectedPointSection(_ summary: BiomarkerSummary) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedKind.color)
                .frame(width: 28, height: 28)
                .background(selectedKind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                if let selectedPoint {
                    Text("\(dateText(selectedPoint.date)) · \(format(selectedPoint.value)) \(selectedPoint.unit)")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(pointImpactText(point: selectedPoint, average: summary.average))
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not enough data yet")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(summary.calculationNote)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func footerStats(_ summary: BiomarkerSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BetterSpacing.small) {
            statTile("Average", value: valueWithUnit(summary.average))
            statTile("Best", value: valueWithUnit(summary.bestValue))
            statTile("Range", value: rangeText(summary))
            statTile("Coverage", value: "\(summary.validSampleCount)/\(summary.expectedDayCount)")
        }
    }

    private func statTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.mutedText)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var loadingState: some View {
        HStack(spacing: BetterSpacing.medium) {
            ProgressView()
                .tint(selectedKind.color)
            Text("Building biomarker trends...")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BetterSpacing.medium)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Not enough data yet")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
            Text("Better will show averages, best values, ranges, and day-level impact once Apple Health has enough biomarker samples.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resetSelectedPoint() {
        selectedPointID = summary?.points.last?.id
    }

    private func valueWithUnit(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(format(value)) \(selectedKind.unit)"
    }

    private func rangeText(_ summary: BiomarkerSummary) -> String {
        guard let minValue = summary.minValue, let maxValue = summary.maxValue else { return "--" }
        return "\(format(minValue))-\(format(maxValue)) \(selectedKind.unit)"
    }

    private func deltaText(value: Double?, average: Double?) -> String {
        guard let value, let average else { return "No average yet" }
        let diff = value - average
        if abs(diff) < 0.05 { return "At \(selectedTimeline.label) average" }
        let sign = diff > 0 ? "+" : ""
        return "\(sign)\(format(diff)) \(selectedKind.unit) vs avg"
    }

    private func pointImpactText(point: BiomarkerDailyPoint, average: Double?) -> String {
        let delta = deltaText(value: point.value, average: average)
        switch selectedKind {
        case .hrv:
            return "\(point.status). \(delta). This can reflect how recovered and adaptable your body looked that night."
        case .restingHeartRate:
            return "\(point.status). \(delta). Lower values often align with less cardiovascular strain and better recovery context."
        case .spo2:
            return "\(point.status). \(delta). Stable overnight oxygen helps make sleep-breathing signals easier to interpret."
        case .respiratoryRate:
            return "\(point.status). \(delta). Breathing shifts can add context for stress, illness, training load, or recovery."
        }
    }

    private func chartAccessibility(_ summary: BiomarkerSummary) -> String {
        "\(selectedKind.displayName) chart, \(summary.validSampleCount) values over \(summary.expectedDayCount) days"
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return format(value)
    }

    private func format(_ value: Double) -> String {
        switch selectedKind {
        case .spo2, .respiratoryRate:
            return String(format: "%.1f", value)
        case .hrv, .restingHeartRate:
            return String(format: "%.0f", value)
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Optimal":
            BetterColors.success
        case "Normal":
            BetterColors.hrv
        case "Fair":
            BetterColors.warning
        case "Needs Attention":
            BetterColors.danger
        default:
            BetterColors.subtext
        }
    }
}

// MARK: - BiomarkerInteractiveChart

private struct BiomarkerInteractiveChart: View {
    let points: [BiomarkerDailyPoint]
    let selectedPointID: String?
    let zones: [BiomarkerZone]
    let chartMin: Double
    let chartMax: Double
    let color: Color
    let onSelect: (BiomarkerDailyPoint) -> Void

    @State private var trimTo: Double = 0

    var body: some View {
        GeometryReader { geo in
            let chartPoints = dataPoints(in: geo.size)

            ZStack {
            Canvas { ctx, size in
                for zone in zones {
                    let lo = max(zone.range.lowerBound, chartMin)
                    let hi = min(zone.range.upperBound, chartMax)
                    guard hi > lo else { continue }
                    let yTop    = yF(hi) * Double(size.height)
                    let yBottom = yF(lo) * Double(size.height)
                    let rect = CGRect(x: 0, y: yTop, width: Double(size.width), height: yBottom - yTop)
                    ctx.fill(Path(rect), with: .color(zone.color.opacity(0.20)))
                }
                let mid = Double(size.height) * 0.5
                var divider = Path()
                divider.move(to: CGPoint(x: 0, y: mid))
                divider.addLine(to: CGPoint(x: Double(size.width), y: mid))
                ctx.stroke(divider, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }

                if chartPoints.count >= 2 {
                    areaPath(pts: chartPoints, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.28), color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(
                            Rectangle()
                                .frame(width: geo.size.width * trimTo)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )

                    linePath(pts: chartPoints)
                        .trim(from: 0, to: trimTo)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    if let selected = selectedPoint(in: chartPoints) {
                        Capsule()
                            .fill(color.opacity(0.16))
                            .frame(width: 2, height: geo.size.height)
                            .position(x: selected.x, y: geo.size.height / 2)
                        Circle()
                            .fill(BetterColors.text)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(color, lineWidth: 3))
                            .shadow(color: color.opacity(0.45), radius: 6)
                            .position(selected)
                    } else if let last = chartPoints.last {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .shadow(color: color.opacity(0.5), radius: 5)
                            .position(last)
                            .opacity(trimTo)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(BetterColors.mutedText)
                        Text("Collecting data...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in selectNearest(to: value.location.x, width: geo.size.width) }
            )
        }
        .onAppear { triggerAnimation() }
        .onChange(of: points) { _, _ in triggerAnimation() }
    }

    private func triggerAnimation() {
        trimTo = 0
        withAnimation(.easeInOut(duration: 0.65).delay(0.1)) {
            trimTo = 1
        }
    }

    private func yF(_ value: Double) -> Double {
        let span = chartMax - chartMin
        guard span > 0 else { return 0.5 }
        let clamped = min(max(value, chartMin), chartMax)
        return 1.0 - (clamped - chartMin) / span
    }

    private func dataPoints(in size: CGSize) -> [CGPoint] {
        let count = points.count
        return points.enumerated().map { i, point in
            let x = size.width * CGFloat(i) / CGFloat(max(count - 1, 1))
            let y = size.height * CGFloat(yF(point.value))
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
    }

    private func areaPath(pts: [CGPoint], height: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: height))
            p.addLine(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.closeSubpath()
        }
    }

    private func selectedPoint(in chartPoints: [CGPoint]) -> CGPoint? {
        guard let selectedPointID,
              let index = points.firstIndex(where: { $0.id == selectedPointID }),
              chartPoints.indices.contains(index)
        else { return nil }
        return chartPoints[index]
    }

    private func selectNearest(to xLocation: CGFloat, width: CGFloat) {
        guard !points.isEmpty else { return }
        let step = width / CGFloat(max(points.count - 1, 1))
        let index = min(max(Int((xLocation / max(step, 1)).rounded()), 0), points.count - 1)
        onSelect(points[index])
    }
}

// MARK: - Vo2MaxCard

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

// MARK: - WideBiologyMetricCard

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

// MARK: - CompactBiologyMetricCard

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
        case .bodyFatPercentage:        return min(max(value / 35, 0.08), 0.92)
        case .restingHeartRateBaseline: return min(max((90 - value) / 45, 0.08), 0.92)
        default:                        return min(max(value / 100, 0.08), 0.92)
        }
    }
}

// MARK: - Shared helpers

private extension BiomarkerKind {
    var iconName: String {
        switch self {
        case .hrv:
            "waveform.path.ecg"
        case .restingHeartRate:
            "heart.fill"
        case .spo2:
            "drop.fill"
        case .respiratoryRate:
            "wind"
        }
    }

    var color: Color {
        switch self {
        case .hrv:
            BetterColors.hrv
        case .restingHeartRate:
            BetterColors.heartRate
        case .spo2:
            BetterColors.cyan
        case .respiratoryRate:
            BetterColors.brand
        }
    }

    var chartMin: Double {
        switch self {
        case .restingHeartRate:
            28
        case .hrv:
            0
        case .spo2:
            88
        case .respiratoryRate:
            8
        }
    }

    var chartMax: Double {
        switch self {
        case .restingHeartRate:
            110
        case .hrv:
            140
        case .spo2:
            102
        case .respiratoryRate:
            24
        }
    }

    var chartZones: [BiomarkerZone] {
        switch self {
        case .restingHeartRate:
            [
                BiomarkerZone(label: "Needs Attention", range: 80...110, color: BetterColors.danger),
                BiomarkerZone(label: "Fair", range: 68...80, color: BetterColors.warning),
                BiomarkerZone(label: "Normal", range: 58...68, color: BetterColors.hrv),
                BiomarkerZone(label: "Optimal", range: 28...58, color: BetterColors.success)
            ]
        case .hrv:
            [
                BiomarkerZone(label: "Needs Attention", range: 0...20, color: BetterColors.danger),
                BiomarkerZone(label: "Fair", range: 20...40, color: BetterColors.warning),
                BiomarkerZone(label: "Normal", range: 40...60, color: BetterColors.hrv),
                BiomarkerZone(label: "Optimal", range: 60...140, color: BetterColors.success)
            ]
        case .spo2:
            [
                BiomarkerZone(label: "Needs Attention", range: 88...93, color: BetterColors.danger),
                BiomarkerZone(label: "Fair", range: 93...95, color: BetterColors.warning),
                BiomarkerZone(label: "Normal", range: 95...98, color: BetterColors.hrv),
                BiomarkerZone(label: "Optimal", range: 98...102, color: BetterColors.success)
            ]
        case .respiratoryRate:
            [
                BiomarkerZone(label: "Needs Attention", range: 20...24, color: BetterColors.danger),
                BiomarkerZone(label: "Fair", range: 18...20, color: BetterColors.warning),
                BiomarkerZone(label: "Optimal", range: 12...18, color: BetterColors.success),
                BiomarkerZone(label: "Fair", range: 10...12, color: BetterColors.warning),
                BiomarkerZone(label: "Needs Attention", range: 8...10, color: BetterColors.danger)
            ]
        }
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

private extension View {
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

#if DEBUG
#Preview("Biomarker Module - Full Data") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        BiomarkerModuleCard(
            summaries: previewBiomarkerSummaries(),
            isLoading: false,
            errorMessage: nil
        )
        .padding(BetterSpacing.screen)
    }
    .preferredColorScheme(.dark)
}

#Preview("Biomarker Module - Sparse SpO2") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        BiomarkerModuleCard(
            summaries: previewBiomarkerSummaries(spo2Values: [96.5]),
            isLoading: false,
            errorMessage: nil
        )
        .padding(BetterSpacing.screen)
    }
    .preferredColorScheme(.dark)
}

#Preview("Biology") {
    BiologyTabView(
        viewModel: BiologyViewModel(
            localRepository: AppEnvironment.preview().localRepository,
            healthRepository: AppEnvironment.preview().healthRepository
        )
    )
}

private func previewBiomarkerSummaries(spo2Values: [Double] = [96.8, 97.2, 96.5, 98.1, 97.7, 97.9, 98.4]) -> [BiomarkerKind: [BiomarkerTimeline: BiomarkerSummary]] {
    [
        .hrv: previewTimelineSummaries(kind: .hrv, values: [52, 58, 49, 64, 67, 61, 70]),
        .restingHeartRate: previewTimelineSummaries(kind: .restingHeartRate, values: [61, 59, 62, 57, 56, 58, 55]),
        .spo2: previewTimelineSummaries(kind: .spo2, values: spo2Values),
        .respiratoryRate: previewTimelineSummaries(kind: .respiratoryRate, values: [14.2, 14.6, 15.1, 14.8, 15.5, 14.9, 14.4])
    ]
}

private func previewTimelineSummaries(kind: BiomarkerKind, values: [Double]) -> [BiomarkerTimeline: BiomarkerSummary] {
    Dictionary(uniqueKeysWithValues: BiomarkerTimeline.allCases.map { timeline in
        let repeated = Array(repeating: values, count: max(1, timeline.rawValue / max(values.count, 1) + 1)).flatMap { $0 }
        let windowValues = Array(repeated.prefix(timeline.rawValue))
        return (timeline, previewSummary(kind: kind, timeline: timeline, values: windowValues))
    })
}

private func previewSummary(kind: BiomarkerKind, timeline: BiomarkerTimeline, values: [Double]) -> BiomarkerSummary {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let points = values.enumerated().compactMap { index, value -> BiomarkerDailyPoint? in
        guard let date = calendar.date(byAdding: .day, value: index - values.count + 1, to: today) else { return nil }
        let status = previewStatus(kind: kind, value: value)
        return BiomarkerDailyPoint(
            kind: kind,
            dateKey: SleepDateKey.calendarDateKey(for: date),
            date: date,
            value: value,
            unit: kind.unit,
            status: status,
            source: kind == .restingHeartRate ? "Apple Health RHR" : "Sleep biometrics",
            isSelectedEligible: true
        )
    }
    let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    return BiomarkerSummary(
        kind: kind,
        timeline: timeline,
        currentValue: values.last,
        average: average,
        bestValue: previewBest(kind: kind, values: values),
        minValue: values.min(),
        maxValue: values.max(),
        validSampleCount: values.count,
        expectedDayCount: timeline.rawValue,
        points: points,
        education: previewEducation(kind),
        calculationNote: "Preview calculation for \(timeline.rawValue) days."
    )
}

private func previewBest(kind: BiomarkerKind, values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    switch kind {
    case .hrv, .spo2:
        return values.max()
    case .restingHeartRate:
        return values.min()
    case .respiratoryRate:
        return values.min { abs($0 - 15) < abs($1 - 15) }
    }
}

private func previewStatus(kind: BiomarkerKind, value: Double) -> String {
    switch kind {
    case .hrv:
        return value >= 60 ? "Optimal" : value >= 40 ? "Normal" : "Fair"
    case .restingHeartRate:
        return value <= 58 ? "Optimal" : value <= 68 ? "Normal" : "Fair"
    case .spo2:
        return value >= 98 ? "Optimal" : value >= 95 ? "Normal" : "Fair"
    case .respiratoryRate:
        return value >= 14 && value <= 16 ? "Optimal" : value >= 12 && value <= 18 ? "Normal" : "Fair"
    }
}

private func previewEducation(_ kind: BiomarkerKind) -> String {
    switch kind {
    case .hrv:
        return "HRV reflects how well your body adapts and recovers. Higher values often align with stronger recovery readiness and lower strain."
    case .restingHeartRate:
        return "Resting heart rate reflects baseline cardiovascular load. Higher values can show strain, poor recovery, illness, or stress."
    case .spo2:
        return "SpO2 reflects overnight oxygen saturation. Stable oxygen levels support clearer sleep-breathing and recovery interpretation."
    case .respiratoryRate:
        return "Breathing rate reflects overnight respiratory rhythm. Shifts can add context for stress, illness, training load, or recovery."
    }
}
#endif
