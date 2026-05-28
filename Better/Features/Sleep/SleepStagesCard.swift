import SwiftUI

/// "Sleep Stages" card. Combines the sleep hypnogram timeline with
/// the interactive Sleep Stages Stacked Bar and legend grid.
///
/// Tap any segment of the horizontal stacked bar or any legend chip to open the history sheet.
struct SleepStagesCard: View {
    let session: SleepSession
    let baseline: SleepBaseline?
    let recentSessions: [SleepSession]

    @State private var selectedStageDetail: SleepStageKind? = nil



    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {

            // 1. Sleep Hypnogram Timeline (continuous line chart)
            // Use displayWakeDate so the hypnogram x-axis ends at the same
            // wake time shown in the hero chip (inBedEndDate ?? endDate). (Bug A2)
            SleepHypnogramView(
                stages: session.stages.filter { $0.type != .inBed },
                sessionStart: session.startDate,
                sessionEnd: session.displayWakeDate
            )

            // 2. Interactive Sleep Stages Stacked Bar Chart
            SleepStagesStackedBar(session: session, baseline: baseline, selectedStageDetail: $selectedStageDetail)
                .padding(.vertical, BetterSpacing.small)

            // 3. 2x2 Interactive Legend Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                LegendChip(kind: .awake, duration: session.awakeDuration, color: BetterColors.stageAwake) {
                    selectedStageDetail = .awake
                }
                LegendChip(kind: .light, duration: session.coreDuration, color: BetterColors.stageCore) {
                    selectedStageDetail = .light
                }
                LegendChip(kind: .deep, duration: session.deepDuration, color: BetterColors.stageDeep) {
                    selectedStageDetail = .deep
                }
                LegendChip(kind: .rem, duration: session.remDuration, color: BetterColors.stageREM) {
                    selectedStageDetail = .rem
                }
            }

            // 4. Full-width Latency interactive row
            if baseline != nil {
                Button {
                    selectedStageDetail = .latency
                } label: {
                    HStack {
                        Circle().fill(BetterColors.subtext.opacity(0.5)).frame(width: 8, height: 8)
                        Text("Fall asleep")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                        Spacer()
                        Text(SleepStagesCard.formatHHMM(session.sleepLatency))
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(BetterColors.text)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BetterColors.mutedText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#0E0E12"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .sheet(item: $selectedStageDetail) { kind in
            SleepStageDetailSheet(
                kind: kind,
                session: session,
                baseline: baseline,
                recentSessions: recentSessions
            )
        }
    }


}

// MARK: - Sleep Stage Kind Definition

enum SleepStageKind: String, CaseIterable, Identifiable, Hashable {
    case awake, light, deep, rem, latency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake:   return "Awake"
        case .light:   return "Light"
        case .deep:    return "Deep"
        case .rem:     return "REM"
        case .latency: return "Fall asleep"
        }
    }

    var color: Color {
        switch self {
        case .awake:   return BetterColors.stageAwake
        case .light:   return BetterColors.stageCore
        case .deep:    return BetterColors.stageDeep
        case .rem:     return BetterColors.stageREM
        case .latency: return BetterColors.subtext.opacity(0.6)
        }
    }

    var lowerIsBetter: Bool {
        self == .awake || self == .latency
    }

    var isAwakeMetric: Bool { self == .awake }

    var maxSeconds: Double {
        switch self {
        case .awake:   return 5400  // 1.5 hours
        case .light:   return 21600 // 6 hours
        case .deep:    return 10800 // 3 hours
        case .rem:     return 10800 // 3 hours
        case .latency: return 3600  // 1 hour
        }
    }
}

// MARK: - Legend Chip Button

private struct LegendChip: View {
    let kind: SleepStageKind
    let duration: TimeInterval
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(SleepStagesCard.formatHHMM(duration))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BetterColors.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: "#0E0E12"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sleep Stages Stacked Bar Chart

struct BarSegmentData: Identifiable {
    let id: SleepStageKind
    let actualDuration: TimeInterval
    let baselineDuration: TimeInterval?
    let color: Color
}

struct SleepStagesStackedBar: View {
    let session: SleepSession
    let baseline: SleepBaseline?
    @Binding var selectedStageDetail: SleepStageKind?

