import SwiftUI

struct ChronotypeDetailExplorationView: View {
    let result: ChronotypeCalculationResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let estimate = result.estimate {
                BodyClockDetailView(result: result, estimate: estimate)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                dismiss()
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(BetterColors.brandLight)
                        }
                    }
            } else {
                VStack {
                    Text("Insufficient Sleep Data")
                        .font(BetterTypography.title)
                        .foregroundStyle(BetterColors.text)
                    Button("Dismiss") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Body Clock Detail View (Root Screen)
struct BodyClockDetailView: View {
    let result: ChronotypeCalculationResult
    let estimate: ChronotypeEstimate

    @State private var isShowingInfo = false

    var lastNight: ChronotypeNight? {
        result.includedNights.last
    }

    var alignment: BodyClockSleepAlignment? {
        guard let lastNight else { return nil }
        return ChronotypeCalculationService().alignment(for: lastNight, estimate: estimate)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BetterSpacing.large) {
                // Large Dial Container
                VStack(spacing: BetterSpacing.medium) {
                    ChronotypeLargeClockView(
                        estimate: estimate,
                        lastNight: lastNight
                    )
                    .frame(width: 250, height: 250)
                    .padding(.top, BetterSpacing.medium)

                    // Sleep Alignment Card
                    if let alignment {
                        VStack(spacing: BetterSpacing.xSmall) {
                            Text("SLEEP ALIGNMENT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.mutedText)
                                .tracking(1.5)

                            Text(alignmentTitle(alignment))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)

                            Text(alignmentDescription(alignment))
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, BetterSpacing.large)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, BetterSpacing.medium)
                    }
                }
                .padding()
                .background(BetterColors.cardSecondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )

                // Navigation Options List
                VStack(spacing: BetterSpacing.medium) {
                    NavigationLink {
                        ChronotypeDetailView(estimate: estimate)
                    } label: {
                        listRow(
                            title: "CHRONOTYPE",
                            value: estimate.bucket.bodyClockDisplayName.replacingOccurrences(of: " Body Clock", with: ""),
                            icon: "sun.max.fill",
                            color: BetterColors.warning
                        )
                    }

                    NavigationLink {
                        SleepRegularityDetailView(nights: result.includedNights, estimate: estimate)
                    } label: {
                        let regularity = calculateRegularity(from: result.includedNights)
                        listRow(
                            title: "SLEEP REGULARITY",
                            value: regularity.category,
                            icon: "waveform.path.ecg",
                            color: BetterColors.cyan
                        )
                    }
                }
            }
            .padding(.horizontal, BetterSpacing.screen)
            .padding(.bottom, BetterSpacing.large)
        }
        .background(BetterColors.background)
        .navigationTitle("Body Clock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(BetterColors.brandLight)
                }
                .popover(isPresented: $isShowingInfo) {
                    VStack(alignment: .leading, spacing: BetterSpacing.small) {
                        Text("About Body Clock")
                            .font(BetterTypography.title)
                            .foregroundStyle(BetterColors.text)
                        Text("Your Body Clock describes your natural circadian rhythm—the internal timing system that regulates your sleepiness, alertness, body temperature, and hormones over a 24-hour cycle.")
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                        Text("Aligning your sleep schedule with this window reduces social jetlag, improves sleep depth, and boosts daily energy.")
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    .padding(BetterSpacing.large)
                    .frame(width: 280)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private func listRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.mutedText)
                    .tracking(1.0)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BetterColors.mutedText.opacity(0.6))
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
    }

    private func alignmentTitle(_ alignment: BodyClockSleepAlignment) -> String {
        let delta = alignment.signedDeltaMinutes
        if abs(delta) <= 20 {
            return "Optimal Alignment"
        } else if delta < 0 {
            return "Ahead"
        } else {
            return "Behind"
        }
    }

    private func alignmentDescription(_ alignment: BodyClockSleepAlignment) -> String {
        let delta = abs(alignment.signedDeltaMinutes)
        let timingWord = alignment.signedDeltaMinutes < 0 ? "ahead of" : "behind"
        if delta <= 20 {
            return "Your sleep midpoint last night was perfectly aligned with your body clock's ideal window."
        } else {
            let hours = delta / 60
            let mins = delta % 60
            let timeString = hours > 0 ? "\(hours)h \(mins)m" : "\(mins) minutes"
            return "The midpoint of your sleep was \(timeString) \(timingWord) your chronotype."
        }
    }
}

