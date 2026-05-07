import SwiftUI

// MARK: - Sleep Dashboard

struct SleepTabView: View {
    @Bindable var viewModel: SleepDashboardViewModel
    var onOpenProfile: () -> Void = {}

    @State private var isHistoryPresented = false
    @State private var heroAppeared = false
    @State private var swipeDelta: CGFloat = 0
    @State private var isSwipeNavigating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer(screenHeight: geometry.size.height)
                mainContent
            }
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        .navigationBarHidden(true)
        .sheet(isPresented: $isHistoryPresented) {
            SleepHistoryCalendarSheet(
                selectedMonth: viewModel.selectedMonth,
                selectedSleepDateKey: viewModel.selectedSleepDateKey,
                summaries: viewModel.selectedMonthSummaries,
                onSelectDate: { key in
                    Task {
                        await viewModel.selectDate(key)
                        isHistoryPresented = false
                    }
                },
                onMonthChange: { month in
                    Task { await viewModel.loadMonth(month) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(screenHeight: CGFloat) -> some View {
        ZStack {
            BetterColors.background
            if let session = viewModel.selectedSession {
                let color = scoreColor(healthSleepScore(for: session).overall)
                RadialGradient(
                    colors: [color.opacity(0.16), color.opacity(0.05), .clear],
                    center: .init(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: screenHeight * 0.52
                )
                .animation(.easeInOut(duration: 0.6), value: color)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading && viewModel.selectedSession == nil {
            SleepDashboardSkeletonView()
        } else if let session = viewModel.selectedSession {
            sessionContent(session: session)
        } else {
            emptyContent
        }
    }

    // MARK: - Session Content

    private func sessionContent(session: SleepSession) -> some View {
        let score = healthSleepScore(for: session)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection(session: session, score: score)
                    .offset(x: swipeDelta * 0.06)

                VStack(spacing: BetterSpacing.medium) {
                    stagesCard(session: session)

                    if session.sleepLatency > 0 {
                        latencyCard(session: session)
                    }

                    if let baseline = viewModel.selectedBaseline, baseline.validNights >= 5 {
                        baselineCard(session: session, baseline: baseline)
                        whatChangedCard(session: session, baseline: baseline)
                    } else {
                        baselineNotReadyCard
                    }

                    if let fallback = viewModel.healthKitFallbackState {
                        HealthKitFallbackBannerView(state: fallback)
                    }

                    if let biometrics = session.biometrics {
                        biometricsCard(biometrics: biometrics)
                    }

                    if let baseline = viewModel.selectedBaseline, baseline.validNights >= 5 {
                        scheduleCard(session: session, baseline: baseline)
                    }

                    if let error = viewModel.errorMessage {
                        errorFooter(message: error)
                    }

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.medium)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .gesture(daySwipeGesture)
    }

    // MARK: - Swipe Navigation

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.interactiveSpring(response: 0.25)) {
                    swipeDelta = value.translation.width
                }
            }
            .onEnded { value in
                if value.translation.width > 72 {
                    navigateDay(by: -1)
                } else if value.translation.width < -72 {
                    navigateDay(by: 1)
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    swipeDelta = 0
                }
            }
    }

    private func navigateDay(by delta: Int) {
        guard !isSwipeNavigating else { return }
        isSwipeNavigating = true
        guard
            let current = SleepDateKey.date(from: viewModel.selectedSleepDateKey),
            let next = Calendar.current.date(byAdding: .day, value: delta, to: current),
            next <= Date()
        else {
            isSwipeNavigating = false
            return
        }
        let nextKey = SleepDateKey.calendarDateKey(for: next, calendar: .current)
        Task {
            heroAppeared = false
            await viewModel.selectDate(nextKey)
            withAnimation { heroAppeared = true }
            isSwipeNavigating = false
        }
    }

    // MARK: - Hero Section

    private func heroSection(session: SleepSession, score: HealthSleepScoreEstimate) -> some View {
        VStack(spacing: BetterSpacing.large) {
            topBar(session: session)
            scoreRingHero(session: session, score: score)
            quickStatsStrip(session: session)
        }
        .padding(.horizontal, BetterSpacing.screen)
        .padding(.top, 52)
        .padding(.bottom, BetterSpacing.large)
    }

    // MARK: - Top Bar

    private func topBar(session: SleepSession) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BETTER SLEEP")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brandLight)
                    .tracking(1.6)
                Button { isHistoryPresented = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedDateLabel)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(BetterColors.text)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(BetterColors.brandLight)
                        .scaleEffect(0.75)
                } else if viewModel.lastSyncedAt != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(BetterColors.success)
                }
                if !viewModel.isViewingToday {
                    Button {
                        Task { await viewModel.jumpToToday() }
                    } label: {
                        Text("Today")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(BetterColors.brand.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                profileButton
            }
        }
    }

    // MARK: - Score Ring Hero

    private func scoreRingHero(session: SleepSession, score: HealthSleepScoreEstimate) -> some View {
        let color = scoreColor(score.overall)
        let fillEnd = 0.15 + 0.70 * (Double(score.overall) / 100.0)
        let isPartial = (viewModel.selectedBaseline?.validNights ?? 0) < 5

        return ZStack(alignment: .center) {
            // Soft glow bloom behind the ring
            Circle()
                .fill(color.opacity(0.10))
                .frame(width: 230, height: 230)
                .blur(radius: 36)

            // 240° AngularGradient arc
            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(90))

                Circle()
                    .trim(from: 0.15, to: heroAppeared ? fillEnd : 0.15)
                    .stroke(
                        AngularGradient(
                            colors: [color, color.opacity(0.55)],
                            center: .center,
                            startAngle: .degrees(-90 + 54),
                            endAngle: .degrees(270 - 54)
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.12), value: heroAppeared)

                VStack(spacing: 3) {
                    Text("\(score.overall)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .contentTransition(.numericText())
                    Text(scoreLabel(score.overall))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                    Text(formatDuration(session.totalSleepTime))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    if isPartial {
                        Text("partial data")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext.opacity(0.6))
                    }
                }
            }
            .frame(width: 192, height: 192)

            // Score breakdown pill — floats below the arc gap
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    scoreBreakdownPill(label: "Duration", value: "\(score.duration)/50")
                    Rectangle()
                        .fill(BetterColors.border)
                        .frame(width: 1, height: 20)
                    scoreBreakdownPill(label: "Bedtime", value: "\(score.bedtime)/30")
                    Rectangle()
                        .fill(BetterColors.border)
                        .frame(width: 1, height: 20)
                    scoreBreakdownPill(label: "Interr.", value: "\(score.interruptions)/20")
                }
                .padding(.horizontal, BetterSpacing.large)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(BetterColors.cardGradient)
                        .overlay(Capsule().stroke(BetterColors.glassStroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 6)
                )
            }
            .frame(height: 258, alignment: .bottom)
        }
        .onAppear {
            withAnimation { heroAppeared = true }
        }
        .onChange(of: viewModel.selectedSleepDateKey) { _, _ in
            heroAppeared = false
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation { heroAppeared = true }
            }
        }
    }

    private func scoreBreakdownPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Quick Stats Strip

    private func quickStatsStrip(session: SleepSession) -> some View {
        HStack(spacing: 10) {
            statChip(
                icon: "gauge.with.dots.needle.67percent",
                label: "Efficiency",
                value: "\(Int(session.efficiency * 100))%",
                color: session.efficiency >= 0.85 ? BetterColors.success : BetterColors.warning
            )
            statChip(
                icon: "timer",
                label: "Latency",
                value: session.sleepLatency > 0 ? "\(Int(session.sleepLatency / 60))m" : "—",
                color: SleepLatencyRating(session.sleepLatency).color
            )
            statChipDate(
                icon: "bed.double.fill",
                label: "Bedtime",
                date: session.inBedStartDate ?? session.startDate,
                color: BetterColors.brand
            )
            statChipDate(
                icon: "alarm",
                label: "Wake",
                date: session.inBedEndDate ?? session.endDate,
                color: BetterColors.stageAwake
            )
        }
    }

    private func statChip(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(BetterColors.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.glassStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }

    private func statChipDate(icon: String, label: String, date: Date, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(date, style: .time)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(BetterColors.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.glassStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }

    // MARK: - Stages Card

    private func stagesCard(session: SleepSession) -> some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                sectionLabel("Sleep Stages", icon: "moon.stars.fill", color: BetterColors.stageDeep)

                SleepHypnogramView(
                    stages: session.stages.filter { $0.type != .inBed },
                    sessionStart: session.startDate,
                    sessionEnd: session.endDate
                )

                stageRingsRow(session: session)

                Divider().background(BetterColors.border.opacity(0.5))

                SleepStageGridView(session: session)
            }
        }
    }

    private func stageRingsRow(session: SleepSession) -> some View {
        HStack(spacing: 0) {
            stageRing(label: "Deep", duration: session.deepDuration, total: session.totalSleepTime, color: BetterColors.stageDeep)
            stageRing(label: "Core", duration: session.coreDuration, total: session.totalSleepTime, color: BetterColors.stageCore)
            stageRing(label: "REM", duration: session.remDuration, total: session.totalSleepTime, color: BetterColors.stageREM)
            stageRing(label: "Awake", duration: session.awakeDuration, total: session.totalSleepTime, color: BetterColors.stageAwake)
        }
    }

    private func stageRing(label: String, duration: TimeInterval, total: TimeInterval, color: Color) -> some View {
        let pct = total > 0 ? min(duration / total, 1.0) : 0.0
        return VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: heroAppeared ? CGFloat(pct) : 0)
                    .stroke(
                        AngularGradient(
                            colors: [color, color.opacity(0.5)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.32), value: heroAppeared)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            .frame(width: 50, height: 50)
            Text(formatDuration(duration))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Latency Card

    private func latencyCard(session: SleepSession) -> some View {
        let rating = SleepLatencyRating(session.sleepLatency)
        return BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                HStack {
                    sectionLabel("Time to Fall Asleep", icon: "timer", color: rating.color)
                    Spacer()
                    Text(rating.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(rating.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(rating.color.opacity(0.14), in: Capsule())
                }
                SleepLatencyGaugeView(latency: session.sleepLatency)
            }
        }
    }

    // MARK: - Baseline Cards

    private func baselineCard(session: SleepSession, baseline: SleepBaseline) -> some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                HStack {
                    sectionLabel("vs Your Baseline", icon: "chart.line.uptrend.xyaxis", color: baselineIconColor(session: session, baseline: baseline))
                    Spacer()
                    baselineSummaryBadge(session: session, baseline: baseline)
                }
                SleepVsBaselineView(session: session, baseline: baseline)
                if let confidence = viewModel.baselineConfidenceLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(BetterColors.subtext)
                        Text("Baseline confidence: \(confidence)")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                }
            }
        }
    }

    private func whatChangedCard(session: SleepSession, baseline: SleepBaseline) -> some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                sectionLabel("What Changed Tonight", icon: "chart.bar.fill", color: BetterColors.brand)
                WhatChangedGridView(session: session, baseline: baseline)
            }
        }
    }

    private var baselineNotReadyCard: some View {
        BetterHealthCard {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundStyle(BetterColors.brand)
                    .frame(width: 42, height: 42)
                    .background(BetterColors.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline Building")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text("Need at least 5 nights of sleep data to build your personal baseline.")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Biometrics Card

    private func biometricsCard(biometrics: NightlyBiometricSummary) -> some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                sectionLabel("Biometrics", icon: "heart.fill", color: BetterColors.heartRate)
                biometricsChipRow(biometrics: biometrics)
                Divider().background(BetterColors.border.opacity(0.5))
                BiometricsTabContent(
                    biometrics: biometrics,
                    baseline: viewModel.selectedBaseline,
                    recentSessions: viewModel.recentSessions
                )
            }
        }
    }

    private func biometricsChipRow(biometrics: NightlyBiometricSummary) -> some View {
        HStack(spacing: 8) {
            if let hr = biometrics.heartRateAverage {
                bioChip(icon: "heart.fill", label: "HR", value: "\(Int(hr))", unit: "bpm", color: BetterColors.heartRate)
            }
            if let hrv = biometrics.hrvAverage {
                bioChip(icon: "waveform.path.ecg", label: "HRV", value: String(format: "%.0f", hrv), unit: "ms", color: BetterColors.hrv)
            }
            if let spo2 = biometrics.oxygenSaturationAverage {
                bioChip(icon: "drop.fill", label: "SpO2", value: "\(Int(spo2 * 100))", unit: "%", color: BetterColors.cyan)
            }
            if let rr = biometrics.respiratoryRateAverage {
                bioChip(icon: "lungs.fill", label: "Breath", value: String(format: "%.1f", rr), unit: "/min", color: BetterColors.brand)
            }
        }
    }

    private func bioChip(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text(unit)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Schedule Card

    private func scheduleCard(session: SleepSession, baseline: SleepBaseline) -> some View {
        BetterHealthCard {
            VStack(spacing: BetterSpacing.large) {
                HStack {
                    sectionLabel("Schedule Consistency", icon: "clock.fill", color: BetterColors.warning)
                    Spacer()
                    ScheduleConsistencySummary(baseline: baseline)
                }
                ScheduleConsistencyView(
                    session: session,
                    baseline: baseline,
                    recentSessions: viewModel.recentSessions
                )
            }
        }
    }

    // MARK: - Shared UI Helpers

    private func sectionLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
        }
    }

    private func baselineIconColor(session: SleepSession, baseline: SleepBaseline) -> Color {
        session.totalSleepTime >= baseline.totalSleepAverage ? BetterColors.success : BetterColors.warning
    }

    private func baselineSummaryBadge(session: SleepSession, baseline: SleepBaseline) -> some View {
        let diffMin = Int((session.totalSleepTime - baseline.totalSleepAverage) / 60)
        let color: Color = diffMin >= 0 ? BetterColors.success : BetterColors.warning
        return HStack(spacing: 3) {
            Image(systemName: diffMin >= 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 11, weight: .semibold))
            Text("\(abs(diffMin))m \(diffMin >= 0 ? "above" : "below") avg")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
    }

    private func errorFooter(message: String) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(BetterColors.warning)
            Text("Sync error: \(message)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(2)
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var profileButton: some View {
        Button { onOpenProfile() } label: {
            Text(profileInitial)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(BetterColors.brandGradient)
                .clipShape(Circle())
                .shadow(color: BetterColors.brand.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }

    private var profileInitial: String {
        guard let name = viewModel.displayName?.trimmedNonEmpty, let first = name.first else {
            return "B"
        }
        return String(first).uppercased()
    }

    // MARK: - Score Helpers

    private func healthSleepScore(for session: SleepSession) -> HealthSleepScoreEstimate {
        HealthSleepScoreEstimator.estimate(session: session, baseline: viewModel.selectedBaseline, sleepGoalHours: viewModel.sleepGoalHours)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: return BetterColors.success
        case 70...: return BetterColors.brand
        case 55...: return BetterColors.warning
        default:    return BetterColors.danger
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70...: return "Good"
        case 55...: return "Fair"
        default:    return "Poor"
        }
    }

    private var selectedDateLabel: String {
        guard let date = SleepDateKey.date(from: viewModel.selectedSleepDateKey) else {
            return viewModel.selectedSleepDateKey
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    // MARK: - Empty State

    private var emptyContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BetterSpacing.xxLarge) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BETTER SLEEP")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.brandLight)
                            .tracking(1.6)
                        Text(viewModel.isViewingToday ? "Tonight's Sleep" : "Sleep History")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                        Button { isHistoryPresented = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                                Text(selectedDateLabel).font(.system(size: 13, weight: .semibold, design: .rounded))
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(BetterColors.subtext)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    profileButton
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, 52)

                SleepNoDataView(
                    authorizationState: viewModel.authorizationState,
                    onConnect: { Task { await viewModel.requestHealthKitAccess() } }
                )

                Spacer(minLength: 40)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

// MARK: - History Calendar Sheet

private struct SleepHistoryCalendarSheet: View {
    let selectedMonth: Date
    let selectedSleepDateKey: String
    let summaries: [SleepDaySummary]
    let onSelectDate: (String) -> Void
    let onMonthChange: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()

                VStack(spacing: BetterSpacing.large) {
                    monthHeader
                    weekdayHeader
                    dayGrid
                    Spacer(minLength: 0)
                }
                .padding(BetterSpacing.screen)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BetterColors.brand)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(BetterColors.cardSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(BetterColors.text)

            Spacer()

            Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                .font(BetterTypography.title)
                .foregroundStyle(BetterColors.text)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(BetterColors.cardSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(BetterColors.text)
            .disabled(isNextMonthInFuture)
            .opacity(isNextMonthInFuture ? 0.35 : 1)
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortWeekdaySymbols
        return HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 14) {
            ForEach(days.indices, id: \.self) { index in
                if let date = days[index] {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 58)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let key = SleepDateKey.calendarDateKey(for: date, calendar: calendar)
        let summary = summaryByKey[key]
        let isSelected = key == selectedSleepDateKey
        let isFuture = date > Date()

        return Button {
            guard !isFuture else { return }
            onSelectDate(key)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(BetterColors.border, lineWidth: 5)
                        .frame(width: 34, height: 34)

                    if let score = summary?.score {
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(score / 100, 0), 1)))
                            .stroke(summary?.dataQuality == .unspecifiedSleepOnly ? BetterColors.warning : BetterColors.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 34, height: 34)
                    }

                    if summary?.dataQuality == .unspecifiedSleepOnly {
                        Circle()
                            .fill(BetterColors.warning)
                            .frame(width: 6, height: 6)
                            .offset(x: 12, y: -12)
                    }
                }
                .opacity(isFuture ? 0.25 : (summary?.hasSession == true ? 1 : 0.45))

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isFuture ? BetterColors.subtext.opacity(0.45) : BetterColors.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isSelected ? BetterColors.cardTertiary : BetterColors.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? BetterColors.brand.opacity(0.7) : BetterColors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var monthDays: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: selectedMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: selectedMonth)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leadingEmpty) + dates
    }

    private var summaryByKey: [String: SleepDaySummary] {
        Dictionary(uniqueKeysWithValues: summaries.map { ($0.sleepDateKey, $0) })
    }

    private var isNextMonthInFuture: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth) else { return true }
        let nextKey = SleepDateKey.calendarDateKey(for: next, calendar: calendar)
        let todayKey = SleepDateKey.today(calendar: calendar)
        return nextKey > todayKey
    }

    private func changeMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        onMonthChange(month)
    }
}