    private func actualDuration(for stage: SleepStageKind) -> TimeInterval {
        switch stage {
        case .awake:   return session.awakeDuration
        case .light:   return session.coreDuration
        case .deep:    return session.deepDuration
        case .rem:     return session.remDuration
        case .latency: return session.sleepLatency
        }
    }

    private func baselineDuration(for stage: SleepStageKind) -> TimeInterval? {
        guard let baseline else { return nil }
        switch stage {
        case .awake:   return baseline.wasoAverage
        case .light:   return max(0, baseline.totalSleepAverage - baseline.deepAverage - baseline.remAverage)
        case .deep:    return baseline.deepAverage
        case .rem:     return baseline.remAverage
        case .latency: return baseline.latencyAverage
        }
    }

    private var segments: [BarSegmentData] {
        let kinds: [SleepStageKind] = [.awake, .light, .deep, .rem]
        return kinds.compactMap { kind -> BarSegmentData? in
            let actual = actualDuration(for: kind)
            let base = baselineDuration(for: kind)
            
            // Only include if actual > 0 to prevent 0-width segments
            if actual > 0 {
                return BarSegmentData(
                    id: kind,
                    actualDuration: actual,
                    baselineDuration: base,
                    color: kind.color
                )
            }
            return nil
        }
    }

    private var totalWeight: Double {
        let sum = segments.reduce(0.0) { sum, segment in
            sum + segment.actualDuration
        }
        return max(sum, 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let spacing: CGFloat = 6
            let visibleCount = CGFloat(segments.count)
            let totalSpacing = visibleCount > 1 ? (visibleCount - 1) * spacing : 0
            let availableW = max(w - totalSpacing, 0)
            let totWeight = totalWeight

            // Determine whether any segment is wide enough for inline deltas
            let widestCol = segments.map { availableW * CGFloat($0.actualDuration / totWeight) }.max() ?? 0
            let useInlineDeltas = widestCol >= 60

            VStack(spacing: 0) {
                HStack(spacing: spacing) {
                    ForEach(segments) { segment in
                        let colW = availableW * CGFloat(segment.actualDuration / totWeight)
                        let isActive = selectedStageDetail == segment.id

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                selectedStageDetail = segment.id
                            }
                        } label: {
                            // Fix 2: Bar block with labels + optional inline delta chip INSIDE
                            ZStack(alignment: .center) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [segment.color, segment.color.opacity(0.88)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(isActive ? 0.9 : 0.0), lineWidth: 1.5)
                                    )
                                    .shadow(color: segment.color.opacity(isActive ? 0.45 : 0.0), radius: 5)

                                // Fix 1: Always show a stage identifier in every visible segment
                                let percentage = Int((segment.actualDuration / totWeight * 100).rounded())
                                let initial = stageInitial(for: segment.id)
                                let labelColor: Color = .white

                                if colW >= 70 {
                                    // Wide: full name + percent, optional inline delta below
                                    VStack(spacing: 2) {
                                        Text("\(segment.id.title) \(percentage)%")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(labelColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.9)
                                            .padding(.horizontal, 4)

                                        // Fix 2: inline delta chip when colW >= 60
                                        if useInlineDeltas, let base = segment.baselineDuration {
                                            let diff = segment.actualDuration - base
                                            let absDiff = abs(diff)
                                            if absDiff >= 60 {
                                                let sign = diff > 0 ? "+" : "−"
                                                Text("\(sign)\(SleepStagesCard.formatHHMM(absDiff))")
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundStyle(labelColor)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }
                                        }
                                    }
                                } else if colW >= 45 {
                                    // Medium: initial + percent stacked, optional inline delta
                                    VStack(spacing: 2) {
                                        VStack(spacing: 1) {
                                            Text(initial)
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                            Text("\(percentage)%")
                                                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                        }
                                        .foregroundStyle(labelColor)

                                        if useInlineDeltas, let base = segment.baselineDuration {
                                            let diff = segment.actualDuration - base
                                            let absDiff = abs(diff)
                                            if absDiff >= 60 && colW >= 60 {
                                                let sign = diff > 0 ? "+" : "−"
                                                Text("\(sign)\(SleepStagesCard.formatHHMM(absDiff))")
                                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                                    .foregroundStyle(labelColor)
                                                    .padding(.horizontal, 3)
                                                    .padding(.vertical, 1)
                                                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }
                                        }
                                    }
                                } else if colW >= 25 {
                                    // Narrow: show percentage only — color communicates the stage,
                                    // and the 2×2 legend grid below provides full names.
                                    Text("\(percentage)%")
                                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(labelColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .padding(.horizontal, 2)
                                } else {
                                    // Very narrow: omit text entirely — legend handles it
                                    EmptyView()
                                }
                            }
                            .frame(height: 40)
                        }
                        .buttonStyle(.plain)
                        .frame(width: colW)
                        .scaleEffect(isActive ? 1.03 : 1.0)
                        .zIndex(isActive ? 1 : 0)
                    }
                }

