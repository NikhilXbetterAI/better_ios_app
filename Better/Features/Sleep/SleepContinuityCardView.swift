import SwiftUI

struct SleepContinuityCardView: View {
    let summary: SleepContinuitySummary
    let restorativeSleepDuration: TimeInterval

    @State private var selectedBlockIndex: Int? = nil

    private var effectiveSelectedBlockIndex: Int? {
        selectedBlockIndex ?? summary.longestBlockIndex ?? summary.blocks.first?.index
    }

    private var longestBlock: SleepContinuityBlock? {
        guard let index = summary.longestBlockIndex else { return nil }
        return summary.blocks.first { $0.index == index }
    }

    private var categoryColor: Color {
        switch summary.continuityCategory {
        case .unavailable:
            BetterColors.mutedText
        case .exceptional:
            BetterColors.success
        case .strong:
            BetterColors.brandLight
        case .good:
            BetterColors.stageDeep
        case .moderatelyFragmented:
            BetterColors.warning
        case .highlyFragmented:
            BetterColors.stageAwake
        }
    }

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                header
                primaryMetric

                if summary.blocks.isEmpty {
                    unavailableState
                } else {
                    SleepContinuityTimelineView(
                        blocks: summary.blocks,
                        selectedBlockIndex: effectiveSelectedBlockIndex,
                        longestBlockIndex: summary.longestBlockIndex,
                        accentColor: categoryColor,
                        onSelectBlock: { selectBlock($0) }
                    )
                    blockDetails
                    footerInsight
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sleep continuity")
        .onAppear(perform: syncSelectionIfNeeded)
        .onChange(of: summary.blocks) { _ in
            syncSelectionIfNeeded()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: selectedBlockIndex)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: BetterSpacing.small) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(categoryColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep continuity")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Longest uninterrupted recovery stretch")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer(minLength: BetterSpacing.small)

            Text(summary.continuityCategory.displayName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(categoryColor)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(categoryColor.opacity(0.13), in: Capsule())
                .accessibilityLabel(summary.continuityCategory.displayName)
        }
    }

    private var primaryMetric: some View {
        HStack(alignment: .lastTextBaseline, spacing: BetterSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Longest uninterrupted sleep block")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                Text(summary.blocks.isEmpty ? "--" : formatDuration(summary.longestBlockDuration))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .accessibilityLabel(primaryAccessibilityLabel)
            }

            Spacer(minLength: BetterSpacing.small)

            VStack(alignment: .trailing, spacing: 4) {
                Text("REM + Deep")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                Text(formatDuration(restorativeSleepDuration))
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.stageDeep)
                    .lineLimit(1)
            }
        }
    }

    private var blockDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(summary.blocks) { block in
                SleepContinuityBlockDetailRow(
                    block: block,
                    isSelected: block.index == effectiveSelectedBlockIndex,
                    isLongest: block.index == summary.longestBlockIndex,
                    accentColor: block.index == summary.longestBlockIndex ? categoryColor : BetterColors.brand,
                    onTap: { selectBlock(block.index) }
                )
            }
        }
    }

    private var unavailableState: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BetterColors.mutedText)
            Text(summary.continuityCategory.userMessage)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.cardSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footerInsight: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: summary.meaningfulAwakeningCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(categoryColor)
                .padding(.top, 1)

            Text(insightText)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var insightText: String {
        guard let longestBlock else {
            return summary.continuityCategory.userMessage
        }

        let prefix = "Block \(longestBlock.index) held for \(formatDuration(longestBlock.sleepDuration))."
        if summary.meaningfulAwakeningCount > 0 {
            return "\(prefix) \(summary.continuityCategory.userMessage)"
        }
        return "\(prefix) No meaningful interruptions split this sleep session."
    }

    private var primaryAccessibilityLabel: String {
        if summary.blocks.isEmpty {
            return "Longest uninterrupted sleep block unavailable. \(summary.continuityCategory.userMessage)"
        }
        return "Longest uninterrupted sleep block, \(accessibleDuration(summary.longestBlockDuration))"
    }

    private func selectBlock(_ index: Int) {
        guard summary.blocks.contains(where: { $0.index == index }) else { return }
        selectedBlockIndex = index
    }

    private func syncSelectionIfNeeded() {
        guard !summary.blocks.isEmpty else {
            selectedBlockIndex = nil
            return
        }

        let validIndices = Set(summary.blocks.map(\.index))
        if let selectedBlockIndex, validIndices.contains(selectedBlockIndex) {
            return
        }

        selectedBlockIndex = summary.longestBlockIndex ?? summary.blocks.first?.index
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func accessibleDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hours" }
        return "\(hours) hours \(minutes) minutes"
    }
}

