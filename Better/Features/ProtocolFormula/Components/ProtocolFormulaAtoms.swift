import SwiftUI

// MARK: - Version chip

struct VersionChip: View {
    let version: ProtocolFormulaVersion
    var size: ChipSize = .medium
    var addinsText: String? = nil

    enum ChipSize {
        case xs, small, medium

        var fontSize: CGFloat {
            switch self { case .xs: 10; case .small: 11; case .medium: 13 }
        }
        var dotSize: CGFloat {
            switch self { case .xs: 5; case .small: 6; case .medium: 8 }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ProtocolPalette.versionColor(hex: version.colorHex))
                .frame(width: size.dotSize, height: size.dotSize)
            Text(version.resolvedLabel)
                .font(.system(size: size.fontSize, weight: .bold))
                .foregroundStyle(BetterColors.text)
            if let addinsText, !addinsText.isEmpty {
                Text(addinsText)
                    .font(.system(size: size.fontSize, weight: .bold))
                    .foregroundStyle(ProtocolPalette.addinColor)
            }
        }
        .padding(.horizontal, size == .xs ? 6 : 10)
        .padding(.vertical, size == .xs ? 3 : 5)
        .background(
            Capsule().fill(Color.white.opacity(0.04))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
    }
}

// MARK: - Delta badge

struct DeltaBadge: View {
    /// Signed delta. `nil` renders as "—".
    let value: Double?
    /// Suffix shown after the number ("min", "%", etc.). No unit prefix is added.
    let unit: String
    /// If `true`, *lower* is good (e.g. latency).
    var lowerIsBetter: Bool = false

    var body: some View {
        if let value, value.isFinite {
            valueText(for: value)
        } else {
            Text("—")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
        }
    }

    private func valueText(for value: Double) -> some View {
        let sign = value > 0 ? "+" : ""
        let isGood = (value > 0) != lowerIsBetter && value != 0
        
        let threshold: Double = {
            if unit.contains("m") || unit.contains("min") {
                return 15.0 // 15 min threshold
            } else if unit == "%" || unit == "pp" || unit == "pts" {
                return 2.0  // 2 points / percent threshold
            }
            return 0.0
        }()
        
        let isSignificant = abs(value) >= threshold
        let color: Color = !isSignificant || value == 0 ? ProtocolPalette.mutedText
            : (isGood ? ProtocolPalette.goodColor : ProtocolPalette.badColor)
            
        return Text("\(sign)\(value, format: .number.precision(.fractionLength(value.magnitude < 10 ? 1 : 0)))\(unit)")
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
    }
}

// MARK: - Metric comparison strip

struct ProtocolMetricComparisonStrip: View {
    let metric: ProtocolFormulaMetric
    let yourValue: Double?
    let baselineValue: Double?
    var compact: Bool = false

    private var color: Color { ProtocolPalette.versionColor(hex: metric.colorHex) }
    private var delta: Double? {
        guard let yourValue = sanitized(yourValue),
              let baselineValue = sanitized(baselineValue) else { return nil }
        return yourValue - baselineValue
    }

    private var scaleMax: Double {
        max(sanitized(yourValue) ?? 0, sanitized(baselineValue) ?? 0, 1) * 1.15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                Text(metric.fullLabel)
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let delta {
                    DeltaBadge(value: delta, unit: metric.deltaUnit, lowerIsBetter: metric.betterIsLower)
                        .font(.system(size: compact ? 10 : 11, weight: .bold))
                }
            }

            metricComparisonRow(
                label: "You",
                value: yourValue,
                color: color,
                compact: compact
            )
            metricComparisonRow(
                label: "Base",
                value: baselineValue,
                color: Color.white.opacity(0.34),
                compact: compact
            )

            if baselineValue == nil || yourValue == nil {
                Text(baselineValue == nil ? "Baseline pending" : "No value yet")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
        .overlay(RoundedRectangle(cornerRadius: compact ? 10 : 12).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    @ViewBuilder
    private func metricComparisonRow(label: String, value: Double?, color: Color, compact: Bool) -> some View {
        let safeValue = sanitized(value)
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .frame(width: compact ? 30 : 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat((safeValue ?? 0) / scaleMax)))
                }
            }
            .frame(height: compact ? 5 : 6)
            Text(formatted(safeValue))
                .font(.system(size: compact ? 9 : 10, weight: .bold).monospacedDigit())
                .foregroundStyle(safeValue == nil ? ProtocolPalette.dimText : BetterColors.text)
                .frame(width: compact ? 56 : 60, alignment: .trailing)
        }
    }

    private func sanitized(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch metric.unit {
        case "%":
            return "\(String(format: "%.1f", value))%"
        case "pts":
            return "\(Int(value.rounded()))pts"
        default:
            let hours = Int(value) / 60
            let minutes = Int(value) % 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }
    }
}

// MARK: - Caveat caption

