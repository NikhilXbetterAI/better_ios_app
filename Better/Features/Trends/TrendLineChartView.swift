import SwiftUI

struct TrendLineChartView: View {
    let points: [TrendChartPoint]
    let metric: TrendMetric

    private var values: [Double] { points.map(\.value) }
    private var minValue: Double { values.min() ?? 0 }
    private var maxValue: Double { values.max() ?? 1 }

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
                            Circle()
                                .fill(BetterColors.brand)
                                .frame(width: 7, height: 7)
                                .position(position(for: point.value, at: index, size: size))
                        }
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        return CGPoint(x: x, y: min(max(4, y), size.height - 4))
    }
}