private struct SleepContinuityTimelineView: View {
    let blocks: [SleepContinuityBlock]
    let selectedBlockIndex: Int?
    let longestBlockIndex: Int?
    let accentColor: Color
    let onSelectBlock: (Int) -> Void

    private var startDate: Date? { blocks.first?.startDate }
    private var endDate: Date? { blocks.last?.endDate }

    private var totalDuration: TimeInterval {
        guard let startDate, let endDate else { return 0 }
        return max(endDate.timeIntervalSince(startDate), 1)
    }

    private var selectedOrLongestIndex: Int? {
        selectedBlockIndex ?? longestBlockIndex
    }

    private var segments: [TimelineSegment] {
        var items: [TimelineSegment] = []
        for (index, block) in blocks.enumerated() {
            items.append(.block(block))
            if index < blocks.count - 1 {
                let nextBlock = blocks[index + 1]
                let gapDuration = max(0, nextBlock.startDate.timeIntervalSince(block.endDate))
                items.append(.gap(
                    id: "gap-\(block.index)-\(nextBlock.index)",
                    previousIndex: block.index,
                    nextIndex: nextBlock.index,
                    duration: gapDuration
                ))
            }
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bedtime \(formattedTime(startDate))")
                Spacer(minLength: BetterSpacing.small)
                Text("Wake \(formattedTime(endDate))")
            }
            .font(BetterTypography.micro)
            .foregroundStyle(BetterColors.subtext)

            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width - 8, 1)
                let layout = timelineLayout(trackWidth: trackWidth)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(layout.segments) { segment in
                            switch segment.kind {
                            case .block(let block):
                                SleepContinuityTimelineBlock(
                                    block: block,
                                    width: segment.width,
                                    isSelected: block.index == selectedOrLongestIndex,
                                    isLongest: block.index == longestBlockIndex,
                                    accentColor: block.index == longestBlockIndex ? accentColor : BetterColors.brand,
                                    onTap: { onSelectBlock(block.index) }
                                )
                            case .gap(let gap):
                                SleepContinuityTimelineGap(
                                    gap: gap,
                                    width: segment.width,
                                    onTap: nil
                                )
                            }
                        }
                    }
                    .frame(width: max(trackWidth, layout.totalWidth), alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 58)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sleep continuity timeline from bedtime to wake time")
        }
        .padding(12)
        .background(BetterColors.cardSecondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.border.opacity(0.6), lineWidth: 1)
        )
    }

    private func timelineLayout(trackWidth: CGFloat) -> TimelineLayout {
        guard !segments.isEmpty else {
            return TimelineLayout(segments: [], totalWidth: trackWidth)
        }

        var laidOut: [TimelineVisualSegment] = []
        for segment in segments {
            let duration = segment.duration
            let rawWidth = max(1, CGFloat(duration / totalDuration) * trackWidth)
            let minWidth: CGFloat
            switch segment.kind {
            case .block:
                minWidth = 16
            case .gap:
                minWidth = 10
            }
            let width = max(minWidth, rawWidth)
            laidOut.append(TimelineVisualSegment(kind: segment.kind, width: width))
        }

        let totalWidth = laidOut.reduce(0) { $0 + $1.width } + CGFloat(max(0, laidOut.count - 1)) * 8
        return TimelineLayout(segments: laidOut, totalWidth: totalWidth)
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct SleepContinuityTimelineBlock: View {
    let block: SleepContinuityBlock
    let width: CGFloat
    let isSelected: Bool
    let isLongest: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isLongest ? [accentColor, accentColor.opacity(0.55)] : [accentColor.opacity(0.85), accentColor.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width, height: 18)
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 1.2)
                    )
                    .shadow(color: isLongest ? accentColor.opacity(0.45) : .clear, radius: isLongest ? 8 : 0, x: 0, y: 0)

                Text(formatDuration(block.sleepDuration))
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? BetterColors.text : BetterColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: max(width, 44), alignment: .leading)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timelineAccessibilityLabel)
    }

    private var timelineAccessibilityLabel: String {
        var parts = ["Block \(block.index), \(accessibleDuration(block.sleepDuration))"]
        if isLongest {
            parts.append("longest uninterrupted sleep block")
        }
        return parts.joined(separator: ", ")
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func accessibleDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hours" }
        return "\(hours) hours \(minutes) minutes"
    }
}

