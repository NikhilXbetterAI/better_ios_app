import SwiftUI

struct ChronotypeTabView: View {
    @Bindable var viewModel: ChronotypeViewModel
    @State private var isLearningExpanded = false
    @State private var selectedAlignmentNightKey: String?
    @State private var showChronotypeInfo = false

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header

                    if viewModel.isLoading && viewModel.state == nil {
                        loadingCard
                    } else if let errorMessage = viewModel.errorMessage {
                        errorCard(errorMessage)
                    } else if let state = viewModel.state {
                        if let estimate = state.chronotypeResult.estimate {
                            bodyClockHero(state: state, estimate: estimate)
                            timingPlanCard(state: state, estimate: estimate)
                            clockVisualCard(state: state, estimate: estimate)
                            sevenNightCard(state: state, estimate: estimate)
                            impactCard(state.sleepWindowImpact)
                            nightExamplesCard(best: state.bestNight, worst: state.worstNight)
                            educationSection(estimate: estimate)
                        } else {
                            insufficientDataCard(state.chronotypeResult)
                        }
                    }

                    Spacer(minLength: 140)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("Chronotype")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.onAppear()
        }
        .refreshable {
            await viewModel.loadData()
        }
        .sheet(isPresented: $showChronotypeInfo) {
            ChronotypeExplanationSheet()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            BetterColors.background
            RadialGradient(
                colors: [BetterColors.cyan.opacity(0.1), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BODY CLOCK")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.cyan)
                .tracking(1.6)
            Text("Chronotype")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Text("Your sleep type and Better's recommended timing.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var loadingCard: some View {
        BetterHealthCard {
            HStack(spacing: BetterSpacing.medium) {
                ProgressView()
                    .tint(BetterColors.brandLight)
                Text("Finding your best sleep window...")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
            }
            .padding(.vertical, BetterSpacing.small)
        }
    }

    private func errorCard(_ message: String) -> some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text("Could not load Chronotype")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text(message)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    private func insufficientDataCard(_ result: ChronotypeCalculationResult) -> some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Label("Building your body clock", systemImage: "calendar.badge.clock")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                    .labelStyle(ChronotypeColoredIconLabelStyle(iconColor: BetterColors.cyan))

                let needed = max(0, 7 - result.validNightCount)
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    progressBar(current: result.validNightCount, total: 7)
                    Text("\(result.validNightCount) of 7 nights tracked")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    if needed > 0 {
                        Text("\(needed) more night\(needed == 1 ? "" : "s") to unlock your body clock estimate.")
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Keep wearing your watch to sleep. Once unlocked you'll see your best sleep window, tonight's timing plan, and how your sleep changes when you hit your window.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressBar(current: Int, total: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BetterColors.cardTertiary.opacity(0.9))
                    .frame(height: 8)
                Capsule()
                    .fill(LinearGradient(
                        colors: [BetterColors.brandLight, BetterColors.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(
                        width: max(0, proxy.size.width * min(1, Double(current) / Double(total))),
                        height: 8
                    )
            }
        }
        .frame(height: 8)
    }

    private func bodyClockHero(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        let chronotypeName = chronotypeTitle(for: estimate.bucket)

        return BetterHealthCard(cornerRadius: 28, padding: BetterSpacing.xLarge) {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                HStack(alignment: .center, spacing: BetterSpacing.medium) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [BetterColors.cyan, BetterColors.brand],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("Your chronotype")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.cyan)
                                .textCase(.uppercase)
                                .tracking(1.0)
                            Button {
                                showChronotypeInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BetterColors.cyan.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Show info about chronotypes.")
                        }
                        Text(chronotypeName)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text(chronotypeMeaning(for: estimate.bucket))
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    confidenceBadge(estimate.bodyClockReadiness, nightCount: state.chronotypeResult.validNightCount)
                        .padding(.top, 4)
                }

                VStack(spacing: BetterSpacing.medium) {
                    recommendedByBetterBlock(state: state, estimate: estimate)
                    Divider().background(BetterColors.border.opacity(0.45))
                    usualSleepBlock(state: state, estimate: estimate)
                }

                coachPill(state: state, estimate: estimate)
            }
        }
    }

    private func recommendedByBetterBlock(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recommended by Better")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.cyan)
                    .textCase(.uppercase)
                Spacer()
                Text("tonight")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Text("\(formatMinute(estimate.optimalSleepWindow.startMinute))-\(formatMinute(estimate.optimalSleepWindow.endMinute))")
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.cyan.opacity(0.16), lineWidth: 1))
    }

    private func usualSleepBlock(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Your usual sleep")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .textCase(.uppercase)

            HStack(spacing: BetterSpacing.small) {
                compactTimingChip(
                    icon: "bed.double.fill",
                    title: "Bedtime",
                    value: state.actualAverageBedtimeMinute.map(formatMinute) ?? "--",
                    color: BetterColors.stageDeep
                )
                compactTimingChip(
                    icon: "alarm.fill",
                    title: "Wake",
                    value: state.actualAverageWakeMinute.map(formatMinute) ?? "--",
                    color: BetterColors.warning
                )
                compactTimingChip(
                    icon: "clock.fill",
                    title: "Sleep",
                    value: state.actualAverageDuration.map(formatDuration) ?? "--",
                    color: BetterColors.brand
                )
            }
        }
    }

    private func compactTimingChip(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(BetterColors.cardSecondary.opacity(0.64), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func clockVisualCard(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        BetterHealthCard(cornerRadius: 24, padding: BetterSpacing.large) {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Circadian Alignment")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                        Text("Your actual bedtime compared to your body's recommended clock.")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    Spacer(minLength: 0)
                }

                ChronotypeBodyClockDial(
                    estimate: estimate,
                    actualBedtimeMinute: state.actualAverageBedtimeMinute,
                    actualWakeMinute: state.actualAverageWakeMinute,
                    alignmentText: alignmentText(state: state, estimate: estimate),
                    impactSummary: state.sleepWindowImpact,
                    formatMinute: formatMinute
                )
            }
        }
    }

    private func socialJetlagChip(minutes: Int, category: SocialJetlagCategory) -> some View {
        let color: Color = {
            switch category {
            case .low: return BetterColors.success
            case .moderate: return BetterColors.warning
            case .high: return BetterColors.danger
            case .severe: return BetterColors.danger
            }
        }()

        return HStack(spacing: BetterSpacing.small) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Social Jetlag")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(formatShortDuration(minutes: minutes))
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                    Text("·")
                        .foregroundStyle(BetterColors.subtext)
                    Text(category.displayLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                }
                Text("Difference between your weekday and weekend sleep timing.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private func timingPlanCard(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        let optimalStart = estimate.optimalSleepWindow.startMinute
        let supplementRows = viewModel.supplementTimingRows(optimalSleepStartMinute: optimalStart)

        return BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("Tonight's timing")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)

                sleepWindowLadder(state: state)

                VStack(spacing: BetterSpacing.medium) {
                    // Supplement rows from active formula (or CTA)
                    ForEach(supplementRows) { row in
                        if row.isCTA {
                            supplementCTARow()
                            Divider().background(BetterColors.border.opacity(0.45))
                        } else {
                            timingPlanRow(
                                icon: "pills.fill",
                                title: row.supplementName,
                                value: "Around \(formatMinute(row.recommendedMinute))",
                                color: BetterColors.brand,
                                caption: "\(row.offsetMinutes) min before your sleep window."
                            )
                            Divider().background(BetterColors.border.opacity(0.45))
                        }
                    }

                    timingPlanRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Avoid starting sleep",
                        value: avoidRangeText(state),
                        color: BetterColors.warning,
                        caption: "Too far outside your window can make sleep lighter."
                    )

                    Divider().background(BetterColors.border.opacity(0.45))

                    timingPlanRow(
                        icon: "sun.max.fill",
                        title: "Anchor your morning",
                        value: state.actualAverageWakeMinute.map { formatMinute($0) } ?? "After waking",
                        color: BetterColors.stageAwake,
                        caption: "Get bright light after waking. It helps your body clock stay steady."
                    )

                    Divider().background(BetterColors.border.opacity(0.45))

                    timingPlanRow(
                        icon: "iphone.slash",
                        title: "Wind down",
                        value: state.recommendedFormulaMinute.map { "\(formatMinute($0)) onward" } ?? "Before bed",
                        color: BetterColors.cyan,
                        caption: "Dim lights and keep screens calm before your formula time."
                    )
                }
            }
        }
    }

    private func supplementCTARow() -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(BetterColors.brand.opacity(0.7))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Add a sleep formula")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.brand.opacity(0.9))
                Text("Get personalized supplement timing for tonight.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func impactCard(_ impact: SleepWindowImpactSummary?) -> some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Label("What happens when you hit your window", systemImage: "chart.bar.xaxis")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                    .labelStyle(ChronotypeColoredIconLabelStyle(iconColor: BetterColors.cyan))

                impactContent(impact)
            }
        }
    }

    private func educationSection(estimate: ChronotypeEstimate) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isLearningExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Learn about your body clock")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                        Text(isLearningExpanded ? "Hide the details" : "Short answers, no science wall.")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BetterColors.subtext)
                        .rotationEffect(.degrees(isLearningExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isLearningExpanded {
                VStack(alignment: .leading, spacing: BetterSpacing.large) {
                    educationBlock(
                        title: "How Better knows",
                        body: "Better looks at your wearable sleep from the last 7 to 90 days. It finds the sleep window your body returns to most often, then checks how steady that timing is."
                    )

                    educationBlock(
                        title: "Why it matters",
                        body: "Your body clock helps set when you feel sleepy and alert. Sleeping closer to it can make nights feel easier and mornings less rough."
                    )

                    educationBlock(
                        title: "Can it change?",
                        body: "Yes, but usually slowly. Age, work, travel, family life, and light can shift your clock. Better updates this as your sleep changes."
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, BetterSpacing.small)
    }

    private func coachPill(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: coachIcon(state: state, estimate: estimate))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(alignmentColor(state: state, estimate: estimate))
            Text(coachPillTitle(state: state, estimate: estimate))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            if let actual = state.actualAverageBedtimeMinute {
                Text("usual \(formatMinute(actual))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(alignmentColor(state: state, estimate: estimate).opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(alignmentColor(state: state, estimate: estimate).opacity(0.18), lineWidth: 1))
    }

    private func sevenNightCard(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        BetterHealthCard(cornerRadius: 22, padding: BetterSpacing.large) {
            sevenNightAlignmentStrip(state: state, estimate: estimate)
        }
    }

    private func sevenNightAlignmentStrip(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> some View {
        let nights = Array(state.chronotypeResult.includedNights.suffix(7))

        return VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text("Last sleep starts")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                Text("near your window")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            if nights.isEmpty {
                Text("Wear your device for a few more nights.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { _, night in
                        alignmentDot(
                            for: night,
                            estimate: estimate,
                            isSelected: (selectedAlignmentNightKey ?? nights.last?.id) == night.id
                        )
                    }
                }

                alignmentLegend

                if let selectedNight = selectedAlignmentNight(from: nights) {
                    alignmentNightSummary(for: selectedNight, estimate: estimate)
                }
            }
        }
        .padding(.top, BetterSpacing.xSmall)
    }

    private func alignmentDot(for night: ChronotypeNight, estimate: ChronotypeEstimate, isSelected: Bool) -> some View {
        let minute = minuteOfDay(for: night.onset)
        let delta = abs(signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: minute))
        let color = alignmentColor(forDelta: delta)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedAlignmentNightKey = night.id
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? color.opacity(0.95) : .clear, lineWidth: 2)
                        .frame(width: 25, height: 25)
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .shadow(color: color.opacity(0.45), radius: 7)
                }
                Text(shortWeekday(for: night.onset))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? BetterColors.text : BetterColors.mutedText)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(shortWeekday(for: night.onset)) sleep start \(alignmentStatusText(forDelta: delta))")
    }

    private var alignmentLegend: some View {
        HStack(spacing: BetterSpacing.small) {
            legendItem(color: BetterColors.success, text: "On Time")
            legendItem(color: BetterColors.warning, text: "Slightly Off")
            legendItem(color: BetterColors.danger, text: "Far Off")
        }
        .padding(.top, 2)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func alignmentNightSummary(for night: ChronotypeNight, estimate: ChronotypeEstimate) -> some View {
        let minute = minuteOfDay(for: night.onset)
        let signedDelta = signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: minute)
        let delta = abs(signedDelta)
        let color = alignmentColor(forDelta: delta)
        let status = alignmentStatusText(forDelta: delta)
        let detail = delta <= 30 ? "inside your best window" : "\(formatShortDuration(minutes: delta)) \(signedDelta > 0 ? "late" : "early")"

        return HStack(spacing: BetterSpacing.small) {
            Image(systemName: delta <= 30 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text("\(shortWeekday(for: night.onset)): \(status) • \(formatMinute(minute)) start • \(detail)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private func sleepWindowLadder(state: ChronotypeDashboardState) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text("Sleep start zone")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Spacer()
                Text("best in the middle")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let bestStart = width * 0.36
                let bestWidth = width * 0.28

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BetterColors.cardTertiary.opacity(0.9))
                        .frame(height: 10)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BetterColors.brandLight, BetterColors.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: bestWidth, height: 10)
                        .offset(x: bestStart)
                        .shadow(color: BetterColors.cyan.opacity(0.35), radius: 10)
                }
            }
            .frame(height: 12)

            HStack(alignment: .top) {
                ladderLabel("Too early", minute: state.avoidSleepBeforeMinute)
                Spacer()
                ladderLabel("Best start", minute: state.chronotypeResult.estimate?.optimalSleepWindow.startMinute)
                Spacer()
                ladderLabel("Too late", minute: state.avoidSleepAfterMinute)
            }
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.cardSecondary.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
    }

    @ViewBuilder
    private func impactContent(_ impact: SleepWindowImpactSummary?) -> some View {
        if let impact, impact.hasEnoughData {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                if let scoreDelta = impact.scoreDelta {
                    let score = Int(scoreDelta.rounded())
                    if score > 0 {
                        Text("On nights you hit your window, your sleep score was \(score) points higher on average.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.success)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if score < 0 {
                        Text("On nights you missed your window, your sleep score was \(abs(score)) points lower on average.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Your sleep score was similar regardless of whether you hit your window.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: BetterSpacing.small) {
                    impactBar("Sleep score", value: impact.scoreDelta, unit: "pts", lowerIsBetter: false)
                    impactBar("Restorative", value: impact.restorativeDelta, lowerIsBetter: false)
                    impactBar("Deep", value: impact.deepDelta, lowerIsBetter: false)
                    impactBar("REM", value: impact.remDelta, lowerIsBetter: false)
                    impactBar("Wake time", value: impact.awakeDelta, lowerIsBetter: true)
                    impactBar("Total sleep", value: impact.durationDelta, lowerIsBetter: false)
                }

                Text("These are patterns from your data, not a guarantee.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .padding(.top, BetterSpacing.xSmall)
            }
        } else {
            Text("More nights needed to compare your best window.")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func nightExamplesCard(best: ChronotypeNightSummary?, worst: ChronotypeNightSummary?) -> some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("Best and worst nights")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)

                if let best {
                    nightRow(title: "Best night", night: best, color: BetterColors.success)
                }

                if let worst {
                    Divider().background(BetterColors.border.opacity(0.45))
                    nightRow(title: "Worst night", night: worst, color: BetterColors.warning)
                }
            }
        }
    }

    private func impactBar(_ title: String, value: Double?, unit: String, lowerIsBetter: Bool) -> some View {
        let delta = value ?? 0
        let isFlat = abs(delta) < 0.5
        let isGood = lowerIsBetter ? delta < 0 : delta > 0
        let magnitude = min(abs(delta) / 20, 1)
        return impactBarRow(
            title: title,
            value: isFlat ? "Same" : String(format: "%+0.0f %@", delta, unit),
            magnitude: magnitude,
            color: isFlat ? BetterColors.subtext : (isGood ? BetterColors.success : BetterColors.warning)
        )
    }

    private func impactBar(_ title: String, value: TimeInterval?, lowerIsBetter: Bool) -> some View {
        let delta = value ?? 0
        let minutes = Int((delta / 60).rounded())
        let isFlat = abs(minutes) < 15
        let isGood = lowerIsBetter ? minutes < 0 : minutes > 0
        let magnitude = min(Double(abs(minutes)) / 45, 1)
        return impactBarRow(
            title: title,
            value: isFlat ? "Same" : String(format: "%+d min", minutes),
            magnitude: magnitude,
            color: isFlat ? BetterColors.subtext : (isGood ? BetterColors.success : BetterColors.warning)
        )
    }

    private func impactBarRow(title: String, value: String, magnitude: Double, color: Color) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BetterColors.cardTertiary.opacity(0.8))
                    Capsule()
                        .fill(color.opacity(0.82))
                        .frame(width: max(8, proxy.size.width * magnitude))
                }
            }
            .frame(height: 8)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 74, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 3)
    }

    private func timingPlanRow(icon: String, title: String, value: String, color: Color, caption: String) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Spacer(minLength: 10)
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.72)
                }
                Text(caption)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ladderLabel(_ title: String, minute: Int?) -> some View {
        VStack(alignment: title == "Too early" ? .leading : (title == "Too late" ? .trailing : .center), spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.mutedText)
                .textCase(.uppercase)
            Text(minute.map(formatMinute) ?? "--")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(title == "Best start" ? BetterColors.cyan : BetterColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private func educationBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nightRow(title: String, night: ChronotypeNightSummary, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Spacer()
                Text("Score \(Int(night.score.rounded()))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
            }

            Text("\(formatMinute(night.bedtimeMinute))-\(formatMinute(night.wakeMinute)) · \(formatDuration(night.duration))")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
            Text(night.reason)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func confidenceBadge(_ readiness: BodyClockReadiness, nightCount: Int) -> some View {
        Text("\(readinessText(readiness)) · \(nightCount) nights")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(readinessColor(readiness))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(readinessColor(readiness).opacity(0.13), in: Capsule())
    }

    private func coachPillTitle(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> String {
        guard let actual = state.actualAverageBedtimeMinute else {
            return "Still learning"
        }

        let delta = signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: actual)
        let absDelta = abs(delta)
        if absDelta <= 20 { return "On track" }
        if absDelta <= 60 { return "Close to window" }
        return delta > 0 ? "Running late" : "Running early"
    }

    private func coachIcon(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> String {
        guard let actual = state.actualAverageBedtimeMinute else { return "sparkles" }
        let delta = abs(signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: actual))
        return delta <= 20 ? "checkmark.circle.fill" : "arrow.left.and.right.circle.fill"
    }

    private func selectedAlignmentNight(from nights: [ChronotypeNight]) -> ChronotypeNight? {
        if let selectedAlignmentNightKey,
           let selected = nights.first(where: { $0.id == selectedAlignmentNightKey }) {
            return selected
        }
        return nights.last
    }

    private func alignmentColor(forDelta delta: Int) -> Color {
        if delta <= 30 { return BetterColors.success }
        if delta <= 90 { return BetterColors.warning }
        return BetterColors.danger
    }

    private func alignmentStatusText(forDelta delta: Int) -> String {
        if delta <= 30 { return "On time" }
        if delta <= 90 { return "Slightly off" }
        return "Far off"
    }

    private func avoidRangeText(_ state: ChronotypeDashboardState) -> String {
        guard let before = state.avoidSleepBeforeMinute,
              let after = state.avoidSleepAfterMinute else {
            return "Still learning"
        }

        return "Before \(formatMinute(before)) or after \(formatMinute(after))"
    }

    private func alignmentText(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> String {
        guard let actual = state.actualAverageBedtimeMinute else { return "Still learning" }
        let delta = signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: actual)
        let absDelta = abs(delta)
        if absDelta <= 20 { return "On track" }
        return "\(formatShortDuration(minutes: absDelta)) \(delta > 0 ? "late" : "early")"
    }

    private func alignmentColor(state: ChronotypeDashboardState, estimate: ChronotypeEstimate) -> Color {
        guard let actual = state.actualAverageBedtimeMinute else { return BetterColors.subtext }
        let delta = abs(signedCircularDelta(from: estimate.optimalSleepWindow.startMinute, to: actual))
        return delta <= 20 ? BetterColors.success : BetterColors.warning
    }

    private func chronotypeTitle(for bucket: ChronotypeBucket) -> String {
        switch bucket {
        case .early:
            return "Early"
        case .earlyIntermediate:
            return "Early-mid"
        case .intermediate:
            return "Intermediate"
        case .lateIntermediate:
            return "Late-mid"
        case .late:
            return "Late"
        }
    }

    private func chronotypeMeaning(for bucket: ChronotypeBucket) -> String {
        switch bucket {
        case .early:
            return "You tend to feel sleepy and wake earlier than most people."
        case .earlyIntermediate:
            return "You lean earlier, but not extremely. Your best sleep starts before the middle of the night."
        case .intermediate:
            return "You sit between an early bird and a night owl. Your best sleep is in the middle range."
        case .lateIntermediate:
            return "You lean later, but not extremely. Your best sleep starts later than average."
        case .late:
            return "You tend to feel sleepy and wake later than most people."
        }
    }

    private func readinessText(_ readiness: BodyClockReadiness) -> String {
        switch readiness {
        case .preview:
            "Early estimate"
        case .goodEstimate:
            "Good estimate"
        case .stable:
            "Stable"
        case .highConfidence:
            "High confidence"
        }
    }

    private func readinessColor(_ readiness: BodyClockReadiness) -> Color {
        switch readiness {
        case .preview:
            BetterColors.warning
        case .goodEstimate:
            BetterColors.cyan
        case .stable:
            BetterColors.brand
        case .highConfidence:
            BetterColors.success
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func formatShortDuration(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
        }
        return "\(minutes) min"
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private func shortWeekday(for date: Date) -> String {
        let index = Calendar.current.component(.weekday, from: date) - 1
        return Calendar.current.shortWeekdaySymbols[max(0, min(index, Calendar.current.shortWeekdaySymbols.count - 1))]
    }

    private func signedCircularDelta(from targetMinute: Int, to actualMinute: Int) -> Int {
        var delta = actualMinute - targetMinute
        while delta > 720 { delta -= 1_440 }
        while delta < -720 { delta += 1_440 }
        return delta
    }
}

private struct ChronotypeColoredIconLabelStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(iconColor)
            configuration.title
        }
    }
}

private extension SocialJetlagCategory {
    var displayLabel: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .severe: "Severe"
        }
    }
}

