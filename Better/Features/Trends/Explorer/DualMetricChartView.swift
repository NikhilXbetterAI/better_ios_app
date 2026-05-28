import SwiftUI

/// Dual-metric line chart. Both metrics are normalized to their own min/max ranges
/// so they always fill the same chart area, even if their units differ.
struct DualMetricChartView: View {
    let points: [TrendChartPoint]
    let secondaryPoints: [TrendChartPoint]
    let primaryMetric: TrendMetric
    let secondaryMetric: TrendMetric?

    @State private var selectedDateKey: String?

    // MARK: - Derived helpers

    private var primaryValues: [Double] { points.map(\.value) }
    private var primaryMin: Double { primaryValues.min() ?? 0 }
    private var primaryMax: Double { primaryValues.max() ?? 1 }

    private var secondaryValues: [Double] { secondaryPoints.map(\.value) }
    private var secondaryMin: Double { secondaryValues.min() ?? 0 }
    private var secondaryMax: Double { secondaryValues.max() ?? 1 }

    private var selectedPrimary: TrendChartPoint? {
        guard let key = selectedDateKey else { return nil }
        return points.first { $0.dateKey == key }
    }
    private var selectedSecondary: TrendChartPoint? {
        guard let key = selectedDateKey else { return nil }
        return secondaryPoints.first { $0.dateKey == key }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            // Axis labels row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BetterColors.brand)
                        .frame(width: 8, height: 8)
                    Text(primaryMetric.displayName)
                        .font(BetterTypography.headline)
                        .foregroundStyle(BetterColors.text)
                    Text(primaryMetric.unitLabel)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                if let secondaryMetric {
                    HStack(spacing: 6) {
                        Text(secondaryMetric.unitLabel)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                        Text(secondaryMetric.displayName)
                            .font(BetterTypography.headline)
                            .foregroundStyle(BetterColors.text)
                        DashedCircle()
                            .frame(width: 8, height: 8)
                    }
                }
            }

            if points.isEmpty {
                emptyState
            } else if primaryMax - primaryMin <= 0.001 && (secondaryPoints.isEmpty || secondaryMax - secondaryMin <= 0.001) {
                flatRangeState
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        horizontalGrid(size: size)

                        // Primary line
                        if points.count > 1 {
                            primaryPath(size: size)
                                .stroke(
                                    BetterColors.brand,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                                )
                        }

                        // Secondary line (dashed)
                        if secondaryPoints.count > 1 {
                            secondaryPath(size: size)
                                .stroke(
                                    BetterColors.cyan,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
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
                                .position(primaryPosition(for: point.value, at: index, size: size))
                        }

                        // Secondary dots
                        if secondaryMetric != nil {
                            ForEach(Array(secondaryPoints.enumerated()), id: \.element.id) { index, point in
                                let isSelected = selectedDateKey == point.dateKey
                                Circle()
                                    .fill(isSelected ? BetterColors.text : BetterColors.cyan)
                                    .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                                    .overlay(
                                        Circle()
                                            .stroke(BetterColors.cyan, lineWidth: isSelected ? 2 : 0)
                                    )
                                    .position(secondaryPosition(for: point.value, at: index, size: size))
                            }
                        }

                        // Selection rule + tooltip
                        if let primPoint = selectedPrimary,
                           let idx = points.firstIndex(where: { $0.dateKey == primPoint.dateKey }) {
                            let anchor = primaryPosition(for: primPoint.value, at: idx, size: size)
                            selectionRule(at: anchor, size: size)
                            combinedTooltip(primary: primPoint, secondary: selectedSecondary)
                                .position(tooltipPosition(anchor: anchor, size: size))
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
                .frame(height: 190)
            }

            // Legend
            if secondaryMetric != nil {
                HStack(spacing: BetterSpacing.large) {
                    legendItem(
                        indicator: AnyView(Circle().fill(BetterColors.brand).frame(width: 8, height: 8)),
                        label: primaryMetric.displayName
                    )
                    legendItem(
                        indicator: AnyView(DashedCircle().frame(width: 8, height: 8)),
                        label: secondaryMetric!.displayName
                    )
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

    // MARK: - Position helpers

    private func primaryPosition(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        normalizedPosition(value: value, min: primaryMin, max: primaryMax,
                           index: index, count: points.count, size: size)
    }

    private func secondaryPosition(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        normalizedPosition(value: value, min: secondaryMin, max: secondaryMax,
                           index: index, count: secondaryPoints.count, size: size)
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
            selectedDateKey = points[0].dateKey
            return
        }
        let clampedX = min(max(0, x), width)
        let rawIndex = (clampedX / max(width, 1)) * CGFloat(points.count - 1)
        let index = min(max(Int(rawIndex.rounded()), 0), points.count - 1)
        selectedDateKey = points[index].dateKey
    }

    // MARK: - Tooltip

    private func selectionRule(at point: CGPoint, size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: 0))
            path.addLine(to: CGPoint(x: point.x, y: size.height))
        }
        .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func combinedTooltip(primary: TrendChartPoint, secondary: TrendChartPoint?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(primary.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)

            // Primary value
            HStack(spacing: 4) {
                Circle()
                    .fill(BetterColors.brand)
                    .frame(width: 6, height: 6)
                Text(formatValue(primary.value, metric: primaryMetric))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
            }
            Text(primaryMetric.displayName)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(BetterColors.subtext)

            // Secondary value (if selected)
            if let secondary, let secondaryMetric {
                Divider()
                    .background(BetterColors.border)
                HStack(spacing: 4) {
                    DashedCircle()
                        .frame(width: 6, height: 6)
                    Text(formatValue(secondary.value, metric: secondaryMetric))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.cyan)
                }
                Text(secondaryMetric.displayName)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            } else if secondaryMetric != nil {
                Divider()
                    .background(BetterColors.border)
                HStack(spacing: 4) {
                    DashedCircle()
                        .frame(width: 6, height: 6)
                    Text("—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                }
                Text(secondaryMetric!.displayName)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 140, alignment: .leading)
        .background(BetterColors.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    private func tooltipPosition(anchor: CGPoint, size: CGSize) -> CGPoint {
        let x = anchor.x < size.width / 2 ? min(anchor.x + 82, size.width - 70) : max(anchor.x - 82, 70)
        let y = anchor.y < 80 ? min(anchor.y + 65, size.height - 60) : max(anchor.y - 65, 60)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Legend

    private func legendItem(indicator: AnyView, label: String) -> some View {
        HStack(spacing: 5) {
            indicator
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

// MARK: - Dashed circle indicator

private struct DashedCircle: View {
    var body: some View {
        Circle()
            .stroke(BetterColors.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1]))
    }
}
