import SwiftUI

/// Three-metric line chart. All metrics are normalized to their own min/max ranges
/// so they always fill the same chart area, even if their units differ.
/// All lines are solid (no dashed strokes).
struct ExplorerChartView: View {
    let points: [TrendChartPoint]
    let secondaryPoints: [TrendChartPoint]
    let tertiaryPoints: [TrendChartPoint]
    let primaryMetric: TrendMetric
    let secondaryMetric: TrendMetric?
    let tertiaryMetric: TrendMetric?
    /// Override the chart canvas height. Defaults to 220 for the inline card.
    var chartHeight: CGFloat = 220

    @State private var selectedDateKey: String?

    // MARK: - Derived helpers

    private var primaryValues: [Double] { points.map(\.value) }
    private var primaryMin: Double { primaryValues.min() ?? 0 }
    private var primaryMax: Double { primaryValues.max() ?? 1 }

    private var secondaryValues: [Double] { secondaryPoints.map(\.value) }
    private var secondaryMin: Double { secondaryValues.min() ?? 0 }
    private var secondaryMax: Double { secondaryValues.max() ?? 1 }

    private var tertiaryValues: [Double] { tertiaryPoints.map(\.value) }
    private var tertiaryMin: Double { tertiaryValues.min() ?? 0 }
    private var tertiaryMax: Double { tertiaryValues.max() ?? 1 }

    private var selectedPrimary: TrendChartPoint? {
        guard let key = selectedDateKey else { return nil }
        return points.first { $0.dateKey == key }
    }
    private var selectedSecondary: TrendChartPoint? {
        guard let key = selectedDateKey else { return nil }
        return secondaryPoints.first { $0.dateKey == key }
    }
    private var selectedTertiary: TrendChartPoint? {
        guard let key = selectedDateKey else { return nil }
        return tertiaryPoints.first { $0.dateKey == key }
    }

    private var hasAnySecondary: Bool { secondaryMetric != nil || tertiaryMetric != nil }

    private var isAllFlat: Bool {
        let primaryFlat = primaryMax - primaryMin <= 0.001
        let secondaryFlat = secondaryPoints.isEmpty || secondaryMax - secondaryMin <= 0.001
        let tertiaryFlat = tertiaryPoints.isEmpty || tertiaryMax - tertiaryMin <= 0.001
        return primaryFlat && secondaryFlat && tertiaryFlat
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            // Axis labels row — all active metrics in one HStack
            HStack(spacing: BetterSpacing.medium) {
                axisLabel(color: BetterColors.brand, metric: primaryMetric)
                if let secondaryMetric {
                    axisLabel(color: BetterColors.success, metric: secondaryMetric)
                }
                if let tertiaryMetric {
                    axisLabel(color: BetterColors.warning, metric: tertiaryMetric)
                }
                Spacer()
            }

            if points.isEmpty {
                emptyState
            } else if isAllFlat {
                flatRangeState
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    let chartHeight = size.height - 18 // reserve bottom 18 pt for date axis labels
                    let chartSize = CGSize(width: size.width, height: chartHeight)

                    ZStack(alignment: .topLeading) {
                        // Grid lines (within chart area)
                        horizontalGrid(size: chartSize)

                        // Primary line
                        if points.count > 1 {
                            primaryPath(size: chartSize)
                                .stroke(
                                    BetterColors.brand,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                                )
                        }

                        // Secondary line (solid)
                        if secondaryPoints.count > 1 {
                            secondaryPath(size: chartSize)
                                .stroke(
                                    BetterColors.success,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                        }

                        // Tertiary line (solid)
                        if tertiaryPoints.count > 1 {
                            tertiaryPath(size: chartSize)
                                .stroke(
                                    BetterColors.warning,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )
                        }

                        // Primary dots
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            let isSelected = selectedDateKey == point.dateKey
                            Circle()
                                .fill(isSelected ? BetterColors.text : BetterColors.brand)
                                .frame(width: isSelected ? 11 : 7, height: isSelected ? 11 : 7)
                                .overlay(
                                    Circle()
                                        .stroke(BetterColors.brand, lineWidth: isSelected ? 3 : 0)
                                )
                                .position(primaryPosition(for: point.value, at: index, size: chartSize))
                        }

                        // Secondary dots
                        if secondaryMetric != nil {
                            ForEach(Array(secondaryPoints.enumerated()), id: \.element.id) { index, point in
                                let isSelected = selectedDateKey == point.dateKey
                                Circle()
                                    .fill(isSelected ? BetterColors.text : BetterColors.success)
                                    .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                                    .overlay(
                                        Circle()
                                            .stroke(BetterColors.success, lineWidth: isSelected ? 2 : 0)
                                    )
                                    .position(secondaryPosition(for: point.value, at: index, size: chartSize))
                            }
                        }

                        // Tertiary dots
                        if tertiaryMetric != nil {
                            ForEach(Array(tertiaryPoints.enumerated()), id: \.element.id) { index, point in
                                let isSelected = selectedDateKey == point.dateKey
                                Circle()
                                    .fill(isSelected ? BetterColors.text : BetterColors.warning)
                                    .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                                    .overlay(
                                        Circle()
                                            .stroke(BetterColors.warning, lineWidth: isSelected ? 2 : 0)
                                    )
                                    .position(tertiaryPosition(for: point.value, at: index, size: chartSize))
                            }
                        }

                        // Selection rule + tooltip
                        if let primPoint = selectedPrimary,
                           let idx = points.firstIndex(where: { $0.dateKey == primPoint.dateKey }) {
                            let anchor = primaryPosition(for: primPoint.value, at: idx, size: chartSize)
                            selectionRule(at: anchor, size: chartSize)
                            combinedTooltip(
                                primary: primPoint,
                                secondary: selectedSecondary,
                                tertiary: selectedTertiary
                            )
                            .position(tooltipPosition(anchor: anchor, size: chartSize))
                        }

                        // Date axis labels — first, middle, last
                        if !points.isEmpty {
                            dateAxisLabels(size: chartSize, totalHeight: size.height)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        updateSelection(at: location.x, width: size.width)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                updateSelection(at: value.location.x, width: size.width)
                            }
                    )
                    .onContinuousHover { phase in
                        if case .active(let location) = phase {
                            updateSelection(at: location.x, width: size.width)
                        }
                    }
                }
                .frame(height: chartHeight)
            }