// MARK: - Sleep Stage Grid

private struct SleepStageGridView: View {
    let session: SleepSession

    private struct StageItem {
        let name: String
        let duration: TimeInterval
        let color: Color
    }

    private var items: [StageItem] {
        [
            StageItem(name: "Deep",  duration: session.deepDuration,  color: BetterColors.stageDeep),
            StageItem(name: "Core",  duration: session.coreDuration,  color: BetterColors.stageCore),
            StageItem(name: "REM",   duration: session.remDuration,   color: BetterColors.stageREM),
            StageItem(name: "Awake", duration: session.awakeDuration, color: BetterColors.stageAwake),
        ]
    }

    var body: some View {
        VStack(spacing: BetterSpacing.small) {
            ForEach(items, id: \.name) { item in
                stageRow(item)
            }
        }
    }

    private func stageRow(_ item: StageItem) -> some View {
        let pct = session.totalSleepTime > 0 ? min(item.duration / session.totalSleepTime, 1.0) : 0
        return VStack(spacing: 7) {
            HStack(spacing: BetterSpacing.small) {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text(formatDuration(item.duration))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
                    .frame(width: 58, alignment: .trailing)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(item.color)
                    .frame(width: 42, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(BetterColors.cardTertiary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.color)
                        .frame(width: max(3, proxy.size.width * CGFloat(pct)))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 12)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Sleep Latency

private enum SleepLatencyRating {
    case fast, normal, late

    init(_ latency: TimeInterval) {
        if latency < 300 { self = .fast }
        else if latency < 1200 { self = .normal }
        else { self = .late }
    }

    var color: Color {
        switch self {
        case .fast:   BetterColors.success
        case .normal: BetterColors.brand
        case .late:   BetterColors.warning
        }
    }

    var label: String {
        switch self {
        case .fast:   "Fast"
        case .normal: "Normal"
        case .late:   "Late"
        }
    }
}

private struct SleepLatencyGaugeView: View {
    let latency: TimeInterval

    private var minutes: Int { Int(latency / 60) }
    private var position: Double { min(latency / (25 * 60), 1.0) }
    private var rating: SleepLatencyRating { SleepLatencyRating(latency) }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("min")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BetterColors.cardSecondary)
                        .frame(height: 6)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BetterColors.success, BetterColors.brand, BetterColors.warning],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width, height: 6)
                    Circle()
                        .fill(BetterColors.text)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, min(geo.size.width * position - 7, geo.size.width - 14)))
                }
            }
            .frame(height: 14)

            HStack {
                Text("Fast")
                Spacer()
                Text("Normal")
                Spacer()
                Text("Late")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(BetterColors.subtext)
        }
    }
}