struct ObservedNotCausalCaption: View {
    var body: some View {
        Text(ProtocolImpactSummary.causalityCaveat)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(ProtocolPalette.dimText)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Low-data banner

struct LowDataBanner: View {
    let nightCount: Int
    let label: String
    var minimum: Int = 3

    var body: some View {
        let remaining = max(0, minimum - nightCount)
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .medium))
            Text("Need \(remaining) more \(label) \(remaining == 1 ? "night" : "nights")")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(ProtocolPalette.mutedText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Continuity badge

struct ContinuityBadge: View {
    let category: SleepContinuityCategory?

    var body: some View {
        Text(category?.displayName ?? "—")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(category == nil ? ProtocolPalette.dimText : BetterColors.text)
    }
}

// MARK: - Edit affordance

struct EditAffordance: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(BetterColors.text)
        .accessibilityLabel("Edit night")
    }
}

// MARK: - Restore Ring

struct RestoreRing: View {
    let pct: Double
    let color: Color
    var size: CGFloat = 80
    var restorativeMin: Double? = nil
    var totalInBedMin: Double? = nil
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: size * 0.08)
            Circle()
                .trim(from: 0.0, to: CGFloat(min(max(pct, 0) / 100.0, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.7), color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 1) {
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: size * 0.22, weight: .black).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                if let rest = restorativeMin, let tib = totalInBedMin {
                    let restHr = Int(rest) / 60
                    let restMin = Int(rest) % 60
                    let tibHr = Int(tib) / 60
                    let tibMin = Int(tib) % 60
                    Text("\(restHr)h\(restMin)m / \(tibHr)h\(tibMin)m")
                        .font(.system(size: size * 0.09, weight: .medium).monospacedDigit())
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stage Bar

struct StageBar: View {
    let deepMin: Double
    let remMin: Double
    let awakeMin: Double
    let totalSleepMin: Double
    var height: CGFloat = 16
    var showLabels: Bool = true

    private var safeDeepMin: Double { Self.safeMinutes(deepMin) }
    private var safeRemMin: Double { Self.safeMinutes(remMin) }
    private var safeAwakeMin: Double { Self.safeMinutes(awakeMin) }
    private var safeTotalSleepMin: Double { Self.safeMinutes(totalSleepMin) }
    private var lightMin: Double { max(0, safeTotalSleepMin - safeDeepMin - safeRemMin) }
    private var totalMin: Double { safeDeepMin + safeRemMin + lightMin + safeAwakeMin }

    var body: some View {
        VStack(spacing: 8) {
            if totalMin > 0 {
                GeometryReader { geo in
                    stageBarHStack(totalWidth: geo.size.width)
                }
                .frame(height: height)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: height)
            }

            if showLabels {
                HStack(spacing: 12) {
                    legendItem(label: "Deep", value: formatMin(safeDeepMin), dotColor: ProtocolPalette.deepColor)
                    legendItem(label: "REM", value: formatMin(safeRemMin), dotColor: ProtocolPalette.remColor)
                    legendItem(label: "Light", value: formatMin(lightMin), dotColor: ProtocolPalette.lightColor)
                    legendItem(label: "Awake", value: formatMin(safeAwakeMin), dotColor: ProtocolPalette.awakeColor)
                }
            }
        }
    }

    @ViewBuilder
    private func stageBarHStack(totalWidth: CGFloat) -> some View {
        let wDeep  = totalWidth * CGFloat(safeDeepMin  / totalMin)
        let wRem   = totalWidth * CGFloat(safeRemMin   / totalMin)
        let wLight = totalWidth * CGFloat(lightMin / totalMin)
        let wAwake = totalWidth * CGFloat(safeAwakeMin / totalMin)
        HStack(spacing: 2) {
            if safeDeepMin > 0 {
                RoundedRectangle(cornerRadius: 3).fill(ProtocolPalette.deepColor)
                    .frame(width: max(2, wDeep - 2))
            }
            if safeRemMin > 0 {
                RoundedRectangle(cornerRadius: 3).fill(ProtocolPalette.remColor)
                    .frame(width: max(2, wRem - 2))
            }
            if lightMin > 0 {
                RoundedRectangle(cornerRadius: 3).fill(ProtocolPalette.lightColor)
                    .frame(width: max(2, wLight - 2))
            }
            if safeAwakeMin > 0 {
                RoundedRectangle(cornerRadius: 3).fill(ProtocolPalette.awakeColor)
                    .frame(width: max(2, wAwake - 2))
            }
        }
    }

    private func legendItem(label: String, value: String, dotColor: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text("\(label) \(value)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProtocolPalette.dimText)
        }
    }

    private func formatMin(_ mins: Double) -> String {
        let h = Int(mins) / 60
        let m = Int(mins) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private static func safeMinutes(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}

// MARK: - Pv Phase Ribbon

struct PvPhaseRibbon: View {
    struct Segment: Identifiable {
        var id: UUID
        var label: String
        var colorHex: String
        var nights: Int
    }
    let segments: [Segment]

    private var total: Int { segments.map { $0.nights }.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(segments) { seg in
                            ribbonSegmentBar(seg: seg, availableWidth: geo.size.width)
                        }
                    }
                }
                .frame(height: 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(segments) { seg in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ProtocolPalette.versionColor(hex: seg.colorHex))
                                .frame(width: 6, height: 6)
                            Text("\(seg.label) (\(seg.nights)n)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                        }
                    }
                }
            }
        }
    }

