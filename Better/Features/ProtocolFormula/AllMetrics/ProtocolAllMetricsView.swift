import SwiftUI

struct ProtocolAllMetricsView: View {
    @Bindable var viewModel: ProtocolAllMetricsViewModel
    @State private var selectedChartIndex: Int? = nil

    // Restrict the tabs and tables to the 6 primary metrics specified in version 3
    static let primaryMetrics: [ProtocolFormulaMetric] = [
        .restorativePct,
        .deep,
        .rem,
        .awake,
        .duration,
        .latency
    ]
    private static let supportedMetrics = primaryMetrics
    private static let advancedMetrics: [ProtocolFormulaMetric] = [
        .restorativeMin,
        .longestBlock,
        .score
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                if let best = viewModel.bestVersion {
                    bestFormulaCard(best)
                }
                metricTabs
                chartCard
                versionMeansTable
                ProtocolCaveatFooter()
            }
            .padding(BetterSpacing.screen)
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func bestFormulaCard(_ best: ProtocolFormulaBestVersion) -> some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                BetterSectionHeader(title: "Best for you", subtitle: "ranked by restorative %")
                HStack(alignment: .firstTextBaseline) {
                    VersionChip(version: best.version)
                    Spacer()
                    if let delta = best.restorativePctDelta {
                        DeltaBadge(value: delta, unit: "%")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    supportingDelta(.deep, value: best.rollup.meanDeepMin, delta: best.deepDelta)
                    supportingDelta(.rem, value: best.rollup.meanRemMin, delta: best.remDelta)
                    supportingDelta(.awake, value: best.rollup.meanAwakeMin, delta: best.awakeDelta)
                    supportingDelta(.latency, value: best.rollup.meanLatencyMin, delta: best.latencyDelta)
                }
                Text("\(best.rollup.nightCount) valid nights. Low-data versions stay out of the ranking.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }
        }
    }

    private func supportingDelta(_ metric: ProtocolFormulaMetric, value: Double?, delta: Double?) -> some View {
        let baseline = value.flatMap { v in delta.map { v - $0 } }
        return ProtocolMetricComparisonStrip(metric: metric, yourValue: value, baselineValue: baseline, compact: true)
    }

    // MARK: - Metric tabs

