import SwiftUI

struct ChronotypeInsightCardView: View {
    let result: ChronotypeCalculationResult

    @State private var didAppear = false
    @State private var activeTimingInfo: TimingInfo?

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                header

                if let estimate = result.estimate {
                    estimateContent(estimate)
                } else {
                    insufficientContent
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(0.08)) {
                didAppear = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [BetterColors.cyan, BetterColors.brand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: BetterColors.cyan.opacity(0.35), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chronotype")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("\(result.validNightCount) valid wearable nights")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer()

            confidenceBadge(result.estimate?.confidence)
        }
    }

    private func estimateContent(_ estimate: ChronotypeEstimate) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            HStack(alignment: .center, spacing: BetterSpacing.large) {
                ChronotypeClockView(estimate: estimate, isAnimated: didAppear)
                    .frame(width: 136, height: 136)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text(estimate.bucket.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    VStack(alignment: .leading, spacing: 4) {
                        timingButton(
                            title: formatMinute(estimate.correctedMidpointMinute),
                            systemImage: "scope",
                            tint: BetterColors.cyan,
                            info: .correctedMidpoint
                        )
                        timingButton(
                            title: formatWindow(estimate.optimalSleepWindow),
                            systemImage: "moon.zzz.fill",
                            tint: BetterColors.brandLight,
                            info: .optimalWindow
                        )
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())

                    Text("Corrected midpoint and ideal sleep window from recent wearable sleep timing.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ChronotypeMetricStripView(estimate: estimate) { info in
                activeTimingInfo = info
            }

            HStack(spacing: BetterSpacing.small) {
                legendDot(BetterColors.brandLight, "Sleep window")
                legendDot(BetterColors.cyan, "Corrected")
                legendDot(BetterColors.warning, "Weekdays")
                legendDot(BetterColors.success, "Weekends")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Chronotype \(estimate.bucket.displayName), corrected midpoint \(formatMinute(estimate.correctedMidpointMinute)), optimal window \(formatWindow(estimate.optimalSleepWindow))"
        )
        .popover(item: $activeTimingInfo, arrowEdge: .bottom) { info in
            timingPopover(info: info)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var insufficientContent: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            ZStack {
                Circle()
                    .fill(BetterColors.warning.opacity(0.14))
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BetterColors.warning)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                Text("More wearable history needed")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text(missingRequirementsText)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(result.validNightCount) valid nights found in the current window")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.warning)
            }
        }
    }

    private func confidenceBadge(_ confidence: ComparisonConfidence?) -> some View {
        Text(confidence?.displayName ?? "Building")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(confidenceColor(confidence))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(confidenceColor(confidence).opacity(0.13), in: Capsule())
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timingButton(title: String, systemImage: String, tint: Color, info: TimingInfo) -> some View {
        Button {
            activeTimingInfo = info
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(info.title)
    }

    private func timingPopover(info: TimingInfo) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text(info.title)
                .font(BetterTypography.title)
                .foregroundStyle(BetterColors.text)
            Text(info.body)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: 280, alignment: .leading)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var missingRequirementsText: String {
        let labels = result.missingRequirements.map { requirement in
            switch requirement {
            case .totalNights:
                "14 total nights"
            case .workdayNights:
                "6 weekday nights"
            case .freeDayNights:
                "3 weekend nights"
            }
        }

        guard !labels.isEmpty else {
            return "Chronotype will appear after enough valid weekday and weekend sleep data is available."
        }

        return "Need at least \(labels.joined(separator: ", "))."
    }
}

private enum TimingInfo: String, Identifiable {
    case correctedMidpoint
    case optimalWindow
    case weekdayMidpoint
    case weekendMidpoint
    case sleepAverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correctedMidpoint:
            "Corrected midpoint"
        case .optimalWindow:
            "Optimal sleep window"
        case .weekdayMidpoint:
            "Weekday midpoint"
        case .weekendMidpoint:
            "Weekend midpoint"
        case .sleepAverage:
            "Sleep average"
        }
    }

    var body: String {
        switch self {
        case .correctedMidpoint:
            "This is the adjusted center of your sleep timing after we account for extra weekend sleep."
        case .optimalWindow:
            "This is the sleep range the model thinks fits your recent timing best."
        case .weekdayMidpoint:
            "This is the middle of your sleep on weekdays."
        case .weekendMidpoint:
            "This is the middle of your sleep on weekends."
        case .sleepAverage:
            "This is your average sleep duration across the nights used in the chronotype calculation."
        }
    }
}

private struct ChronotypeClockView: View {
    let estimate: ChronotypeEstimate
    let isAnimated: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2 - 13

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BetterColors.cardSecondary.opacity(0.92), BetterColors.card.opacity(0.58)],
                            center: .center,
                            startRadius: 8,
                            endRadius: size / 2
                        )
                    )

                Circle()
                    .stroke(BetterColors.glassStroke.opacity(0.75), lineWidth: 1)

                ForEach(0..<24, id: \.self) { hour in
                    Capsule()
                        .fill(hour % 6 == 0 ? BetterColors.subtext.opacity(0.58) : BetterColors.subtext.opacity(0.24))
                        .frame(width: hour % 6 == 0 ? 2 : 1, height: hour % 6 == 0 ? 8 : 5)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(hour) / 24 * 360))
                }

                ChronotypeSleepWindowArc(window: estimate.optimalSleepWindow, progress: isAnimated ? 1 : 0)
                    .stroke(
                        AngularGradient(
                            colors: [BetterColors.brandLight, BetterColors.cyan, BetterColors.brandLight],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .shadow(color: BetterColors.cyan.opacity(0.5), radius: 8)
                    .padding(8)

                marker(
                    minute: estimate.workdayMidpointMinute,
                    color: BetterColors.warning,
                    center: center,
                    radius: radius - 7,
                    size: 9
                )
                marker(
                    minute: estimate.freeDayMidpointMinute,
                    color: BetterColors.success,
                    center: center,
                    radius: radius - 7,
                    size: 9
                )
                marker(
                    minute: estimate.correctedMidpointMinute,
                    color: BetterColors.cyan,
                    center: center,
                    radius: radius - 18,
                    size: 13
                )

                VStack(spacing: 2) {
                    Text(formatMinute(estimate.correctedMidpointMinute))
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                    Text("midpoint")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
    }

    private func marker(minute: Int, color: Color, center: CGPoint, radius: CGFloat, size: CGFloat) -> some View {
        let point = pointForMinute(minute, center: center, radius: radius)
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(BetterColors.text.opacity(0.82), lineWidth: 1.5))
            .shadow(color: color.opacity(0.72), radius: 8)
            .position(isAnimated ? point : center)
    }
}

