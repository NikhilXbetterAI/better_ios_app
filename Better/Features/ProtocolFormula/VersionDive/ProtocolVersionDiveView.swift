import SwiftUI

struct ProtocolVersionDiveView: View {
    @Bindable var viewModel: ProtocolVersionDiveViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                versionSelector
                if let version = viewModel.selectedVersion {
                    headerHeroCard(version: version)
                    comparisonBarsSection(version: version)
                    nightlyScatterPlotSection(version: version)
                    ProtocolCaveatFooter()
                } else {
                    Text("No versions found.")
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .font(.system(size: 14, weight: .bold))
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

    // MARK: - Version selector

    private var versionSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.versions) { version in
                    let isSel = viewModel.selectedVersionID == version.id
                    let col = ProtocolPalette.versionColor(hex: version.colorHex)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            viewModel.selectedVersionID = version.id
                        }
                    } label: {
                        VersionChip(version: version, size: .small)
                            .overlay(
                                Capsule()
                                    .stroke(col, lineWidth: isSel ? 2.0 : 0.0)
                            )
                            .shadow(color: col.opacity(isSel ? 0.25 : 0.0), radius: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Header Hero Card

    private func headerHeroCard(version: ProtocolFormulaVersion) -> some View {
        let color = ProtocolPalette.versionColor(hex: version.colorHex)
        let rollup = viewModel.selectedRollup
        let pct = rollup?.meanRestorativePctOfInBed ?? 0
        return VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version Dive")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .textCase(.uppercase)

                    Text(version.resolvedLabel)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(BetterColors.text)

                    if !version.formulaText.isEmpty {
                        Text(version.formulaText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ProtocolPalette.mutedText)
                            .lineLimit(3)
                    }
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rollup?.nightCount ?? 0)")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(BetterColors.text)
                        .monospacedDigit()
                    Text("nights")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }

            // RestoreRing split with baseline bar
            HStack(spacing: BetterSpacing.large) {
                RestoreRing(
                    pct: pct,
                    color: color,
                    size: 96,
                    restorativeMin: rollup?.meanRestorativeMin,
                    totalInBedMin: rollup.map { ($0.meanTotalSleepMin ?? 0) + ($0.meanAwakeMin ?? 0) }
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Restorative Sleep %")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProtocolPalette.dimText)

                    miniHorizontalBar(
                        label: "You",
                        value: pct,
                        maxVal: 100,
                        color: color,
                        unit: "%"
                    )

                    // Baseline bar
                    if let basePct = viewModel.baseline?.meanRestorativePctOfInBed {
                        miniHorizontalBar(
                            label: "Baseline",
                            value: basePct,
                            maxVal: 100,
                            color: Color.white.opacity(0.35),
                            unit: "%",
                            isDashed: true
                        )
                    }
                }
            }
            .padding(.vertical, 4)

            // Proportional StageBar
            if let roll = rollup, roll.nightCount >= 1 {
                Divider().overlay(Color.white.opacity(0.08))
                
                StageBar(
                    deepMin: roll.meanDeepMin ?? 0,
                    remMin: roll.meanRemMin ?? 0,
                    awakeMin: roll.meanAwakeMin ?? 0,
                    totalSleepMin: roll.meanTotalSleepMin ?? 0,
                    height: 12,
                    showLabels: true
                )
            }
            
            if let roll = rollup, roll.nightCount < 3 {
                LowDataBanner(nightCount: roll.nightCount, label: version.resolvedLabel, minimum: 3)
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

    private func miniHorizontalBar(label: String, value: Double, maxVal: Double, color: Color, unit: String, isDashed: Bool = false) -> some View {
        let safeValue = value.isFinite && value >= 0 ? value : 0
        let safeMax = maxVal.isFinite && maxVal > 0 ? maxVal : 1
        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .frame(width: 48, alignment: .leading)
            
            GeometryReader { geo in
                let fraction = min(1, max(0, CGFloat(safeValue / safeMax)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    if isDashed {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                            .fill(color)
                            .frame(width: max(4, geo.size.width * fraction))
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 6)
            
            Text(String(format: "%.1f%@", safeValue, unit))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: - Comparison bars section

    private func comparisonBarsSection(version: ProtocolFormulaVersion) -> some View {
        let color = ProtocolPalette.versionColor(hex: version.colorHex)
        let metrics = ProtocolAllMetricsView.primaryMetrics.filter { $0 != .restorativePct }

        return VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Metrics comparison")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)

            BetterHealthCard {
                VStack(spacing: 16) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        let pair = viewModel.comparison(for: metric)
                        comparisonMetricGroup(
                            metric: metric,
                            myValue: pair.my,
                            baseValue: pair.base,
                            color: color
                        )
                        if index < metrics.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func comparisonMetricGroup(metric: ProtocolFormulaMetric, myValue: Double?, baseValue: Double?, color: Color) -> some View {
        let maxVal = max(myValue ?? 0, baseValue ?? 0, 1) * 1.15
        let a11yValue: String = {
            var parts: [String] = []
            if let myValue { parts.append("you \(Int(myValue.rounded())) \(metric.unit)") }
            if let baseValue { parts.append("baseline \(Int(baseValue.rounded())) \(metric.unit)") }
            return parts.joined(separator: ", ")
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(metric.fullLabel)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(BetterColors.text)

            miniHorizontalBar(
                label: "You",
                value: myValue ?? 0,
                maxVal: maxVal,
                color: color,
                unit: metric.unit
            )

            if let baseValue {
                miniHorizontalBar(
                    label: "Baseline",
                    value: baseValue,
                    maxVal: maxVal,
                    color: Color.white.opacity(0.35),
                    unit: metric.unit,
                    isDashed: true
                )
            }

            if let myV = myValue, let baseV = baseValue {
                let delta = myV - baseV
                let isGood = metric.betterIsLower ? delta < 0 : delta > 0
                let sign = delta >= 0 ? "+" : ""
                Text("\(sign)\(Int(delta.rounded()))\(metric.deltaUnit) vs baseline")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.fullLabel)
        .accessibilityValue(a11yValue)
    }

    // MARK: - Nightly scatter plot

    private func nightlyScatterPlotSection(version: ProtocolFormulaVersion) -> some View {
        let points = viewModel.nightlyPoints.compactMap { $0.restorativePctOfInBed }
        let color = ProtocolPalette.versionColor(hex: version.colorHex)
        let mean = viewModel.selectedRollup?.meanRestorativePctOfInBed
        
        return VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Nightly restorative %")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            BetterHealthCard {
                if points.isEmpty {
                    Text("No night detail logged for this version.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .frame(height: 80, alignment: .center)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 8) {
                        NightlyDotsChart(
                            points: points,
                            baselineValue: viewModel.baseline?.meanRestorativePctOfInBed,
                            meanValue: mean,
                            color: color
                        )
                        .frame(height: 120)
                        
                        HStack {
                            Text("Night 1")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                            Spacer()
                            if let mean {
                                Text("Mean (\(Int(mean.rounded()))%)")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(color)
                            }
                            Spacer()
                            Text("Night \(points.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Nightly dots chart

private struct NightlyDotsChart: View {
    let points: [Double]
    let baselineValue: Double?
    let meanValue: Double?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let safePoints = points.filter { $0.isFinite && $0 >= 0 }
            let safeBaseline = baselineValue.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let safeMean = meanValue.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let allVals = safePoints + (safeBaseline.map { [$0] } ?? []) + (safeMean.map { [$0] } ?? [])
            let minV = (allVals.min() ?? 0) * 0.90
            let maxV = (allVals.max() ?? 100) * 1.10
            let range = max(1.0, maxV - minV)
            
            guard !safePoints.isEmpty else { return AnyView(EmptyView()) }
            let xStep = safePoints.count > 1 ? w / CGFloat(safePoints.count - 1) : w / 2
            func yPos(_ v: Double) -> CGFloat { h - CGFloat((v - minV) / range) * (h - 16) - 8 }

            return AnyView(ZStack(alignment: .topLeading) {
                // Grid lines
                ForEach(1...3, id: \.self) { i in
                    let ratio = CGFloat(i) * 0.25
                    let gy = h * ratio
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: gy))
                        path.addLine(to: CGPoint(x: w, y: gy))
                    }
                    .stroke(Color.white.opacity(0.03), lineWidth: 1)
                }

                // Baseline line
                if let bv = safeBaseline {
                    let by = yPos(bv)
                    Path { p in
                        var x: CGFloat = 0
                        while x <= w { p.move(to: CGPoint(x: x, y: by)); p.addLine(to: CGPoint(x: min(x + 4, w), y: by)); x += 8 }
                    }
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                }
                
                // Version Mean line
                if let mv = safeMean {
                    let my = yPos(mv)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: my))
                        p.addLine(to: CGPoint(x: w, y: my))
                    }
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }

                // Dots
                ForEach(Array(safePoints.enumerated()), id: \.offset) { i, val in
                    let x = safePoints.count > 1 ? CGFloat(i) * xStep : w / 2
                    let y = yPos(val)
                    
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)
                        .shadow(color: color.opacity(0.35), radius: 3)
                }
            })
        }
    }
}