// MARK: - Large Concentric 24h Clock Dial
struct ChronotypeLargeClockView: View {
    let estimate: ChronotypeEstimate
    let lastNight: ChronotypeNight?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outerRadius = size / 2 - 12
            let innerRadius = outerRadius - 16

            ZStack {
                // Dial Background Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BetterColors.cardSecondary.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )

                // Outer Dial Ring
                Circle()
                    .stroke(BetterColors.border, lineWidth: 1)

                // Inner Dial Ring
                Circle()
                    .stroke(BetterColors.border.opacity(0.5), lineWidth: 0.5)
                    .frame(width: innerRadius * 2, height: innerRadius * 2)

                // 24 Hour ticks
                ForEach(0..<24, id: \.self) { hour in
                    let isPrimary = hour % 3 == 0
                    let tickLen: CGFloat = isPrimary ? 8 : 4
                    let color = isPrimary ? BetterColors.subtext.opacity(0.6) : BetterColors.mutedText.opacity(0.24)

                    Capsule()
                        .fill(color)
                        .frame(width: isPrimary ? 1.5 : 1, height: tickLen)
                        .offset(y: -outerRadius)
                        .rotationEffect(.degrees(Double(hour) / 24.0 * 360.0))
                }

                // Hour labels around clock (12 AM, 3 AM, 6 AM, 9 AM, 12 PM, 3 PM, 6 PM, 9 PM)
                ForEach([0, 3, 6, 9, 12, 15, 18, 21], id: \.self) { hour in
                    let label = hourText(hour)
                    let pos = labelPosition(hour: hour, center: center, radius: outerRadius + 18)

                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                        .position(pos)
                }

                // Arc 1: Ideal sleep window (Inner circle)
                ChronotypeConcentricSleepArc(
                    startMinute: estimate.optimalSleepWindow.startMinute,
                    endMinute: estimate.optimalSleepWindow.endMinute
                )
                .stroke(
                    BetterColors.cardTertiary.opacity(0.8),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: innerRadius * 2, height: innerRadius * 2)

                // Arc 2: Last Night's sleep window (Outer circle)
                if let lastNight {
                    let onsetMin = minuteOfDay(for: lastNight.onset)
                    let wakeMin = minuteOfDay(for: lastNight.wake)

                    ChronotypeConcentricSleepArc(
                        startMinute: onsetMin,
                        endMinute: wakeMin
                    )
                    .stroke(
                        LinearGradient(
                            colors: [BetterColors.brandLight, BetterColors.cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .shadow(color: BetterColors.cyan.opacity(0.4), radius: 6)

                    // White dot at onset with sleep bed icon
                    let onsetPoint = pointForMinute(onsetMin, center: center, radius: outerRadius)
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(radius: 3)
                        .overlay(
                            Image(systemName: "bed.double.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(BetterColors.card)
                        )
                        .position(onsetPoint)

                    // White dot at wake
                    let wakePoint = pointForMinute(wakeMin, center: center, radius: outerRadius)
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(radius: 2)
                        .position(wakePoint)
                }

                // Midpoint display inside clock
                VStack(spacing: 2) {
                    Text(formatMinute(estimate.correctedMidpointMinute))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                    Text("ideal midpoint")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                }
            }
        }
    }

    private func hourText(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        default:
            let h = hour % 12
            let suffix = hour < 12 ? "AM" : "PM"
            return "\(h) \(suffix)"
        }
    }

    private func labelPosition(hour: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (Double(hour) / 24.0 * 360.0 - 90.0) * .pi / 180.0
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private func pointForMinute(_ minute: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (Double(minute) / 1_440.0 * 360.0 - 90.0) * .pi / 180.0
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

struct ChronotypeConcentricSleepArc: Shape {
    let startMinute: Int
    let endMinute: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Double(startMinute) / 1_440.0 * 360.0 - 90.0
        let delta = (endMinute - startMinute + 1_440) % 1_440
        let sweep = Double(delta == 0 ? 1_440 : delta) / 1_440.0 * 360.0

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

// MARK: - Chronotype Detail View
struct ChronotypeDetailView: View {
    let estimate: ChronotypeEstimate

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Wave Graphic Header Illustration
                ChronotypeWaveHeader(bucket: estimate.bucket)
                    .frame(height: 240)

                VStack(alignment: .leading, spacing: BetterSpacing.large) {
                    // Chronotype Name and Paragraph
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        Text(estimate.bucket.bodyClockDisplayName.replacingOccurrences(of: " Body Clock", with: ""))
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(BetterColors.text)

                        Text(chronotypeDescriptionText(estimate.bucket))
                            .font(.system(size: 16))
                            .lineSpacing(6)
                            .foregroundStyle(BetterColors.subtext)
                    }

                    // Optimal Bedtime Arc Timeline
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        Text("OPTIMAL SLEEP SCHEDULE FOR YOU")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                            .tracking(1.5)

                        ChronotypeArcTimelineView(window: estimate.optimalSleepWindow, idealMidpoint: estimate.correctedMidpointMinute)
                            .frame(height: 120)
                            .padding(.vertical, BetterSpacing.small)
                    }
                    .padding()
                    .background(BetterColors.cardSecondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(BetterColors.glassStroke, lineWidth: 1)
                    )

                    // Timing Breakdown
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        Text("TIMING BREAKDOWN")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                            .tracking(1.5)

                        VStack(spacing: 0) {
                            timingRow(label: "Weekday midpoint", value: formatMinute(estimate.workdayMidpointMinute), color: BetterColors.warning)
                            Divider().background(BetterColors.border)
                            timingRow(label: "Weekend midpoint", value: formatMinute(estimate.freeDayMidpointMinute), color: BetterColors.success)
                            Divider().background(BetterColors.border)
                            timingRow(label: "Corrected midpoint (MSFsc)", value: formatMinute(estimate.correctedMidpointMinute), color: BetterColors.cyan)
                            Divider().background(BetterColors.border)
                            timingRow(label: "Avg sleep duration", value: formatDurationDetail(estimate.weeklyAverageDuration), color: BetterColors.brandLight)
                        }
                        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BetterColors.border, lineWidth: 1))

                        Text("MSFsc (Munich ChronoType Questionnaire method) corrects your free-day sleep midpoint for sleep debt accumulated during the week, giving a truer picture of your circadian preference.")
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Learning Sections
                    VStack(alignment: .leading, spacing: BetterSpacing.large) {
                        educationalSection(
                            title: "How Better knows your chronotype",
                            body: "Your natural circadian rhythm influences your body temperature, sleep-wake cycle, and physical activity. Better calculates your sleep midpoint on free days and adjusts for sleep debt using the research-backed MSFsc method across your last 90 days of sleep."
                        )

                        educationalSection(
                            title: "Why chronotype matters",
                            body: "Chronotype defines your optimal sleep schedule that presets your body's daily rhythms for digestion, alertness, and hormone release. Living according to your chronotype can benefit your energy levels, sleep, and overall well-being."
                        )

                        educationalSection(
                            title: "Can chronotype change?",
                            body: "Your chronotype can adapt as your life changes, but shifts are usually gradual. As people age, their chronotype often becomes earlier. Daily routines, work schedules, or family responsibilities can also cause shifts."
                        )
                    }
                    .padding(.top, BetterSpacing.small)
                }
                .padding(BetterSpacing.screen)
            }
        }
        .background(BetterColors.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timingRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 12)
    }

    private func formatDurationDetail(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    private func educationalSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Text(body)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func chronotypeDescriptionText(_ bucket: ChronotypeBucket) -> String {
        switch bucket {
        case .early:
            return "You are a classic morning type. You feel most energetic in the early hours and naturally wake up early. Social events in the late evening may feel challenging, but you excel in early morning productivity."
        case .earlyIntermediate:
            return "You lean towards morning preference. You enjoy waking up relatively early and feel most productive in the first half of the day, though you can adjust to evening events occasionally."
        case .intermediate:
            return "You have an intermediate body clock. You are flexible, neither an extreme morning lark nor a night owl. You function well during standard daytime hours and have a balanced daily energy profile."
        case .lateIntermediate:
            return "You lean towards evening preference. You find your energy peaking in the afternoon or evening. You prefer sleeping in a bit later and may find early mornings require extra effort to feel fully alert."
        case .late:
            return "You are a classic evening type (night owl). You feel most creative and alert late in the day. Your body naturally wants to stay up late and wake up late, making early morning schedules feel out of sync."
        }
    }
}

