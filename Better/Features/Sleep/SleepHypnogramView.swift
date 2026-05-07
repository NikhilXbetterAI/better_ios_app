import SwiftUI

// MARK: - Segmented stage timeline matching SleepTimeline in SleepTab.tsx

struct SleepHypnogramView: View {
    let stages: [SleepStage]
    let sessionStart: Date
    let sessionEnd: Date

    @State private var dragX: CGFloat? = nil
    @State private var chartWidth: CGFloat = 1

    private var totalDuration: TimeInterval {
        max(sessionEnd.timeIntervalSince(sessionStart), 1)
    }

    // Stage currently under the scrub position
    private var activeStage: SleepStage? {
        guard let x = dragX, chartWidth > 0 else { return nil }
        let progress = Double(x / chartWidth)
        let targetTime = sessionStart.addingTimeInterval(totalDuration * progress)
        return stages.first { $0.startDate <= targetTime && $0.endDate >= targetTime }
    }

    var body: some View {
        VStack(spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.small) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(stageLanes, id: \.type) { lane in
                        Text(lane.label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                            .frame(height: 22, alignment: .center)
                    }
                }
                .frame(width: 34)

                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        laneGrid(size: geo.size)

                        ForEach(stages) { stage in
                            let isActive = activeStage?.id == stage.id
                            let isDimmed = dragX != nil && !isActive
                            let f = frame(for: stage, size: geo.size)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stage.type.color)
                                .frame(width: f.width, height: f.height)
                                .position(x: f.midX, y: f.midY)
                                .opacity(isDimmed ? 0.25 : (stage.type == .awake ? 0.9 : 1))
                        }

                        // Scrub line
                        if let x = dragX {
                            Rectangle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 1.5, height: geo.size.height)
                                .position(x: x, y: geo.size.height / 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .onAppear { chartWidth = geo.size.width }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragX = max(0, min(geo.size.width, value.location.x))
                                chartWidth = geo.size.width
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) { dragX = nil }
                            }
                    )
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Tooltip replaces time labels while scrubbing
            if let x = dragX {
                scrubTooltip(x: x)
                    .transition(.opacity)
            } else {
                timeLabelsRow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: dragX == nil)
    }

    // MARK: - Tooltip shown while scrubbing

    private func scrubTooltip(x: CGFloat) -> some View {
        let progress = chartWidth > 0 ? Double(x / chartWidth) : 0
        let currentTime = sessionStart.addingTimeInterval(totalDuration * progress)
        let stage = activeStage

        return HStack(spacing: 6) {
            if let stage {
                Circle()
                    .fill(stage.type.color)
                    .frame(width: 7, height: 7)
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
            (.rem, "REM"),
            (.core, "Core"),
            (.deep, "Deep"),
        ]
    }

    private func laneGrid(size: CGSize) -> some View {
        Path { path in
            for index in 0...stageLanes.count {
                let y = size.height * CGFloat(index) / CGFloat(stageLanes.count)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(BetterColors.border, lineWidth: 1)
        .background(BetterColors.cardSecondary.opacity(0.55))
    }

    private func frame(for stage: SleepStage, size: CGSize) -> CGRect {
        let startOffset = max(0, stage.startDate.timeIntervalSince(sessionStart))
        let endOffset = min(totalDuration, stage.endDate.timeIntervalSince(sessionStart))
        let x = size.width * CGFloat(startOffset / totalDuration)
        let width = max(2, size.width * CGFloat(max(0, endOffset - startOffset) / totalDuration))
        let laneHeight = size.height / CGFloat(stageLanes.count)
        let laneIndex = stageLanes.firstIndex { $0.type == stage.type } ?? 2
        let y = laneHeight * CGFloat(laneIndex) + 3
        return CGRect(x: x, y: y, width: width, height: max(4, laneHeight - 6))
    }

    private func stageName(_ type: SleepStageType) -> String {
        switch type {
        case .deep:        return "Deep Sleep"
        case .core:        return "Core Sleep"
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
}

// MARK: - Stage legend pills

struct StageLegendRow: View {
    let showAll: Bool

    private let items: [(SleepStageType, String)] = [
        (.deep,  "Deep"),
        (.core,  "Core"),
        (.rem,   "REM"),
        (.awake, "Awake"),
    ]

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            ForEach(items, id: \.0) { type, label in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(type.color)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            Spacer()
        }
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
            StageLegendRow(showAll: true)
        }
        .padding()
    }
}
