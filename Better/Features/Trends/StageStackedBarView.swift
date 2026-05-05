import SwiftUI

struct StageStackedBarView: View {
    let points: [StageCompositionPoint]

    @State private var selectedDateKey: String?

    private var selectedPoint: StageCompositionPoint? {
        guard let selectedDateKey else { return nil }
        return points.first { $0.dateKey == selectedDateKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            header

            if points.isEmpty {
                Text("Detailed stages are unavailable for the selected range.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BetterSpacing.large)
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        grid(size: size)
                        stageArea(stage: .deep, size: size)
                        stageArea(stage: .core, size: size)
                        stageArea(stage: .rem, size: size)
                        stageArea(stage: .awake, size: size)

                        if let selectedPoint,
                           let index = points.firstIndex(where: { $0.dateKey == selectedPoint.dateKey }) {
                            let x = xPosition(for: index, width: size.width)
                            selectionRule(x: x, height: size.height)
                            tooltip(for: selectedPoint)
                                .position(tooltipPosition(x: x, size: size))
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

                axisLabels
                stageLegend
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Stage Composition")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                Text("Tap or drag across the chart for nightly details.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Text("%")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func stageArea(stage: CompositionStage, size: CGSize) -> some View {
        areaPath(for: stage, size: size)
            .fill(stage.color.opacity(stage.opacity))
            .overlay(
                areaPath(for: stage, size: size)
                    .stroke(stage.color.opacity(0.75), lineWidth: 1)
            )
    }

    private func areaPath(for stage: CompositionStage, size: CGSize) -> Path {
        Path { path in
            guard !points.isEmpty else { return }

            let topPoints = points.enumerated().map { index, point in
                CGPoint(
                    x: xPosition(for: index, width: size.width),
                    y: yPosition(for: cumulativeTop(stage: stage, point: point), height: size.height)
                )
            }
            let bottomPoints = points.enumerated().map { index, point in
                CGPoint(
                    x: xPosition(for: index, width: size.width),
                    y: yPosition(for: cumulativeBottom(stage: stage, point: point), height: size.height)
                )
            }

            guard let first = topPoints.first else { return }
            path.move(to: first)
            for point in topPoints.dropFirst() {
                path.addLine(to: point)
            }
            for point in bottomPoints.reversed() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }

    private func cumulativeBottom(stage: CompositionStage, point: StageCompositionPoint) -> Double {
        switch stage {
        case .deep:
            return 0
        case .core:
            return point.deepPercent
        case .rem:
            return point.deepPercent + point.corePercent
        case .awake:
            return point.deepPercent + point.corePercent + point.remPercent
        }
    }

    private func cumulativeTop(stage: CompositionStage, point: StageCompositionPoint) -> Double {
        switch stage {
        case .deep:
            return point.deepPercent
        case .core:
            return point.deepPercent + point.corePercent
        case .rem:
            return point.deepPercent + point.corePercent + point.remPercent
        case .awake:
            return point.deepPercent + point.corePercent + point.remPercent + point.awakePercent
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        points.count == 1 ? width / 2 : width * CGFloat(index) / CGFloat(points.count - 1)
    }

    private func yPosition(for percent: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(percent, 0), 1)
        return height - (height * CGFloat(clamped))
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

    private func grid(size: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Path { path in
                for step in 0...4 {
                    let y = size.height * CGFloat(step) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(BetterColors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            VStack {
                Text("100")
                Spacer()
                Text("50")
                Spacer()
                Text("0")
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(BetterColors.mutedText)
            .offset(x: 4)
        }
    }

    private func selectionRule(x: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(BetterColors.text.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func tooltip(for point: StageCompositionPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            tooltipRow("Deep", duration: point.deepDuration, percent: point.deepPercent, color: BetterColors.stageDeep)
            tooltipRow("Core", duration: point.coreDuration, percent: point.corePercent, color: BetterColors.stageCore)
            tooltipRow("REM", duration: point.remDuration, percent: point.remPercent, color: BetterColors.stageREM)
            tooltipRow("Awake", duration: point.awakeDuration, percent: point.awakePercent, color: BetterColors.stageAwake)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 150, alignment: .leading)
        .background(BetterColors.cardTertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    private func tooltipRow(_ label: String, duration: TimeInterval, percent: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text("\(formatDuration(duration)) \(Int((percent * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
        }
    }

    private func tooltipPosition(x: CGFloat, size: CGSize) -> CGPoint {
        let tooltipX = x < size.width / 2 ? min(x + 88, size.width - 75) : max(x - 88, 75)
        return CGPoint(x: tooltipX, y: 76)
    }

    private var axisLabels: some View {
        HStack {
            Text(points.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
            Spacer()
            Text(points.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(BetterColors.subtext)
    }

    private var stageLegend: some View {
        HStack(spacing: BetterSpacing.medium) {
            legend("Deep", BetterColors.stageDeep)
            legend("Core", BetterColors.stageCore)
            legend("REM", BetterColors.stageREM)
            legend("Awake", BetterColors.stageAwake)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(BetterTypography.caption).foregroundStyle(BetterColors.subtext)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private enum CompositionStage: CaseIterable {
    case deep
    case core
    case rem
    case awake

    var color: Color {
        switch self {
        case .deep:
            return BetterColors.stageDeep
        case .core:
            return BetterColors.stageCore
        case .rem:
            return BetterColors.stageREM
        case .awake:
            return BetterColors.stageAwake
        }
    }

    var opacity: Double {
        switch self {
        case .rem:
            return 0.9
        case .awake:
            return 0.82
        default:
            return 0.86
        }
    }
}