private struct ChronotypeMetricStripView: View {
    let estimate: ChronotypeEstimate
    let onSelectTimingInfo: (TimingInfo) -> Void

    var body: some View {
        HStack(spacing: 0) {
                metricCell(label: "Weekdays", value: formatMinute(estimate.workdayMidpointMinute), icon: "briefcase.fill", color: BetterColors.warning, info: .weekdayMidpoint)
                divider
                metricCell(label: "Weekends", value: formatMinute(estimate.freeDayMidpointMinute), icon: "sparkles", color: BetterColors.success, info: .weekendMidpoint)
                divider
                metricCell(label: "Sleep avg", value: formatDuration(estimate.weeklyAverageDuration), icon: "clock.fill", color: BetterColors.cyan, info: .sleepAverage)
            }
        .padding(.vertical, BetterSpacing.small)
        .background(BetterColors.cardSecondary.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(BetterColors.border.opacity(0.58))
            .frame(width: 1, height: 42)
    }

    private func metricCell(label: String, value: String, icon: String, color: Color, info: TimingInfo) -> some View {
        Button {
            onSelectTimingInfo(info)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChronotypeSleepWindowArc: Shape {
    let window: SleepWindowRecommendation
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = angle(for: window.startMinute)
        let sweep = sweepDegrees(from: window.startMinute, to: window.endMinute) * progress
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(start + sweep),
            clockwise: false
        )
        return path
    }
}

private extension ChronotypeInsightCardView {
    func confidenceColor(_ confidence: ComparisonConfidence?) -> Color {
        switch confidence {
        case .high:
            BetterColors.success
        case .medium:
            BetterColors.brand
        case .low:
            BetterColors.warning
        case .unavailable, nil:
            BetterColors.subtext
        }
    }
}

private extension ChronotypeBucket {
    var displayName: String {
        switch self {
        case .early:
            "Early"
        case .earlyIntermediate:
            "Early-intermediate"
        case .intermediate:
            "Intermediate"
        case .lateIntermediate:
            "Late-intermediate"
        case .late:
            "Late"
        }
    }
}

private func formatWindow(_ window: SleepWindowRecommendation) -> String {
    "\(formatMinute(window.startMinute))-\(formatMinute(window.endMinute))"
}

private func formatMinute(_ minute: Int) -> String {
    let normalized = ((minute % 1_440) + 1_440) % 1_440
    let hour = normalized / 60
    let minute = normalized % 60
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    let suffix = hour < 12 ? "AM" : "PM"
    return String(format: "%d:%02d %@", hour12, minute, suffix)
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
}

private func pointForMinute(_ minute: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
    let radians = (Double(minute) / 1_440 * 360 - 90) * .pi / 180
    return CGPoint(
        x: center.x + CGFloat(cos(radians)) * radius,
        y: center.y + CGFloat(sin(radians)) * radius
    )
}

private func angle(for minute: Int) -> Double {
    Double(minute) / 1_440 * 360 - 90
}

private func sweepDegrees(from startMinute: Int, to endMinute: Int) -> Double {
    let delta = (endMinute - startMinute + 1_440) % 1_440
    return Double(delta == 0 ? 1_440 : delta) / 1_440 * 360
}

#if DEBUG
#Preview("Chronotype Insight") {
    ChronotypeInsightCardView(
        result: ChronotypeCalculationResult(
            status: .estimated,
            estimate: ChronotypeEstimate(
                bucket: .earlyIntermediate,
                correctedMidpointMinute: 231,
                workdayMidpointMinute: 261,
                freeDayMidpointMinute: 231,
                workdayMedianDuration: 6.2 * 3_600,
                freeDayMedianDuration: 6.6 * 3_600,
                weeklyAverageDuration: 6.28 * 3_600,
                validNightCount: 59,
                workdayNightCount: 41,
                freeDayNightCount: 18,
                excludedNightCount: 3,
                excludedCountsByReason: [:],
                confidence: .high,
                optimalSleepWindow: SleepWindowRecommendation(startMinute: 44, endMinute: 419, duration: 6.25 * 3_600)
            ),
            includedNights: [],
            excludedCountsByReason: [:],
            totalCandidateNightCount: 62,
            validNightCount: 59,
            workdayNightCount: 41,
            freeDayNightCount: 18,
            missingRequirements: [],
            windowDays: 90,
            windowStart: .now.addingTimeInterval(-90 * 86_400),
            windowEnd: .now
        )
    )
    .padding()
    .background(BetterColors.background)
    .preferredColorScheme(.dark)
}
#endif
