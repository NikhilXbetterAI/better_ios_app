import SwiftUI

enum ChronotypeDialMode: String, CaseIterable, Identifiable {
    case bestWindow
    case yourUsual
    case impact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestWindow: "Best time"
        case .yourUsual: "Your sleep"
        case .impact: "What changed"
        }
    }

    var subtitle: String {
        switch self {
        case .bestWindow: "target"
        case .yourUsual: "actual"
        case .impact: "results"
        }
    }
}

enum ChronotypeDialMarker: String, Identifiable {
    case bedtime
    case midpoint
    case wake
    case actual

    var id: String { rawValue }
}

struct ChronotypeBodyClockDial: View {
    let estimate: ChronotypeEstimate
    let actualBedtimeMinute: Int?
    let actualWakeMinute: Int?
    let alignmentText: String
    let impactSummary: SleepWindowImpactSummary?
    let formatMinute: (Int) -> String

    @State private var selectedMode: ChronotypeDialMode = .bestWindow
    @State private var selectedMarker: ChronotypeDialMarker = .bedtime
    @State private var didAppear = false
    @Namespace private var modeNamespace

    var body: some View {
        VStack(spacing: BetterSpacing.medium) {
            modeSelector
            explanationChip

            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let radius: CGFloat = 82

                ZStack {
                    // 1. Background segments representing day/night progression
                    phaseArc(start: 18 * 60, end: 24 * 60, color: Color(hex: "#10132B"), radius: radius)
                    phaseArc(start: 0, end: 5 * 60, color: Color(hex: "#102B4A"), radius: radius)
                    phaseArc(start: 5 * 60, end: 9 * 60, color: BetterColors.stageAwake.opacity(0.35), radius: radius)
                    phaseArc(start: 9 * 60, end: 18 * 60, color: BetterColors.cardTertiary.opacity(0.5), radius: radius)

                    // 2. Base separator line for the dial
                    Circle()
                        .stroke(BetterColors.border.opacity(0.4), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)

                    // 3. Clock time labels (ticks) around the dial
                    ForEach(labelMinutes, id: \.minute) { item in
                        dialLabel(item.label, minute: item.minute, center: center, radius: radius + 22)
                    }

                    // 4. Target Sleep Arc (Recommended) - Outer Ring
                    ClockArc(startMinute: estimate.optimalSleepWindow.startMinute, endMinute: estimate.optimalSleepWindow.endMinute)
                        .trim(from: 0, to: didAppear ? 1 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [BetterColors.brandLight, BetterColors.cyan, BetterColors.stageREM],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: selectedMode == .yourUsual ? 8 : 12, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius * 2)
                        .opacity(selectedMode == .yourUsual ? 0.35 : 1.0)
                        .shadow(color: BetterColors.cyan.opacity(selectedMode == .yourUsual ? 0.1 : 0.4), radius: 8)

                    // 5. Actual Sleep Arc (Your Usual) - Inner Ring
                    if let actualBedtimeMinute, let actualWakeMinute, selectedMode != .bestWindow {
                        ClockArc(startMinute: actualBedtimeMinute, endMinute: actualWakeMinute)
                            .stroke(
                                BetterColors.text.opacity(selectedMode == .yourUsual ? 0.85 : 0.35),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: selectedMode == .yourUsual ? [] : [6, 6])
                            )
                            .frame(width: (radius - 16) * 2, height: (radius - 16) * 2)
                    }

                    // 6. Interactive Marker Buttons
                    marker(.bedtime, minute: estimate.optimalSleepWindow.startMinute, icon: "moon.fill", color: BetterColors.brandLight, center: center, radius: radius)
                    marker(.midpoint, minute: estimate.correctedMidpointMinute, icon: "circle.fill", color: BetterColors.cyan, center: center, radius: radius)
                    marker(.wake, minute: estimate.optimalSleepWindow.endMinute, icon: "sunrise.fill", color: BetterColors.stageAwake, center: center, radius: radius)

                    if let actualBedtimeMinute, selectedMode != .bestWindow {
                        marker(.actual, minute: actualBedtimeMinute, icon: "bed.double.fill", color: BetterColors.text, center: center, radius: radius - 16)
                    }

                    // 7. Dynamic Center Readout (Shows different timing values based on selected mode)
                    centerReadout
                        .frame(width: radius * 1.5)
                        .position(center)
                        .opacity(didAppear ? 1 : 0)
                        .scaleEffect(didAppear ? 1 : 0.96)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .padding(.top, 8)
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.86).delay(0.08)) {
                    didAppear = true
                }
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(ChronotypeDialMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(mode.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(mode.subtitle)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedMode == mode ? BetterColors.background : BetterColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(BetterColors.text)
                                    .matchedGeometryEffect(id: "selectedDialMode", in: modeNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(BetterColors.cardTertiary.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(BetterColors.border, lineWidth: 1))
    }

    private var explanationChip: some View {
        HStack(alignment: .top, spacing: BetterSpacing.small) {
            Image(systemName: chipIcon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(chipColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(chipTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text(chipBody)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(BetterColors.cardSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
    }

    private var chipTitle: String {
        switch selectedMode {
        case .bestWindow:
            switch selectedMarker {
            case .bedtime: "Your best sleep window"
            case .midpoint: "Middle of your best sleep"
            case .wake: "Best wake time"
            case .actual: "Your usual sleep"
            }
        case .yourUsual:
            "Your real sleep pattern"
        case .impact:
            "What changed in your sleep"
        }
    }

    private var chipBody: String {
        switch selectedMode {
        case .bestWindow:
            switch selectedMarker {
            case .bedtime:
                return "This is the target start time Better recommends for tonight."
            case .midpoint:
                return "This is the middle of the sleep your body seems to prefer."
            case .wake:
                return "This is the wake time that fits your best window."
            case .actual:
                return "Your usual timing is shown as the inner outline ring."
            }
        case .yourUsual:
            return "The outline ring is when you really slept. The blue arc is your best window."
        case .impact:
            guard let impactSummary, impactSummary.hasEnoughData else {
                return "Better needs more inside-window and outside-window nights to compare sleep."
            }
            let score = Int((impactSummary.scoreDelta ?? 0).rounded())
            if score == 0 { return "Sleep score was about the same in your window." }
            return "When you hit the blue window, sleep score was \(abs(score)) points \(score > 0 ? "higher" : "lower")."
        }
    }

    private var chipIcon: String {
        switch selectedMode {
        case .bestWindow:
            selectedMarker == .wake ? "sunrise.fill" : "moon.fill"
        case .yourUsual:
            "bed.double.fill"
        case .impact:
            "chart.bar.xaxis"
        }
    }

    private var chipColor: Color {
        switch selectedMode {
        case .bestWindow:
            selectedMarker == .wake ? BetterColors.stageAwake : BetterColors.brandLight
        case .yourUsual:
            BetterColors.text.opacity(0.82)
        case .impact:
            BetterColors.cyan
        }
    }

    private var centerReadout: some View {
        VStack(spacing: 3) {
            switch selectedMode {
            case .bestWindow:
                Text("RECOMMENDED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.cyan)
                    .tracking(1.2)
                Text("\(formatMinute(estimate.optimalSleepWindow.startMinute))")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                Text("to")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Text("\(formatMinute(estimate.optimalSleepWindow.endMinute))")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)

            case .yourUsual:
                Text("YOUR USUAL")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .tracking(1.2)
                if let bedtime = actualBedtimeMinute, let wake = actualWakeMinute {
                    Text("\(formatMinute(bedtime))")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                    Text("to")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    Text("\(formatMinute(wake))")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                } else {
                    Text("No data")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }

            case .impact:
                Text("SLEEP SCORE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.cyan)
                    .tracking(1.2)
                if let impactSummary, let scoreDelta = impactSummary.scoreDelta {
                    let score = Int(scoreDelta.rounded())
                    Text(score >= 0 ? "+\(score)" : "\(score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(score >= 0 ? BetterColors.success : BetterColors.warning)
                    Text("points")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                } else {
                    Text("Calculating")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    private var labelMinutes: [(minute: Int, label: String)] {
        [
            (21 * 60, "9 PM"),
            (0, "12 AM"),
            (3 * 60, "3 AM"),
            (6 * 60, "6 AM"),
            (9 * 60, "9 AM"),
            (12 * 60, "NOON")
        ]
    }

    private func phaseArc(start: Int, end: Int, color: Color, radius: CGFloat) -> some View {
        ClockArc(startMinute: start, endMinute: end)
            .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
            .frame(width: radius * 2, height: radius * 2)
    }

    private func dialLabel(_ text: String, minute: Int, center: CGPoint, radius: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(BetterColors.mutedText)
            .position(point(for: minute, center: center, radius: radius))
    }

    private func marker(_ marker: ChronotypeDialMarker, minute: Int, icon: String, color: Color, center: CGPoint, radius: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedMarker = marker
                if marker == .actual { selectedMode = .yourUsual }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(BetterColors.background)
                    .frame(width: selectedMarker == marker ? 24 : 18, height: selectedMarker == marker ? 24 : 18)
                Circle()
                    .stroke(color.opacity(0.95), lineWidth: selectedMarker == marker ? 2.0 : 1.2)
                    .frame(width: selectedMarker == marker ? 24 : 18, height: selectedMarker == marker ? 24 : 18)
                Image(systemName: icon)
                    .font(.system(size: marker == .midpoint ? 4 : 8, weight: .bold))
                    .foregroundStyle(color)
            }
            .shadow(color: color.opacity(selectedMarker == marker ? 0.35 : 0.0), radius: 4)
        }
        .buttonStyle(.plain)
        .position(point(for: minute, center: center, radius: radius))
        .opacity(didAppear ? 1 : 0)
        .scaleEffect(didAppear ? 1 : 0.75)
    }

    private func point(for minute: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = (Double(minute) / 1_440 * 360 - 90) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}

private struct ClockArc: Shape {
    let startMinute: Int
    let endMinute: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Double(startMinute) / 1_440 * 360 - 90
        let delta = (endMinute - startMinute + 1_440) % 1_440
        let sweep = Double(delta == 0 ? 1_440 : delta) / 1_440 * 360

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweep),
            clockwise: false
        )
        return path
    }
}
