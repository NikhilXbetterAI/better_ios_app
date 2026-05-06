import SwiftUI

// MARK: - Sleep tab root view

struct SleepTabView: View {
    @Bindable var viewModel: SleepDashboardViewModel
    var onOpenProfile: () -> Void = {}
    @State private var isHistoryPresented = false
    @State private var isSleepScoreCalculationVisible = false

    var body: some View {
        ZStack {
            background

            if let session = viewModel.selectedSession {
                sessionContent(session: session)
            } else {
                emptyContent
            }
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        .navigationTitle("")
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

    // MARK: - Backgrounds

    private var background: some View {
        LinearGradient(
            colors: [BetterColors.background, BetterColors.backgroundElevated],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Session content

    private func sessionContent(session: SleepSession) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BetterSpacing.medium) {
                headerSection(session: session)
                    .padding(.horizontal, BetterSpacing.screen)

                // ── Sleep Score ──────────────────────────────────────────
                SleepMetricCard(
                    title: "Sleep Score",
                    iconName: "moon.fill",
                    iconColor: BetterColors.brand,
                    defaultExpanded: true,
                    summary: {
                        SleepScoreBadge(score: healthSleepScore(for: session).overall)
                    },
                    content: {
                        scoreCardContent(session: session)
                    }
                )
                .padding(.horizontal, BetterSpacing.screen)

                // ── vs Baseline ─────────────────────────────────────────
                if let baseline = viewModel.selectedBaseline, baseline.validNights >= 5 {
                    SleepMetricCard(
                        title: "vs Your Baseline",
                        iconName: "chart.line.uptrend.xyaxis",
                        iconColor: baselineIconColor(session: session, baseline: baseline),
                        summary: {
                            baselineSummaryBadge(session: session, baseline: baseline)
                        },
                        content: {
                            SleepVsBaselineView(session: session, baseline: baseline)
                            if let confidence = viewModel.baselineConfidenceLabel {
                                Text("Baseline confidence: \(confidence)")
                                    .font(BetterTypography.caption)
                                    .foregroundStyle(BetterColors.subtext)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )
                    .padding(.horizontal, BetterSpacing.screen)

                    // What Changed grid
                    SleepPlainCard(title: "What Changed Tonight") {
                        WhatChangedGridView(session: session, baseline: baseline)
                    }
                    .padding(.horizontal, BetterSpacing.screen)
                } else {
                    baselineNotReadyCard
                        .padding(.horizontal, BetterSpacing.screen)
                }

                // ── Data-quality fallback banner ─────────────────────────
                if let fallback = viewModel.healthKitFallbackState {
                    HealthKitFallbackBannerView(state: fallback)
                        .padding(.horizontal, BetterSpacing.screen)
                }

                if !viewModel.sleepInsights.isEmpty {
                    SleepPlainCard(title: "Sleep Insights") {
                        SleepInsightListView(insights: viewModel.sleepInsights)
                    }
                    .padding(.horizontal, BetterSpacing.screen)
                }

                // ── Sleep Stages ────────────────────────────────────────
                SleepMetricCard(
                    title: "Sleep Stages",
                    iconName: "moon.stars.fill",
                    iconColor: BetterColors.stageDeep,
                    summary: {
                        stageSummaryBadge(session: session)
                    },
                    content: {
                        stagesCardContent(session: session)
                    }
                )
                .padding(.horizontal, BetterSpacing.screen)

                // ── Sleep Latency ───────────────────────────────────────
                if session.sleepLatency > 0 {
                    sleepLatencyCard(session: session)
                        .padding(.horizontal, BetterSpacing.screen)
                }

                // ── Heart Rate & Biometrics ─────────────────────────────
                if let biometrics = session.biometrics {
                    SleepMetricCard(
                        title: "Heart Rate",
                        iconName: "heart.fill",
                        iconColor: BetterColors.heartRate,
                        summary: {
                            HeartRateSummary(biometrics: biometrics)
                        },
                        content: {
                            BiometricsTabContent(
                                biometrics: biometrics,
                                baseline: viewModel.selectedBaseline,
                                recentSessions: viewModel.recentSessions
                            )
                        }
                    )
                    .padding(.horizontal, BetterSpacing.screen)
                }

                // ── Respiratory Rate ────────────────────────────────────
                if let rate = session.biometrics?.respiratoryRateAverage {
                    SleepMetricCard(
                        title: "Respiratory Rate",
                        iconName: "wind",
                        iconColor: BetterColors.hrv,
                        summary: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", rate))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(BetterColors.text)
                                Text("br/min")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(BetterColors.subtext)
                            }
                        },
                        content: {
                            RespiratoryRateCardContent(
                                rate: rate,
                                baseline: viewModel.selectedBaseline,
                                recentSessions: viewModel.recentSessions
                            )
                        }
                    )
                    .padding(.horizontal, BetterSpacing.screen)
                }

                // ── Schedule Consistency ────────────────────────────────
                if let baseline = viewModel.selectedBaseline, baseline.validNights >= 5 {
                    SleepMetricCard(
                        title: "Schedule Consistency",
                        iconName: "clock.fill",
                        iconColor: BetterColors.warning,
                        summary: {
                            ScheduleConsistencySummary(baseline: baseline)
                        },
                        content: {
                            ScheduleConsistencyView(
                                session: session,
                                baseline: baseline,
                                recentSessions: viewModel.recentSessions
                            )
                        }
                    )
                    .padding(.horizontal, BetterSpacing.screen)
                }

                // Error footer
                if let error = viewModel.errorMessage, viewModel.selectedSession != nil {
                    errorFooter(message: error)
                        .padding(.horizontal, BetterSpacing.screen)
                }

                Spacer(minLength: BetterSpacing.xxLarge)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, BetterSpacing.screen)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    // MARK: - Empty / permission state

    private var emptyContent: some View {
        Group {
            if viewModel.isLoading {
                SleepDashboardSkeletonView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: BetterSpacing.xxLarge) {
                        headerNoSession

                        SleepNoDataView(
                            authorizationState: viewModel.authorizationState,
                            onConnect: { Task { await viewModel.requestHealthKitAccess() } }
                        )

                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, BetterSpacing.screen)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
        }
    }

    // MARK: - Header

    private func headerSection(session: SleepSession) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BETTER SLEEP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brand)
                    .tracking(0.8)

                Text(headerTitle(for: session))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 8) {
                    Button {
                        isHistoryPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11, weight: .semibold))
                            Text(selectedDateLabel)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    }
                    .buttonStyle(.plain)

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(BetterColors.brand)
                            .scaleEffect(0.75)
                    } else if viewModel.lastSyncedAt != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BetterColors.success)
                    }
                }
            }

            Spacer()

            if !viewModel.isViewingToday {
                Button {
                    Task { await viewModel.jumpToToday() }
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BetterColors.cardSecondary, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            profileButton
        }
    }

    private var profileButton: some View {
        Button { onOpenProfile() } label: {
            Text("B")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(BetterColors.brand)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }

    private var headerNoSession: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BETTER SLEEP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brand)
                    .tracking(0.8)
                Text(viewModel.isViewingToday ? "Tonight's Sleep" : "Sleep History")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Button {
                    isHistoryPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedDateLabel)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !viewModel.isViewingToday {
                Button {
                    Task { await viewModel.jumpToToday() }
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BetterColors.cardSecondary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            profileButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BetterSpacing.screen)
    }

    private func headerTitle(for session: SleepSession) -> String {
        guard viewModel.isViewingToday else { return "Sleep History" }
        // Evening-based: if session started before noon today → "Last Night's Sleep"
        let noon = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: Date()
        ) ?? Date()
        return session.endDate < noon ? "Last Night's Sleep" : "Tonight's Sleep"
    }

    // MARK: - Score card content

    private func scoreCardContent(session: SleepSession) -> some View {
        let healthScore = healthSleepScore(for: session)

        return HStack(alignment: .center, spacing: BetterSpacing.large) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSleepScoreCalculationVisible.toggle()
                }
            } label: {
                SleepQualityRingView(
                    score: healthScore.overall,
                    isPartial: viewModel.selectedBaseline?.validNights ?? 0 < 5
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sleep score")
            .accessibilityHint(isSleepScoreCalculationVisible ? "Hide sleep score calculation" : "Show sleep score calculation")

            VStack(spacing: BetterSpacing.small) {
                metricRow(label: "Time Asleep",  value: formatDuration(session.totalSleepTime))
                metricRow(label: "Time in Bed",  value: formatDuration(session.totalInBedTime))
                metricRow(label: "Efficiency",   value: String(format: "%.0f%%", session.efficiency * 100))
                metricRow(label: "Latency",      value: "\(Int(session.sleepLatency / 60)) min")

                if isSleepScoreCalculationVisible {
                    Divider().background(BetterColors.border)

                    metricRow(label: "Duration Score", value: "\(healthScore.duration)/50")
                    metricRow(label: "Bedtime Score", value: "\(healthScore.bedtime)/30")
                    metricRow(label: "Interruptions", value: "\(healthScore.interruptions)/20")
                }

                Divider().background(BetterColors.border)

                metricRow(label: "Bed",   value: session.inBedStartDate ?? session.startDate,   icon: "bed.double.fill")
                metricRow(label: "Wake",  value: session.inBedEndDate ?? session.endDate,       icon: "bolt.fill")
            }
        }
    }

    private func healthSleepScore(for session: SleepSession) -> HealthSleepScoreEstimate {
        HealthSleepScoreEstimator.estimate(session: session, baseline: viewModel.selectedBaseline, sleepGoalHours: viewModel.sleepGoalHours)
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
        }
    }

    private func metricRow(label: String, value: Date, icon: String) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(BetterColors.subtext)
                Text(label)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Text(value, style: .time)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
        }
    }

    // MARK: - Baseline helpers

    private func baselineIconColor(session: SleepSession, baseline: SleepBaseline) -> Color {
        session.totalSleepTime >= baseline.totalSleepAverage ? BetterColors.success : BetterColors.warning
    }

    private func baselineSummaryBadge(session: SleepSession, baseline: SleepBaseline) -> some View {
        let diffMin = Int((session.totalSleepTime - baseline.totalSleepAverage) / 60)
        let color: Color = diffMin >= 0 ? BetterColors.success : BetterColors.warning
        return HStack(spacing: 3) {
            Image(systemName: diffMin >= 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 11, weight: .semibold))
            Text("\(abs(diffMin)) min \(diffMin >= 0 ? "above" : "below") avg")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
    }

    private var baselineNotReadyCard: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 36, height: 36)
                .background(BetterColors.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Baseline Building")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Your personal baseline needs at least 5 nights of data. Keep wearing your Apple Watch to sleep.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
    }

    // MARK: - Stages card content

    private func stagesCardContent(session: SleepSession) -> some View {
        VStack(spacing: BetterSpacing.medium) {
            // Hypnogram
            SleepHypnogramView(
                stages: session.stages.filter { $0.type != .inBed },
                sessionStart: session.startDate,
                sessionEnd: session.endDate
            )

            StageDistributionSummaryView(session: session)

            StageLegendRow(showAll: true)

            Divider().background(BetterColors.border)

            SleepStageGridView(session: session)
        }
    }

    private func stageSummaryBadge(session: SleepSession) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(BetterColors.stageCore)
                .frame(width: 7, height: 7)
            Text("Core")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Text(formatDuration(session.coreDuration))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
        }
    }

    // MARK: - Error footer

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

    // MARK: - Loading indicator

    private var loadingIndicator: some View {
        VStack(spacing: BetterSpacing.large) {
            ProgressView()
                .tint(BetterColors.brand)
                .scaleEffect(1.4)
            Text("Syncing sleep data…")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Formatting helpers

    private var selectedDateLabel: String {
        guard let date = SleepDateKey.date(from: viewModel.selectedSleepDateKey) else {
            return viewModel.selectedSleepDateKey
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

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

// MARK: - Sleep Latency Card

extension SleepTabView {
    private func sleepLatencyCard(session: SleepSession) -> some View {
        let rating = SleepLatencyRating(session.sleepLatency)
        let latencyMin = Int(session.sleepLatency / 60)
        return SleepMetricCard(
            title: "Time to Fall Asleep",
            iconName: "timer",
            iconColor: rating.color,
            summary: {
                HStack(spacing: 6) {
                    Text("\(latencyMin) min")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(rating.label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(rating.color)
                }
            },
            content: {
                SleepLatencyGaugeView(latency: session.sleepLatency)
            }
        )
    }
}

// MARK: - Sleep Stage Detail Rows

private struct StageDistributionSummaryView: View {
    let session: SleepSession

    private var total: TimeInterval {
        max(session.totalSleepTime, 1)
    }

    var body: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BetterColors.brand)
            Text(summaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, BetterSpacing.small)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summaryText: String {
        let core = Int(((session.coreDuration / total) * 100).rounded())
        let rem = Int(((session.remDuration / total) * 100).rounded())
        let deep = Int(((session.deepDuration / total) * 100).rounded())
        let awake = Int(((session.awakeDuration / total) * 100).rounded())
        return "Core \(core)% • REM \(rem)% • Deep \(deep)% • Awake \(awake)%"
    }
}

private struct SleepStageGridView: View {
    let session: SleepSession

    private struct StageItem {
        let name: String
        let duration: TimeInterval
        let color: Color
    }

    private var items: [StageItem] {
        [
            StageItem(name: "Deep", duration: session.deepDuration, color: BetterColors.stageDeep),
            StageItem(name: "Core", duration: session.coreDuration, color: BetterColors.stageCore),
            StageItem(name: "REM", duration: session.remDuration, color: BetterColors.stageREM),
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
        .padding(.vertical, 10)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

}

// MARK: - Sleep Latency Gauge

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
                Text(rating.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(rating.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(rating.color.opacity(0.15), in: Capsule())
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

private struct SleepInsightListView: View {
    let insights: [SleepInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            ForEach(insights.prefix(4)) { insight in
                HStack(alignment: .top, spacing: BetterSpacing.small) {
                    Image(systemName: iconName(for: insight.category))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(color(for: insight.displayStyle), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title)
                            .font(BetterTypography.footnote)
                            .foregroundStyle(BetterColors.text)
                        Text(insight.body)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func iconName(for category: SleepInsightCategory) -> String {
        switch category {
        case .duration:
            "clock.fill"
        case .efficiency:
            "gauge.with.dots.needle.67percent"
        case .consistency:
            "calendar"
        case .recovery:
            "arrow.up.heart.fill"
        case .sleepStages:
            "moon.stars.fill"
        case .missingData:
            "exclamationmark.triangle.fill"
        case .baselineBuilding:
            "calendar.badge.clock"
        case .protocolComparison:
            "pills.fill"
        case .contextComparison:
            "chart.bar.fill"
        }
    }

    private func color(for style: SleepInsightDisplayStyle?) -> Color {
        switch style {
        case .positive:
            BetterColors.success
        case .caution:
            BetterColors.warning
        case .informational:
            BetterColors.brand
        case .neutral, nil:
            BetterColors.subtext
        }
    }
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
