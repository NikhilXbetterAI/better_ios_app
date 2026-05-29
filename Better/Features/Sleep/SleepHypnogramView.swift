import SwiftUI

// MARK: - Segmented stage timeline matching Apple Health style sleep stages

struct SleepHypnogramView: View {
    let stages: [SleepStage]
    let sessionStart: Date
    let sessionEnd: Date

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragX: CGFloat? = nil
    @State private var chartWidth: CGFloat = 1

    private let labelWidth: CGFloat = 55

    private var totalDuration: TimeInterval {
        max(sessionEnd.timeIntervalSince(sessionStart), 1)
    }

    // Stage currently under the scrub position
    private var activeStage: SleepStage? {
        guard let x = dragX, chartWidth > labelWidth else { return nil }
        let progress = Double((x - labelWidth) / (chartWidth - labelWidth))
        let clamped = min(max(progress, 0), 1)
        let targetTime = sessionStart.addingTimeInterval(totalDuration * clamped)
        return stages.first { $0.startDate <= targetTime && $0.endDate >= targetTime }
    }

    var body: some View {
        VStack(spacing: BetterSpacing.small) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    laneGrid(size: geo.size)

                    // 1. Lane labels in the dedicated left column
                    let laneHeight = geo.size.height / CGFloat(stageLanes.count)
                    ForEach(0..<stageLanes.count, id: \.self) { index in
                        let lane = stageLanes[index]
                        Text(lane.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .frame(width: labelWidth - 8, alignment: .leading)
                            .position(x: (labelWidth - 8) / 2 + 4, y: laneHeight * (CGFloat(index) + 0.5))
                    }

                    // 2. Watermarked Hourly Time Labels at the bottom of the grid
                    let hourCount = Int(totalDuration / 3600)
                    if hourCount > 0 {
                        ForEach(1..<hourCount, id: \.self) { hr in
                            if hr % 2 == 0 { // Label every 2 hours
                                let pct = Double(hr) * 3600.0 / totalDuration
                                let x = labelWidth + pct * (geo.size.width - labelWidth)
                                let hrDate = sessionStart.addingTimeInterval(Double(hr) * 3600)
                                Text(formatHour(hrDate))
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundStyle(BetterColors.mutedText.opacity(0.45))
                                    .position(x: x, y: geo.size.height - 6)
                            }
                        }
                    }

                    // 3. Gradient connectors between consecutive stages (stage-color-to-stage-color)
                    if stages.count > 1 {
                        ForEach(0..<stages.count - 1, id: \.self) { index in
                            let s1 = stages[index]
                            let s2 = stages[index + 1]
                            let gap = s2.startDate.timeIntervalSince(s1.endDate)
                            if gap < 300 {
                                let f1 = frame(for: s1, size: geo.size)
                                let f2 = frame(for: s2, size: geo.size)
                                let sameStage = s1.type == s2.type
                                let goingDown = f2.midY > f1.midY
                                let yStart = goingDown ? f1.maxY : f1.minY
                                let yEnd = goingDown ? f2.minY : f2.maxY
                                let connectorHeight = abs(yEnd - yStart)

                                if sameStage || connectorHeight < 2 {
                                    // Same lane — draw nothing; blocks are visually flush
                                    EmptyView()
                                } else {
                                    let topColor = goingDown ? s1.type.color : s2.type.color
                                    let bottomColor = goingDown ? s2.type.color : s1.type.color
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    topColor.opacity(differentiateWithoutColor ? 0.7 : 0.55),
                                                    bottomColor.opacity(differentiateWithoutColor ? 0.7 : 0.55)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: differentiateWithoutColor ? 2.5 : 1.5, height: connectorHeight)
                                        .position(x: f1.maxX, y: (yStart + yEnd) / 2)
                                }
                            }
                        }
                    }

                    // 4. Opaque rounded stage blocks
                    ForEach(stages) { stage in
                        let isActive = activeStage?.id == stage.id
                        let isDimmed = dragX != nil && !isActive
                        let f = frame(for: stage, size: geo.size)

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(stage.type.color.opacity(isDimmed ? 0.25 : 1.0))
                            .frame(width: f.width, height: f.height)
                            .position(x: f.midX, y: f.midY)
                            .overlay {
                                stageAccessibilityMarker(stage.type, isDimmed: isDimmed)
                                    .frame(width: f.width, height: f.height)
                                    .position(x: f.midX, y: f.midY)
                            }
                            .shadow(color: stage.type.color.opacity(isDimmed || reduceMotion ? 0 : 0.3), radius: 2)
                    }

                    // 5. Scrub line and vertical-jumping tracker dot
                    if let x = dragX {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1.5, height: geo.size.height)
                            .position(x: x, y: geo.size.height / 2)
                            .allowsHitTesting(false)

                        if let active = activeStage {
                            let f = frame(for: active, size: geo.size)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 9, height: 9)
                                .overlay {
                                    if differentiateWithoutColor {
                                        stageSymbol(active.type)
                                            .font(.system(size: 5, weight: .black))
                                            .foregroundStyle(Color.black)
                                    }
                                }
                                .shadow(color: active.type.color.opacity(reduceMotion ? 0 : 1), radius: 4)
                                .position(x: x, y: f.midY)
                        }
                    }
                }
                .onAppear { chartWidth = geo.size.width }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragX = max(labelWidth, min(geo.size.width, value.location.x))
                            chartWidth = geo.size.width
                        }
                        .onEnded { _ in
                            if reduceMotion {
                                dragX = nil
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) { dragX = nil }
                            }
                        }
                )
            }
            .frame(height: 150) // Taller chart area for better layout
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Tooltip replaces time labels while scrubbing
            if let x = dragX {
                scrubTooltip(x: x)
                    .padding(.leading, labelWidth)
                    .transition(.opacity)
            } else {
                timeLabelsRow
                    .padding(.leading, labelWidth)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: dragX == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stage timeline")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: - Tooltip shown while scrubbing

    private func scrubTooltip(x: CGFloat) -> some View {
        let usableW = max(chartWidth - labelWidth, 1)
        let progress = min(max(Double((x - labelWidth) / usableW), 0), 1)
        let currentTime = sessionStart.addingTimeInterval(totalDuration * progress)
        let stage = activeStage

        return HStack(spacing: 6) {
            if let stage {
                stageMarker(stage.type)
                Text(stageName(stage.type))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("·")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BetterColors.mutedText)
                Text(formatDuration(stage.endDate.timeIntervalSince(stage.startDate)))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(stage.type.color)
            }
            Spacer(minLength: 0)
            Text(currentTime, style: .time)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Static time labels

    private var timeLabelsRow: some View {
        HStack {
            Text("Bed")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.mutedText)
            Text(sessionStart, style: .time)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text("Wake")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.mutedText)
            Text(sessionEnd, style: .time)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Helpers

    private var stageLanes: [(type: SleepStageType, label: String)] {
        [
            (.awake, "Awake"),
            (.core, "Light"),
            (.deep, "Deep"),
            (.rem, "REM"),
        ]
    }

    private func laneGrid(size: CGSize) -> some View {
        ZStack {
            Color.black

            // Subtle hour separators (vertical dashed lines)
            let usableW = max(size.width - labelWidth, 1)
            let hourCount = Int(totalDuration / 3600)
            if hourCount > 0 {
                Path { path in
                    for hr in 1..<hourCount {
                        let pct = Double(hr) * 3600.0 / totalDuration
                        let x = labelWidth + usableW * CGFloat(pct)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
                .stroke(Color.white.opacity(0.025), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Horizontal lane borders (only span the chart area)
            Path { path in
                for index in 0...stageLanes.count {
                    let y = size.height * CGFloat(index) / CGFloat(stageLanes.count)
                    path.move(to: CGPoint(x: labelWidth, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.03), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func stageMarker(_ type: SleepStageType) -> some View {
        ZStack {
            Circle()
                .fill(type.color)
                .frame(width: 10, height: 10)
            if differentiateWithoutColor {
                stageSymbol(type)
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(Color.black)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stageAccessibilityMarker(_ type: SleepStageType, isDimmed: Bool) -> some View {
        if differentiateWithoutColor {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(isDimmed ? 0.35 : 0.7), lineWidth: 1)
                stageSymbol(type)
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Color.white.opacity(isDimmed ? 0.45 : 0.9))
                    .minimumScaleFactor(0.5)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func stageSymbol(_ type: SleepStageType) -> some View {
        switch type {
        case .awake:
            Image(systemName: "exclamationmark")
        case .core:
            Image(systemName: "minus")
        case .deep:
            Image(systemName: "pause.fill")
        case .rem:
            Image(systemName: "circle.fill")
        case .unspecified:
            Image(systemName: "questionmark")
        case .inBed:
            Image(systemName: "bed.double.fill")
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            "From \(accessibilityTime(sessionStart)) to \(accessibilityTime(sessionEnd)).",
            "Total time \(formatDuration(totalDuration))."
        ]

        let stageTotals = Dictionary(grouping: stages, by: \.type)
            .mapValues { grouped in
                grouped.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            }
        let orderedStages: [SleepStageType] = [.awake, .core, .deep, .rem]
        let stageParts = orderedStages.compactMap { type -> String? in
            guard let duration = stageTotals[type], duration > 0 else { return nil }
            return "\(stageName(type)) \(formatDuration(duration))"
        }
        if !stageParts.isEmpty {
            parts.append(stageParts.joined(separator: ", ") + ".")
        }
        if let first = stages.first {
            parts.append("Started with \(stageName(first.type)).")
        }
        if let last = stages.last {
            parts.append("Ended with \(stageName(last.type)).")
        }
        return parts.joined(separator: " ")
    }

    private func frame(for stage: SleepStage, size: CGSize) -> CGRect {
        let usableW = max(size.width - labelWidth, 1)
        let startOffset = max(0, stage.startDate.timeIntervalSince(sessionStart))
        let endOffset = min(totalDuration, stage.endDate.timeIntervalSince(sessionStart))
        let x = labelWidth + usableW * CGFloat(startOffset / totalDuration)
        let width = max(2, usableW * CGFloat(max(0, endOffset - startOffset) / totalDuration))
        let laneHeight = size.height / CGFloat(stageLanes.count)
        let laneIndex = stageLanes.firstIndex { $0.type == stage.type } ?? 2
        let barHeight: CGFloat = 20
        let y = laneHeight * CGFloat(laneIndex) + (laneHeight - barHeight) / 2
        return CGRect(x: x, y: y, width: width, height: barHeight)
    }

    private func stageName(_ type: SleepStageType) -> String {
        switch type {
        case .deep:        return "Deep Sleep"
        case .core:        return "Light Sleep"
        case .rem:         return "REM Sleep"
        case .awake:       return "Awake"
        case .unspecified: return "Sleep"
        case .inBed:       return "In Bed"
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatHour(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date)
    }

    private func accessibilityTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

#Preview("Hypnogram") {
    let session = PreviewSleepData.sampleSession
    ZStack {
        BetterColors.background.ignoresSafeArea()
        VStack(spacing: 16) {
            SleepHypnogramView(
                stages: session.stages,
                sessionStart: session.startDate,
                sessionEnd: session.endDate
            )
        }
        .padding()
    }
}
