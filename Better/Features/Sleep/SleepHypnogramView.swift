import SwiftUI

// MARK: - Segmented stage timeline matching SleepTimeline in SleepTab.tsx

struct SleepHypnogramView: View {
    let stages: [SleepStage]
    let sessionStart: Date
    let sessionEnd: Date

    private var totalDuration: TimeInterval {
        max(sessionEnd.timeIntervalSince(sessionStart), 1)
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
                            let frame = frame(for: stage, size: geo.size)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stage.type.color)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .opacity(stage.type == .awake ? 0.9 : 1)
                        }
                    }
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Time labels
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
    }

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