// MARK: - Custom Wave Header Illustration
struct ChronotypeWaveHeader: View {
    let bucket: ChronotypeBucket

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                // Sky background gradient
                LinearGradient(
                    colors: skyColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Sun
                Circle()
                    .fill(sunGradient)
                    .frame(width: 140, height: 140)
                    .blur(radius: 0.5)
                    .shadow(color: sunColor.opacity(0.4), radius: 30)
                    .offset(y: -20)

                // Wave 1 (Back wave)
                WaveShape(offset: 15, percent: 0.38)
                    .fill(waveColor1)
                    .opacity(0.5)

                // Wave 2 (Middle wave)
                WaveShape(offset: 25, percent: 0.3)
                    .fill(waveColor2)
                    .opacity(0.7)

                // Wave 3 (Front wave)
                WaveShape(offset: 20, percent: 0.22)
                    .fill(waveColor3)
            }
            .drawingGroup()
            .frame(width: width, height: height)
        }
    }

    private var skyColors: [Color] {
        switch bucket {
        case .early, .earlyIntermediate, .intermediate:
            // Warm Sunrise
            [Color(hex: "#FF8A65"), Color(hex: "#FFCC80"), Color(hex: "#263238").opacity(0.1)]
        case .lateIntermediate, .late:
            // Twilight/Dusk
            [Color(hex: "#311B92"), Color(hex: "#880E4F"), Color(hex: "#10111B")]
        }
    }

    private var sunColor: Color {
        switch bucket {
        case .early, .earlyIntermediate, .intermediate:
            Color(hex: "#FFE082")
        case .lateIntermediate, .late:
            Color(hex: "#FFD54F")
        }
    }

    private var sunGradient: LinearGradient {
        LinearGradient(
            colors: [sunColor, sunColor.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var waveColor1: Color {
        switch bucket {
        case .early, .earlyIntermediate, .intermediate:
            Color(hex: "#0C5A82")
        case .lateIntermediate, .late:
            Color(hex: "#061A40")
        }
    }

    private var waveColor2: Color {
        switch bucket {
        case .early, .earlyIntermediate, .intermediate:
            Color(hex: "#148FBB")
        case .lateIntermediate, .late:
            Color(hex: "#0C3C80")
        }
    }

    private var waveColor3: Color {
        switch bucket {
        case .early, .earlyIntermediate, .intermediate:
            Color(hex: "#1BB2D9")
        case .lateIntermediate, .late:
            Color(hex: "#1A5A9E")
        }
    }
}

struct WaveShape: Shape {
    var offset: CGFloat
    var percent: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let y = height * CGFloat(1.0 - percent)

        path.move(to: CGPoint(x: 0, y: y))

        // Draw overlapping curve
        let control1 = CGPoint(x: width * 0.28, y: y - offset)
        let control2 = CGPoint(x: width * 0.72, y: y + offset)
        path.addCurve(to: CGPoint(x: width, y: y), control1: control1, control2: control2)

        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        return path
    }
}

// MARK: - Optimal Bedtime Arc Timeline View
struct ChronotypeArcTimelineView: View {
    let window: SleepWindowRecommendation
    let idealMidpoint: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                // Background shallow arc (9 PM to 9 AM)
                ChronotypeTimelineArc()
                    .stroke(BetterColors.border.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Highlighted sleep window arc
                ChronotypeTimelineHighlightArc(startMinute: window.startMinute, endMinute: window.endMinute)
                    .stroke(
                        LinearGradient(colors: [BetterColors.brandLight, BetterColors.cyan], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .shadow(color: BetterColors.cyan.opacity(0.35), radius: 6)

                // Dots and Labels
                let onsetPoint = pointOnArc(for: window.startMinute, rect: proxy.frame(in: .local))
                let midpointPoint = pointOnArc(for: idealMidpoint, rect: proxy.frame(in: .local))
                let wakePoint = pointOnArc(for: window.endMinute, rect: proxy.frame(in: .local))

                // Time markings
                // 9 PM label at far left
                Text("9 PM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BetterColors.mutedText)
                    .position(x: 16, y: height - 12)

                // 9 AM label at far right
                Text("9 AM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BetterColors.mutedText)
                    .position(x: width - 16, y: height - 12)

                // Onset marker
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .position(onsetPoint)

                // Midpoint marker
                Circle()
                    .fill(BetterColors.cyan)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .position(midpointPoint)

                // Wake marker
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .position(wakePoint)

                // Text under columns
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ASLEEP")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(BetterColors.mutedText)
                        Text(formatMinute(window.startMinute))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 3) {
                        Text("MIDPOINT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(BetterColors.mutedText)
                        Text(formatMinute(idealMidpoint))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("AWAKE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(BetterColors.mutedText)
                        Text(formatMinute(window.endMinute))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                    }
                }
                .padding(.horizontal, 32)
                .position(x: width / 2, y: height - 18)
            }
        }
    }

    private func pointOnArc(for minute: Int, rect: CGRect) -> CGPoint {
        // Arc spans from 9 PM (1260) to 9 AM (540). Total 720 minutes.
        let arcWidth = rect.width - 64
        let fraction = Double((minute - 1260 + 1_440) % 1_440) / 720.0
        let x = 32 + CGFloat(fraction) * arcWidth

        // Semicircular height curve
        let radius = arcWidth / 2
        let relativeX = CGFloat(fraction) * arcWidth - radius
        let sq = radius * radius - relativeX * relativeX
        let yOffset = sq > 0 ? sqrt(sq) : 0
        // Offset y to represent the dome shape
        let y = rect.height - 42 - yOffset * 0.45

        return CGPoint(x: x, y: y)
    }
}

struct ChronotypeTimelineArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arcWidth = rect.width - 64
        let radius = arcWidth / 2
        let centerY = rect.height - 42

        path.addArc(
            center: CGPoint(x: rect.midX, y: centerY + radius * 0.55),
            radius: radius,
            startAngle: .degrees(180 + 35),
            endAngle: .degrees(360 - 35),
            clockwise: false
        )
        return path
    }
}

struct ChronotypeTimelineHighlightArc: Shape {
    let startMinute: Int
    let endMinute: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arcWidth = rect.width - 64
        let radius = arcWidth / 2
        let centerY = rect.height - 42

        let startFraction = Double((startMinute - 1260 + 1_440) % 1_440) / 720.0
        let endFraction = Double((endMinute - 1260 + 1_440) % 1_440) / 720.0

        let startAngle = 180 + 35 + startFraction * (180 - 70)
        let endAngle = 180 + 35 + endFraction * (180 - 70)

        path.addArc(
            center: CGPoint(x: rect.midX, y: centerY + radius * 0.55),
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

// MARK: - Sleep Regularity Detail View
struct SleepRegularityDetailView: View {
    let nights: [ChronotypeNight]
    let estimate: ChronotypeEstimate

    var body: some View {
        let stats = calculateRegularity(from: nights)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                // Header card
                VStack(spacing: BetterSpacing.small) {
                    Text("SLEEP REGULARITY")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                        .tracking(1.5)

                    Text(stats.category)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.cyan)

                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(BetterColors.mutedText)
                        Text(String(format: "SD of Midpoint: %.0f min", stats.sdMinutes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.mutedText)
                    }

                    Text(stats.description)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BetterSpacing.large)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(BetterColors.cardSecondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )

                // Recent Timing Chart
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    Text("RECENT TIMING CONSISTENCY")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.mutedText)
                        .tracking(1.5)

                    RegularityTimelineChart(
                        nights: nights.suffix(14),
                        idealStartMinute: estimate.optimalSleepWindow.startMinute,
                        idealEndMinute: estimate.optimalSleepWindow.endMinute
                    )
                    .frame(height: CGFloat(min(nights.suffix(14).count, 14) * 36) + 40)
                    .padding()
                    .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(BetterColors.border, lineWidth: 1)
                    )
                }

                // Learn More
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    Text("What is Sleep Regularity?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("Sleep Regularity measures how consistent your sleep and wake times are from day to day. High sleep regularity aligns your body clock, boosting your sleep quality, daily mood, and alertness.")
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Tips to lock in your rhythm")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text("1. Try to go to bed and wake up at the same time every day, even on weekends.\n2. Expose your eyes to bright natural sunlight shortly after waking up.\n3. Avoid blue light and heavy meals for at least 2 hours before bed.")
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, BetterSpacing.small)
            }
            .padding(BetterSpacing.screen)
        }
        .background(BetterColors.background)
        .navigationTitle("Sleep Regularity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Regularity Timeline Chart
struct RegularityTimelineChart: View {
    let nights: ArraySlice<ChronotypeNight>
    let idealStartMinute: Int
    let idealEndMinute: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let rowHeight: CGFloat = 36
            let chartWidth = width - 70 // Leave 70pt for date label

            ZStack(alignment: .topLeading) {
                // Background Vertical Time Guides (9 PM, 12 AM, 3 AM, 6 AM, 9 AM)
                let guideMinutes = [1260, 0, 180, 360, 540]
                ForEach(guideMinutes, id: \.self) { minOfDay in
                    let xOffset = 70 + fractionForMinute(minOfDay) * chartWidth
                    Path { path in
                        path.move(to: CGPoint(x: xOffset, y: 0))
                        path.addLine(to: CGPoint(x: xOffset, y: height - 20))
                    }
                    .stroke(BetterColors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Text(timeLabel(minOfDay))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(BetterColors.mutedText)
                        .position(x: xOffset, y: height - 10)
                }

                // Vertical Ideal Window band
                let idealX = 70 + fractionForMinute(idealStartMinute) * chartWidth
                let idealW = widthOfWindow(start: idealStartMinute, end: idealEndMinute) * chartWidth
                Rectangle()
                    .fill(BetterColors.brand.opacity(0.12))
                    .frame(width: idealW, height: height - 20)
                    .position(x: idealX + idealW / 2, y: (height - 20) / 2)

                // List of Sleep Bars
                VStack(spacing: 0) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                        HStack(spacing: 0) {
                            // Date Label
                            Text(formatDate(night.sleepDateKey))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.mutedText)
                                .frame(width: 60, alignment: .leading)
                                .padding(.leading, 10)

                            // Horizontal Bar Area
                            ZStack(alignment: .leading) {
                                let onsetMin = minuteOfDay(for: night.onset)
                                let wakeMin = minuteOfDay(for: night.wake)

                                let barX = fractionForMinute(onsetMin) * chartWidth
                                let barW = max(widthOfWindow(start: onsetMin, end: wakeMin) * chartWidth, 10)

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [BetterColors.brandLight.opacity(0.72), BetterColors.cyan.opacity(0.85)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: barW, height: 12)
                                    .offset(x: barX)
                            }
                            .frame(width: chartWidth, height: rowHeight)
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    private func fractionForMinute(_ minute: Int) -> CGFloat {
        // Spans 9 PM (1260) to 9 AM (540). Total 720 minutes.
        let delta = (minute - 1260 + 1_440) % 1_440
        return CGFloat(min(max(Double(delta) / 720.0, 0.0), 1.0))
    }

    private func widthOfWindow(start: Int, end: Int) -> CGFloat {
        let delta = (end - start + 1_440) % 1_440
        return CGFloat(min(max(Double(delta) / 720.0, 0.0), 1.0))
    }

    private func timeLabel(_ minute: Int) -> String {
        switch minute {
        case 1260: return "9 PM"
        case 0: return "12 AM"
        case 180: return "3 AM"
        case 360: return "6 AM"
        case 540: return "9 AM"
        default: return ""
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E d"
        return f
    }()

    private func formatDate(_ dateKey: String) -> String {
        guard let date = Self.dateFormatter.date(from: dateKey) else { return dateKey }
        return Self.displayFormatter.string(from: date)
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

// MARK: - Regularity Calculator
func calculateRegularity(from nights: [ChronotypeNight]) -> (sdMinutes: Double, category: String, description: String) {
    guard nights.count >= 3 else {
        return (0, "Insufficient Data", "Need at least 3 nights of sleep data to calculate regularity.")
    }

    // Circular Mean of midpoints
    let minutes = nights.map(\.midpointMinute)
    let angles = minutes.map { Double($0) / 1_440.0 * 2.0 * Double.pi }
    let sine = angles.map(sin).reduce(0, +) / Double(angles.count)
    let cosine = angles.map(cos).reduce(0, +) / Double(angles.count)
    var meanAngle = atan2(sine, cosine)
    if meanAngle < 0 { meanAngle += 2 * Double.pi }
    let anchor = meanAngle / (2 * Double.pi) * 1_440.0

    // Unwrap midpoints around the anchor
    let unwrapped = minutes.map { minute -> Double in
        var value = Double(minute)
        while value - anchor > 720 { value -= 1_440 }
        while anchor - value > 720 { value += 1_440 }
        return value
    }

    let mean = unwrapped.reduce(0, +) / Double(unwrapped.count)
    let variance = unwrapped.map { pow($0 - mean, 2) }.reduce(0, +) / Double(unwrapped.count)
    let sd = sqrt(variance)

    let category: String
    let desc: String
    if sd < 30 {
        category = "Optimal"
        desc = "Your sleep timing is highly consistent day-to-day, keeping your biological clock perfectly locked in sync."
    } else if sd < 60 {
        category = "Good"
        desc = "Your sleep timing is stable with minor variations, supporting strong daily energy levels."
    } else if sd < 90 {
        category = "Fair"
        desc = "Your sleep timing fluctuates, which can occasionally cause sleepiness and social jetlag."
    } else {
        category = "Inconsistent"
        desc = "Your sleep timing is irregular. Setting a consistent wake-up time will help align your circadian rhythm."
    }

    return (sd, category, desc)
}

// MARK: - Format Utilities (duplicated for self-containment)
private func formatMinute(_ minute: Int) -> String {
    let normalized = ((minute % 1_440) + 1_440) % 1_440
    let hour = normalized / 60
    let minVal = normalized % 60
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    let suffix = hour < 12 ? "AM" : "PM"
    return String(format: "%d:%02d %@", hour12, minVal, suffix)
}