                // Fix 2: below-bar dot-chip row when segments are too narrow for inline deltas
                if !useInlineDeltas {
                    HStack(spacing: 8) {
                        ForEach(segments) { segment in
                            if let base = segment.baselineDuration {
                                let diff = segment.actualDuration - base
                                let absDiff = abs(diff)
                                if absDiff >= 60 {
                                    let sign = diff > 0 ? "+" : "−"
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(segment.color)
                                            .frame(width: 5, height: 5)
                                        Text("\(sign)\(SleepStagesCard.formatHHMM(absDiff))")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(BetterColors.subtext)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(height: 64)
    }

    // Fix 1: stage initials helper
    private func stageInitial(for kind: SleepStageKind) -> String {
        switch kind {
        case .awake:   return "A"
        case .light:   return "L"
        case .deep:    return "D"
        case .rem:     return "R"
        case .latency: return "Z"
        }
    }

    /// Color-coded baseline comparison text per critical invariant rules:
    /// Deep & REM: green if increased, danger if decreased.
    /// Awake: green if decreased, orange if increased.
    /// Light: neutral subtext.
    private func baselineTextColor(for segment: BarSegmentData, diff: TimeInterval) -> Color {
        switch segment.id {
        case .deep, .rem:
            return diff > 0 ? BetterColors.success : BetterColors.danger
        case .awake:
            return diff < 0 ? BetterColors.success : BetterColors.stageAwake
        case .light, .latency:
            return BetterColors.subtext
        }
    }

}

// MARK: - Detailed Popup Sheet

struct SleepStageDetailSheet: View {
    let kind: SleepStageKind
    let session: SleepSession
    let baseline: SleepBaseline?
    let recentSessions: [SleepSession]
    
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch kind {
        case .awake:   return "Awake Time"
        case .light:   return "Light Sleep"
        case .deep:    return "Deep Sleep"
        case .rem:     return "REM Sleep"
        case .latency: return "Time to Fall Asleep"
        }
    }

    private var sessionSeconds: TimeInterval {
        switch kind {
        case .awake:   return session.awakeDuration
        case .light:   return session.coreDuration
        case .deep:    return session.deepDuration
        case .rem:     return session.remDuration
        case .latency: return session.sleepLatency
        }
    }

    private var baselineAvgSeconds: Double? {
        guard let baseline else { return nil }
        switch kind {
        case .awake: return baseline.wasoAverage
        case .light: return baseline.totalSleepAverage - baseline.deepAverage - baseline.remAverage
        case .deep:  return baseline.deepAverage
        case .rem:   return baseline.remAverage
        case .latency: return baseline.latencyAverage
        }
    }

    private var deltaLabel: String? {
        guard let avg = baselineAvgSeconds, avg > 0 else { return nil }
        let diff = sessionSeconds - avg
        let sign = diff > 0 ? "+" : "-"
        return "\(sign)\(SleepStagesCard.formatHHMM(abs(diff)))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header Stats Block
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TONIGHT")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.mutedText)
                                .tracking(1.5)
                            Text(SleepStagesCard.formatHHMM(sessionSeconds))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)
                        }
                        
                        if let deltaLabel, let avg = baselineAvgSeconds {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("VS USUAL (\(SleepStagesCard.formatHHMM(avg)))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(BetterColors.mutedText)
                                    .tracking(1.2)
                                Text(deltaLabel)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(sessionSeconds > avg ? (kind.lowerIsBetter ? BetterColors.warning : BetterColors.success) : (kind.lowerIsBetter ? BetterColors.success : BetterColors.warning))
                            }
                            .padding(.bottom, 4)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, BetterSpacing.large)
                    
                    // Detailed Trend Line Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LAST 14 DAYS TREND")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                            .tracking(1.5)
                            .padding(.horizontal, BetterSpacing.large)
                        
                        StageHistoryLineChart(
                            sessions: recentSessions,
                            kind: kind,
                            baselinePct: baselineDisplay,
                            accent: kind.color
                        )
                        .frame(height: 200)
                        .padding(BetterSpacing.large)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.horizontal, BetterSpacing.large)
                    }
                    
