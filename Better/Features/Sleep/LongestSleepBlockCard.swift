import SwiftUI

/// Redesigned dashboard card showing the user's longest uninterrupted sleep block
/// for the night. Reuses `session.continuitySummary` — no recomputation
/// (CLAUDE.md invariant #11).
struct LongestSleepBlockCard: View {
    let session: SleepSession

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsTimes = false

    private var summary: SleepContinuitySummary { session.continuitySummary }
    private var category: SleepContinuityCategory { summary.continuityCategory }

    private var bestBlock: SleepContinuityBlock? {
        guard let index = summary.longestBlockIndex else { return summary.blocks.first }
        return summary.blocks.first(where: { $0.index == index }) ?? summary.blocks.first
    }

    // Colors matching category definition
    private var categoryColor: Color {
        switch category {
        case .exceptional, .strong: return BetterColors.success
        case .good:                 return BetterColors.brand
        case .moderatelyFragmented: return BetterColors.warning
        case .highlyFragmented:     return BetterColors.danger
        case .unavailable:          return BetterColors.subtext
        }
    }

    // Short display name for category pill
    private var shortCategoryDisplayName: String {
        switch category {
        case .unavailable:          return "Unavailable"
        case .exceptional:          return "Exceptional"
        case .strong:               return "Strong"
        case .good:                 return "Good"
        case .moderatelyFragmented: return "Moderate"
        case .highlyFragmented:     return "Fragmented"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            // Header Row: LONGEST UNINTERRUPTED + BLOCKS/Breaks
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("LONGEST UNINTERRUPTED")
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.subtext)
                        .tracking(1.2)

                    durationRow

                    if category != .unavailable {
                        categoryPill
                    }
                }

                Spacer()

                if category != .unavailable {
                    blocksColumn
                }
            }

            // Proportional Timeline Bar (only if we have sleep blocks & valid duration)
            if !summary.blocks.isEmpty && summary.longestBlockDuration > 0 {
                timelineBar
            }

            // Insight message with category vertical line
            insightRow

            // Interactive Expandable Block List
            if showsTimes && !summary.blocks.isEmpty {
                blockListView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !summary.blocks.isEmpty else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78)) {
                showsTimes.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(summary.blocks.isEmpty ? [] : .isButton)
        .accessibilityLabel("Longest continuity block")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint(summary.blocks.isEmpty ? "" : "Double tap to \(showsTimes ? "hide" : "show") block times.")
    }

    @ViewBuilder
    private var durationRow: some View {
        // Use the block's own wall-clock span (start→end) so the displayed
        // duration matches the start/end times shown in the block list.
        // Bug A1: longestBlockDuration is pure-sleep seconds; it can differ
        // from wall-clock span when short awakenings are absorbed into the block.
        let duration: TimeInterval = {
            if let block = bestBlock {
                return block.endDate.timeIntervalSince(block.startDate)
            }
            return summary.longestBlockDuration
        }()
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60

        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if duration > 0 {
                Text("\(hours)")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                Text("h")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(categoryColor.opacity(0.8))

                Spacer().frame(width: 4)

                Text("\(minutes)")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                Text("m")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(categoryColor.opacity(0.8))
            } else {
                Text("—")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(categoryColor)
    }

    @ViewBuilder
    private var categoryPill: some View {
        Text(shortCategoryDisplayName)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(categoryColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(categoryColor.opacity(differentiateWithoutColor ? 0.75 : 0.3), lineWidth: differentiateWithoutColor ? 1.5 : 1)
            )
            .overlay(alignment: .leading) {
                if differentiateWithoutColor {
                    Text(categorySymbol)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(categoryColor)
                        .padding(.leading, 4)
                }
            }
            .padding(.leading, differentiateWithoutColor ? 8 : 0)
    }

    @ViewBuilder
    private var blocksColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("BLOCKS")
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
                .tracking(1.2)

            Text("\(summary.blocks.count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)

            Text("\(summary.meaningfulAwakeningCount) break\(summary.meaningfulAwakeningCount == 1 ? "" : "s")")
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    @ViewBuilder
    private var timelineBar: some View {
        let sessionStart = session.inBedStartDate ?? session.startDate
        let sessionEnd = session.inBedEndDate ?? session.endDate
        let totalDuration = max(sessionEnd.timeIntervalSince(sessionStart), 1)

        let block = bestBlock ?? SleepContinuityBlock(index: 0, startDate: sessionStart, endDate: sessionEnd, sleepDuration: 0)
        let startOffset = block.startDate.timeIntervalSince(sessionStart)
        let blockDur = summary.longestBlockDuration

        let startRatio = max(0.0, min(1.0, startOffset / totalDuration))
        let widthRatio = max(0.0, min(1.0 - startRatio, blockDur / totalDuration))

        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return f
        }()

        VStack(spacing: BetterSpacing.small) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 14)

                    // Highlights the longest block
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [categoryColor, categoryColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * widthRatio, height: 14)
                        .offset(x: geo.size.width * startRatio)
                }
            }
            .frame(height: 14)

            HStack {
                Text(formatter.string(from: sessionStart))
                    .font(BetterTypography.micro.monospacedDigit())
                    .foregroundStyle(BetterColors.mutedText)

                Spacer()

                Text(formatter.string(from: sessionEnd))
                    .font(BetterTypography.micro.monospacedDigit())
                    .foregroundStyle(BetterColors.mutedText)
            }
        }
    }

    @ViewBuilder
    private var insightRow: some View {
        HStack(spacing: BetterSpacing.medium) {
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 3)
                .overlay {
                    if differentiateWithoutColor {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    }
                }

            Text(category.userMessage)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32, alignment: .leading)
    }

    @ViewBuilder
    private var blockListView: some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return f
        }()

        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            // Dashed Divider line
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(
                    BetterColors.border.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            .frame(height: 1)
            .padding(.vertical, BetterSpacing.xSmall)

            ForEach(summary.blocks.sorted(by: { $0.index < $1.index })) { block in
                let isLongest = block.index == summary.longestBlockIndex

                HStack(spacing: BetterSpacing.small) {
                    Circle()
                        .fill(isLongest ? categoryColor : BetterColors.subtext.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .overlay {
                            if differentiateWithoutColor {
                                Circle()
                                    .stroke(isLongest ? Color.white.opacity(0.85) : BetterColors.subtext, lineWidth: 1)
                            }
                        }

                    Text("\(formatter.string(from: block.startDate)) → \(formatter.string(from: block.endDate))")
                        .font(BetterTypography.footnote.monospacedDigit())
                        .foregroundStyle(isLongest ? BetterColors.text : BetterColors.subtext)

                    Spacer()

                    Text(formatBlockDuration(block.sleepDuration))
                        .font(BetterTypography.footnote.bold().monospacedDigit())
                        .foregroundStyle(isLongest ? categoryColor : BetterColors.subtext)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func formatBlockDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var categorySymbol: String {
        switch category {
        case .exceptional, .strong:
            return "+"
        case .good:
            return "."
        case .moderatelyFragmented:
            return "!"
        case .highlyFragmented:
            return "x"
        case .unavailable:
            return "?"
        }
    }

    private var accessibilitySummary: String {
        guard summary.longestBlockDuration > 0 else {
            return "No uninterrupted sleep block is available."
        }
        return "\(formatBlockDuration(summary.longestBlockDuration)), \(shortCategoryDisplayName.lowercased()). \(summary.blocks.count) blocks, \(summary.meaningfulAwakeningCount) breaks. \(category.userMessage)"
    }
}