// MARK: - Biometrics Tab Content

private enum BiometricTab: String, CaseIterable {
    case hr   = "HR"
    case hrv  = "HRV"
    case rr   = "RR"
    case spo2 = "SpO2"

    var icon: String {
        switch self {
        case .hr:   return "heart.fill"
        case .hrv:  return "waveform.path.ecg"
        case .rr:   return "lungs.fill"
        case .spo2: return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .hr:   return BetterColors.heartRate
        case .hrv:  return BetterColors.hrv
        case .rr:   return BetterColors.brand
        case .spo2: return BetterColors.cyan
        }
    }
}

private struct BiometricsTabContent: View {
    let biometrics: NightlyBiometricSummary
    let baseline: SleepBaseline?
    let recentSessions: [SleepSession]

    @State private var selectedTab: BiometricTab = .hr

    var body: some View {
        VStack(spacing: BetterSpacing.large) {
            HeartRateCardContent(
                biometrics: biometrics,
                baseline: baseline,
                recentSessions: recentSessions
            )

            HStack(spacing: 4) {
                ForEach(BiometricTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func tabButton(_ tab: BiometricTab) -> some View {
        let isSelected = tab == selectedTab
        let value = metricValue(for: tab)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let v = value {
                    Text(v)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(isSelected ? tab.color : BetterColors.subtext)
                }
            }
            .foregroundStyle(isSelected ? tab.color : BetterColors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? BetterColors.card : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .opacity(value == nil ? 0.35 : 1)
    }

    private func metricValue(for tab: BiometricTab) -> String? {
        switch tab {
        case .hr:   return biometrics.heartRateAverage.map { "\(Int($0)) bpm" }
        case .hrv:  return biometrics.hrvAverage.map { String(format: "%.0f ms", $0) }
        case .rr:   return biometrics.respiratoryRateAverage.map { String(format: "%.1f br/min", $0) }
        case .spo2: return biometrics.oxygenSaturationAverage.map { "\(Int($0 * 100))%" }
        }
    }
}

// MARK: - Shared Formatting

private func formatDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

// MARK: - Preview

#Preview("Sleep Tab – With Data") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    vm.selectedSession = PreviewSleepData.sampleSession
    vm.selectedBaseline = PreviewSleepData.sampleBaseline
    vm.dataQuality = .detailedStages
    vm.authorizationState = .canQueryHealthData

    return NavigationStack {
        SleepTabView(viewModel: vm)
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep Tab – No Data") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    vm.authorizationState = .notRequested

    return NavigationStack {
        SleepTabView(viewModel: vm)
    }
    .preferredColorScheme(.dark)
}