                    // Explanatory info card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(kind.color)
                            Text(aboutTitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)
                        }
                        Text(aboutDescription)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(BetterSpacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#0E0E12"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.04), lineWidth: 1))
                    .padding(.horizontal, BetterSpacing.large)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brandLight)
                }
            }
        }
    }

    private var baselineDisplay: Double? {
        guard let avg = baselineAvgSeconds, let baseline else { return nil }
        if kind == .latency { return avg / 60 }
        let denom = max(baseline.totalSleepAverage + baseline.wasoAverage, 1)
        return avg / denom * 100
    }

    private var aboutTitle: String {
        switch kind {
        case .awake:   return "Why Awake Time Matters"
        case .light:   return "The Role of Light Sleep"
        case .deep:    return "The Power of Deep Sleep"
        case .rem:     return "Why REM Sleep is Essential"
        case .latency: return "About Sleep Latency"
        }
    }

    private var aboutDescription: String {
        switch kind {
        case .awake:
            return "Waking up briefly is normal, but high awake durations fragment sleep quality. Reducing WASO (wake after sleep onset) supports cardiac and nervous system recovery."
        case .light:
            return "Light sleep covers the majority of the night. It plays a key role in memory consolidation, cellular maintenance, and preparing the brain for deep and REM sleep stages."
        case .deep:
            return "Deep sleep is physical restoration. Growth hormone is secreted, muscle tissues repair, and waste is cleared from the brain. Increasing deep sleep boosts daytime energy."
        case .rem:
            return "REM sleep is when vivid dreaming occurs. It is critical for emotional regulation, cognitive processing, problem solving, and long-term memory formation."
        case .latency:
            return "Sleep latency is the time it takes to fall asleep. Normal latency is between 10 to 20 minutes. Falling asleep too quickly or too slowly can indicate sleep debt or stress."
        }
    }
}

// MARK: - Detailed Trend Line Chart

struct StageHistoryLineChart: View {
    let sessions: [SleepSession]
    let kind: SleepStageKind
    let baselinePct: Double?
    let accent: Color

