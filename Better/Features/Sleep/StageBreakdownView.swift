import SwiftUI

// MARK: - Stage breakdown bars matching StageBars in SleepTab.tsx

struct StageBreakdownView: View {
    let session: SleepSession
    let baseline: SleepBaseline?
    let showUnavailableMessage: Bool

    init(session: SleepSession, baseline: SleepBaseline?) {
        self.session = session
        self.baseline = baseline
        self.showUnavailableMessage = session.dataQuality == .unspecifiedSleepOnly
                                   || session.dataQuality == .inBedOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            if showUnavailableMessage {
                stageUnavailableBanner
            } else {
                ForEach(rows, id: \.type) { row in
                    StageBarRow(
                        type: row.type,
                        tonightMinutes: row.tonightMinutes,
                        baselineMinutes: row.baselineMinutes
                    )
                }
                if baseline != nil {
                    legend
                }
            }
        }
    }

    // MARK: - Private

    private struct StageRow {
        let type: SleepStageType
        let tonightMinutes: Double
        let baselineMinutes: Double?
    }

    private var rows: [StageRow] {
        [
            StageRow(type: .deep,  tonightMinutes: session.deepDuration / 60,  baselineMinutes: baseline.map { $0.deepAverage / 60 }),
            StageRow(type: .core,  tonightMinutes: session.coreDuration / 60,  baselineMinutes: nil),
            StageRow(type: .rem,   tonightMinutes: session.remDuration / 60,   baselineMinutes: baseline.map { $0.remAverage / 60 }),
            StageRow(type: .awake, tonightMinutes: session.awakeDuration / 60, baselineMinutes: baseline.map { $0.wasoAverage / 60 }),
        ]
    }

    private var stageUnavailableBanner: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "info.circle")
                .foregroundStyle(BetterColors.brand)
            Text("Stage detail unavailable. Apple Watch sleep stages require watchOS 9+.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var legend: some View {
        HStack(spacing: BetterSpacing.large) {
            legendItem(height: 6, label: "Tonight", opacity: 1.0)
            legendItem(height: 4, label: "\(baseline?.windowDays ?? 30)-Day Avg", opacity: 0.4)
        }
        .padding(.top, BetterSpacing.xSmall)
    }

    private func legendItem(height: CGFloat, label: String, opacity: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BetterColors.subtext.opacity(opacity))
                .frame(width: 14, height: height)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }
}

// MARK: - Individual stage bar row

private struct StageBarRow: View {
    let type: SleepStageType
    let tonightMinutes: Double
    let baselineMinutes: Double?

    private var maxMinutes: Double {
        switch type {
        case .deep:  180
        case .core:  300
        case .rem:   200
        case .awake: 90
        default:     180
        }
    }

    private var diff: Double? {
        baselineMinutes.map { tonightMinutes - $0 }
    }

    private var isPositiveDiff: Bool {
        guard let diff else { return true }
        return type == .awake ? diff <= 0 : diff >= 0
    }

    var body: some View {
        VStack(spacing: 4) {
            // Label row
            HStack {
                HStack(spacing: BetterSpacing.small) {
                    Circle()
                        .fill(type.color)
                        .frame(width: 8, height: 8)
                    Text(type.displayName)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                }
                Spacer()
                HStack(spacing: BetterSpacing.small) {
                    Text(formatMinutes(tonightMinutes))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    if let diff {
                        Text("\(diff >= 0 ? "+" : "")\(formatMinutes(abs(diff)))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isPositiveDiff ? BetterColors.success : BetterColors.warning)
                    }
                }
            }

            // Tonight bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BetterColors.cardTertiary)

                    // Baseline ghost bar
                    if let baselineMinutes {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(type.color.opacity(0.25))
                            .frame(width: geo.size.width * CGFloat(min(baselineMinutes / maxMinutes, 1)))
                    }

                    // Tonight bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(width: geo.size.width * CGFloat(min(tonightMinutes / maxMinutes, 1)))
                }
            }
            .frame(height: 7)

            // Percentage label
            HStack {
                Spacer()
                if let total = totalAsleepMinutes, total > 0 {
                    Text("\(Int((tonightMinutes / total) * 100))%")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
    }

    // Used only for awake — total asleep for percentage is derived outside
    private var totalAsleepMinutes: Double? { nil }

    private func formatMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
