import SwiftUI

struct ProtocolFormulaHomeView: View {
    @Bindable var viewModel: ProtocolFormulaHomeViewModel
    let onOpenFormulaSetup: () -> Void
    let onOpenEditLog: () -> Void
    var onOpenTimeline: (() -> Void)? = nil
    var onOpenAllMetrics: (() -> Void)? = nil
    var onOpenVersionDive: (() -> Void)? = nil

    @State private var showAddinEditor: Bool = false
    @State private var impactDetailMetric: ProtocolFormulaMetric? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                // Header navigation & segment switcher
                HStack {
                    segmentedSwitch
                    Spacer()
                    EditAffordance(action: onOpenEditLog)
                }
                
                if viewModel.showFirstSwitchHint {
                    hintCard
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProtocolPalette.badColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ProtocolPalette.badColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProtocolPalette.badColor.opacity(0.2), lineWidth: 1))
                }
                
                if let active = viewModel.activeVersion {
                    switch viewModel.segment {
                    case .lastNight:
                        // HOME A: Last Night First (Morning Review)
                        lastNightHeroCard(active)
                        impactComparisonCard
                        tonightCompactCard(active)
                        trendSection
                        protocolSummarySection
                        quickNavRow

                    case .tonight:
                        // HOME B: Tonight First (Evening action view)
                        tonightDominantHeroCard(active)
                        lastNightCompactRecapCard(active)
                        impactComparisonCard
                        trendSection
                        trialProgressSection(active)
                        quickNavRow
                    }
                } else {
                    noFormulaCard
                }
            }
            .padding(BetterSpacing.screen)
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $impactDetailMetric) { metric in
            if let impact = viewModel.impact, let active = viewModel.activeVersion {
                ImpactMetricDetailSheet(metric: metric, impact: impact, activeVersion: active)
            }
        }
    }

    // MARK: - Segmented Switch

    private var segmentedSwitch: some View {
        HStack(spacing: 0) {
            segmentButton(.lastNight, "Last night")
            segmentButton(.tonight, "Tonight")
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }

    private func segmentButton(_ seg: ProtocolFormulaHomeViewModel.Segment, _ title: String) -> some View {
        let selected = viewModel.segment == seg
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                viewModel.segment = seg
            }
        } label: {
            Text(title)
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? Color.white.opacity(0.08) : .clear))
                .foregroundStyle(selected ? BetterColors.text : ProtocolPalette.mutedText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Hint Card

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(ProtocolPalette.addinColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Log tonight's dose")
                    .font(.footnote.weight(.bold))
                Text("Tap Mark taken once you've taken your formula. Switch back to Last night anytime.")
                    .font(.caption)
                    .foregroundStyle(ProtocolPalette.mutedText)
            }
            Spacer()
            Button("Dismiss") { viewModel.dismissHint() }
                .font(.caption.weight(.bold))
                .foregroundStyle(ProtocolPalette.brandColor)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dismiss hint")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - HOME A: Last Night Hero Card

    private func lastNightHeroCard(_ active: ProtocolFormulaVersion) -> some View {
        let color = viewModel.lastNightVersion.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? ProtocolPalette.brandColor
        let snapshot = viewModel.lastNightSnapshot
        let pct = snapshot?.restorativePctOfInBed ?? 0
        _ = active

        return VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Night")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)

                    Text(viewModel.lastNightSession?.sleepDateKey ?? "No session logged")
                        .font(.title3.weight(.black))
                        .foregroundStyle(BetterColors.text)

                    HStack(spacing: 6) {
                        if let lastNightVer = viewModel.lastNightVersion {
                            VersionChip(version: lastNightVer, size: .xs)
                                .accessibilityLabel("Formula \(lastNightVer.resolvedLabel)")
                        } else {
                            Text("No formula taken")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                        if let addins = viewModel.lastNightLog?.addins, !addins.isEmpty {
                            Text("+\(addins.count) add-in\(addins.count == 1 ? "" : "s")")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ProtocolPalette.addinColor)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }

            // Hero split — ring shows the %, side shows label + minutes + interactive baseline
            HStack(spacing: BetterSpacing.large) {
                RestoreRing(
                    pct: pct,
                    color: color,
                    size: 96,
                    restorativeMin: snapshot?.restorativeSleepMinutes,
                    totalInBedMin: snapshot?.restorativeDenominatorMinutes
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total Restorative Sleep %")
                .accessibilityValue("\(Int(pct.rounded())) percent")

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Restorative Sleep")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ProtocolPalette.dimText)

                        if let snap = snapshot, let restMin = snap.restorativeSleepMinutes {
                            let tibMin = snap.restorativeDenominatorMinutes ?? ((snap.totalSleepMinutes ?? 0) + (snap.awakeMinutes ?? 0))
                            let restH = Int(restMin) / 60; let restM = Int(restMin) % 60
                            let tibH = Int(tibMin) / 60; let tibM = Int(tibMin) % 60
                            let restStr = restH > 0 ? "\(restH)h \(restM)m" : "\(restM)m"
                            let tibStr = tibH > 0 ? "\(tibH)h \(tibM)m" : "\(tibM)m"
                            Text(restStr)
                                .font(.title2.weight(.black).monospacedDigit())
                                .foregroundStyle(BetterColors.text)
                            Text("of \(tibStr) in bed")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ProtocolPalette.mutedText)
                        } else {
                            Text("—")
                                .font(.title2.weight(.black))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                    }

                    // Tappable baseline comparison pill
                    if let impact = viewModel.impact, !impact.isLowData,
                       let deltaPct = impact.deltaRestorativePctOfInBed {
                        Button { impactDetailMetric = .restorativePct } label: {
                            heroBaselinePill(delta: deltaPct, unit: "%")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(baselineStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                }
            }
            .padding(.vertical, 4)

            if let snap = snapshot {
                Divider().overlay(Color.white.opacity(0.08))
                StageBar(
                    deepMin: snap.deepMinutes ?? 0,
                    remMin: snap.remMinutes ?? 0,
                    awakeMin: snap.awakeMinutes ?? 0,
                    totalSleepMin: snap.totalSleepMinutes ?? 0,
                    height: 12,
                    color: color,
                    showLabels: true
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stageBarAccessibilityLabel(snap: snap))
            }
        }
        .padding(BetterSpacing.medium)
        .background(
            LinearGradient(colors: [color.opacity(0.12), ProtocolPalette.surfaceColor],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.24), lineWidth: 1))
    }

    /// Tappable pill shown in the hero card — natural language baseline sentence.
    private func heroBaselinePill(delta: Double, unit: String) -> some View {
        let sign = delta >= 0 ? "+" : ""
        let color: Color = delta >= 0 ? ProtocolPalette.goodColor : ProtocolPalette.badColor
        let direction = delta >= 0 ? "higher" : "lower"
        let displayUnit = unit == "%" ? "pp" : unit
        let formatted = "\(sign)\(String(format: "%.1f", delta))\(displayUnit)"
        return HStack(spacing: 5) {
            Text(formatted)
                .font(.system(size: 13, weight: .black).monospacedDigit())
                .foregroundStyle(color)
            Text("\(direction) than baseline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProtocolPalette.mutedText)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        .accessibilityLabel("Total Restorative Sleep %, \(formatted) \(direction) than baseline. Tap for details.")
        .accessibilityAddTraits(.isButton)
    }

    private func stageBarAccessibilityLabel(snap: ProtocolNightMetricSnapshot) -> String {
        func fmt(_ mins: Double?) -> String {
            let m = Int(mins ?? 0)
            let h = m / 60
            let r = m % 60
            return h > 0 ? "\(h)h \(r)m" : "\(r)m"
        }
        return "Deep \(fmt(snap.deepMinutes)), REM \(fmt(snap.remMinutes)), Awake \(fmt(snap.awakeMinutes))"
    }

    // 4 Key Metrics Grid — uses single-night vs baseline delta when available
    private var lastNightMetricsGrid: some View {
        let snapshot = viewModel.lastNightSnapshot
        let deltas = viewModel.lastNightVsBaselineDeltas

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            homeMetricTile(metric: .deep, value: snapshot?.deepMinutes, delta: deltas?.deep)
            homeMetricTile(metric: .rem, value: snapshot?.remMinutes, delta: deltas?.rem)
            homeMetricTile(metric: .awake, value: snapshot?.awakeMinutes, delta: deltas?.awake)
            homeMetricTile(metric: .duration, value: snapshot?.totalSleepMinutes, delta: deltas?.totalSleep)
        }
    }

    private func homeMetricTile(
        metric: ProtocolFormulaMetric,
        value: Double?,
        delta: Double?,
        pctVsBaseline: Double? = nil
    ) -> some View {
        let baselineValue = value.flatMap { current in delta.map { current - $0 } }
        return ProtocolMetricComparisonStrip(
            metric: metric,
            yourValue: value,
            baselineValue: baselineValue,
            compact: true
        )
    }

    // MARK: - Impact vs Baseline Comparison Card

    private var impactComparisonMetrics: [ProtocolFormulaMetric] {
        [.restorativePct, .deep, .rem, .awake, .duration]
    }

    private func impactPair(for metric: ProtocolFormulaMetric) -> ProtocolFormulaHomeViewModel.ImpactPair {
        viewModel.impactPairs[metric]
            ?? ProtocolFormulaHomeViewModel.ImpactPair(you: nil, baseline: nil, delta: nil, unit: metric.unit)
    }

    private var impactComparisonCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                Text("Your Metrics vs Baseline")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ProtocolPalette.dimText)
                    .textCase(.uppercase)
                Spacer()
                if let count = viewModel.impact?.nightCount, count > 0 {
                    Text("\(count) night\(count == 1 ? "" : "s")")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }

            if viewModel.baselineStatus != .ready || (viewModel.impact?.isLowData ?? true) {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                    Text(baselineStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                    Spacer()
                }
                .padding(.vertical, 10)
            }

            // 2-column grid of tappable metric cards
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(impactComparisonMetrics, id: \.self) { metric in
                    impactMetricGridCard(metric)
                }
            }

            Text(ProtocolImpactSummary.causalityCaveat)
                .font(.caption2)
                .foregroundStyle(ProtocolPalette.dimText)
        }
        .padding(BetterSpacing.medium)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    /// Compact tappable card in the 2-col Impact vs Baseline grid.
    private func impactMetricGridCard(_ metric: ProtocolFormulaMetric) -> some View {
        let pair = impactPair(for: metric)

        return Button {
            impactDetailMetric = metric
        } label: {
            ProtocolMetricComparisonStrip(
                metric: metric,
                yourValue: pair.you,
                baselineValue: pair.baseline,
                compact: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metric.fullLabel), tap for details")
    }

    private func impactFormattedValue(_ value: Double?, unit: String) -> String {
        guard let v = value else { return "—" }
        switch unit {
        case "%":   return "\(Int(v.rounded()))%"
        case "pts": return "\(Int(v.rounded()))pts"
        default:
            let h = Int(v) / 60; let m = Int(v) % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    // Tonight Compact CTA Card
    private func tonightCompactCard(_ active: ProtocolFormulaVersion) -> some View {
        let tonightVer = viewModel.versions.first { $0.id == viewModel.selectedTonightVersionID } ?? active
        let color = ProtocolPalette.versionColor(hex: tonightVer.colorHex)
        
        return VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)

                    HStack(spacing: 8) {
                        Text("Take Tonight:")
                            .font(.subheadline.weight(.bold))
                        VersionChip(version: tonightVer, size: .small)
                            .accessibilityLabel("Formula \(tonightVer.resolvedLabel)")
                    }
                }
                Spacer()
            }

            if !tonightVer.formulaText.isEmpty {
                Text(tonightVer.formulaText)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }

            // Supplement log actions — show save-state banner when saving/saved/error
            tonightLogActionArea(color: color, compact: true)

            // Dashed supplement expander button
            Button {
                withAnimation { showAddinEditor.toggle() }
            } label: {
                HStack {
                    Image(systemName: showAddinEditor ? "minus" : "plus")
                        .font(.caption.weight(.bold))
                    Text(showAddinEditor ? "Hide add-on supplement editor" : "Add tonight's add-on supplements")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(ProtocolPalette.addinColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ProtocolPalette.addinColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
            }
            .buttonStyle(.plain)

            if showAddinEditor {
                addinEditor
            }
        }
        .padding(BetterSpacing.medium)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    // MARK: - HOME B: Tonight Dominant Hero Card

    private func tonightDominantHeroCard(_ active: ProtocolFormulaVersion) -> some View {
        let selected = viewModel.versions.first { $0.id == viewModel.selectedTonightVersionID } ?? active
        let color = ProtocolPalette.versionColor(hex: selected.colorHex)
        let nightCount = viewModel.impact?.nightCount ?? 0
        
        return VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            // Trial progress ribbon text
            HStack {
                Text("Tonight's schedule")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                Spacer()
                Text("Night \(nightCount)/14")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ProtocolPalette.dimText)
                    .monospacedDigit()
            }

            Text("Take Tonight: \(selected.resolvedLabel)")
                .font(.title.weight(.black))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(BetterColors.text)

            if !selected.formulaText.isEmpty {
                Text(selected.formulaText)
                    .font(.body.weight(.bold))
                    .foregroundStyle(BetterColors.text.opacity(0.85))
            }

            // Baseline-delta context — tappable pill opens the restorativePct detail sheet.
            if let impact = viewModel.impact, !impact.isLowData,
               let deltaPct = impact.deltaRestorativePctOfInBed {
                Button { impactDetailMetric = .restorativePct } label: {
                    heroBaselinePill(delta: deltaPct, unit: "%")
                }
                .buttonStyle(.plain)
            }

            // Tonight dominant card actions
            tonightLogActionArea(color: color, compact: false)
            
            // Inline add-on supplementary editor
            addinEditor
            
            // Select version switch row
            VStack(alignment: .leading, spacing: 8) {
                Text("Took a different version tonight?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ProtocolPalette.dimText)

                HStack(spacing: 8) {
                    ForEach(viewModel.visibleVersions) { ver in
                        let isSel = ver.id == selected.id
                        Button {
                            viewModel.selectTonightVersion(ver)
                        } label: {
                            Text(ver.resolvedLabel)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(isSel ? ProtocolPalette.versionColor(hex: ver.colorHex).opacity(0.18) : Color.white.opacity(0.03)))
                                .overlay(Capsule().stroke(isSel ? ProtocolPalette.versionColor(hex: ver.colorHex) : Color.white.opacity(0.08), lineWidth: 1))
                                .foregroundStyle(isSel ? BetterColors.text : ProtocolPalette.mutedText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Formula \(ver.resolvedLabel)")
                        .accessibilityAddTraits(isSel ? [.isSelected] : [])
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(BetterSpacing.medium)
        .background(
            LinearGradient(colors: [color.opacity(0.14), ProtocolPalette.surfaceColor],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.24), lineWidth: 1))
    }

    // HOME B: Last Night Compact Recap Card
    private func lastNightCompactRecapCard(_ active: ProtocolFormulaVersion) -> some View {
        let snapshot = viewModel.lastNightSnapshot
        let pct = snapshot?.restorativePctOfInBed ?? 0
        let color = viewModel.lastNightVersion.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? ProtocolPalette.brandColor
        
        return VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last night recap")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)

                    Text(viewModel.lastNightSession?.sleepDateKey ?? "No session logged")
                        .font(.headline.weight(.black))
                        .foregroundStyle(BetterColors.text)
                }
                Spacer()
                if let lastNightVer = viewModel.lastNightVersion {
                    VersionChip(version: lastNightVer, size: .xs)
                        .accessibilityLabel("Formula \(lastNightVer.resolvedLabel)")
                }
            }

            HStack(spacing: BetterSpacing.large) {
                // Circular stats summary
                VStack(spacing: 2) {
                    Text("\(Int(pct.rounded()))%")
                        .font(.title.weight(.black).monospacedDigit())
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Text("Restorative")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                }
                .frame(width: 80)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Restorative sleep")
                .accessibilityValue("\(Int(pct.rounded())) percent")
                
                // Inline compact list of metrics
                VStack(alignment: .leading, spacing: 4) {
                    compactRow(label: "Deep sleep", value: snapshot?.deepMinutes)
                    compactRow(label: "REM sleep", value: snapshot?.remMinutes)
                    compactRow(label: "Awake time", value: snapshot?.awakeMinutes)
                    compactRow(label: "Sleep duration", value: snapshot?.totalSleepMinutes)
                }
            }
            
            if let snap = snapshot {
                StageBar(
                    deepMin: snap.deepMinutes ?? 0,
                    remMin: snap.remMinutes ?? 0,
                    awakeMin: snap.awakeMinutes ?? 0,
                    totalSleepMin: snap.totalSleepMinutes ?? 0,
                    height: 8,
                    color: color,
                    showLabels: false
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stageBarAccessibilityLabel(snap: snap))
            }

            if let impact = viewModel.impact, !impact.isLowData,
               let deltaPct = impact.deltaRestorativePctOfInBed {
                Button { impactDetailMetric = .restorativePct } label: {
                    heroBaselinePill(delta: deltaPct, unit: "%")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(BetterSpacing.medium)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private func compactRow(label: String, value: Double?) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(ProtocolPalette.dimText)
            Spacer()
            if let value {
                let hrs = Int(value) / 60
                let mins = Int(value) % 60
                let str = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
                Text(str)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
        }
    }

    // MARK: - Shared Trend Chart Sparkline Section

    private var trendSection: some View {
        let points = viewModel.recentSnapshots.compactMap { snap -> PvRestoreSpark.SparkPoint? in
            guard let val = snap.restorativePctOfInBed,
                  let verID = snap.versionID,
                  let ver = viewModel.versionsByID[verID] else { return nil }
            return PvRestoreSpark.SparkPoint(
                dateKey: snap.sleepDateKey,
                value: val,
                color: ProtocolPalette.versionColor(hex: ver.colorHex)
            )
        }
        
        return VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("14-night restorative trend")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            BetterHealthCard {
                VStack(spacing: 8) {
                    PvRestoreSpark(
                        points: points,
                        baseline: viewModel.baseline?.meanRestorativePctOfInBed
                    )
                    .frame(height: 70)
                    
                    HStack {
                        Text("14 nights ago")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                        Spacer()
                        if let mean = viewModel.baseline?.meanRestorativePctOfInBed {
                            Text("Baseline (\(Int(mean.rounded()))%)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                        Spacer()
                        Text("Last night")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                }
            }
        }
    }

    // MARK: - HOME A: Your Protocol Summary Strip

    private var protocolSummarySection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Your protocol")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            BetterHealthCard {
                PvPhaseRibbon(segments: viewModel.ribbonSegments)
            }
        }
    }

    // MARK: - HOME B: Trial Progress Strip

    private func trialProgressSection(_ active: ProtocolFormulaVersion) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Trial progress")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            BetterHealthCard {
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    PvPhaseRibbon(segments: viewModel.ribbonSegments)
                    
                    // Show comparison text: active average vs baseline
                    if let impact = viewModel.impact, !impact.isLowData {
                        if let deltaPct = impact.deltaRestorativePctOfInBed {
                            let sign = deltaPct >= 0 ? "+" : ""
                            Text("\(active.resolvedLabel) averages \(sign)\(deltaPct, format: .number.precision(.fractionLength(1))) pp restorative sleep vs baseline.")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                        }
                    } else {
                        Text(trialStatusText(active))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ProtocolPalette.dimText)
                    }
                }
            }
        }
    }

    // MARK: - Add-in Editor (Tonight)

    private var addinEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Add-on supplements taken")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ProtocolPalette.addinColor)
                Spacer()
            }
            
            HStack(spacing: 8) {
                TextField("e.g. GABA 100mg", text: $viewModel.draftAddinText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.09), lineWidth: 1))
                
                Button("Add") {
                    viewModel.addTonightAddin()
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(ProtocolPalette.addinColor))
                .foregroundStyle(Color.black)
                .buttonStyle(.plain)
            }
            
            removableAddinChips(viewModel.tonightAddins, remove: viewModel.removeTonightAddin)
        }
        .padding(10)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ProtocolPalette.addinColor.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }

    @ViewBuilder
    private func removableAddinChips(_ addins: [ProtocolFormulaComponent],
                                     remove: @escaping (ProtocolFormulaComponent) -> Void) -> some View {
        if !addins.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(addins) { addin in
                        Button {
                            remove(addin)
                        } label: {
                            Text("+ \(addin.name) ✕")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ProtocolPalette.addinColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(ProtocolPalette.addinColor.opacity(0.12)))
                                .overlay(Capsule().stroke(ProtocolPalette.addinColor.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Tonight action area (shared between compact + dominant hero card)

    @ViewBuilder
    private func tonightLogActionArea(color: Color, compact: Bool) -> some View {
        let state = viewModel.tonightLogSaveState
        let isSaving: Bool = {
            if case .saving = state { return true }
            return false
        }()
        let vertPad: CGFloat = compact ? 10 : 12

        switch state {
        case .idle, .saving(_):
            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.markTonightTaken() }
                } label: {
                    HStack(spacing: 8) {
                        if case .saving(let status) = state, status == .taken {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.black)
                                .scaleEffect(0.8)
                        }
                        Text("Mark taken")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, vertPad)
                    .background(Capsule().fill(color.opacity(isSaving ? 0.5 : 1.0)))
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                Button {
                    Task { await viewModel.markTonightSkipped() }
                } label: {
                    HStack(spacing: 8) {
                        if case .saving(let status) = state, status == .skipped {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(BetterColors.text)
                                .scaleEffect(0.8)
                        }
                        Text("Didn't take")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, vertPad)
                    .background(Capsule().stroke(Color.white.opacity(isSaving ? 0.07 : 0.18), lineWidth: 1))
                    .foregroundStyle(BetterColors.text.opacity(isSaving ? 0.3 : 1.0))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }

        case .saved(let savedStatus):
            HStack(spacing: 10) {
                Image(systemName: savedIconName(for: savedStatus))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(savedStatus == .taken ? ProtocolPalette.goodColor : ProtocolPalette.mutedText)
                Text(savedCopy(for: savedStatus))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(savedStatus == .taken ? ProtocolPalette.goodColor : BetterColors.text)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, vertPad)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(
                    (savedStatus == .taken ? ProtocolPalette.goodColor : Color.white).opacity(0.08)
                )
            )
            .overlay(Capsule().stroke(
                (savedStatus == .taken ? ProtocolPalette.goodColor : Color.white).opacity(0.2),
                lineWidth: 1
            ))
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))

        case .error(let retryStatus):
            Button {
                Task { await viewModel.retryTonightLogSave() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(ProtocolPalette.badColor)
                    Text(retryStatus == .taken ? "Couldn't save taken — retry" : "Couldn't save didn't take — retry")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ProtocolPalette.badColor)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, vertPad)
                .padding(.horizontal, 16)
                .background(Capsule().fill(ProtocolPalette.badColor.opacity(0.08)))
                .overlay(Capsule().stroke(ProtocolPalette.badColor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func savedIconName(for status: ProtocolFormulaNightStatus) -> String {
        switch status {
        case .taken:
            return "checkmark.circle.fill"
        case .skipped:
            return "moon.zzz.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private func savedCopy(for status: ProtocolFormulaNightStatus) -> String {
        switch status {
        case .taken:
            return "Saved: tonight marked taken"
        case .skipped:
            return "Saved: tonight marked as didn't take"
        case .unknown:
            return "Saved: tonight status recorded"
        }
    }

    // MARK: - Baseline status

    private var baselineStatusText: String {
        switch viewModel.baselineStatus {
        case .ready: return "Comparing vs baseline…"
        case .needsMoreNights(let n):
            return n == 1 ? "1 more night to compare" : "\(n) more nights to compare"
        case .baselineBuilding(let valid, let required):
            if let readiness = viewModel.baselineReadiness {
                return "Found \(valid)/\(required) qualifying staged-sleep nights in the 90-day pre-protocol window (\(readiness.totalCachedNightCount) cached)."
            }
            return "Baseline building: \(valid)/\(required) qualifying staged-sleep nights"
        case .baselineMissingMetricData(let missing):
            return "Baseline missing metric data: \(missing.joined(separator: ", "))"
        case .baselineMissing:
            return "Baseline not available yet"
        case .noFormula:
            return "Add a formula to start tracking"
        }
    }

    private func trialStatusText(_ active: ProtocolFormulaVersion) -> String {
        switch viewModel.baselineStatus {
        case .needsMoreNights(let n):
            let label = active.resolvedLabel
            return n == 1 ? "1 more \(label) night to calculate lift." : "\(n) more \(label) nights to calculate lift."
        case .baselineBuilding(let valid, let required):
            if let readiness = viewModel.baselineReadiness {
                return "Baseline building — \(valid)/\(required) qualifying staged-sleep nights in the 90-day pre-protocol window (\(readiness.totalCachedNightCount) cached)."
            }
            return "Baseline building — \(valid)/\(required) qualifying staged-sleep nights."
        case .baselineMissingMetricData(let missing):
            return "Baseline is missing metric fields: \(missing.joined(separator: ", "))."
        case .baselineMissing:
            return "Baseline not available yet — keep tracking sleep."
        case .ready, .noFormula:
            return "Collect 3 nights of \(active.resolvedLabel) to calculate overall lift stats."
        }
    }

    // MARK: - Quick nav (Timeline / All metrics / Version dive / Edit log)

    private var quickNavRow: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Explore")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                quickNavTile(
                    title: "Timeline",
                    subtitle: "Phase-by-phase",
                    systemImage: "calendar.day.timeline.left",
                    action: onOpenTimeline
                )
                quickNavTile(
                    title: "All metrics",
                    subtitle: "Deep, REM, more",
                    systemImage: "chart.line.uptrend.xyaxis",
                    action: onOpenAllMetrics
                )
                quickNavTile(
                    title: "Version dive",
                    subtitle: "Per-formula stats",
                    systemImage: "scope",
                    action: onOpenVersionDive
                )
                quickNavTile(
                    title: "Edit log",
                    subtitle: "Calendar review",
                    systemImage: "square.and.pencil",
                    action: onOpenEditLog
                )
            }
        }
    }

    private func quickNavTile(title: String, subtitle: String, systemImage: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.brandColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ProtocolPalette.brandColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BetterColors.text)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProtocolPalette.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.5 : 1)
    }

    private var noFormulaCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                BetterSectionHeader(title: "No formula yet")
                Text("Create your first formula version to start logging and comparing nights.")
                    .font(.system(size: 13))
                    .foregroundStyle(ProtocolPalette.mutedText)
                Button(action: onOpenFormulaSetup) {
                    Text("Add a formula")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(BetterColors.brand))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
