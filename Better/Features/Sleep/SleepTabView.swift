import SwiftUI

// MARK: - Sleep tab root view

struct SleepTabView: View {
    @Bindable var viewModel: SleepDashboardViewModel
    @State private var isHistoryPresented = false

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
        ScrollView {
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
                        SleepScoreBadge(score: Int(session.qualityScore.overall))
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

                // ── Heart Rate ──────────────────────────────────────────
                if let biometrics = session.biometrics, biometrics.heartRateAverage != nil {
                    SleepMetricCard(
                        title: "Heart Rate",
                        iconName: "heart.fill",
                        iconColor: BetterColors.heartRate,
                        summary: {
                            HeartRateSummary(biometrics: biometrics)
                        },
                        content: {
                            HeartRateCardContent(biometrics: biometrics, baseline: viewModel.selectedBaseline)
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
                            RespiratoryRateCardContent(rate: rate, baseline: viewModel.selectedBaseline)
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
                            ScheduleConsistencyView(session: session, baseline: baseline)
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
            .padding(.top, BetterSpacing.screen)
        }
    }

    // MARK: - Empty / permission state

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: BetterSpacing.xxLarge) {
                headerNoSession

                if viewModel.isLoading {
                    loadingIndicator
                } else {
                    SleepNoDataView(
                        authorizationState: viewModel.authorizationState,
                        onConnect: { Task { await viewModel.requestHealthKitAccess() } }
                    )
                }

                Spacer(minLength: 40)
            }
            .padding(.top, BetterSpacing.screen)
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

            // Sync status indicator
            if viewModel.isLoading {
                ProgressView()
                    .tint(BetterColors.brand)
                    .scaleEffect(0.85)
            } else if let syncedAt = viewModel.lastSyncedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BetterColors.success)
                    Text(syncedAt, style: .relative)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
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
        HStack(alignment: .center, spacing: BetterSpacing.large) {
            SleepQualityRingView(
                score: Int(session.qualityScore.overall),
                isPartial: session.qualityScore.isPartial
            )

            VStack(spacing: BetterSpacing.small) {
                metricRow(label: "Time Asleep",  value: formatDuration(session.totalSleepTime))
                metricRow(label: "Time in Bed",  value: formatDuration(session.totalInBedTime))
                metricRow(label: "Efficiency",   value: String(format: "%.0f%%", session.efficiency * 100))
                metricRow(label: "Latency",      value: "\(Int(session.sleepLatency / 60)) min")

                Divider().background(BetterColors.border)

                metricRow(label: "Bed",   value: session.startDate,   icon: "bed.double.fill")
                metricRow(label: "Wake",  value: session.endDate,     icon: "bolt.fill")
            }
        }
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

            StageLegendRow(showAll: true)

            Divider().background(BetterColors.border)

            // Stage bars
            StageBreakdownView(session: session, baseline: viewModel.selectedBaseline)
        }
    }

    private func stageSummaryBadge(session: SleepSession) -> some View {
        let items: [(SleepStageType, Int)] = [
            (.deep,  Int(session.deepDuration / 60)),
            (.core,  Int(session.coreDuration / 60)),
            (.rem,   Int(session.remDuration / 60)),
            (.awake, Int(session.awakeDuration / 60)),
        ]
        return HStack(spacing: BetterSpacing.small) {
            ForEach(items, id: \.0) { type, mins in
                HStack(spacing: 3) {
                    Circle().fill(type.color).frame(width: 6, height: 6)
                    Text("\(mins)m")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                }
            }
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

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

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