    private func ribbonSegmentBar(seg: Segment, availableWidth: CGFloat) -> some View {
        let fraction = CGFloat(seg.nights) / CGFloat(max(1, total))
        return RoundedRectangle(cornerRadius: 3)
            .fill(ProtocolPalette.versionColor(hex: seg.colorHex))
            .frame(width: max(4, availableWidth * fraction - 3), height: 8)
    }
}

// MARK: - Pv Restore Sparkline

struct PvRestoreSpark: View {
    struct SparkPoint: Identifiable {
        var id: String { dateKey }
        var dateKey: String
        var value: Double
        var color: Color
    }

    let points: [SparkPoint]
    let baseline: Double?

    private var sanitizedPoints: [SparkPoint] {
        points.filter { $0.value.isFinite && $0.value >= 0 }
    }
    private var values: [Double] { sanitizedPoints.map { $0.value } }
    private var sanitizedBaseline: Double? {
        guard let baseline, baseline.isFinite, baseline >= 0 else { return nil }
        return baseline
    }
    private var minVal: Double { (values.min() ?? 0) * 0.95 }
    private var maxVal: Double { (values.max() ?? 100) * 1.05 }
    private var range: Double { max(1.0, maxVal - minVal) }
    private var count: Int { sanitizedPoints.count }

    var body: some View {
        GeometryReader { geo in
            Group {
                if count > 1 {
                    ZStack {
                        // Mid grid line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                        }
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)

                        // Y-axis bounds (Min/Max)
                        VStack(alignment: .leading) {
                            Text("\(Int(maxVal.rounded()))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                            Spacer()
                            Text("\(Int(minVal.rounded()))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)

                        // Baseline dashed line
                        if let baseline = sanitizedBaseline {
                            baselinePath(baseline: baseline, w: geo.size.width, h: geo.size.height)
                            
                            // Baseline Label on the right edge
                            Text("Base: \(Int(baseline.rounded()))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(ProtocolPalette.mutedText)
                                .padding(.horizontal, 4)
                                .background(ProtocolPalette.backgroundColor.opacity(0.75))
                                .position(x: geo.size.width - 32, y: yPos(baseline, h: geo.size.height))
                        }

                        // Segment lines coloured by version
                        ForEach(0..<count - 1, id: \.self) { i in
                            segmentLine(i: i, w: geo.size.width, h: geo.size.height)
                        }

                        // End dot
                        if let lastVal = values.last {
                            Circle()
                                .fill(sanitizedPoints.last?.color ?? Color.white)
                                .frame(width: 6, height: 6)
                                .position(x: xPos(count - 1, w: geo.size.width), y: yPos(lastVal, h: geo.size.height))
                        }
                    }
                } else {
                    Text("Need at least 2 logged nights to render trend.")
                        .font(.system(size: 11))
                        .foregroundStyle(ProtocolPalette.dimText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func xPos(_ i: Int, w: CGFloat) -> CGFloat {
        count > 1 ? CGFloat(i) * (w / CGFloat(count - 1)) : w / 2
    }

    private func yPos(_ v: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((v - minVal) / range) * (h - 8) - 4
    }

    private func baselinePath(baseline: Double, w: CGFloat, h: CGFloat) -> some View {
        let by = yPos(baseline, h: h)
        return Path { path in
            var x: CGFloat = 0
            while x < w {
                path.move(to: CGPoint(x: x, y: by))
                path.addLine(to: CGPoint(x: x + 4, y: by))
                x += 8
            }
        }
        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
    }

    private func segmentLine(i: Int, w: CGFloat, h: CGFloat) -> some View {
        let p0 = CGPoint(x: xPos(i, w: w),     y: yPos(sanitizedPoints[i].value, h: h))
        let p1 = CGPoint(x: xPos(i + 1, w: w), y: yPos(sanitizedPoints[i + 1].value, h: h))
        return Path { path in
            path.move(to: p0)
            path.addLine(to: p1)
        }
        .stroke(sanitizedPoints[i + 1].color,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Restore Bar (replaces RestoreRing)

struct RestoreBar: View {
    let pct: Double
    let baselinePct: Double?
    let color: Color
    var height: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: height)

                    // Current Value
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(pct, 0) / 100.0, 1.0)), height: height)

                    // Baseline Notch
                    if let base = baselinePct, base.isFinite, base > 0 {
                        let notchX = geo.size.width * CGFloat(min(max(base, 0) / 100.0, 1.0))
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: height + 6)
                            .offset(x: max(0, min(notchX - 1.5, geo.size.width - 3)), y: -3)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    }
                }
            }
            .frame(height: height + 6)
        }
    }
}
