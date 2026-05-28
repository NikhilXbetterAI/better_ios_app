import SwiftUI

struct ChronotypeInsightCardView: View {
    let result: ChronotypeCalculationResult

    @State private var didAppear = false
    @State private var isShowingDetail = false
    @State private var highlightedMetric: TimingInfo? = nil

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
        .contentShape(Rectangle())
        .onTapGesture {
            if result.estimate != nil {
                isShowingDetail = true
            }
        }
        .sheet(isPresented: $isShowingDetail) {
            ChronotypeDetailExplorationView(result: result)
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
                HStack(spacing: 4) {
                    Text("Body Clock")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    if result.estimate != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BetterColors.mutedText.opacity(0.6))
                    }
                }
                Text("\(result.validNightCount) valid wearable nights")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer()

            readinessBadge(result.estimate?.bodyClockReadiness)
        }
    }

    private func estimateContent(_ estimate: ChronotypeEstimate) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            HStack(alignment: .center, spacing: BetterSpacing.large) {
                ChronotypeClockView(
                    estimate: estimate,
                    isAnimated: didAppear,
                    highlightedMetric: highlightedMetric
                )
                .frame(width: 136, height: 136)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text(estimate.bucket.bodyClockDisplayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Natural bedtime: \(formatMinute(estimate.optimalSleepWindow.startMinute))", systemImage: "moon.zzz.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(BetterColors.brandLight)

                        let drift = abs(estimate.workdayMidpointMinute - estimate.freeDayMidpointMinute)
                        let wrappedDrift = min(drift, 1_440 - drift)
                        if wrappedDrift >= 60 {
                            Label(socialJetLagText(wrappedDrift), systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                                .labelStyle(ColoredIconLabelStyle(iconColor: BetterColors.warning))
                        }
                    }

                    Text("Your Body Clock is estimated from recent wearable sleep timing.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: BetterSpacing.small) {
                legendDot(BetterColors.brandLight, "Sleep window")
                legendDot(BetterColors.warning, "Weekday")
                legendDot(BetterColors.success, "Weekend")
            }

            // Explanatory directive button to click for details
            Button {
                isShowingDetail = true
            } label: {
                HStack(spacing: 6) {
                    Text("How is this calculated?")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(BetterColors.brandLight)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(BetterColors.cardSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BetterColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, BetterSpacing.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Body Clock \(estimate.bucket.bodyClockDisplayName), natural bedtime \(formatMinute(estimate.optimalSleepWindow.startMinute))"
        )
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

    private func readinessBadge(_ readiness: BodyClockReadiness?) -> some View {
        Text(readinessDisplayName(readiness))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(readinessColor(readiness))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(readinessColor(readiness).opacity(0.13), in: Capsule())
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

    private func socialJetLagText(_ driftMinutes: Int) -> String {
        if driftMinutes >= 60 {
            let hours = driftMinutes / 60
            let mins = driftMinutes % 60
            let formatted = mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
            return "Social jet lag: you sleep \(formatted) later on weekends"
        } else {
            return "Social jet lag: you sleep \(driftMinutes) min later on weekends"
        }
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
            return "Body Clock will appear after enough valid weekday and weekend sleep data is available."
        }

        return "Need at least \(labels.joined(separator: ", "))."
    }
}

// TimingInfo is used by ChronotypeClockView to highlight arc/markers on the clock dial.
private enum TimingInfo: String, Identifiable {
    case correctedMidpoint
    case optimalWindow
    case weekdayMidpoint
    case weekendMidpoint
    case sleepAverage

    var id: String { rawValue }
}

private struct ChronotypeClockView: View {
    let estimate: ChronotypeEstimate
    let isAnimated: Bool
    let highlightedMetric: TimingInfo?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2 - 13

            ZStack {
                // Static background + ticks rendered to a single Metal layer.
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
                }
                .drawingGroup()

                let isArcHighlighted = highlightedMetric == .optimalWindow || highlightedMetric == .sleepAverage
                let isAnyHighlighted = highlightedMetric != nil
                let arcOpacity = isArcHighlighted ? 1.0 : (isAnyHighlighted ? 0.18 : 1.0)
                let arcGlow = isArcHighlighted ? 14.0 : 8.0

                ChronotypeSleepWindowArc(window: estimate.optimalSleepWindow, progress: isAnimated ? 1 : 0)
                    .stroke(
                        AngularGradient(
                            colors: [BetterColors.brandLight, BetterColors.cyan, BetterColors.brandLight],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: isArcHighlighted ? 12 : 9, lineCap: .round)
                    )
                    .shadow(color: BetterColors.cyan.opacity(isArcHighlighted ? 0.75 : 0.5), radius: arcGlow)
                    .opacity(arcOpacity)
                    .padding(8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedMetric)

                marker(
                    minute: estimate.workdayMidpointMinute,
                    color: BetterColors.warning,
                    center: center,
                    radius: radius - 7,
                    baseSize: 9,
                    isHighlighted: highlightedMetric == .weekdayMidpoint,
                    isAnyHighlighted: isAnyHighlighted
                )
                marker(
                    minute: estimate.freeDayMidpointMinute,
                    color: BetterColors.success,
                    center: center,
                    radius: radius - 7,
                    baseSize: 9,
                    isHighlighted: highlightedMetric == .weekendMidpoint,
                    isAnyHighlighted: isAnyHighlighted
                )
                marker(
                    minute: estimate.correctedMidpointMinute,
                    color: BetterColors.cyan,
                    center: center,
                    radius: radius - 18,
                    baseSize: 13,
                    isHighlighted: highlightedMetric == .correctedMidpoint,
                    isAnyHighlighted: isAnyHighlighted
                )

                VStack(spacing: 2) {
                    Text(formatMinute(estimate.correctedMidpointMinute))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                    Text("sleep center")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
    }

    private func marker(
        minute: Int,
        color: Color,
        center: CGPoint,
        radius: CGFloat,
        baseSize: CGFloat,
        isHighlighted: Bool,
        isAnyHighlighted: Bool
    ) -> some View {
        let size = isHighlighted ? baseSize * 1.5 : baseSize
        let opacity = isHighlighted ? 1.0 : (isAnyHighlighted ? 0.25 : 1.0)
        let point = pointForMinute(minute, center: center, radius: radius)
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(BetterColors.text.opacity(isHighlighted ? 0.95 : 0.82), lineWidth: isHighlighted ? 2.5 : 1.5))
            .shadow(color: color.opacity(isHighlighted ? 0.95 : 0.72), radius: isHighlighted ? 12 : 8)
            .opacity(opacity)
            .position(isAnimated ? point : center)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedMetric)
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
    func readinessDisplayName(_ readiness: BodyClockReadiness?) -> String {
        switch readiness {
        case .highConfidence:
            "High confidence"
        case .stable:
            "Stable"
        case .preview:
            "Preview"
        case nil:
            "Building"
        }
    }

    func readinessColor(_ readiness: BodyClockReadiness?) -> Color {
        switch readiness {
        case .highConfidence:
            BetterColors.success
        case .stable:
            BetterColors.brand
        case .preview:
            BetterColors.warning
        case nil:
            BetterColors.subtext
        }
    }
}

private func formatMinute(_ minute: Int) -> String {
    let normalized = ((minute % 1_440) + 1_440) % 1_440
    let hour = normalized / 60
    let minute = normalized % 60
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    let suffix = hour < 12 ? "AM" : "PM"
    return String(format: "%d:%02d %@", hour12, minute, suffix)
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

/// LabelStyle that lets the icon use a custom color while the title inherits its own style.
private struct ColoredIconLabelStyle: LabelStyle {
    let iconColor: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(iconColor)
            configuration.title
        }
    }
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
                bodyClockReadiness: .highConfidence,
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