    @State private var scrubIndex: Int? = nil
    @State private var chartWidth: CGFloat = 1

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        let recent = sessions.suffix(14)
        return recent.enumerated().map { idx, session in
            Point(id: idx, date: session.startDate, value: value(for: session))
        }
    }

    private func value(for session: SleepSession) -> Double {
        switch kind {
        case .latency:
            return session.sleepLatency / 60
        default:
            let denom = max(session.totalSleepTime + session.awakeDuration, 1)
            let secs: TimeInterval = {
                switch kind {
                case .awake: return session.awakeDuration
                case .light: return session.coreDuration
                case .deep:  return session.deepDuration
                case .rem:   return session.remDuration
                case .latency: return 0
                }
            }()
            return secs / denom * 100
        }
    }

    private var range: (lo: Double, hi: Double) {
        let values = points.map(\.value)
        let lo = (values.min() ?? 0)
        let hi = max(values.max() ?? 1, lo + 1)
        var bottom = min(lo, baselinePct ?? lo) * 0.85
        var top = max(hi, baselinePct ?? hi) * 1.15
        if bottom < 0 { bottom = 0 }
        if top - bottom < 5 { top = bottom + 5 }
        return (bottom, top)
    }

    var body: some View {
        if points.isEmpty {
            VStack {
                Spacer()
                Text("Need a few more nights to chart your history.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.mutedText)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geo in
                let size = geo.size
                let (lo, hi) = range
                let stepX = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
                
                let xPos: (Int) -> CGFloat = { i in
                    CGFloat(i) * stepX
                }
                
                let yPos: (Double) -> CGFloat = { val in
                    let t = (val - lo) / (hi - lo)
                    return size.height - CGFloat(t) * size.height
                }

                ZStack(alignment: .topLeading) {
                    // Grid background lines (horizontal guides)
                    Path { p in
                        for index in 0...4 {
                            let y = size.height * CGFloat(index) / 4
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.025), lineWidth: 1)

                    // Usual baseline guide
                    if let baselinePct, baselinePct >= lo, baselinePct <= hi {
                        let y = yPos(baselinePct)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        
                        Text("usual \(Int(baselinePct.rounded()))\(kind == .latency ? "m" : "%")")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .padding(.horizontal, 4)
                            .background(Color(hex: "#0F0F11"))
                            .offset(x: 4, y: max(0, y - 13))
                    }

                    // Area fill under the trend line
                    areaPath(size: size, yPos: yPos, xPos: xPos)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.18), accent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Smooth line graph
                    linePath(size: size, yPos: yPos, xPos: xPos)
                        .stroke(
                            LinearGradient(
                                colors: [accent.opacity(0.6), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    // Points on the line
                    ForEach(points) { pt in
                        Circle()
                            .fill(scrubIndex == pt.id ? Color.white : accent)
                            .frame(width: scrubIndex == pt.id ? 8 : 4, height: scrubIndex == pt.id ? 8 : 4)
                            .shadow(color: accent.opacity(0.5), radius: 2)
                            .position(x: xPos(pt.id), y: yPos(pt.value))
                    }

                    // Scrub line and tooltip popup
                    if let idx = scrubIndex, idx >= 0, idx < points.count {
                        let p = points[idx]
                        let x = xPos(p.id)
                        let y = yPos(p.value)
                        
                        // Scrubber line
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: size.height)
                            .position(x: x, y: size.height / 2)
                        
                        // Highlighted dot
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: accent, radius: 4)
                            .position(x: x, y: y)

                        let label = kind == .latency
                            ? "\(Int(p.value.rounded()))m"
                            : "\(Int(p.value.rounded()))%"
                        
                        VStack(spacing: 2) {
                            Text(label)
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(BetterColors.text)
                            Text(dateLabel(p.date))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(accent.opacity(0.4), lineWidth: 1))
                        .offset(x: min(max(x - 30, 0), size.width - 60), y: min(max(y - 45, 0), size.height - 45))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !points.isEmpty else { return }
                            let rel = value.location.x
                            let raw = stepX > 0 ? Int((rel / stepX).rounded()) : 0
                            scrubIndex = min(max(raw, 0), points.count - 1)
                            chartWidth = size.width
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.4)) { scrubIndex = nil }
                        }
                )
            }
        }
    }

    private func linePath(size: CGSize, yPos: (Double) -> CGFloat, xPos: (Int) -> CGFloat) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            path.move(to: CGPoint(x: xPos(0), y: yPos(points[0].value)))
            for pt in points.dropFirst() {
                path.addLine(to: CGPoint(x: xPos(pt.id), y: yPos(pt.value)))
            }
        }
    }

    private func areaPath(size: CGSize, yPos: (Double) -> CGFloat, xPos: (Int) -> CGFloat) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            path.move(to: CGPoint(x: xPos(0), y: size.height))
            for pt in points {
                path.addLine(to: CGPoint(x: xPos(pt.id), y: yPos(pt.value)))
            }
            path.addLine(to: CGPoint(x: xPos(points.count - 1), y: size.height))
            path.closeSubpath()
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - utilities

extension SleepStagesCard {
    static func formatHHMM(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        if total >= 60 { return "\(total / 60)h \(total % 60)m" }
        return "\(total)m"
    }
}
