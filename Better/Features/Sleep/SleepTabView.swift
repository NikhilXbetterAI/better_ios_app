import SwiftUI

// MARK: - Sleep Dashboard

struct SleepTabView: View {
    @Bindable var viewModel: SleepDashboardViewModel
    @Bindable var sleepModeViewModel: SleepModeViewModel
    var redLightFilterService: RedLightFilterService? = nil
    var onOpenProfile: () -> Void = {}

    @State private var isHistoryPresented = false
    @State private var heroAppeared = false
    @State private var swipeDelta: CGFloat = 0
    @State private var isSwipeNavigating = false
    @State private var showWhatChanged = false
    @State private var showSchedule = false
    @State private var showSleepMode = false
    @State private var showSleepModeSchedule = false

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
        .task {
            await sleepModeViewModel.reloadSchedule()
        }
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
        .sheet(isPresented: $showSleepModeSchedule) {
            NavigationStack {
                ZStack {
                    BetterColors.background.ignoresSafeArea()
                    ScrollView {
                        SleepModeScheduleView(
                            viewModel: sleepModeViewModel,
                            onSaveSuccess: { showSleepModeSchedule = false }
                        )
                        .padding(BetterSpacing.screen)
                    }
                }
                .navigationTitle("Sleep Mode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showSleepModeSchedule = false
                        }
                        .font(BetterTypography.subheadline.bold())
                        .foregroundStyle(BetterColors.brand)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showSleepMode) {
            SleepModeView(viewModel: sleepModeViewModel, redLightService: redLightFilterService)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(screenHeight: CGFloat) -> some View {
        ZStack {
            ProtocolPalette.backgroundColor
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

                    SleepContinuityCardView(
                        summary: session.continuitySummary,
                        restorativeSleepDuration: session.restorativeSleepDuration
                    )

                    if session.sleepLatency > 0 {
                        latencyCard(session: session)
                    }

                    if let baseline = viewModel.selectedBaseline, baseline.validNights >= 5 {
                        baselineCard(session: session, baseline: baseline)
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
                        viewMoreCard(session: session, baseline: baseline)
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
            if let alignment = viewModel.selectedSleepBodyClockAlignment {
                bodyClockAlignmentPill(alignment)
            }
            quickStatsStrip(session: session)
            SleepModeEntryCard(
                subtitle: sleepModeViewModel.entrySubtitle,
                notificationStatus: sleepModeViewModel.notificationStatus,
                onStart: { showSleepMode = true },
                onSchedule: { showSleepModeSchedule = true }
            )
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
                    scoreBreakdownPill(label: "Wakeups", value: "\(score.interruptions)/20")
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

    private func bodyClockAlignmentPill(_ alignment: BodyClockSleepAlignment) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: bodyClockAlignmentIcon(alignment.category))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(bodyClockAlignmentColor(alignment.category))
                .frame(width: 28, height: 28)
                .background(bodyClockAlignmentColor(alignment.category).opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(bodyClockAlignmentTitle(alignment.category))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(bodyClockAlignmentDeltaText(alignment))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: BetterSpacing.small)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(BetterColors.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BetterColors.glassStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bodyClockAlignmentTitle(alignment.category)), \(bodyClockAlignmentDeltaText(alignment))")
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
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            sectionLabel("Sleep Stages", icon: "moon.stars.fill", color: BetterColors.stageDeep)

            SleepHypnogramView(
                stages: session.stages.filter { $0.type != .inBed },
                sessionStart: session.startDate,
                sessionEnd: session.endDate
            )

            SleepStageGridView(session: session, baseline: viewModel.selectedBaseline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private func stageRingsRow(session: SleepSession) -> some View {
        HStack(spacing: 0) {
            stageRing(label: "Light", duration: session.coreDuration, total: session.totalSleepTime, color: BetterColors.stageCore)
            stageRing(label: "Deep", duration: session.deepDuration, total: session.totalSleepTime, color: BetterColors.stageDeep)
            stageRing(label: "REM", duration: session.remDuration, total: session.totalSleepTime, color: BetterColors.stageREM)
            stageRing(label: "Awake", duration: session.awakeDuration, total: session.totalSleepTime, color: BetterColors.stageAwake)
        }
    }

    private func stageRing(label: String, duration: TimeInterval, total: TimeInterval, color: Color) -> some View {
        let pct = total > 0 ? min(duration / total, 1.0) : 0.0
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: heroAppeared ? CGFloat(pct) : 0)
                    .stroke(
                        AngularGradient(
                            colors: [color, color.opacity(0.5)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.32), value: heroAppeared)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            .frame(width: 68, height: 68)
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
        return VStack(alignment: .leading, spacing: BetterSpacing.large) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    // MARK: - Baseline Cards

    private func baselineCard(session: SleepSession, baseline: SleepBaseline) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
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
                        .foregroundStyle(ProtocolPalette.dimText)
                    Text("Baseline confidence: \(confidence)")
                        .font(BetterTypography.caption)
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private func viewMoreCard(session: SleepSession, baseline: SleepBaseline) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    showWhatChanged.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                    Text("View More")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Spacer()
                    Image(systemName: showWhatChanged ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ProtocolPalette.dimText)
                }
            }
            .buttonStyle(.plain)

            if showWhatChanged {
                VStack(spacing: BetterSpacing.large) {
                    Divider()
                        .background(ProtocolPalette.borderColor)
                        .padding(.top, BetterSpacing.medium)

                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        sectionLabel("What Changed Tonight", icon: "chart.bar.fill", color: BetterColors.brand)
                        WhatChangedGridView(session: session, baseline: baseline)
                    }

                    Divider().background(ProtocolPalette.borderColor)

                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private var baselineNotReadyCard: some View {
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
                    .foregroundStyle(ProtocolPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    // MARK: - Biometrics Card

    private func biometricsCard(biometrics: NightlyBiometricSummary) -> some View {
        SleepBiometricFocusCard(
            biometrics: biometrics,
            recentSessions: viewModel.recentSessions
        )
    }



    // MARK: - Shared UI Helpers

    private func sectionLabel(_ title: String, icon: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(ProtocolPalette.dimText)
            .textCase(.uppercase)
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

    private func bodyClockAlignmentTitle(_ category: BodyClockAlignmentCategory) -> String {
        switch category {
        case .aligned:
            return "Aligned with your Body Clock"
        case .slightlyEarly:
            return "A little early for your Body Clock"
        case .slightlyLate:
            return "A little late for your Body Clock"
        case .early:
            return "Earlier than your Body Clock"
        case .late:
            return "Later than your Body Clock"
        }
    }

    private func bodyClockAlignmentDeltaText(_ alignment: BodyClockSleepAlignment) -> String {
        let minutes = abs(alignment.signedDeltaMinutes)
        guard minutes > 0 else { return "On time vs Body Clock" }

        let direction = alignment.signedDeltaMinutes < 0 ? "early" : "late"
        return "\(minutes)m \(direction) vs Body Clock"
    }

    private func bodyClockAlignmentIcon(_ category: BodyClockAlignmentCategory) -> String {
        switch category {
        case .aligned:
            return "checkmark.circle.fill"
        case .slightlyEarly, .early:
            return "sunrise.fill"
        case .slightlyLate, .late:
            return "moon.zzz.fill"
        }
    }

    private func bodyClockAlignmentColor(_ category: BodyClockAlignmentCategory) -> Color {
        switch category {
        case .aligned:
            return BetterColors.success
        case .slightlyEarly, .slightlyLate:
            return BetterColors.cyan
        case .early, .late:
            return BetterColors.warning
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
    let baseline: SleepBaseline?

    private struct StageItem {
        let name: String
        let duration: TimeInterval
        let color: Color
        let maxSeconds: Double
        let baselineAvgSeconds: Double?
        let baselineSdSeconds: Double?
    }

    private var items: [StageItem] {
        let lightAvg = baseline.map { $0.totalSleepAverage - $0.deepAverage - $0.remAverage }
        return [
            StageItem(name: "Awake",   duration: session.awakeDuration,  color: BetterColors.stageAwake, maxSeconds: 7200,  baselineAvgSeconds: nil, baselineSdSeconds: nil),
            StageItem(name: "Light",   duration: session.coreDuration,   color: BetterColors.stageCore,  maxSeconds: 18000, baselineAvgSeconds: lightAvg, baselineSdSeconds: nil),
            StageItem(name: "Deep",    duration: session.deepDuration,   color: BetterColors.stageDeep,  maxSeconds: 9000,  baselineAvgSeconds: baseline?.deepAverage, baselineSdSeconds: baseline?.deepStandardDeviation),
            StageItem(name: "REM",     duration: session.remDuration,    color: BetterColors.stageREM,   maxSeconds: 10800, baselineAvgSeconds: baseline?.remAverage,  baselineSdSeconds: baseline?.remStandardDeviation),
        ]
    }

    private var totalDuration: TimeInterval { session.totalSleepTime + session.awakeDuration }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if baseline != nil {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 16, height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                        Text("Typical range")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                }
                .padding(.bottom, 6)
            }

            VStack(spacing: 6) {
                ForEach(items, id: \.name) { item in
                    stageRow(item)
                }

                // Restorative Sleep (Deep + REM)
                restorativeSleepRow
            }
        }
    }

    private func stageRow(_ item: StageItem) -> some View {
        let pct = totalDuration > 0 ? min(item.duration / totalDuration, 1.0) : 0
        let valueFraction = item.maxSeconds > 0 ? min(item.duration / item.maxSeconds, 1.0) : 0

        var rangeLow: Double? = nil
        var rangeHigh: Double? = nil
        if let avg = item.baselineAvgSeconds {
            let sd = item.baselineSdSeconds ?? 0
            rangeLow  = max(0, (avg - sd)) / item.maxSeconds
            rangeHigh = min(1, (avg + sd)) / item.maxSeconds
        }

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.color)
                Spacer()
                Text(formatDuration(item.duration))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BetterColors.text)
            }

            StageRangeBar(
                valueFraction: valueFraction,
                rangeLow: rangeLow,
                rangeHigh: rangeHigh,
                color: item.color
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var restorativeSleepRow: some View {
        let restorative = session.deepDuration + session.remDuration
        let pct = totalDuration > 0 ? min(restorative / totalDuration, 1.0) : 0
        let baselineRestorative = baseline.map { $0.deepAverage + $0.remAverage }
        let baselineSd = baseline.map { sqrt($0.deepStandardDeviation * $0.deepStandardDeviation + $0.remStandardDeviation * $0.remStandardDeviation) }

        let maxSeconds: Double = 14400
        let valueFraction = min(restorative / maxSeconds, 1.0)
        var rangeLow: Double? = nil
        var rangeHigh: Double? = nil
        if let avg = baselineRestorative, let sd = baselineSd {
            rangeLow  = max(0, (avg - sd)) / maxSeconds
            rangeHigh = min(1, (avg + sd)) / maxSeconds
        }

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(colors: [BetterColors.stageDeep, BetterColors.stageREM], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 8, height: 8)
                Text("Restorative Sleep")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.stageDeep)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDuration(restorative))
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BetterColors.text)
                    if let avg = baselineRestorative {
                        Text(formatDuration(avg))
                            .font(.system(size: 10, design: .rounded).monospacedDigit())
                            .foregroundStyle(BetterColors.subtext)
                    }
                }
            }

            StageRangeBar(
                valueFraction: valueFraction,
                rangeLow: rangeLow,
                rangeHigh: rangeHigh,
                color: BetterColors.stageDeep
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            BetterColors.stageDeep.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BetterColors.stageDeep.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Stage Range Bar

private struct StageRangeBar: View {
    let valueFraction: Double
    let rangeLow: Double?
    let rangeHigh: Double?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 10)

                // Current value fill
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(valueFraction)), height: 10)

                // Typical range window overlay
                if let lo = rangeLow, let hi = rangeHigh, hi > lo {
                    let x = geo.size.width * CGFloat(lo)
                    let w = geo.size.width * CGFloat(hi - lo)
                    Canvas { ctx, size in
                        let rect = CGRect(x: 0, y: 0, width: w, height: size.height)
                        // Draw diagonal stripes
                        ctx.withCGContext { cg in
                            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
                            cg.setLineWidth(1.5)
                            let step: CGFloat = 5
                            var x0: CGFloat = -size.height
                            while x0 < w + size.height {
                                cg.move(to: CGPoint(x: x0, y: size.height))
                                cg.addLine(to: CGPoint(x: x0 + size.height, y: 0))
                                x0 += step
                            }
                            cg.clip(to: [rect])
                            cg.strokePath()
                        }
                    }
                    .frame(width: w, height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .offset(x: x)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 10)
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
                        .fill(Color.white.opacity(0.05))
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

// MARK: - Sleep Biometric Focus Card

private enum SleepVitalTab: String, CaseIterable {
    case rhr    = "RHR"
    case hrv    = "HRV"
    case spo2   = "SpO2"
    case breath = "Breath"

    var label: String { rawValue }

    var fullName: String {
        switch self {
        case .rhr: return "Resting heart rate"
        case .hrv: return "Heart rate variability"
        case .spo2: return "Blood oxygen"
        case .breath: return "Respiratory rate"
        }
    }

    var color: Color {
        switch self {
        case .rhr:    return BetterColors.heartRate
        case .hrv:    return BetterColors.hrv
        case .spo2:   return BetterColors.cyan
        case .breath: return BetterColors.brand
        }
    }

    var unit: String {
        switch self {
        case .rhr:    return "bpm"
        case .hrv:    return "ms"
        case .spo2:   return "%"
        case .breath: return "br/min"
        }
    }

    var chartMin: Double {
        switch self {
        case .rhr:    return 40
        case .hrv:    return 0
        case .spo2:   return 88
        case .breath: return 8
        }
    }

    var chartMax: Double {
        switch self {
        case .rhr:    return 100
        case .hrv:    return 120
        case .spo2:   return 100
        case .breath: return 24
        }
    }

    var zones: [SleepBiometricZone] {
        switch self {
        case .rhr:
            return [
                SleepBiometricZone(label: "Needs Attention", range: 80...100, color: BetterColors.danger),
                SleepBiometricZone(label: "Fair",            range: 69...80,  color: BetterColors.warning),
                SleepBiometricZone(label: "Normal",          range: 59...69,  color: BetterColors.hrv),
                SleepBiometricZone(label: "Optimal",         range: 40...59,  color: BetterColors.success),
            ]
        case .hrv:
            return [
                SleepBiometricZone(label: "Needs Attention", range: 0...20,   color: BetterColors.danger),
                SleepBiometricZone(label: "Fair",            range: 20...40,  color: BetterColors.warning),
                SleepBiometricZone(label: "Normal",          range: 40...60,  color: BetterColors.hrv),
                SleepBiometricZone(label: "Optimal",         range: 60...120, color: BetterColors.success),
            ]
        case .spo2:
            return [
                SleepBiometricZone(label: "Needs Attention", range: 88...93,  color: BetterColors.danger),
                SleepBiometricZone(label: "Fair",            range: 93...95,  color: BetterColors.warning),
                SleepBiometricZone(label: "Normal",          range: 95...98,  color: BetterColors.hrv),
                SleepBiometricZone(label: "Optimal",         range: 98...100, color: BetterColors.success),
            ]
        case .breath:
            return [
                SleepBiometricZone(label: "Needs Attention", range: 8...10,   color: BetterColors.danger),
                SleepBiometricZone(label: "Fair",            range: 10...12,  color: BetterColors.warning),
                SleepBiometricZone(label: "Normal",          range: 12...14,  color: BetterColors.hrv),
                SleepBiometricZone(label: "Optimal",         range: 14...16,  color: BetterColors.success),
                SleepBiometricZone(label: "Normal",          range: 16...18,  color: BetterColors.hrv),
                SleepBiometricZone(label: "Fair",            range: 18...20,  color: BetterColors.warning),
                SleepBiometricZone(label: "Needs Attention", range: 20...24,  color: BetterColors.danger),
            ]
        }
    }

    func currentValue(from biometrics: NightlyBiometricSummary) -> Double? {
        switch self {
        case .rhr:    return biometrics.heartRateMinimum
        case .hrv:    return biometrics.hrvAverage
        case .spo2:   return biometrics.oxygenSaturationAverage.map { $0 * 100 }
        case .breath: return biometrics.respiratoryRateAverage
        }
    }

    func value(from session: SleepSession) -> Double? {
        switch self {
        case .rhr: return session.biometrics?.heartRateMinimum
        case .hrv: return session.biometrics?.hrvAverage
        case .spo2: return session.biometrics?.oxygenSaturationAverage.map { $0 * 100 }
        case .breath: return session.biometrics?.respiratoryRateAverage
        }
    }

    var educationIcon: String {
        switch self {
        case .rhr: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .spo2: return "lungs.fill"
        case .breath: return "wind"
        }
    }

    var education: String {
        switch self {
        case .rhr:
            return "Resting heart rate reflects overnight cardiovascular load. Lower values often line up with better recovery, while sharp increases can point to strain."
        case .hrv:
            return "HRV reflects how well your body adapts and recovers. Higher values often align with stronger recovery readiness and lower nervous-system strain."
        case .spo2:
            return "SpO2 reflects overnight oxygen saturation. Stable oxygen levels support clearer sleep-breathing and recovery interpretation."
        case .breath:
            return "Breathing rate reflects overnight respiratory rhythm. Shifts can add context for stress, illness, training load, or recovery."
        }
    }

    func statusLabel(for value: Double) -> String {
        zones.first { $0.range.contains(value) }?.label ?? "–"
    }

    func statusColor(for value: Double) -> Color {
        zones.first { $0.range.contains(value) }?.color ?? BetterColors.subtext
    }

    func impactText(value: Double, average: Double?) -> String {
        let status = statusLabel(for: value)
        let comparison: String
        if let average {
            let diff = value - average
            let direction = diff >= 0 ? "above" : "below"
            comparison = "\(String(format: "%.1f", abs(diff))) \(unit) \(direction) this window's average."
        } else {
            comparison = "More nights will make this comparison more useful."
        }

        switch self {
        case .rhr:
            return "\(status). \(comparison) A higher overnight heart rate can reflect strain, late load, or incomplete recovery."
        case .hrv:
            return "\(status). \(comparison) Higher HRV often suggests better adaptation and recovery readiness."
        case .spo2:
            return "\(status). \(comparison) Stable oxygen saturation helps make sleep-breathing signals easier to interpret."
        case .breath:
            return "\(status). \(comparison) Breathing shifts can add context for stress, illness, training load, or recovery."
        }
    }
}

private struct SleepBiometricZone {
    let label: String
    let range: ClosedRange<Double>
    let color: Color
}

private struct SleepBiometricFocusCard: View {
    let biometrics: NightlyBiometricSummary
    let recentSessions: [SleepSession]

    @State private var selected: SleepVitalTab = .hrv
    @State private var timeline: SleepBiometricTimeline = .thirtyDays
    @State private var selectedPointKey: String?
    @Namespace private var pillNS

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            headerRow
            pillRow
            valueRow
            educationPanel
            SleepBiometricZoneChart(
                points: points,
                selectedPointKey: selectedPointKey,
                zones: selected.zones,
                chartMin: selected.chartMin,
                chartMax: selected.chartMax,
                color: selected.color,
                onSelect: { point in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedPointKey = point.dateKey
                    }
                }
            )
            selectedDayCallout
            footerGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        .onAppear(perform: resetSelection)
        .onChange(of: selected) { _, _ in resetSelection() }
        .onChange(of: timeline) { _, _ in resetSelection() }
        .onChange(of: recentSessions.count) { _, _ in resetSelection() }
    }

    private var points: [SleepBiometricPoint] {
        let sorted = recentSessions.sorted { $0.endDate < $1.endDate }
        return sorted.suffix(timeline.dayCount).compactMap { session in
            guard let value = selected.value(from: session),
                  let date = SleepDateKey.date(from: session.sleepDateKey)
            else { return nil }
            return SleepBiometricPoint(
                dateKey: session.sleepDateKey,
                date: date,
                value: value
            )
        }
    }

    private var selectedPoint: SleepBiometricPoint? {
        guard let selectedPointKey else { return points.last }
        return points.first { $0.dateKey == selectedPointKey } ?? points.last
    }

    private var average: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private var bestValue: Double? {
        switch selected {
        case .rhr:
            return points.map(\.value).min()
        case .hrv, .spo2:
            return points.map(\.value).max()
        case .breath:
            return points.map(\.value).min { abs($0 - 14) < abs($1 - 14) }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BIOMARKERS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(selected.color)
                    .tracking(1.2)
                Text(selected.fullName)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
            }
            Spacer()
            timelinePicker
        }
    }