            // Legend — only when secondary or tertiary is active
            if hasAnySecondary {
                HStack(spacing: BetterSpacing.large) {
                    legendItem(color: BetterColors.brand, label: primaryMetric.displayName)
                    if let secondaryMetric {
                        legendItem(color: BetterColors.success, label: secondaryMetric.displayName)
                    }
                    if let tertiaryMetric {
                        legendItem(color: BetterColors.warning, label: tertiaryMetric.displayName)
                    }
                }
                .padding(.horizontal, BetterSpacing.small)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: points.map(\.dateKey)) { _, keys in
            if let selectedDateKey, !keys.contains(selectedDateKey) {
                self.selectedDateKey = nil
            }
        }
    }

    // MARK: - Axis label helper

    private func axisLabel(color: Color, metric: TrendMetric) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(metric.displayName)
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Text(metric.unitLabel)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Empty / flat states

    private var emptyState: some View {
        ContentUnavailableView(
            "No \(primaryMetric.displayName.lowercased()) data",
            systemImage: "chart.xyaxis.line",
            description: Text("This metric will appear once enough nights are cached.")
        )
        .foregroundStyle(BetterColors.subtext)
        .frame(height: 150)
    }

    private var flatRangeState: some View {
        VStack(spacing: BetterSpacing.small) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(BetterColors.mutedText)
            Text("Not enough variation")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.mutedText)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid

    private func horizontalGrid(size: CGSize) -> some View {
        Path { path in
            for step in 0...3 {
                let y = size.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(BetterColors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    // MARK: - Date axis labels

    @ViewBuilder
    private func dateAxisLabels(size: CGSize, totalHeight: CGFloat) -> some View {
        let labelY = totalHeight - 9  // center of the 18-pt reserved band
        let count = points.count
        let midIndex = count / 2
        let dateFormatter = makeDateFormatter()

        if count >= 1 {
            // First
            Text(dateFormatter.string(from: points[0].date))
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize()
                .position(x: xForIndex(0, count: count, width: size.width), y: labelY)
        }
        if count >= 3 {
            // Middle
            Text(dateFormatter.string(from: points[midIndex].date))
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize()
                .position(x: xForIndex(midIndex, count: count, width: size.width), y: labelY)
        }
        if count >= 2 {
            // Last
            Text(dateFormatter.string(from: points[count - 1].date))
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize()
                .position(x: xForIndex(count - 1, count: count, width: size.width), y: labelY)
        }
    }

    private func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    private func xForIndex(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(count - 1)
    }

    // MARK: - Paths

    private func primaryPath(size: CGSize) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            for index in points.indices {
                let pt = primaryPosition(for: points[index].value, at: index, size: size)
                index == points.startIndex ? path.move(to: pt) : path.addLine(to: pt)
            }
        }
    }

    private func secondaryPath(size: CGSize) -> Path {
        Path { path in
            guard secondaryPoints.count > 1 else { return }
            for index in secondaryPoints.indices {
                let pt = secondaryPosition(for: secondaryPoints[index].value, at: index, size: size)
                index == secondaryPoints.startIndex ? path.move(to: pt) : path.addLine(to: pt)
            }
        }
    }

    private func tertiaryPath(size: CGSize) -> Path {
        Path { path in
            guard tertiaryPoints.count > 1 else { return }
            for index in tertiaryPoints.indices {
                let pt = tertiaryPosition(for: tertiaryPoints[index].value, at: index, size: size)
                index == tertiaryPoints.startIndex ? path.move(to: pt) : path.addLine(to: pt)
            }
        }
    }

    // MARK: - Position helpers

    private func primaryPosition(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        normalizedPosition(value: value, min: primaryMin, max: primaryMax,
                           index: index, count: points.count, size: size)
    }

    private func secondaryPosition(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        normalizedPosition(value: value, min: secondaryMin, max: secondaryMax,
                           index: index, count: secondaryPoints.count, size: size)
    }

    private func tertiaryPosition(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        normalizedPosition(value: value, min: tertiaryMin, max: tertiaryMax,
                           index: index, count: tertiaryPoints.count, size: size)
    }

    private func normalizedPosition(value: Double, min minVal: Double, max maxVal: Double,
                                    index: Int, count: Int, size: CGSize) -> CGPoint {
        let spread = maxVal - minVal
        let x: CGFloat = count == 1
            ? size.width / 2
            : size.width * CGFloat(index) / CGFloat(count - 1)
        guard spread > 0.001 else {
            return CGPoint(x: x, y: size.height / 2)
        }
        let normalized = (value - minVal) / spread
        let y = size.height - (size.height * CGFloat(normalized))
        return CGPoint(x: x, y: min(max(20, y), size.height - 18))
    }

    // MARK: - Selection

    private func updateSelection(at x: CGFloat, width: CGFloat) {
        guard !points.isEmpty else { return }
        if points.count == 1 {
            if selectedDateKey != points[0].dateKey {
                selectedDateKey = points[0].dateKey
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        }
        let clampedX = min(max(0, x), width)
        let rawIndex = (clampedX / max(width, 1)) * CGFloat(points.count - 1)
        let index = min(max(Int(rawIndex.rounded()), 0), points.count - 1)
        let newKey = points[index].dateKey
        if selectedDateKey != newKey {
            selectedDateKey = newKey
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Tooltip

    private func selectionRule(at point: CGPoint, size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: 0))
            path.addLine(to: CGPoint(x: point.x, y: size.height))
        }
        .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func combinedTooltip(
        primary: TrendChartPoint,
        secondary: TrendChartPoint?,
        tertiary: TrendChartPoint?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(primary.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)

            // Primary value
            tooltipRow(
                color: BetterColors.brand,
                value: formatValue(primary.value, metric: primaryMetric),
                label: primaryMetric.displayName,
                accent: BetterColors.text
            )

            // Secondary value
            if let secondaryMetric {
                Divider().background(BetterColors.border)
                if let secondary {
                    tooltipRow(
                        color: BetterColors.success,
                        value: formatValue(secondary.value, metric: secondaryMetric),
                        label: secondaryMetric.displayName,
                        accent: BetterColors.success
                    )
                } else {
                    tooltipRow(
                        color: BetterColors.success,
                        value: "—",
                        label: secondaryMetric.displayName,
                        accent: BetterColors.mutedText
                    )
                }
            }

            // Tertiary value
            if let tertiaryMetric {
                Divider().background(BetterColors.border)
                if let tertiary {
                    tooltipRow(
                        color: BetterColors.warning,
                        value: formatValue(tertiary.value, metric: tertiaryMetric),
                        label: tertiaryMetric.displayName,
                        accent: BetterColors.warning
                    )
                } else {
                    tooltipRow(
                        color: BetterColors.warning,
                        value: "—",
                        label: tertiaryMetric.displayName,
                        accent: BetterColors.mutedText
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 150, alignment: .leading)
        .background(BetterColors.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    @ViewBuilder
    private func tooltipRow(color: Color, value: String, label: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
        Text(label)
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(BetterColors.subtext)
    }

    private func tooltipPosition(anchor: CGPoint, size: CGSize) -> CGPoint {
        let x = anchor.x < size.width / 2 ? min(anchor.x + 87, size.width - 75) : max(anchor.x - 87, 75)
        let y = anchor.y < 90 ? min(anchor.y + 70, size.height - 70) : max(anchor.y - 70, 70)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Value formatting

    private func formatValue(_ value: Double, metric: TrendMetric) -> String {
        switch metric {
        case .totalSleep, .longestRestorativeBlock, .deepSleep, .remSleep:
            let h = Int(value)
            let m = Int((value - Double(h)) * 60)
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        case .score:
            return "\(Int(value.rounded()))/100"
        case .hrv:
            return String(format: "%.0f ms", value)
        case .waso, .latency:
            return String(format: "%.0f min", value)
        case .respiratoryRate:
            return String(format: "%.1f br/m", value)
        case .oxygenSaturation:
            return String(format: "%.0f%%", value)
        }
    }
}
