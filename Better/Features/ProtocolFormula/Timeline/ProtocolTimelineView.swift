import SwiftUI

struct ProtocolTimelineView: View {
    @Bindable var viewModel: ProtocolTimelineViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                summaryHeader
                if viewModel.cards.isEmpty {
                    emptyStateCard
                } else {
                    phaseRibbonSection
                    heatmapSection
                    versionCards
                    ProtocolCaveatFooter()
                }
            }
            .padding(BetterSpacing.screen)
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        BetterHealthCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total tracked")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .textCase(.uppercase)
                    Text("\(viewModel.totalNights) nights")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(BetterColors.text)
                    Text("\(viewModel.cards.count) versions")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .monospacedDigit()
                }
                Spacer()
                if let lift = viewModel.bestRestorativeLiftMin {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Best lift")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ProtocolPalette.mutedText)
                            .textCase(.uppercase)
                        DeltaBadge(value: lift, unit: "m", lowerIsBetter: false)
                            .font(.system(size: 20, weight: .bold))
                            .accessibilityLabel("Best restorative lift")
                            .accessibilityValue("\(Int(lift.rounded())) minutes vs baseline")
                        ProtocolCaveatFooter()
                    }
                }
            }
        }
    }

    // MARK: - Phase ribbon

    private var phaseRibbonSection: some View {
        let segments = viewModel.cards.compactMap { card -> PvPhaseRibbon.Segment? in
            guard card.loggedNightCount > 0 else { return nil }
            return PvPhaseRibbon.Segment(
                id: card.version.id,
                label: card.version.resolvedLabel,
                colorHex: card.version.colorHex,
                nights: card.loggedNightCount
            )
        }
        
        return Group {
            if !segments.isEmpty {
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("Phase distribution")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)
                    
                    BetterHealthCard {
                        PvPhaseRibbon(segments: segments)
                    }
                }
            }
        }
    }

    // MARK: - 30-day heatmap strip

    private var heatmapSection: some View {
        Group {
            if !viewModel.heatmap.isEmpty {
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("Last 30 nights")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)

                    BetterHealthCard {
                        VStack(alignment: .leading, spacing: BetterSpacing.small) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 1) {
                                    ForEach(viewModel.heatmap) { cell in
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(heatmapColor(for: cell))
                                            if let label = cell.versionLabel, let initial = label.first {
                                                Text(String(initial))
                                                    .font(.system(size: 8, weight: .black))
                                                    .foregroundStyle(Color.black.opacity(0.45))
                                            }
                                        }
                                        .frame(width: 10, height: 22)
                                        .accessibilityLabel(heatmapAccessibilityLabel(for: cell))
                                    }
                                }
                            }
                            heatmapLegend
                        }
                    }
                }
            }
        }
    }

    private var heatmapLegend: some View {
        let labels: [(label: String, hex: String)] = viewModel.cards.reduce(into: []) { acc, card in
            let label = card.version.resolvedLabel
            if !acc.contains(where: { $0.label == label }) {
                acc.append((label, card.version.colorHex))
            }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(labels, id: \.label) { entry in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ProtocolPalette.versionColor(hex: entry.hex))
                            .frame(width: 8, height: 8)
                        Text(entry.label)
                            .font(.caption2)
                            .foregroundStyle(ProtocolPalette.mutedText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Legend, version \(entry.label)")
                }
            }
            .padding(.top, 2)
        }
    }

    private func heatmapAccessibilityLabel(for cell: ProtocolTimelineViewModel.HeatmapCell) -> String {
        if let label = cell.versionLabel, let status = cell.status {
            return "Date \(cell.id), version \(label), \(status.displayLabel)"
        }
        return "Date \(cell.id), no log"
    }

    private func heatmapColor(for cell: ProtocolTimelineViewModel.HeatmapCell) -> Color {
        if let hex = cell.colorHex, cell.status == .taken {
            return ProtocolPalette.versionColor(hex: hex)
        }
        if cell.status == .skipped {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.08)
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.small) {
                Text("No nights logged yet")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text("Start logging from the Home screen to see your version timeline.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.medium)
        }
    }

    // MARK: - Vertical version cards

    private var versionCards: some View {
        ZStack(alignment: .leading) {
            // Connector line
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 2)
                .padding(.leading, 19)

            VStack(spacing: BetterSpacing.large) {
                ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                    versionCard(card, isCurrent: index == 0)
                }

                // Baseline card
                if let baseline = viewModel.baseline {
                    baselineCard(baseline)
                }
            }
        }
    }

    private func versionCard(_ card: ProtocolTimelineViewModel.VersionCard, isCurrent: Bool) -> some View {
        let version = card.version
        let color = ProtocolPalette.versionColor(hex: version.colorHex)
        let rollup = card.rollup
        
        return HStack(alignment: .top, spacing: 0) {
            // Node dot
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(ProtocolPalette.backgroundColor, lineWidth: 3)
                    )
                if isCurrent {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 4)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 40)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                // Header details
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(version.resolvedLabel)
                                .font(.system(size: 20, weight: .black))
                                .foregroundStyle(BetterColors.text)
                            if isCurrent {
                                Text("NOW")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(color))
                            }
                        }
                        
                        if !version.formulaText.isEmpty {
                            Text(version.formulaText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                                .lineLimit(2)
                        }
                        
                        if let range = card.firstDateKey.map({ viewModel.formattedDateRange(first: $0, last: card.lastDateKey) }) {
                            Text("\(range) · \(logSummary(for: card))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ProtocolPalette.dimText)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    
                    if let pct = rollup?.meanRestorativePctOfInBed {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f%%", pct))
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(BetterColors.text)
                                .monospacedDigit()
                            if let delta = card.restorativeDeltaMin {
                                DeltaBadge(value: delta, unit: "m", lowerIsBetter: false)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }
                }

                // Stage Bar + Metric cells
                if let rollup = rollup, rollup.nightCount >= 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                    
                    StageBar(
                        deepMin: rollup.meanDeepMin ?? 0,
                        remMin: rollup.meanRemMin ?? 0,
                        awakeMin: rollup.meanAwakeMin ?? 0,
                        totalSleepMin: rollup.meanTotalSleepMin ?? 0,
                        height: 10,
                        showLabels: true
                    )
                    let base = viewModel.baseline
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ProtocolMetricComparisonStrip(
                            metric: .deep,
                            yourValue: rollup.meanDeepMin,
                            baselineValue: base?.meanDeepMin,
                            compact: true
                        )
                        ProtocolMetricComparisonStrip(
                            metric: .rem,
                            yourValue: rollup.meanRemMin,
                            baselineValue: base?.meanRemMin,
                            compact: true
                        )
                        ProtocolMetricComparisonStrip(
                            metric: .awake,
                            yourValue: rollup.meanAwakeMin,
                            baselineValue: base?.meanAwakeMin,
                            compact: true
                        )
                        ProtocolMetricComparisonStrip(
                            metric: .duration,
                            yourValue: rollup.meanTotalSleepMin,
                            baselineValue: base?.meanTotalSleepMin,
                            compact: true
                        )
                    }
                } else {
                    Divider().overlay(Color.white.opacity(0.08))
                    logOnlyState(card)
                }

                // Add-in chips
                let addins = card.addins
                if !addins.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(addins) { addin in
                                Text("+ \(addin.name)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ProtocolPalette.addinColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(ProtocolPalette.addinColor.opacity(0.12)))
                                    .overlay(Capsule().stroke(ProtocolPalette.addinColor.opacity(0.35), lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .padding(BetterSpacing.medium)
            .background(
                isCurrent
                    ? LinearGradient(colors: [color.opacity(0.08), ProtocolPalette.surfaceColor],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [ProtocolPalette.surfaceColor], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isCurrent ? color.opacity(0.24) : ProtocolPalette.borderColor, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Version \(version.resolvedLabel)\(isCurrent ? ", current" : ""), \(logSummary(for: card))")
        }
    }

    private func baselineCard(_ baseline: ProtocolBaselineSnapshot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(ProtocolPalette.backgroundColor, lineWidth: 3))
                .frame(width: 40)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text("Baseline")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text("\(viewModel.formattedDateRange(first: Self.dateKey(from: baseline.windowStart), last: Self.dateKey(from: baseline.windowEnd))) · 90-day window · \(baseline.validNightCount) valid nights")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.dimText)
                if let mean = baseline.meanRestorativeMin {
                    Text("Average of \(Int(mean.rounded())) min restorative sleep. All version delta averages compare against this reference period.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProtocolPalette.mutedText)
                }
                if !baseline.hasExtendedMetrics {
                    Text("Missing metric fields: \(baseline.missingExtendedMetricLabels.joined(separator: ", "))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }
            .padding(BetterSpacing.medium)
            .background(ProtocolPalette.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        }
    }

    private func logSummary(for card: ProtocolTimelineViewModel.VersionCard) -> String {
        var parts: [String] = []
        if card.takenLogCount > 0 {
            parts.append("\(card.takenLogCount) taken")
        }
        if card.skippedLogCount > 0 {
            parts.append("\(card.skippedLogCount) skipped")
        }
        return parts.isEmpty ? "0 nights" : parts.joined(separator: ", ")
    }

    private func logOnlyState(_ card: ProtocolTimelineViewModel.VersionCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep data not matched yet")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(BetterColors.text)
            Text("Logged nights are on the timeline now. Metrics will attach when matching sleep sessions arrive.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ProtocolPalette.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep data not matched yet")
        .accessibilityValue(logSummary(for: card))
    }

    private static func dateKey(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }

    private func timelineMetricTile(label: String, value: Double?, delta: Double?, unit: String, lowerIsBetter: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            if let value {
                let hrs = Int(value) / 60
                let mins = Int(value) % 60
                let str = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
                Text(str)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(BetterColors.text)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
            
            if let delta, delta != 0 {
                let sign = delta > 0 ? "+" : ""
                let isGood = (delta > 0) != lowerIsBetter
                Text("\(sign)\(Int(delta.rounded()))\(unit) avg")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
            } else {
                Text("—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(metricAccessibilityValue(value: value, delta: delta, unit: unit))
    }

    private func metricAccessibilityValue(value: Double?, delta: Double?, unit: String) -> String {
        var parts: [String] = []
        if let value {
            parts.append("\(Int(value.rounded())) \(unit)")
        } else {
            parts.append("no data")
        }
        if let delta, delta != 0 {
            let sign = delta > 0 ? "plus" : "minus"
            parts.append("\(sign) \(Int(abs(delta).rounded())) \(unit) vs baseline")
        }
        return parts.joined(separator: ", ")
    }
}