#if DEBUG
#Preview("Chronotype") {
    let env = AppEnvironment.preview()
    NavigationStack {
        ChronotypeTabView(viewModel: ChronotypeViewModel(localRepository: env.localRepository))
    }
    .preferredColorScheme(.dark)
}
#endif

struct ChronotypeExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: BetterSpacing.large) {
                        Text("Your biological clock determines your optimal sleep and wake times. Aligning with your natural rhythm improves sleep quality and energy.")
                            .font(BetterTypography.body)
                            .foregroundStyle(BetterColors.subtext)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                            chronotypeRow(
                                title: "Early Bird (Lark)",
                                meaning: "Naturally wakes early and feels tired early in the evening.",
                                window: "Ideal Bedtime: 9:00 PM - 11:00 PM",
                                color: BetterColors.brandLight
                            )
                            
                            Divider().background(BetterColors.border.opacity(0.3))

                            chronotypeRow(
                                title: "Intermediate (Bear)",
                                meaning: "Standard circadian rhythm, matching daylight and standard work hours.",
                                window: "Ideal Bedtime: 11:00 PM - 1:30 AM",
                                color: BetterColors.cyan
                            )
                            
                            Divider().background(BetterColors.border.opacity(0.3))

                            chronotypeRow(
                                title: "Night Owl (Wolf)",
                                meaning: "Naturally sleeps late and wakes late. Most productive in the evenings.",
                                window: "Ideal Bedtime: 1:30 AM - 3:30 AM",
                                color: BetterColors.stageAwake
                            )
                        }
                        .padding(BetterSpacing.medium)
                        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
                    }
                    .padding(.horizontal, BetterSpacing.screen)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("About Chronotypes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.cyan)
                }
            }
        }
    }

    private func chronotypeRow(title: String, meaning: String, window: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
            }
            Text(meaning)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Text(window)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.top, 2)
        }
    }
}