    private var pillRow: some View {
        HStack(spacing: 5) {
            ForEach(SleepVitalTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selected = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tab == selected ? .black : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == selected {
                                Capsule()
                                    .fill(tab.color)
                                    .matchedGeometryEffect(id: "sleepPill", in: pillNS)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.label), \(tab == selected ? "selected" : "not selected")")
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04), in: Capsule())
    }

    private var timelinePicker: some View {
        HStack(spacing: 3) {
            ForEach(SleepBiometricTimeline.allCases, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        timeline = option
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(option == timeline ? .black : BetterColors.subtext)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(option == timeline ? selected.color : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.accessibilityLabel), \(option == timeline ? "selected" : "not selected")")
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04), in: Capsule())
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let value = selectedPoint?.value ?? selected.currentValue(from: biometrics) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formattedValue(value))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.text)
                            .contentTransition(.numericText())
                        Text(selected.unit)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                    if let delta = deltaText(value: value) {
                        Text(delta)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                }
                Spacer()
                Text(selected.statusLabel(for: value))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selected.statusColor(for: value), in: Capsule())
            } else {
                Text("–")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selected)
    }

    private var educationPanel: some View {
        HStack(alignment: .top, spacing: BetterSpacing.small) {
            Image(systemName: selected.educationIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected.color)
                .frame(width: 28, height: 28)
                .background(selected.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(selected.education)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.small)
        .background(selected.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var selectedDayCallout: some View {
        if let point = selectedPoint {
            HStack(alignment: .top, spacing: BetterSpacing.small) {
                Circle()
                    .fill(selected.statusColor(for: point.value))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(point.date.formatted(.dateTime.month(.abbreviated).day())) · \(formattedValue(point.value)) \(selected.unit)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(selected.impactText(value: point.value, average: average))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(BetterSpacing.small)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footerGrid: some View {
        HStack(spacing: BetterSpacing.small) {
            statTile("Average", value: average.map { formattedValue($0) } ?? "--")
            statTile("Best", value: bestValue.map { formattedValue($0) } ?? "--")
            statTile("Range", value: rangeText)
            statTile("Coverage", value: "\(points.count)/\(timeline.dayCount)")
        }
    }

    private var rangeText: String {
        guard let min = points.map(\.value).min(), let max = points.map(\.value).max() else { return "--" }
        return "\(formattedValue(min))-\(formattedValue(max))"
    }

    private func deltaText(value: Double) -> String? {
        guard let average else { return nil }
        let diff = value - average
        let sign = diff >= 0 ? "+" : ""

        switch selected {
        case .rhr, .hrv:
            return "\(sign)\(String(format: "%.0f", diff)) \(selected.unit) vs selected avg"
        case .spo2, .breath:
            return "\(sign)\(String(format: "%.1f", diff)) \(selected.unit) vs selected avg"
        }
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resetSelection() {
        selectedPointKey = points.last?.dateKey
    }

    private func formattedValue(_ value: Double) -> String {
        switch selected {
        case .breath, .spo2: return String(format: "%.1f", value)
        default:             return String(format: "%.0f", value)
        }
    }
}

private struct SleepBiometricZoneChart: View {
    let points: [SleepBiometricPoint]
    let selectedPointKey: String?
    let zones: [SleepBiometricZone]
    let chartMin: Double
    let chartMax: Double
    let color: Color
    let onSelect: (SleepBiometricPoint) -> Void

    @State private var trimAmount: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, size in
                    drawChart(context: &context, size: size)
                }

                if let selected = selectedPoint, let position = pointPosition(selected, in: size) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(color.opacity(0.5))
                            .frame(width: 1)
                        Circle()
                            .fill(color)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 2))
                        Spacer(minLength: 0)
                    }
                    .frame(height: size.height)
                    .position(x: position.x, y: size.height / 2)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectPoint(at: value.location.x, width: size.width)
                    }
            )
        }
        .frame(height: 120)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45)) { trimAmount = 1 }
        }
        .onChange(of: points) { _, _ in
            trimAmount = 0
            withAnimation(.easeInOut(duration: 0.45)) { trimAmount = 1 }
        }
    }

    private var selectedPoint: SleepBiometricPoint? {
        guard let selectedPointKey else { return points.last }
        return points.first { $0.dateKey == selectedPointKey } ?? points.last
    }

    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let spread = max(0.1, chartMax - chartMin)

        func yPos(_ value: Double) -> CGFloat {
            let normalized = (value - chartMin) / spread
            return size.height - size.height * CGFloat(normalized)
        }

        for zone in zones {
            let clampedLow = max(chartMin, zone.range.lowerBound)
            let clampedHigh = min(chartMax, zone.range.upperBound)
            guard clampedHigh > clampedLow else { continue }
            let top = yPos(clampedHigh)
            let bottom = yPos(clampedLow)
            context.fill(
                Path(CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))),
                with: .color(zone.color.opacity(0.16))
            )
        }

        guard points.count > 1 else { return }

        let drawCount = max(2, Int(Double(points.count) * trimAmount))
        let visible = Array(points.prefix(drawCount))
        let step = size.width / CGFloat(points.count - 1)

        var linePath = Path()
        for (index, point) in visible.enumerated() {
            let x = CGFloat(index) * step
            let y = min(max(5, yPos(point.value)), size.height - 5)
            let position = CGPoint(x: x, y: y)
            if index == 0 {
                linePath.move(to: position)
            } else {
                linePath.addLine(to: position)
            }
        }

        context.stroke(
            linePath,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round)
        )
    }

    private func pointPosition(_ point: SleepBiometricPoint, in size: CGSize) -> CGPoint? {
        guard let index = points.firstIndex(of: point), points.count > 1 else { return nil }
        let spread = max(0.1, chartMax - chartMin)
        let step = size.width / CGFloat(points.count - 1)
        let normalized = (point.value - chartMin) / spread
        let y = size.height - size.height * CGFloat(normalized)
        return CGPoint(x: CGFloat(index) * step, y: min(max(5, y), size.height - 5))
    }

    private func selectPoint(at x: CGFloat, width: CGFloat) {
        guard !points.isEmpty else { return }
        guard points.count > 1 else {
            onSelect(points[0])
            return
        }

        let step = width / CGFloat(points.count - 1)
        let index = min(max(Int((x / step).rounded()), 0), points.count - 1)
        onSelect(points[index])
    }
}