private struct SleepContinuityTimelineGap: View {
    let gap: TimelineGap
    let width: CGFloat
    let onTap: (() -> Void)?

    var body: some View {
        let gapView = VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(BetterColors.stageAwake.opacity(0.86))
                .frame(width: width, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BetterColors.stageAwake.opacity(0.24), lineWidth: 1)
                )

            if width >= 30 {
                Text(formatDuration(gap.duration))
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.stageAwake)
                    .lineLimit(1)
            }
        }
        .frame(width: max(width, 10), alignment: .center)

        if let onTap {
            Button(action: onTap) {
                gapView
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Meaningful interruption between Block \(gap.previousIndex) and Block \(gap.nextIndex), \(accessibleDuration(gap.duration))")
        } else {
            gapView
                .accessibilityLabel("Meaningful interruption between Block \(gap.previousIndex) and Block \(gap.nextIndex), \(accessibleDuration(gap.duration))")
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func accessibleDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hours" }
        return "\(hours) hours \(minutes) minutes"
    }
}

private struct SleepContinuityBlockDetailRow: View {
    let block: SleepContinuityBlock
    let isSelected: Bool
    let isLongest: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Block \(block.index)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)

                    if isLongest {
                        Text("Longest")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.14), in: Capsule())
                    }

                    Spacer(minLength: BetterSpacing.small)

                    Text(formatDuration(block.sleepDuration))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isSelected ? accentColor : BetterColors.subtext)
                }

                if isSelected {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formattedTime(block.startDate)) - \(formattedTime(block.endDate))")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.text)

                        Text(briefWakeText)
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("This stretch stayed intact because no awake period reached 5 minutes.")
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? accentColor.opacity(0.10) : BetterColors.cardSecondary.opacity(0.55)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.24) : BetterColors.border.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var briefWakeText: String {
        guard block.shortAwakeningCount > 0 else {
            return "No brief wakes were counted inside this block."
        }

        let wakeWord = block.shortAwakeningCount == 1 ? "brief wake" : "brief wakes"
        let durationText = block.includedShortAwakeDuration > 0 ? " (\(formatDuration(block.includedShortAwakeDuration)))" : ""
        return "\(block.shortAwakeningCount) \(wakeWord) ignored inside this block\(durationText)."
    }

    private var accessibilityLabel: String {
        var label = "Block \(block.index), \(accessibleDuration(block.sleepDuration))"
        if isLongest {
            label += ", longest uninterrupted sleep block"
        }
        if isSelected {
            label += ", expanded"
        }
        return label
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func accessibleDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hours" }
        return "\(hours) hours \(minutes) minutes"
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TimelineLayout {
    let segments: [TimelineVisualSegment]
    let totalWidth: CGFloat
}

private struct TimelineVisualSegment: Identifiable {
    let kind: TimelineSegmentKind
    let width: CGFloat

    var id: String {
        switch kind {
        case .block(let block):
            return "block-\(block.id.uuidString)"
        case .gap(let gap):
            return gap.id
        }
    }
}

private enum TimelineSegmentKind {
    case block(SleepContinuityBlock)
    case gap(TimelineGap)
}

private enum TimelineSegment: Identifiable {
    case block(SleepContinuityBlock)
    case gap(id: String, previousIndex: Int, nextIndex: Int, duration: TimeInterval)

    var id: String {
        switch self {
        case .block(let block):
            return "block-\(block.id.uuidString)"
        case .gap(let id, _, _, _):
            return id
        }
    }

    var duration: TimeInterval {
        switch self {
        case .block(let block):
            return block.sleepDuration
        case .gap(_, _, _, let duration):
            return duration
        }
    }

    var kind: TimelineSegmentKind {
        switch self {
        case .block(let block):
            return .block(block)
        case .gap(let id, let previousIndex, let nextIndex, let duration):
            return .gap(TimelineGap(id: id, previousIndex: previousIndex, nextIndex: nextIndex, duration: duration))
        }
    }
}

private struct TimelineGap {
    let id: String
    let previousIndex: Int
    let nextIndex: Int
    let duration: TimeInterval
}

#if DEBUG
#Preview("Continuity - Fragmented") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepContinuityCardView(
            summary: SleepContinuitySummary(
                blocks: [
                    SleepContinuityBlock(index: 1, startDate: Date(), endDate: Date().addingTimeInterval(100 * 60), sleepDuration: 100 * 60, includedShortAwakeDuration: 4 * 60, shortAwakeningCount: 1),
                    SleepContinuityBlock(index: 2, startDate: Date().addingTimeInterval(110 * 60), endDate: Date().addingTimeInterval(195 * 60), sleepDuration: 85 * 60, includedShortAwakeDuration: 2 * 60, shortAwakeningCount: 1),
                    SleepContinuityBlock(index: 3, startDate: Date().addingTimeInterval(205 * 60), endDate: Date().addingTimeInterval(320 * 60), sleepDuration: 115 * 60, includedShortAwakeDuration: 0, shortAwakeningCount: 0),
                    SleepContinuityBlock(index: 4, startDate: Date().addingTimeInterval(336 * 60), endDate: Date().addingTimeInterval(436 * 60), sleepDuration: 100 * 60, includedShortAwakeDuration: 3 * 60, shortAwakeningCount: 1)
                ],
                longestBlockDuration: 115 * 60,
                longestBlockIndex: 3,
                meaningfulAwakeningCount: 3,
                continuityCategory: .highlyFragmented
            ),
            restorativeSleepDuration: 130 * 60
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Continuity - Strong") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepContinuityCardView(
            summary: SleepContinuitySummary(
                blocks: [
                    SleepContinuityBlock(index: 1, startDate: Date(), endDate: Date().addingTimeInterval(270 * 60), sleepDuration: 270 * 60, includedShortAwakeDuration: 7 * 60, shortAwakeningCount: 2),
                    SleepContinuityBlock(index: 2, startDate: Date().addingTimeInterval(285 * 60), endDate: Date().addingTimeInterval(375 * 60), sleepDuration: 90 * 60, includedShortAwakeDuration: 0, shortAwakeningCount: 0)
                ],
                longestBlockDuration: 270 * 60,
                longestBlockIndex: 1,
                meaningfulAwakeningCount: 1,
                continuityCategory: .strong
            ),
            restorativeSleepDuration: 155 * 60
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Continuity - Unavailable") {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepContinuityCardView(
            summary: .unavailable,
            restorativeSleepDuration: 0
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
