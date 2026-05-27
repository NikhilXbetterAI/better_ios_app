import SwiftUI

struct StageDurationCompositionView: View {
    let points: [StageCompositionPoint]
    let selectedWindow: TrendWindow
    let onSelectWindow: (TrendWindow) -> Void

    @State private var selectedDateKey: String?

    private var sortedPoints: [StageCompositionPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var selectedPoint: StageCompositionPoint? {
        if let selectedDateKey,
           let point = sortedPoints.first(where: { $0.dateKey == selectedDateKey }) {
            return point
        }
        return sortedPoints.last
    }

    private var axisMaxDuration: TimeInterval {
        let longestNight = sortedPoints.map(\.totalStageDuration).max() ?? 0
        let roundedHours = ceil(longestNight / 3_600)
        return max(roundedHours * 3_600, 8 * 3_600)
    }

    private var averageSleepDuration: TimeInterval {
        guard !sortedPoints.isEmpty else { return 0 }
        return sortedPoints.map(\.sleepDuration).reduce(0, +) / Double(sortedPoints.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            header
            windowSelector

            if sortedPoints.isEmpty {
                emptyState
            } else {
                chart
                stageInspector
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
        .onAppear {
            selectedDateKey = selectedPoint?.dateKey
        }
        .onChange(of: sortedPoints.map(\.dateKey)) { _, keys in
            guard !keys.isEmpty else {
                selectedDateKey = nil
                return
            }
            if let selectedDateKey, keys.contains(selectedDateKey) {
                return
            }
            selectedDateKey = keys.last
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Sleep Stage Composition")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text("Duration-stacked stages across nights")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer(minLength: BetterSpacing.medium)

            VStack(alignment: .trailing, spacing: 4) {
                Text(selectedPoint?.date.formatted(.dateTime.month(.abbreviated).day()) ?? selectedWindow.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Text(formatDuration(selectedPoint?.sleepDuration ?? averageSleepDuration))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                Text(selectedPoint == nil ? "avg sleep" : "sleep duration")
                    .font(BetterTypography.micro)
                    .foregroundStyle(BetterColors.mutedText)
            }
        }
    }

    private var windowSelector: some View {
        HStack(spacing: BetterSpacing.small) {
            ForEach(TrendWindow.allCases) { window in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selectedDateKey = nil
                    }
                    onSelectWindow(window)
                } label: {
                    Text(window.displayName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedWindow == window ? BetterColors.text : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedWindow == window
                                ? BetterColors.brand
                                : BetterColors.cardSecondary,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(BetterColors.backgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BetterColors.stageDeep)
            Text("Detailed stages are unavailable for this range.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var chart: some View {
        GeometryReader { proxy in
            let chartWidth = proxy.size.width
            let chartHeight = proxy.size.height
            let yAxisWidth: CGFloat = 34
            let xAxisHeight: CGFloat = 24
            let plotSize = CGSize(width: chartWidth - yAxisWidth, height: chartHeight - xAxisHeight)
            let maxHours = axisMaxDuration / 3_600
            let contentWidth = max(plotSize.width, preferredContentWidth)

            ZStack(alignment: .topLeading) {
                chartBackground

                yAxisLabels(maxHours: maxHours, height: plotSize.height)
                    .frame(width: yAxisWidth, height: plotSize.height)
                    .offset(x: 0, y: 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            horizontalGrid(height: plotSize.height, width: contentWidth)
                            bars(width: contentWidth, height: plotSize.height)
                            selectedTooltip(width: contentWidth, height: plotSize.height)
                        }
                        .frame(width: contentWidth, height: plotSize.height)

                        xAxisLabels(width: contentWidth)
                            .frame(width: contentWidth, height: xAxisHeight)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location.x, width: contentWidth)
                            }
                    )
                }
                .frame(width: plotSize.width, height: chartHeight)
                .offset(x: yAxisWidth, y: 8)
            }
        }
        .frame(height: 292)
    }

    private var chartBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        BetterColors.backgroundElevated.opacity(0.96),
                        BetterColors.cardSecondary.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BetterColors.border, lineWidth: 1)
            )
    }

    private var preferredContentWidth: CGFloat {
        switch selectedWindow {
        case .week:
            return CGFloat(max(sortedPoints.count, 7)) * 38
        case .month:
            return CGFloat(max(sortedPoints.count, 30)) * 12
        case .twoMonths:
            return CGFloat(max(sortedPoints.count, 60)) * 9
        }
    }