private enum SleepBiometricTimeline: Int, CaseIterable {
    case sevenDays = 7
    case thirtyDays = 30
    case sixtyDays = 60

    var dayCount: Int { rawValue }

    var label: String {
        switch self {
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .sixtyDays: return "60D"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .sixtyDays: return "60 days"
        }
    }
}

private struct SleepBiometricPoint: Identifiable, Equatable {
    var id: String { dateKey }
    let dateKey: String
    let date: Date
    let value: Double
}

// MARK: - Shared Formatting

private func formatDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

// MARK: - Preview

#if DEBUG
#Preview("Sleep Tab – With Data") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    let _ = {
        vm.selectedSession = PreviewSleepData.sampleSession
        vm.selectedBaseline = PreviewSleepData.sampleBaseline
        vm.dataQuality = .detailedStages
        vm.authorizationState = .canQueryHealthData
        vm.selectedSleepBodyClockAlignment = BodyClockSleepAlignment(
            actualMidpointMinute: 250,
            targetMidpointMinute: 240,
            signedDeltaMinutes: 10,
            category: .aligned
        )
    }()

    NavigationStack {
        SleepTabView(
            viewModel: vm,
            sleepModeViewModel: SleepModeViewModel(
                scheduleService: env.sleepModeScheduleService,
                localRepository: env.localRepository
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep Tab – Body Clock Early") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    let _ = {
        vm.selectedSession = PreviewSleepData.sampleSession
        vm.selectedBaseline = PreviewSleepData.sampleBaseline
        vm.dataQuality = .detailedStages
        vm.authorizationState = .canQueryHealthData
        vm.selectedSleepBodyClockAlignment = BodyClockSleepAlignment(
            actualMidpointMinute: 180,
            targetMidpointMinute: 240,
            signedDeltaMinutes: -60,
            category: .slightlyEarly
        )
    }()

    NavigationStack {
        SleepTabView(
            viewModel: vm,
            sleepModeViewModel: SleepModeViewModel(
                scheduleService: env.sleepModeScheduleService,
                localRepository: env.localRepository
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep Tab – Body Clock Late") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    let _ = {
        vm.selectedSession = PreviewSleepData.sampleSession
        vm.selectedBaseline = PreviewSleepData.sampleBaseline
        vm.dataQuality = .detailedStages
        vm.authorizationState = .canQueryHealthData
        vm.selectedSleepBodyClockAlignment = BodyClockSleepAlignment(
            actualMidpointMinute: 300,
            targetMidpointMinute: 240,
            signedDeltaMinutes: 60,
            category: .slightlyLate
        )
    }()

    NavigationStack {
        SleepTabView(
            viewModel: vm,
            sleepModeViewModel: SleepModeViewModel(
                scheduleService: env.sleepModeScheduleService,
                localRepository: env.localRepository
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep Tab – No Data") {
    let env = AppEnvironment.preview()
    let vm = SleepDashboardViewModel(
        syncCoordinator: env.syncCoordinator,
        localRepository: env.localRepository
    )
    let _ = { vm.authorizationState = .notRequested }()

    NavigationStack {
        SleepTabView(
            viewModel: vm,
            sleepModeViewModel: SleepModeViewModel(
                scheduleService: env.sleepModeScheduleService,
                localRepository: env.localRepository
            )
        )
    }
    .preferredColorScheme(.dark)
}
#endif