    private var metricTabs: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Self.supportedMetrics) { metric in
                let isSelected = viewModel.activeMetric == metric
                let color = ProtocolPalette.versionColor(hex: metric.colorHex)
                let baselineVal = viewModel.baseline.flatMap { metric.baselineValue(from: $0) }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        viewModel.activeMetric = metric
                        selectedChartIndex = nil
                    }
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .opacity(isSelected ? 1.0 : 0.35)
                            .frame(width: 8, height: 8)
                        Text(metric.shortLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? BetterColors.text : ProtocolPalette.mutedText)
                        // Baseline reference value
                        if let bv = baselineVal {
                            Text("Base: \(Self.formatValue(bv, metric: metric))\(metric.unit)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ProtocolPalette.dimText.opacity(isSelected ? 0.9 : 0.55))
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? color.opacity(0.10) : Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? color : Color.white.opacity(0.08), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart card

    private var chartCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.activeMetric.fullLabel)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(BetterColors.text)
                        Text(viewModel.activeMetric.betterIsLower ? "Lower is better" : "Higher is better")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                    Spacer()
                    if let point = selectedChartPoint ?? viewModel.chartPoints.last {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Self.formatValue(point.value, metric: viewModel.activeMetric))
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(BetterColors.text)
                                .monospacedDigit()
                            Text(viewModel.activeMetric.unit)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                        }
                    }
                    if selectedChartIndex != nil {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedChartIndex = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear selected point")
                    }
                }

                if viewModel.chartPoints.isEmpty {
                    Text("No data yet — log nights to see trends.")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .frame(height: 120, alignment: .center)
                        .frame(maxWidth: .infinity)
                } else {
                    NightlyTrendChart(
                        points: viewModel.chartPoints,
                        versions: viewModel.versions,
                        metric: viewModel.activeMetric,
                        baselineValue: viewModel.baselineValue,
                        selectedIndex: $selectedChartIndex
                    )
                    .frame(height: 150)

                    if let selected = selectedChartPoint {
                        chartInspector(for: selected)
                    } else {
                        Text("Tap or drag the chart to inspect a night.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                }

                // Version legend
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.versions) { version in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(ProtocolPalette.versionColor(hex: version.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(version.resolvedLabel)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(BetterColors.text)
                            }
                        }
                        if viewModel.baselineValue != nil {
                            HStack(spacing: 5) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 12, height: 1.5)
                                Text("Baseline")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ProtocolPalette.mutedText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Version means table

    private var versionMeansTable: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            BetterSectionHeader(title: "Mean per version", subtitle: "Primary metrics first")

            VStack(spacing: BetterSpacing.medium) {
                ForEach(viewModel.versions) { version in
                    let rollup = viewModel.rollup(for: version)
                    let baseline = viewModel.baseline
                    let isCurrent = version.isActive
                    let restorativePct = rollup?.meanRestorativePctOfInBed
                    let restorativeDelta = restorativePct.flatMap { pct in
                        baseline.flatMap { base in
                            base.meanRestorativePctOfInBed.map { pct - $0 }
                        }
                    }

                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(ProtocolPalette.versionColor(hex: version.colorHex))
                                        .frame(width: 7, height: 7)
                                    Text(version.resolvedLabel)
                                        .font(.system(size: 18, weight: .black))
                                        .foregroundStyle(BetterColors.text)
                                    if isCurrent {
                                        Text("CURRENT")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(ProtocolPalette.versionColor(hex: version.colorHex)))
                                    }
                                }
                                Text("\(rollup?.nightCount ?? 0) nights")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ProtocolPalette.dimText)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(restorativePct.map { Self.formatValue($0, metric: .restorativePct) + "%" } ?? "—")
                                    .font(.system(size: 24, weight: .black).monospacedDigit())
                                    .foregroundStyle(BetterColors.text)
                                if let restorativeDelta {
                                    DeltaBadge(value: restorativeDelta, unit: "%", lowerIsBetter: false)
                                } else {
                                    Text("Baseline pending")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ProtocolPalette.dimText)
                                }
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(Self.supportedMetrics.filter { $0 != .restorativePct }) { metric in
                                ProtocolMetricComparisonStrip(
                                    metric: metric,
                                    yourValue: rollup.flatMap { metric.rollupMean(from: $0) },
                                    baselineValue: baseline.flatMap { metric.baselineValue(from: $0) },
                                    compact: true
                                )
                            }
                        }

                        DisclosureGroup {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 1), spacing: 8) {
                                ForEach(Self.advancedMetrics) { metric in
                                    ProtocolMetricComparisonStrip(
                                        metric: metric,
                                        yourValue: rollup.flatMap { metric.rollupMean(from: $0) },
                                        baselineValue: baseline.flatMap { metric.baselineValue(from: $0) },
                                        compact: true
                                    )
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Advanced metrics")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                        .tint(ProtocolPalette.dimText)

                        if let baseline, !baseline.hasExtendedMetrics {
                            Text("Baseline still missing some metric fields: \(baseline.missingExtendedMetricLabels.joined(separator: ", "))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                    }
                    .padding(BetterSpacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isCurrent ? ProtocolPalette.versionColor(hex: version.colorHex).opacity(0.06) : Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isCurrent ? ProtocolPalette.versionColor(hex: version.colorHex).opacity(0.18) : ProtocolPalette.borderColor, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var selectedChartPoint: ProtocolAllMetricsViewModel.ChartPoint? {
        guard let selectedChartIndex,
              viewModel.chartPoints.indices.contains(selectedChartIndex) else { return nil }
        return viewModel.chartPoints[selectedChartIndex]
    }

    private func chartInspector(for point: ProtocolAllMetricsViewModel.ChartPoint) -> some View {
        let baseline = viewModel.baselineValue
        let delta = baseline.map { point.value - $0 }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.formatDate(point.dateKey))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                    Text(point.version.resolvedLabel)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(BetterColors.text)
                }
                Spacer()
                Text(formattedMetricValue(point.value, metric: viewModel.activeMetric))
                    .font(.system(size: 20, weight: .black).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
            }

            HStack {
                Text("Baseline \(baseline.map { formattedMetricValue($0, metric: viewModel.activeMetric) } ?? "—")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.dimText)
                Spacer()
                if let delta {
                    DeltaBadge(value: delta, unit: viewModel.activeMetric.unit, lowerIsBetter: viewModel.activeMetric.betterIsLower)
                }
            }
        }
        .padding(12)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private static func formatValue(_ value: Double, metric: ProtocolAllMetricsViewModel.Metric) -> String {
        switch metric {
        case .restorativePct: String(format: "%.1f", value)
        case .score: String(format: "%.0f", value)
        default: String(Int(value.rounded()))
        }
    }

    private static func formatDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return key }
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let monthName = month >= 1 && month <= 12 ? names[month - 1] : "\(month)"
        return "\(monthName) \(day)"
    }

    private func formattedMetricValue(_ value: Double, metric: ProtocolAllMetricsViewModel.Metric) -> String {
        switch metric.unit {
        case "%":
            return "\(Self.formatValue(value, metric: metric))%"
        case "pts":
            return "\(Self.formatValue(value, metric: metric))pts"
        default:
            return "\(Self.formatValue(value, metric: metric)) \(metric.unit)"
        }
    }
}

// MARK: - Nightly trend chart (interactive)

private struct NightlyTrendChart: View {
    let points: [ProtocolAllMetricsViewModel.ChartPoint]
    let versions: [ProtocolFormulaVersion]
    let metric: ProtocolAllMetricsViewModel.Metric
    let baselineValue: Double?
    @Binding var selectedIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pointValues = points.map { $0.value }
            let values = baselineValue.map { pointValues + [$0] } ?? pointValues
            let minV = (values.min() ?? 0) * 0.95
            let maxV = (values.max() ?? 100) * 1.05
            let range = max(1.0, maxV - minV)
            guard points.count > 1 else { return AnyView(EmptyView()) }

            let xStep = w / CGFloat(points.count - 1)
            func xPos(_ i: Int) -> CGFloat { CGFloat(i) * xStep }
            func yPos(_ val: Double) -> CGFloat {
                h - CGFloat((val - minV) / range) * (h - 16) - 8
            }

            let groups = Self.phaseGroups(points: points)
            let color = ProtocolPalette.versionColor(hex: metric.colorHex)
            let selIdx = selectedIndex

            return AnyView(ZStack(alignment: .topLeading) {
                // Phase background shading
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    let x0 = xPos(g.startIndex)
                    let x1 = xPos(g.endIndex)
                    if let ver = versions.first(where: { $0.id == g.versionID }) {
                        Rectangle()
                            .fill(ProtocolPalette.versionColor(hex: ver.colorHex).opacity(0.06))
                            .frame(width: max(0, x1 - x0), height: h)
                            .offset(x: x0)
                    }
                }

                // Grid lines
                ForEach(1...3, id: \.self) { i in
                    let ratio = CGFloat(i) * 0.25
                    let gy = h * ratio
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: gy))
                        path.addLine(to: CGPoint(x: w, y: gy))
                    }
                    .stroke(Color.white.opacity(0.03), lineWidth: 1)
                }

                // Phase dividers
                ForEach(1..<groups.count, id: \.self) { index in
                    let gPrev = groups[index - 1]
                    let gNext = groups[index]
                    let boundaryX = (xPos(gPrev.endIndex) + xPos(gNext.startIndex)) / 2
                    Path { path in
                        path.move(to: CGPoint(x: boundaryX, y: 0))
                        path.addLine(to: CGPoint(x: boundaryX, y: h))
                    }
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
                }

                // Baseline dashed line
                if let bv = baselineValue {
                    let by = yPos(bv)
                    Path { p in
                        var x: CGFloat = 0
                        while x <= w {
                            p.move(to: CGPoint(x: x, y: by))
                            p.addLine(to: CGPoint(x: min(x + 4, w), y: by))
                            x += 8
                        }
                    }
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                }

                // Sparkline
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let point = CGPoint(x: xPos(i), y: yPos(pt.value))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Phase mean hollow circles (hidden while a point is selected)
                if selIdx == nil {
                    ForEach(groups) { g in
                        let x0 = xPos(g.startIndex)
                        let x1 = xPos(g.endIndex)
                        let midX = (x0 + x1) / 2
                        let groupPoints = points[g.startIndex...g.endIndex]
                        let sum = groupPoints.map { $0.value }.reduce(0, +)
                        let mean = sum / Double(groupPoints.count)
                        if let ver = versions.first(where: { $0.id == g.versionID }) {
                            let col = ProtocolPalette.versionColor(hex: ver.colorHex)
                            Circle()
                                .stroke(col, lineWidth: 2)
                                .background(Circle().fill(ProtocolPalette.backgroundColor))
                                .frame(width: 8, height: 8)
                                .position(x: midX, y: yPos(mean))
                        }
                    }
                }

                // End dot (hidden while selecting)
                if selIdx == nil, let last = points.last, let lastIndex = points.indices.last {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .position(x: xPos(lastIndex), y: yPos(last.value))
                }

                // ── Crosshair + tooltip ──
                if let idx = selIdx, points.indices.contains(idx) {
                    let cx = xPos(idx)
                    let pt = points[idx]
                    let verColor = ProtocolPalette.versionColor(hex: pt.version.colorHex)

                    // Vertical crosshair
                    Path { p in
                        p.move(to: CGPoint(x: cx, y: 0))
                        p.addLine(to: CGPoint(x: cx, y: h))
                    }
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3]))

                    // Enlarged highlighted dot
                    ZStack {
                        Circle().fill(ProtocolPalette.backgroundColor).frame(width: 14, height: 14)
                        Circle().stroke(verColor, lineWidth: 2.5).frame(width: 14, height: 14)
                        Circle().fill(verColor).frame(width: 6, height: 6)
                    }
                    .position(x: cx, y: yPos(pt.value))

                    // Floating tooltip (edge-clamped)
                    let tooltipWidth: CGFloat = 150
                    let rawX = cx - tooltipWidth / 2
                    let clampedX = min(max(rawX, 0), w - tooltipWidth)
                    let tooltipY = max(0, yPos(pt.value) - 72)

                    ChartTooltip(point: pt, metric: metric, baselineValue: baselineValue)
                        .frame(width: tooltipWidth)
                        .offset(x: clampedX, y: tooltipY)
                }

                // Invisible full-area touch capture
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let rawIdx = Int((value.location.x / xStep).rounded())
                                let clamped = min(max(rawIdx, 0), points.count - 1)
                                if selectedIndex != clamped { selectedIndex = clamped }
                            }
                    )
            })
        }
    }

    private struct PhaseGroup: Identifiable {
        var id: String { "\(versionID.uuidString)-\(startIndex)" }
        var versionID: UUID
        var startIndex: Int
        var endIndex: Int
    }

    private static func phaseGroups(points: [ProtocolAllMetricsViewModel.ChartPoint]) -> [PhaseGroup] {
        var groups: [PhaseGroup] = []
        for (i, p) in points.enumerated() {
            if groups.last?.versionID == p.version.id {
                groups[groups.count - 1].endIndex = i
            } else {
                groups.append(PhaseGroup(versionID: p.version.id, startIndex: i, endIndex: i))
            }
        }
        return groups
    }
}