    private func bars(width: CGFloat, height: CGFloat) -> some View {
        let spacing = barSpacing
        let count = max(sortedPoints.count, 1)
        let barWidth = max(4, min(30, (width - (CGFloat(count - 1) * spacing)) / CGFloat(count)))

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(sortedPoints) { point in
                stageBar(
                    for: point,
                    barWidth: barWidth,
                    maxHeight: height,
                    isSelected: point.dateKey == selectedPoint?.dateKey
                )
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedDateKey = point.dateKey
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .padding(.horizontal, 2)
    }

    private var barSpacing: CGFloat {
        switch selectedWindow {
        case .week:
            return 12
        case .month:
            return 5
        case .twoMonths:
            return 3
        }
    }

    private func stageBar(for point: StageCompositionPoint, barWidth: CGFloat, maxHeight: CGFloat, isSelected: Bool) -> some View {
        let barHeight = max(8, maxHeight * CGFloat(point.totalStageDuration / axisMaxDuration))
        let scale: CGFloat = isSelected ? 1.08 : 1

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                stageSegment(duration: point.awakeDuration, maxHeight: maxHeight, color: BetterColors.stageAwake)
                stageSegment(duration: point.coreDuration, maxHeight: maxHeight, color: BetterColors.stageCore)
                stageSegment(duration: point.deepDuration, maxHeight: maxHeight, color: BetterColors.stageDeep)
                stageSegment(duration: point.remDuration, maxHeight: maxHeight, color: BetterColors.stageREM)
            }
            .frame(width: barWidth * scale, height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: isSelected ? 8 : 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isSelected ? 8 : 4, style: .continuous)
                    .stroke(isSelected ? BetterColors.text.opacity(0.9) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? BetterColors.brand.opacity(0.45) : .clear, radius: 10, y: 3)
        }
        .frame(width: max(barWidth * 1.18, 8), height: maxHeight, alignment: .bottom)
        .animation(.snappy(duration: 0.22), value: isSelected)
    }

    private func stageSegment(duration: TimeInterval, maxHeight: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: max(duration > 0 ? 1.5 : 0, maxHeight * CGFloat(duration / axisMaxDuration)))
    }

    private func horizontalGrid(height: CGFloat, width: CGFloat) -> some View {
        Path { path in
            for step in 0...4 {
                let y = height * CGFloat(step) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(BetterColors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }

    private func selectedTooltip(width: CGFloat, height: CGFloat) -> some View {
        guard let selectedPoint,
              let index = sortedPoints.firstIndex(where: { $0.dateKey == selectedPoint.dateKey }) else {
            return AnyView(EmptyView())
        }

        let x = selectionX(index: index, width: width)
        let barHeight = max(8, height * CGFloat(selectedPoint.totalStageDuration / axisMaxDuration))
        let clampedTooltipX = min(max(x, 82), max(width - 82, 82))
        let tooltipY = max(56, height - barHeight - 52)

        return AnyView(
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(BetterColors.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()))
                            .foregroundStyle(BetterColors.subtext)
                        Spacer()
                        Text(formatDuration(selectedPoint.sleepDuration))
                            .foregroundStyle(BetterColors.text)
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())

                    tooltipRow("Awake", duration: selectedPoint.awakeDuration, total: selectedPoint.totalStageDuration, color: BetterColors.stageAwake)
                    tooltipRow("Light", duration: selectedPoint.coreDuration, total: selectedPoint.totalStageDuration, color: BetterColors.stageCore)
                    tooltipRow("Deep", duration: selectedPoint.deepDuration, total: selectedPoint.totalStageDuration, color: BetterColors.stageDeep)
                    tooltipRow("REM", duration: selectedPoint.remDuration, total: selectedPoint.totalStageDuration, color: BetterColors.stageREM)
                }
                .padding(10)
                .frame(width: 164, alignment: .leading)
                .background(BetterColors.cardTertiary.opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BetterColors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
                .position(x: clampedTooltipX, y: tooltipY)
            }
            .frame(width: width, height: height, alignment: .bottomLeading)
        )
    }

    private func tooltipRow(_ label: String, duration: TimeInterval, total: TimeInterval, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text("\(formatDuration(duration)) \(formatPercent(duration, total: total))")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
        }
    }

    private func yAxisLabels(maxHours: Double, height: CGFloat) -> some View {
        VStack(alignment: .trailing) {
            Text("\(Int(maxHours.rounded()))h")
            Spacer()
            Text("\(Int((maxHours / 2).rounded()))h")
            Spacer()
            Text("0h")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(BetterColors.mutedText)
        .frame(height: height)
    }

    private func xAxisLabels(width: CGFloat) -> some View {
        HStack {
            Text(sortedPoints.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
            Spacer()
            if let selectedPoint {
                Text(selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()))
                    .foregroundStyle(BetterColors.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BetterColors.brand, in: Capsule())
            }
            Spacer()
            Text(sortedPoints.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(BetterColors.subtext)
        .frame(width: width)
    }

    private func updateSelection(at x: CGFloat, width: CGFloat) {
        guard !sortedPoints.isEmpty else { return }
        let count = sortedPoints.count
        guard count > 1 else {
            selectedDateKey = sortedPoints[0].dateKey
            return
        }
        let clampedX = min(max(0, x), width)
        let rawIndex = (clampedX / max(width, 1)) * CGFloat(count - 1)
        let index = min(max(Int(rawIndex.rounded()), 0), count - 1)
        withAnimation(.snappy(duration: 0.18)) {
            selectedDateKey = sortedPoints[index].dateKey
        }
    }

    private func selectionX(index: Int, width: CGFloat) -> CGFloat {
        guard sortedPoints.count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(sortedPoints.count - 1)
    }

    private var stageInspector: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text(selectedPoint?.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Selected night")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                Text("\(formatDuration(selectedPoint?.totalStageDuration ?? 0)) total")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.subtext)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BetterSpacing.small) {
                stagePill("Awake", duration: selectedPoint?.awakeDuration ?? 0, total: selectedPoint?.totalStageDuration ?? 0, color: BetterColors.stageAwake)
                stagePill("Light", duration: selectedPoint?.coreDuration ?? 0, total: selectedPoint?.totalStageDuration ?? 0, color: BetterColors.stageCore)
                stagePill("Deep", duration: selectedPoint?.deepDuration ?? 0, total: selectedPoint?.totalStageDuration ?? 0, color: BetterColors.stageDeep)
                stagePill("REM", duration: selectedPoint?.remDuration ?? 0, total: selectedPoint?.totalStageDuration ?? 0, color: BetterColors.stageREM)
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stagePill(_ label: String, duration: TimeInterval, total: TimeInterval, color: Color) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                Text(formatDuration(duration))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
            }
            Spacer()
            Text(formatPercent(duration, total: total))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, BetterSpacing.small)
        .padding(.vertical, 10)
        .background(BetterColors.backgroundElevated.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatPercent(_ duration: TimeInterval, total: TimeInterval) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int(((duration / total) * 100).rounded()))%"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3_600
        let m = (Int(interval) % 3_600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
