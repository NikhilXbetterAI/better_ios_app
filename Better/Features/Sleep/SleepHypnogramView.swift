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
        VStack(spacing: BetterSpacing.xSmall) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(stages) { stage in
                        let fraction = stage.endDate.timeIntervalSince(stage.startDate) / totalDuration
                        let width = max(geo.size.width * CGFloat(fraction) - 1.5, 2)
                        Rectangle()
                            .fill(stage.type.color)
                            .frame(width: width)
                            .opacity(stage.type == .awake ? 0.55 : 1)
                    }
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Time labels
            HStack {
                Text(sessionStart, style: .time)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
                Text(sessionEnd, style: .time)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
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