// MARK: - Floating tooltip card

private struct ChartTooltip: View {
    let point: ProtocolAllMetricsViewModel.ChartPoint
    let metric: ProtocolAllMetricsViewModel.Metric
    let baselineValue: Double?

    private var formattedValue: String { Self.fmt(point.value, metric: metric) }
    private var formattedBaseline: String? {
        baselineValue.map { Self.fmt($0, metric: metric) }
    }

    private var deltaInfo: (text: String, color: Color)? {
        guard let bv = baselineValue else { return nil }
        let delta = point.value - bv
        let sign = delta >= 0 ? "+" : ""
        let isGood = (delta > 0) != metric.betterIsLower
        let col: Color = delta == 0 ? ProtocolPalette.mutedText
            : (isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
        switch metric.unit {
        case "%":
            return ("\(sign)\(String(format: "%.1f", delta))% vs base", col)
        case "pts":
            return ("\(sign)\(Int(delta.rounded()))pts vs base", col)
        default:
            let h = Int(abs(delta)) / 60; let m = Int(abs(delta)) % 60
            let absStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return ("\(delta >= 0 ? "+" : "-")\(absStr) vs base", col)
        }
    }

    private static func fmt(_ value: Double, metric: ProtocolAllMetricsViewModel.Metric) -> String {
        switch metric.unit {
        case "%":   return "\(String(format: "%.1f", value))%"
        case "pts": return "\(Int(value.rounded()))pts"
        default:
            let h = Int(value) / 60; let m = Int(value) % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(formattedDate(point.dateKey))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ProtocolPalette.dimText)

            Text(formattedValue)
                .font(.system(size: 15, weight: .black).monospacedDigit())
                .foregroundStyle(BetterColors.text)

            HStack(spacing: 4) {
                Circle()
                    .fill(ProtocolPalette.versionColor(hex: point.version.colorHex))
                    .frame(width: 5, height: 5)
                Text(point.version.resolvedLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }

            if let formattedBaseline {
                Text("Baseline \(formattedBaseline)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ProtocolPalette.dimText)
            }

            if let (text, col) = deltaInfo {
                Text(text)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(col)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.14))
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func formattedDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return key }
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let mName = month >= 1 && month <= 12 ? names[month - 1] : "\(month)"
        return "\(mName) \(day)"
    }
}
