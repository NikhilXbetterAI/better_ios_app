import SwiftUI

struct TrendLineChartView: View {
    let points: [TrendChartPoint]
    let metric: TrendMetric

    @State private var selectedDateKey: String?

    private var values: [Double] { points.map(\.value) }
    private var minValue: Double { values.min() ?? 0 }
    private var maxValue: Double { values.max() ?? 1 }
    private var selectedPoint: TrendChartPoint? {
        guard let selectedDateKey else { return nil }
        return points.first { $0.dateKey == selectedDateKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                Text(metric.displayName)
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                Text(metric.unitLabel)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            if points.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    let path = chartPath(size: size)
                    ZStack {
                        horizontalGrid(size: size)
                        path
                            .stroke(BetterColors.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            let isSelected = selectedDateKey == point.dateKey
                            Circle()
                                .fill(isSelected ? BetterColors.text : BetterColors.brand)
                                .frame(width: isSelected ? 11 : 7, height: isSelected ? 11 : 7)
                                .overlay(
                                    Circle()
                                        .stroke(BetterColors.brand, lineWidth: isSelected ? 3 : 0)
                                )
                                .position(position(for: point.value, at: index, size: size))
                        }
                        if let selectedPoint,
                           let index = points.firstIndex(where: { $0.dateKey == selectedPoint.dateKey }) {
                            let pointPosition = position(for: selectedPoint.value, at: index, size: size)
                            selectionRule(at: pointPosition, size: size)
                            tooltip(for: selectedPoint)
                                .position(tooltipPosition(anchor: pointPosition, size: size))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location.x, width: size.width)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateSelection(at: location.x, width: size.width)
                        case .ended:
                            break
                        }
                    }
                }
                .frame(height: 190)
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

    private var emptyState: some View {
        ContentUnavailableView(
            "No \(metric.displayName.lowercased()) data",
            systemImage: "chart.xyaxis.line",
            description: Text("This metric will appear once cached nights include enough data.")
        )
        .foregroundStyle(BetterColors.subtext)
        .frame(height: 150)
    }

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

    private func chartPath(size: CGSize) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            for index in points.indices {
                let point = position(for: points[index].value, at: index, size: size)
                index == points.startIndex ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    private func position(for value: Double, at index: Int, size: CGSize) -> CGPoint {
        let spread = max(0.1, maxValue - minValue)
        let x = points.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(points.count - 1)
        let normalized = (value - minValue) / spread
        let y = size.height - (size.height * CGFloat(normalized))
        return CGPoint(x: x, y: min(max(20, y), size.height - 18))
    }

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

    private func selectionRule(at point: CGPoint, size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: 0))
            path.addLine(to: CGPoint(x: point.x, y: size.height))
        }
        .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func tooltip(for point: TrendChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Text(valueText(for: point))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            if metric == .totalSleep {
                tooltipRow("In bed", formatDuration(point.details.timeInBed))
                tooltipRow("Efficiency", String(format: "%.0f%%", point.details.efficiency * 100))
            } else if metric == .score {
                tooltipRow("Duration", "\(Int(point.details.score.durationScore))")
                tooltipRow("Efficiency", "\(Int(point.details.score.efficiencyScore))")
                tooltipRow("REM", "\(Int(point.details.score.remScore))")
                tooltipRow("Deep", "\(Int(point.details.score.deepScore))")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 132, alignment: .leading)
        .background(BetterColors.cardTertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    private func tooltipRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
        }
    }

    private func tooltipPosition(anchor: CGPoint, size: CGSize) -> CGPoint {
        let x = anchor.x < size.width / 2 ? min(anchor.x + 78, size.width - 66) : max(anchor.x - 78, 66)
        let y = anchor.y < 78 ? min(anchor.y + 62, size.height - 56) : max(anchor.y - 62, 56)
        return CGPoint(x: x, y: y)
    }

    private func valueText(for point: TrendChartPoint) -> String {
        switch metric {
        case .totalSleep:
            return formatDuration(point.details.totalSleep)
        case .score:
            return "\(Int(point.value.rounded())) / 100"
        case .deepSleep, .remSleep:
            return String(format: "%.1f h", point.value)
        case .hrv:
            return String(format: "%.0f ms", point.value)
        case .waso, .latency:
            return String(format: "%.0f min", point.value)
        case .respiratoryRate:
            return String(format: "%.1f br/min", point.value)
        case .oxygenSaturation:
            return String(format: "%.0f%%", point.value)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
