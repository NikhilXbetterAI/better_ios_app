import SwiftUI

// MARK: - Sleep Dashboard

struct SleepTabView: View {
    @Bindable var viewModel: SleepDashboardViewModel
    @Bindable var sleepModeViewModel: SleepModeViewModel
    var redLightFilterService: RedLightFilterService? = nil
    var onOpenProfile: () -> Void = {}

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHistoryPresented = false
    @State private var heroAppeared = false
    @State private var swipeDelta: CGFloat = 0
    @State private var isSwipeNavigating = false
    @State private var showSleepMode = false
    @State private var showSleepModeSchedule = false
    @State private var showScoreBreakdown = false
    @State private var dotPulse = false

    var body: some View {
        GeometryReader { geometry in
            // Score computed once here so backgroundLayer and sessionContent
            // share the same value — not recomputed inside GeometryReader callbacks.
            let precomputedScore = viewModel.selectedSession.map {
                healthSleepScore(for: $0)
            }
            ZStack {
                backgroundLayer(screenHeight: geometry.size.height, precomputedScore: precomputedScore)
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
            SleepModeView(
                viewModel: sleepModeViewModel,
                redLightService: redLightFilterService,
                onEditSchedule: { showSleepModeSchedule = true }
            )
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(screenHeight: CGFloat, precomputedScore: HealthSleepScoreEstimate?) -> some View {
        ZStack {
            Color.black
            if let score = precomputedScore {
                let color = scoreColor(score.overall)
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

                // Cards column — sections are grouped into VStack(spacing:0) so
                // headers are visually attached to their card (not floating apart).
                // Sections are separated by BetterSpacing.section (26pt).
                VStack(spacing: BetterSpacing.section) {
                    SleepModeLauncherView(
                        schedule: sleepModeViewModel.schedule,
                        onOpen: { showSleepMode = true }
                    )
                    .onLongPressGesture(minimumDuration: 0.4) {
                        showSleepModeSchedule = true
                    }
                    .frame(maxWidth: .infinity)

                    let activeBaseline: SleepBaseline? = {
                        guard let b = viewModel.selectedBaseline,
                              b.validNights >= BaselineEngine.dashboardMinimumValidNights else { return nil }
                        return b
                    }()

                    // Sleep Stages section — header pinned to card
                    VStack(alignment: .leading, spacing: 8) {
                        dashboardSectionHeader("Sleep Stages")
                        SleepStagesCard(
                            session: session,
                            baseline: activeBaseline,
                            recentSessions: viewModel.recentSessions
                        )
                        .frame(maxWidth: .infinity)
                        if activeBaseline == nil {
                            baselineNotReadyCard
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Longest stretch section
                    VStack(alignment: .leading, spacing: 8) {
                        dashboardSectionHeader("Longest Stretch")
                        LongestSleepBlockCard(session: session)
                            .frame(maxWidth: .infinity)
                    }

                    if let fallback = viewModel.healthKitFallbackState {
                        HealthKitFallbackBannerView(state: fallback)
                            .frame(maxWidth: .infinity)
                    }

                    // Biomarkers section — always shown. When the session has no
                    // HK biometric data (e.g. iPhone-only tracking), we pass an
                    // empty summary so SleepBiomarkerReactionsCard can render its
                    // own "no readings captured tonight" state instead of hiding
                    // the entire section.
                    let bioForCard = session.biometrics ?? NightlyBiometricSummary(
                        sleepSessionID: session.id,
                        sleepDateKey: session.sleepDateKey
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        dashboardSectionHeader("Biomarkers")
                        biometricsCard(biometrics: bioForCard)
                            .frame(maxWidth: .infinity)
                    }

                    if let error = viewModel.errorMessage {
                        errorFooter(message: error)
                    }
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.medium)
                .background(Color.black)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 120) }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Bug fix: status-bar text was bleeding through the hero chip strip
            // mid-scroll. A thin material strip at the top safe-area inset acts
            // as an opaque gutter so the system clock never overlaps content.
            Color.clear
                .frame(height: 0)
                .background(.ultraThinMaterial)
                .background(Color.black)
        }
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
            combinedInsightLine(session: session, score: score)
            dataSourceLine(session: session)
            SleepFactsStrip(session: session, baseline: viewModel.selectedBaseline)
        }
        .padding(.horizontal, BetterSpacing.screen)
        .padding(.top, 58)
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
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
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
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
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
        let isPartial = session.qualityScore.isPartial  // true only when dataQuality == .unspecifiedSleepOnly
        let baselineBuilding = !isPartial && (viewModel.selectedBaseline?.validNights ?? 0) < BaselineEngine.dashboardMinimumValidNights

        return ZStack(alignment: .center) {
            // Soft glow bloom behind the ring
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 250, height: 250)
                    .blur(radius: 40)
            }

            // Tick marks dial between concentric rings.
            // Pre-filtered to exclude the 45°–135° bottom gap (43 ticks vs 60).
            let tickIndices: [Int] = (0..<60).filter { i in
                let a = Double(i) * 6.0; return a < 45 || a > 135
            }
            ZStack {
                ForEach(tickIndices, id: \.self) { index in
                    let angle = Double(index) * 6.0
                    Rectangle()
                        .fill(Color.white.opacity(index % 5 == 0 ? 0.12 : 0.04))
                        .frame(width: index % 5 == 0 ? 1.5 : 1, height: index % 5 == 0 ? 8 : 4)
                        .offset(y: -118)
                        .rotationEffect(.degrees(angle))
                }
            }

            // Concentric outer fine ring
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: 236, height: 236)
                .rotationEffect(.degrees(90))

            // Concentric inner fine ring
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: 188, height: 188)
                .rotationEffect(.degrees(90))

            // 240° gauge track & progress ZStack
            ZStack {
                // Track
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(color.opacity(0.10), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(90))

                // Neon blur glow arc — compositingGroup() isolates the layer so
                // Core Animation rasterizes it independently, avoiding per-frame
                // parent-context compositing during the trim animation.
                Circle()
                    .trim(from: 0.15, to: heroAppeared ? fillEnd : 0.15)
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .compositingGroup()
                    .blur(radius: 6)
                    .opacity(reduceMotion ? 0 : 0.22)
                    .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.72).delay(0.12), value: heroAppeared)

                // Foreground active progress arc
                Circle()
                    .trim(from: 0.15, to: heroAppeared ? fillEnd : 0.15)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.72).delay(0.12), value: heroAppeared)

                // Leading tip pulsing indicator dot
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if differentiateWithoutColor {
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                    .shadow(color: reduceMotion ? .clear : color, radius: 4, x: 0, y: 0)
                    .scaleEffect(reduceMotion ? 1.0 : (dotPulse ? 1.35 : 0.95))
                    .opacity(reduceMotion ? 1.0 : (dotPulse ? 1.0 : 0.7))
                    // Animation scoped directly to this view so it doesn't
                    // invalidate sibling ring layers on every pulse frame.
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: dotPulse
                    )
                    .offset(x: 106, y: 0)
                    .rotationEffect(.degrees(360.0 * (heroAppeared ? fillEnd : 0.15) + 90.0))
                    .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.72).delay(0.12), value: heroAppeared)

                VStack(spacing: 4) {
                    Text("\(score.overall)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .tracking(-1.5)
                        .foregroundStyle(BetterColors.text)
                        .contentTransition(.numericText())
                    Text(scoreLabel(score.overall))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(color)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78)) {
                            showScoreBreakdown = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Score details")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Image(systemName: "info.circle")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(BetterColors.subtext.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    if isPartial {
                        Text("partial data")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext.opacity(0.6))
                    } else if baselineBuilding {
                        Text("bedtime score building")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(BetterColors.subtext.opacity(0.5))
                    }
                }
            }
            .frame(width: 212, height: 212)

        }
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityHint("Tap Score details to see breakdown")
        .popover(isPresented: $showScoreBreakdown, arrowEdge: .top) {
            scoreBreakdownPopover(score: score, session: session)
                .presentationCompactAdaptation(.popover)
        }
        .onAppear {
            if reduceMotion {
                heroAppeared = true
            } else {
                withAnimation { heroAppeared = true }
                // No withAnimation wrapper — pulse animation is scoped directly
                // on the dot view via the .animation(value:) modifier above.
                dotPulse = true
            }
        }
        .onChange(of: viewModel.selectedSleepDateKey) { _, _ in
            heroAppeared = false
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                if reduceMotion {
                    heroAppeared = true
                } else {
                    withAnimation { heroAppeared = true }
                }
            }
        }
    }

    @ViewBuilder
    private func scoreBreakdownPopover(score: HealthSleepScoreEstimate, session: SleepSession) -> some View {
        let travelExempt = viewModel.selectedContextEntry?.travel == true

        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Score details")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    scoreBreakdownPill(label: "Duration", value: "\(score.duration)/50")
                    pillDivider
                    if travelExempt {
                        HStack(spacing: 4) {
                            Image(systemName: "airplane").font(.system(size: 9))
                                .foregroundStyle(BetterColors.brand)
                            scoreBreakdownPill(label: "Bedtime", value: "exempt")
                        }
                    } else if viewModel.baselineIsBuilding {
                        lockedScorePill(label: "Bedtime", maxPts: 30)
                    } else {
                        scoreBreakdownPill(label: "Bedtime", value: "\(score.bedtime)/30")
                    }
                    pillDivider
                    scoreBreakdownPill(label: "Interruptions", value: "\(score.interruptions)/20")
                }
            }

            Text("Duration 50 · Bedtime 30 · Interruptions 20. Same weights as Apple Health Sleep Score. Bedtime unlocks after \(BaselineEngine.dashboardMinimumValidNights) nights.")
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BetterSpacing.large)
        .frame(minWidth: 280)
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(BetterColors.border)
            .frame(width: 1, height: 20)
    }

    private func lockedScorePill(label: String, maxPts: Int) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BetterColors.subtext.opacity(0.5))
                Text("—/\(maxPts)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext.opacity(0.5))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext.opacity(0.4))
            Text("unlocks at \(BaselineEngine.dashboardMinimumValidNights)n")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.brand.opacity(0.6))
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

    /// Subtle one-line insight under the score ring. Plain-English combination
    /// of the body-clock midpoint delta and the bedtime shift vs the user's
    /// baseline bedtime — no jargon, no card chrome.
    private func sleepInsightLine(text: String, tint: Color) -> some View {
        HStack(spacing: BetterSpacing.small) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .overlay {
                    if differentiateWithoutColor {
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    }
                }
                .shadow(color: reduceMotion ? .clear : tint.opacity(0.8), radius: 3, x: 0, y: 0)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black)
        )
        .overlay(
            Capsule()
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, BetterSpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    /// Body-clock alignment sentence (separate from bedtime-vs-baseline).
    /// Includes a low-confidence caveat when the chronotype estimate is early.
    private func bodyClockInsightLine(alignment: BodyClockSleepAlignment?) -> String? {
        guard let alignment else { return nil }
        let delta = alignment.signedDeltaMinutes
        let absDelta = abs(delta)
        var line: String
        if absDelta <= 10 {
            line = "Timing was steady vs your body clock."
        } else {
            let direction = delta < 0 ? "earlier" : "later"
            let formatted = absDelta >= 60
                ? "\(absDelta / 60)h \(absDelta % 60)m"
                : "\(absDelta)m"
            line = "Timing was \(formatted) \(direction) than your body clock."
        }
        // Low-confidence caveat — insufficientData or estimated with minimal nights
        // (freeDayNightCount ≥ 3 is the minimum; estimate can swing ±2h at that level)
        if let result = viewModel.bodyClockResult,
           result.status == .estimated, result.freeDayNightCount < 7 {
            line += " (early estimate)"
        }
        return line
    }

    /// Bedtime vs personal baseline sentence. Separate reference point from body clock.
    private func bedtimeInsightLine(session: SleepSession, baseline: SleepBaseline?) -> String? {
        guard let bedtimeDelta = bedtimeShiftMinutes(session: session, baseline: baseline),
              abs(bedtimeDelta) >= 10 else { return nil }
        let direction = bedtimeDelta < 0 ? "earlier" : "later"
        let abs = Swift.abs(bedtimeDelta)
        let formatted = abs >= 60 ? "\(abs / 60)h \(abs % 60)m" : "\(abs)m"
        return "Bedtime was \(formatted) \(direction) than your baseline."
    }

    /// Plain-text version of the primary recommendation. Used by `combinedInsightLine`
    /// so observation + recommendation can render as a single line under the score ring.
    private func recommendationText(session: SleepSession, score: HealthSleepScoreEstimate) -> String {
        if session.waso >= 30 * 60 || session.continuitySummary.meaningfulAwakeningCount >= 2 {
            return "Protect your first sleep block and keep the wind-down simple."
        }
        if score.overall >= 85 {
            return "Keep the same bedtime window."
        }
        if score.duration < 43 {
            return "Protect bedtime first — duration is the largest score input."
        }
        if score.bedtime < 24 {
            return "Aim within 30 min of your baseline bedtime."
        }
        return "Keep timing steady and avoid adding extra variables."
    }

    /// Single observation + recommendation under the score ring.
    ///
    /// Shows at most two lines so the hero never looks like a notification stack:
    ///   Line 1 — the single most relevant observation: body-clock alignment if
    ///             available, otherwise bedtime-vs-baseline, otherwise nothing.
    ///   Line 2 — an actionable recommendation (always shown).
    ///
    /// Bedtime-vs-baseline is suppressed when a body-clock line is already shown
    /// because both reference sleep timing from the same night — showing both
    /// would look like duplicate alerts to the user.
    @ViewBuilder
    private func combinedInsightLine(session: SleepSession, score: HealthSleepScoreEstimate) -> some View {
        let clockLine = bodyClockInsightLine(alignment: viewModel.selectedSleepBodyClockAlignment)
        let bedLine   = bedtimeInsightLine(session: session, baseline: viewModel.selectedBaseline)
        let rec       = recommendationText(session: session, score: score)
        let tint = viewModel.selectedSleepBodyClockAlignment
            .map { bodyClockAlignmentColor($0.category) } ?? scoreColor(score.overall)

        // Pick the single primary observation: clock wins, bed as fallback.
        let primaryLine: String? = clockLine ?? bedLine
        let primaryTint: Color   = clockLine != nil ? tint : BetterColors.warning.opacity(0.85)

        VStack(spacing: 4) {
            if let primaryLine {
                sleepInsightLine(text: primaryLine, tint: primaryTint)
            }
            sleepInsightLine(text: rec, tint: tint.opacity(0.7))
        }
    }

    // `primaryRecommendationLine` was retired — its text is now folded into
    // `combinedInsightLine` so the hero shows one observation+recommendation
    // line instead of two stacked rows. The text source is `recommendationText`.

    /// Section header used throughout the dashboard. Height is fixed so the
    /// header is always flush against the card below it — no floating gap.
    private func dashboardSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(BetterTypography.title)
            .foregroundStyle(BetterColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dataSourceIcon(for session: SleepSession) -> String {
        let name = (session.sources.first?.name ?? "").lowercased()
        if name.contains("watch") { return "applewatch" }
        if name.contains("iphone") || name.contains("phone") { return "iphone" }
        return "waveform.path.ecg"   // generic health fallback for third-party or manual
    }

    private func dataSourceLine(session: SleepSession) -> some View {
        let source = session.sources.first?.name ?? "Apple Health"
        let stageText: String = {
            switch session.dataQuality {
            case .detailedStages:
                return "stages estimated by device"
            case .mixedSources:
                return "combined sleep sources"
            case .unspecifiedSleepOnly:
                return "limited stage data"
            case .inBedOnly:
                return "in-bed time only"
            case .noData:
                return "no sleep data"
            }
        }()
        let syncedText = viewModel.lastSyncedAt.map { "synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "syncing latest data"
        let text = "\(source) · \(stageText) · \(syncedText)"

        return HStack(spacing: 6) {
            Image(systemName: dataSourceIcon(for: session))
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .foregroundStyle(BetterColors.subtext)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    /// Signed minute distance from baseline bedtime to actual bedtime on a 24h
    /// clock — negative = earlier than usual, positive = later. Returns `nil`
    /// when the baseline isn't ready.
    private func bedtimeShiftMinutes(session: SleepSession, baseline: SleepBaseline?) -> Int? {
        guard let baseline, baseline.validNights >= BaselineEngine.dashboardMinimumValidNights else { return nil }
        let date = session.inBedStartDate ?? session.startDate
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let actual = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        var diff = actual - baseline.bedtimeMinuteAverage
        diff = diff.truncatingRemainder(dividingBy: 1440)
        if diff > 720 { diff -= 1440 }
        if diff < -720 { diff += 1440 }
        return Int(diff.rounded())
    }

    // MARK: - Baseline placeholder

    private var baselineNotReadyCard: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 20))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 42, height: 42)
                .background(BetterColors.brand.opacity(0.12), in: Circle())
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
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
    }

    // MARK: - Biometrics Card

    private func biometricsCard(biometrics: NightlyBiometricSummary) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            BiomarkerSourceRow(provenance: viewModel.biomarkerProvenance)
            SleepBiomarkerReactionsCard(
                biometrics: biometrics,
                recentSessions: viewModel.recentSessions,
                baseline: viewModel.biomarkerBaseline,
                reactions: viewModel.biomarkerReactions,
                readiness: viewModel.biomarkerReadiness,
                provenance: viewModel.biomarkerProvenance
            )
        }
    }



    // MARK: - Shared UI Helpers

    private func sectionLabel(_ title: String, icon: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(ProtocolPalette.dimText)
            .textCase(.uppercase)
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
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
        HealthSleepScoreEstimator.estimate(
            session: session,
            baseline: viewModel.selectedBaseline,
            sleepGoalHours: viewModel.sleepGoalHours,
            contextEntry: viewModel.selectedContextEntry
        )
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
                .padding(.top, 58)

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
        VStack(spacing: BetterSpacing.large) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.brand)
            }
            monthHeader
            weekdayHeader
            dayGrid
            Spacer(minLength: 0)
        }
        .padding(BetterSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BetterColors.background.ignoresSafeArea())
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
                            .stroke(ringColor(score: score, dataQuality: summary?.dataQuality), style: StrokeStyle(lineWidth: 5, lineCap: .round))
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

    private func ringColor(score: Double, dataQuality: SleepDataQuality?) -> Color {
        if dataQuality == .unspecifiedSleepOnly { return BetterColors.warning }
        switch Int(score) {
        case 85...: return BetterColors.success
        case 70...: return BetterColors.brand
        case 55...: return BetterColors.warning
        default:    return BetterColors.danger
        }
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
    case rhr    = "Min HR"  // "Low HR" reads as bradycardia alert — this is a recovery metric
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
        case .breath: return "breaths/min"
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
            // Half-open upper bounds prevent exact-integer values (e.g. 10.0) from
            // matching two zones and landing in the worse one via .first { }.
            return [
                SleepBiometricZone(label: "Needs Attention", range: 8.0...9.999,  color: BetterColors.danger),
                SleepBiometricZone(label: "Fair",            range: 10.0...11.999, color: BetterColors.warning),
                SleepBiometricZone(label: "Normal",          range: 12.0...13.999, color: BetterColors.hrv),
                SleepBiometricZone(label: "Optimal",         range: 14.0...15.999, color: BetterColors.success),
                SleepBiometricZone(label: "Normal",          range: 16.0...17.999, color: BetterColors.hrv),
                SleepBiometricZone(label: "Fair",            range: 18.0...19.999, color: BetterColors.warning),
                SleepBiometricZone(label: "Needs Attention", range: 20.0...24.0,   color: BetterColors.danger),
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
            return "Your lowest heart rate while asleep. Lower typically means your body is calm and recovering; sharp increases can point to strain."
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

// MARK: - Biomarker Key bridge

private extension BiomarkerKey {
    var asTab: SleepVitalTab {
        switch self {
        case .rhr:    return .rhr
        case .hrv:    return .hrv
        case .spo2:   return .spo2
        case .breath: return .breath
        }
    }
}

private extension SleepVitalTab {
    var asBiomarkerKey: BiomarkerKey {
        switch self {
        case .rhr:    return .rhr
        case .hrv:    return .hrv
        case .spo2:   return .spo2
        case .breath: return .breath
        }
    }
}

private struct BiomarkerSourceRow: View {
    let provenance: [BiomarkerKey: BiomarkerProvenance]

    private var available: [BiomarkerProvenance] {
        BiomarkerKey.allCases.compactMap { provenance[$0] }.filter { $0.confidence != .missing }
    }

    private var sourceText: String {
        let names = Array(Set(available.flatMap(\.sourceNames))).sorted()
        guard !names.isEmpty else { return "Sources will appear after biomarker readings sync." }
        if names.count == 1 {
            return names[0]
        }
        return "\(names[0]) +\(names.count - 1) sources"
    }

    private var trustText: String {
        guard !available.isEmpty else { return "No biomarker readings yet" }
        if available.contains(where: { $0.confidence == .low }) {
            return "Limited confidence"
        }
        if available.contains(where: { $0.confidence == .mixed }) {
            return "Mixed source confidence"
        }
        return "Auto-captured overnight"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BetterColors.subtext)
            Text(sourceText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
            Text("·")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Text(trustText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Biomarker Reactions Card (collapsed summary)

/// Default biomarker surface: four rows comparing tonight to the user's cached
/// 30/60-day "usual." Each row taps to open `BiomarkerDetailSheet` with the
/// full chart + baseline overlay.
private struct SleepBiomarkerReactionsCard: View {
    let biometrics: NightlyBiometricSummary
    let recentSessions: [SleepSession]
    let baseline: BiomarkerBaseline?
    let reactions: [BiomarkerKey: SleepBiomarkerReaction]

    let readiness: [BiomarkerKey: BiomarkerBaselineReadiness]
    let provenance: [BiomarkerKey: BiomarkerProvenance]

    @State private var presentedKey: BiomarkerKey?
    @State private var selectedFeedbackKey: BiomarkerKey?

    private static let order: [BiomarkerKey] = [.rhr, .hrv, .spo2, .breath]

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            headerRow
            VStack(spacing: 0) {
                ForEach(Array(Self.order.enumerated()), id: \.element) { index, key in
                    bodySignalRow(for: key)
                    if index < Self.order.count - 1 {
                        Divider()
                            .background(BetterColors.border)
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
        .sensoryFeedback(.impact(weight: .light), trigger: selectedFeedbackKey)
        .sheet(item: $presentedKey) { key in
            BiomarkerDetailSheet(
                tab: key.asTab,
                biometrics: biometrics,
                recentSessions: recentSessions,
                baseline: baseline,
                reaction: reactions[key],
                readiness: readiness[key] ?? .unavailable(minimumCount: 5),
                provenance: provenance[key]
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerEyebrow)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.brandLight)
                .tracking(0.7)
                .textCase(.uppercase)
            Text(headerHeadline)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerHeadline: String {
        let rows = presentations
        let captured = rows.filter { $0.signal != .missing }.count
        guard captured > 0 else {
            return "Biomarker readings were not captured last night"
        }
        let ready = rows.filter { $0.signal != .building && $0.signal != .missing }
        guard !ready.isEmpty else {
            return "Your baseline body signals are still building"
        }
        let harder = ready.filter { $0.signal == .harder }.count
        let recovered = ready.filter { $0.signal == .recovered }.count
        let steady = ready.filter { $0.signal == .steady }.count
        let rhr = presentation(for: .rhr)
        let hrv = presentation(for: .hrv)
        if rhr.signal == .harder && hrv.signal == .recovered {
            return "Your heart worked harder, but recovery still improved"
        }
        if rhr.signal == .harder {
            return "Your heart worked harder last night"
        }
        if hrv.signal == .harder {
            return "Recovery looked lighter last night"
        }
        if harder > recovered && harder >= steady {
            return "Your body worked harder than baseline last night"
        }
        if recovered > harder && recovered >= steady {
            return "Your body recovered better than baseline last night"
        }
        return "Your body stayed close to baseline last night"
    }

    private var headerEyebrow: String {
        if let baseline {
            return "Compared with \(baseline.windowDays)-night baseline"
        }
        return "Personal baseline building"
    }

    private var headerSubtitle: String {
        let rows = presentations
        let rhr = presentation(for: .rhr)
        let hrv = presentation(for: .hrv)
        let spo2 = presentation(for: .spo2)
        let breath = presentation(for: .breath)

        if rows.allSatisfy({ $0.signal == .missing }) {
            return "No overnight heart, oxygen, or breathing readings were captured."
        }
        if rows.allSatisfy({ $0.signal == .building || $0.signal == .missing }) {
            return "Keep wearing your device overnight to unlock your baseline comparison."
        }
        if rhr.signal == .harder && hrv.signal == .recovered {
            return "Resting heart rate was above baseline. HRV improved. Oxygen and breathing stayed normal."
        }
        if rhr.signal == .harder {
            return "Resting heart rate was the main change. Oxygen, breathing, and HRV add context below."
        }
        if hrv.signal == .harder {
            return "HRV was below baseline. Heart rate, oxygen, and breathing add context below."
        }
        if rhr.signal == .steady && hrv.signal == .steady && spo2.signal == .steady && breath.signal == .steady {
            return "Heart rate, HRV, oxygen, and breathing stayed in your normal range."
        }
        return "A few readings shifted, but oxygen and breathing stayed easy to scan below."
    }

    private var presentations: [BiomarkerBodySignalPresentation] {
        Self.order.map { presentation(for: $0) }
    }

    private func presentation(for key: BiomarkerKey) -> BiomarkerBodySignalPresentation {
        let tab = key.asTab
        let tonight = tab.currentValue(from: biometrics)
        let reaction = reactions[key]
        let keyReadiness = readiness[key] ?? .unavailable(minimumCount: 5)
        let keyProvenance = provenance[key]

        return BiomarkerBodySignalPresentation.make(
            key: key,
            tonight: tonight,
            baseline: baseline,
            reaction: reaction,
            readiness: keyReadiness,
            provenance: keyProvenance
        )
    }

    private func bodySignalRow(for key: BiomarkerKey) -> some View {
        let tab = key.asTab
        let item = presentation(for: key)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedFeedbackKey = key
                presentedKey = key
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tab.color.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: tab.educationIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tab.color)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(tab.fullName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    HStack(spacing: 6) {
                        Text(item.statusText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(signalColor(item.signal))
                            .lineLimit(1)
                        Text(item.percentText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                valueGroup(item: item, tab: tab)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BetterColors.subtext.opacity(0.58))
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(BodySignalButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(item: item, tab: tab))
        .accessibilityHint("Double tap to open \(tab.fullName) details")
    }

    @ViewBuilder
    private func valueGroup(item: BiomarkerBodySignalPresentation, tab: SleepVitalTab) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(item.value.map { formatted(value: $0, tab: tab) } ?? "—")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(compactUnit(for: tab))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func compactUnit(for tab: SleepVitalTab) -> String {
        switch tab {
        case .breath:
            return "/min"
        default:
            return tab.unit
        }
    }

    private func formatted(value: Double, tab: SleepVitalTab) -> String {
        // Keep this aligned with `MiniDeltaBar.formatted(_:)` and
        // `SingleBiomarkerChartView.formattedValue(_:)` — SpO₂ renders as
        // whole percent (pulse-ox accuracy is ±2%).
        switch tab {
        case .rhr, .hrv: return String(format: "%.0f", value)
        case .spo2:      return String(format: "%.0f", value)
        case .breath:    return String(format: "%.1f", value)
        }
    }

    private func signalColor(_ signal: BiomarkerBodySignal) -> Color {
        switch signal {
        case .harder:
            return BetterColors.warning
        case .recovered:
            return BetterColors.success
        case .steady:
            return BetterColors.hrv
        case .building, .missing:
            return BetterColors.subtext
        }
    }

    private func accessibilityLabel(item: BiomarkerBodySignalPresentation, tab: SleepVitalTab) -> String {
        let value = item.value.map { "\(formatted(value: $0, tab: tab)) \(tab.unit)" } ?? "No reading"
        return "\(tab.fullName), \(value), \(item.statusText), \(item.percentText). \(item.meaningText)"
    }
}

private struct BodySignalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension BiomarkerKey: Identifiable {
    public var id: String { rawValue }
}

// MARK: - MiniDeltaBar

/// Tiny ±1σ "usual range" track with a tick marker for tonight's value.
/// Used both in the collapsed `SleepBiomarkerReactionsCard` rows and (at a
/// larger size) inside the `BiomarkerDetailSheet` baseline panel.
private struct MiniDeltaBar: View {
    enum Style { case compact, expanded }

    let tab: SleepVitalTab
    let reaction: SleepBiomarkerReaction
    let tonight: Double
    var style: Style = .compact

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: trackSpacing) {
            track
            label
        }
    }

    private var trackHeight: CGFloat { style == .compact ? 5 : 8 }
    private var trackSpacing: CGFloat { style == .compact ? 4 : 6 }
    private var labelFont: Font {
        style == .compact
            ? .system(size: 11, weight: .medium, design: .rounded)
            : .system(size: 13, weight: .semibold, design: .rounded)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mean = reaction.baselineMean
            let stdDev = max(0.01, reaction.baselineStdDev)
            // Domain spans ±2σ around the personal baseline.
            let lower = mean - 2 * stdDev
            let upper = mean + 2 * stdDev
            let domain = max(0.01, upper - lower)
            let usualLow = ((mean - stdDev) - lower) / domain
            let usualHigh = ((mean + stdDev) - lower) / domain
            let clampedTonight = max(lower, min(upper, tonight))
            let tonightPos = (clampedTonight - lower) / domain

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tab.color.opacity(0.35))
                    .frame(width: max(2, CGFloat(usualHigh - usualLow) * width), height: trackHeight)
                    .offset(x: CGFloat(usualLow) * width)

                Capsule()
                    .fill(BetterColors.subtext.opacity(0.7))
                    .frame(width: 1.5, height: trackHeight + 4)
                    .offset(x: CGFloat((mean - lower) / domain) * width - 0.75, y: -2)

                Circle()
                    .fill(tickColor)
                    .frame(width: tickSize, height: tickSize)
                    .overlay(Circle().stroke(differentiateWithoutColor ? Color.white.opacity(0.85) : Color.black, lineWidth: differentiateWithoutColor ? 1.5 : 1))
                    .offset(x: CGFloat(tonightPos) * width - tickSize / 2,
                            y: (trackHeight - tickSize) / 2)
            }
        }
        .frame(height: max(trackHeight + 4, tickSize))
    }

    private var tickSize: CGFloat { style == .compact ? 9 : 12 }

    private var tickColor: Color {
        switch reaction.direction {
        case .improved: return BetterColors.success
        case .worse:    return BetterColors.danger
        case .neutral:  return BetterColors.text
        }
    }

    private var label: some View {
        let usual = formatted(reaction.baselineMean)
        let tonightStr = formatted(tonight)
        let diff = formatted(abs(reaction.delta))
        let arrow: String = reaction.delta == 0
            ? ""
            : (reaction.delta > 0 ? "↑" : "↓")
        let deltaText: String = {
            switch reaction.direction {
            case .neutral:
                return "in range"
            case .improved:
                return "\(arrow)\(diff) better"
            case .worse:
                return "\(arrow)\(diff) off baseline"
            }
        }()

        if style == .compact {
            // Compact rows already show tonight's value in large bold type on the
            // right — repeating it here just causes truncation. Show only the
            // baseline and the relative shift (≈ 12 chars max).
            return AnyView(
                HStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Text("baseline ").foregroundStyle(BetterColors.subtext)
                        Text(usual).foregroundStyle(BetterColors.text)
                    }
                    Text("·").foregroundStyle(BetterColors.subtext)
                    Text(deltaText).foregroundStyle(deltaColor)
                }
                .font(labelFont)
                .lineLimit(1)
            )
        } else {
            // Expanded (detail sheet baseline panel) — show full context.
            return AnyView(
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("baseline ").foregroundStyle(BetterColors.subtext)
                        Text(usual).foregroundStyle(BetterColors.text)
                    }
                    Text("·").foregroundStyle(BetterColors.subtext)
                    HStack(spacing: 0) {
                        Text("tonight ").foregroundStyle(BetterColors.subtext)
                        Text(tonightStr).foregroundStyle(BetterColors.text)
                    }
                    Text("(\(deltaText))").foregroundStyle(deltaColor)
                }
                .font(labelFont)
                .lineLimit(1)
            )
        }
    }


    private var deltaColor: Color {
        switch reaction.direction {
        case .improved: return BetterColors.success
        case .worse:    return BetterColors.danger
        case .neutral:  return BetterColors.subtext
        }
    }

    private func formatted(_ value: Double) -> String {
        switch tab {
        case .rhr, .hrv: return String(format: "%.0f", value)
        case .spo2:      return String(format: "%.0f", value)   // whole percent — pulse-ox accuracy is ±2%
        case .breath:    return String(format: "%.1f", value)
        }
    }
}

// MARK: - SingleBiomarkerChartView

/// Focused chart card for a single biomarker — no tab switcher. Used inside
/// `BiomarkerDetailSheet` so the detail view stays scoped to the biomarker the
/// user tapped. Renders the 7D / 30D / 60D timeline picker, the zone chart
/// (with the dashed personal-baseline line), a selected-day callout, and the
/// average / best / range / coverage footer grid.
private struct SingleBiomarkerChartView: View {
    let tab: SleepVitalTab
    let recentSessions: [SleepSession]
    let baseline: BiomarkerBaseline?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @State private var timeline: SleepBiometricTimeline = .thirtyDays
    @State private var selectedPointKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                Text("Trend")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .tracking(0.6)
                Spacer()
                timelinePicker
            }

            SleepBiometricZoneChart(
                points: points,
                selectedPointKey: selectedPointKey,
                zones: tab.zones,
                chartMin: dynamicChartMin,
                chartMax: dynamicChartMax,
                color: tab.color,
                onSelect: { point in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedPointKey = point.dateKey
                    }
                },
                baselineValue: baseline?.means[tab.asBiomarkerKey]
            )

            selectedDayCallout
            footerGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BetterSpacing.large)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
        .onAppear(perform: resetSelection)
        .onChange(of: timeline) { _, _ in resetSelection() }
        .onChange(of: recentSessions.count) { _, _ in resetSelection() }
    }

    private var points: [SleepBiometricPoint] {
        // recentSessions is pre-sorted ascending by sleepDateKey from loadRecentSessions
        // before being passed in — no re-sort needed here.
        return recentSessions.suffix(timeline.dayCount).compactMap { session in
            guard let value = tab.value(from: session),
                  let date = SleepDateKey.date(from: session.sleepDateKey)
            else { return nil }
            return SleepBiometricPoint(dateKey: session.sleepDateKey, date: date, value: value)
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

    /// Dynamic chart floor derived from actual data + baseline −2σ so values
    /// that sit below the hardcoded static minimum are never clamped to the
    /// bottom pixel of the chart.
    private var dynamicChartMin: Double {
        let key = tab.asBiomarkerKey
        var candidates = points.map(\.value)
        if let mean = baseline?.means[key], let std = baseline?.stdDevs[key] {
            candidates.append(mean - 2 * std)
        }
        guard let dataMin = candidates.min() else { return tab.chartMin }
        // Add 10% breathing room below the lowest value, then snap to a
        // multiple of 5 so grid lines stay clean.
        let raw = dataMin * 0.90
        let snapped = (raw / 5.0).rounded(.down) * 5.0
        return min(snapped, tab.chartMin)
    }

    /// Dynamic chart ceiling derived from actual data + baseline +2σ.
    private var dynamicChartMax: Double {
        let key = tab.asBiomarkerKey
        var candidates = points.map(\.value)
        if let mean = baseline?.means[key], let std = baseline?.stdDevs[key] {
            candidates.append(mean + 2 * std)
        }
        guard let dataMax = candidates.max() else { return tab.chartMax }
        let raw = dataMax * 1.10
        let snapped = (raw / 5.0).rounded(.up) * 5.0
        return max(snapped, tab.chartMax)
    }

    private var bestValue: Double? {
        switch tab {
        case .rhr:
            // Floor at 40 bpm — values below the optimal-zone bottom are likely
            // device fit / measurement artifacts and shouldn't be shown as "Best".
            guard let raw = points.map(\.value).min() else { return nil }
            return max(raw, 40)
        case .hrv, .spo2:    return points.map(\.value).max()
        case .breath:        return points.map(\.value).min { abs($0 - 14) < abs($1 - 14) }
        }
    }

    /// Pick the right comparator for a scrubbed point. When the user scrubs a
    /// past night, comparing to the **window mean** drives the delta to ≈ 0
    /// (the point is itself in the window). Compare to the cached personal
    /// baseline mean instead — only fall back to the window mean if there is
    /// no baseline (early days), or when the point is tonight.
    private func referenceAverage(for point: SleepBiometricPoint) -> Double? {
        let isTonight = (point.dateKey == points.last?.dateKey)
        if isTonight { return average }
        if let baseline, let mean = baseline.means[tab.asBiomarkerKey] {
            return mean
        }
        return average
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
                        .background(option == timeline ? tab.color : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.accessibilityLabel), \(option == timeline ? "selected" : "not selected")")
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04), in: Capsule())
    }

    @ViewBuilder
    private var selectedDayCallout: some View {
        if let point = selectedPoint {
            HStack(alignment: .top, spacing: BetterSpacing.small) {
                Circle()
                    .fill(tab.statusColor(for: point.value))
                    .frame(width: 9, height: 9)
                    .overlay {
                        if differentiateWithoutColor {
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        }
                    }
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(point.date.formatted(.dateTime.month(.abbreviated).day())) · \(formattedValue(point.value)) \(tab.unit)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(tab.impactText(value: point.value, average: referenceAverage(for: point)))
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
            statTile(bestLabel, value: bestValue.map { formattedValue($0) } ?? "--")
            statTile("Range", value: rangeText)
            statTile("Nights", value: "\(points.count)/\(timeline.dayCount)")
        }
    }

    private var bestLabel: String {
        switch tab {
        case .rhr:    return "Lowest"
        case .hrv:    return "Highest"
        case .spo2:   return "Highest"
        case .breath: return "Optimal"
        }
    }

    private var rangeText: String {
        guard let min = points.map(\.value).min(), let max = points.map(\.value).max() else { return "--" }
        return "\(formattedValue(min))-\(formattedValue(max))"
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
        switch tab {
        case .breath: return String(format: "%.1f", value)
        case .spo2:   return String(format: "%.0f", value)   // whole percent — pulse-ox accuracy is ±2%
        default:      return String(format: "%.0f", value)
        }
    }
}

// MARK: - Biomarker Detail Sheet (single biomarker, education-first)

/// Single-biomarker detail surface. Opens from a tap on a row in
/// `SleepBiomarkerReactionsCard` and shows ONLY the tapped biomarker — no tab
/// switcher to the other three. Designed to be readable by a curious 11-year-
/// old: hero number → what this means → trend chart with personal baseline →
/// tonight vs your usual → how it impacts sleep → collapsible reference
/// ranges.
private struct BiomarkerDetailSheet: View {
    let tab: SleepVitalTab
    let biometrics: NightlyBiometricSummary
    let recentSessions: [SleepSession]
    let baseline: BiomarkerBaseline?
    let reaction: SleepBiomarkerReaction?
    let readiness: BiomarkerBaselineReadiness
    let provenance: BiomarkerProvenance?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var referenceExpanded: Bool = false

    init(
        tab: SleepVitalTab,
        biometrics: NightlyBiometricSummary,
        recentSessions: [SleepSession],
        baseline: BiomarkerBaseline?,
        reaction: SleepBiomarkerReaction?,
        readiness: BiomarkerBaselineReadiness,
        provenance: BiomarkerProvenance?
    ) {
        self.tab = tab
        self.biometrics = biometrics
        self.recentSessions = recentSessions
        self.baseline = baseline
        self.reaction = reaction
        self.readiness = readiness
        self.provenance = provenance
    }

    private var key: BiomarkerKey { tab.asBiomarkerKey }
    private var tonight: Double? { tab.currentValue(from: biometrics) }
    private var sampleCount: Int { baseline?.sampleCounts[key] ?? 0 }
    private var hasBaseline: Bool { readiness.isReady }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.large) {
                    hero
                    educationPanel
                    SingleBiomarkerChartView(
                        tab: tab,
                        recentSessions: recentSessions,
                        baseline: baseline
                    )
                    baselinePanel
                    measurementFooter
                    referenceRangeSection
                }
                .padding(BetterSpacing.large)
            }
            .background(BetterColors.background.ignoresSafeArea())
            .navigationTitle(tab.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(BetterTypography.subheadline.bold())
                        .foregroundStyle(BetterColors.brand)
                }
            }
        }
        .preferredColorScheme(.dark)
    }


    // MARK: Hero


    private var hero: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let tonight {
                    Text(formattedValue(tonight))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                } else {
                    Text("—")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
                Text(tab.unit)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
                directionChip
            }

            Text(heroSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var directionChip: some View {
        if let reaction {
            // Color signals sentiment (green = good, red = off-usual).
            let color: Color = {
                switch reaction.direction {
                case .improved: return BetterColors.success
                case .worse:    return BetterColors.danger
                case .neutral:  return BetterColors.subtext
                }
            }()
            // Per-metric, directional copy avoids implying a medical judgment
            // from a single night. "Improved/Worse" is reserved for multi-night
            // trend surfaces — single-night cards say what direction the value
            // moved relative to the user's usual range.
            let label: String = {
                switch (tab, reaction.direction) {
                case (.rhr,  .improved): return "Lower than baseline"
                case (.rhr,  .worse):    return "Higher than baseline"
                case (.hrv,  .improved): return "Higher than baseline"
                case (.hrv,  .worse):    return "Lower than baseline"
                case (.spo2, .improved): return "Higher than baseline"
                case (.spo2, .worse):    return "Lower than baseline"
                case (.breath, .improved): return "In baseline range"
                case (.breath, .worse):    return "Outside baseline range"
                case (_,     .neutral):  return "In baseline range"
                }
            }()
            // Icon direction follows the physical delta (↓ if tonight < baseline,
            // ↑ if tonight > baseline). For low HR, a drop IS the improvement — so
            // the arrow points down inside a green chip, which reads naturally.
            let icon: String = {
                switch reaction.direction {
                case .neutral:
                    return "checkmark.circle.fill"
                case .worse:
                    return "exclamationmark.circle.fill"
                case .improved:
                    return reaction.delta < 0
                        ? "arrow.down.right.circle.fill"
                        : "arrow.up.right.circle.fill"
                }
            }()
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
        } else if !hasBaseline {
            Text("Baseline · \(readiness.shortLabel)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
    }


    private var heroSubtitle: String {
        if let reaction {
            return reaction.plainEnglishHeadline()
        }
        if !hasBaseline {
            return readiness.neutralCopy
        }
        if tonight == nil {
            return "No reading captured tonight."
        }
        return "Tonight matched your baseline range."
    }

    // MARK: Education panel

    private var educationPanel: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.small) {
                Image(systemName: tab.educationIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tab.color)
                    .frame(width: 34, height: 34)
                    .background(tab.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("What this means")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Spacer()
            }
            Text(key.simpleExplanation)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BetterColors.brandLight)
                    .padding(.top, 2)
                Text(impactCopy)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BetterSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BetterColors.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(BetterSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
    }

    private var impactCopy: String {
        if let reaction {
            return BiomarkerInsightSynthesizer.impactLine(reaction: reaction, sleepScore: nil)
        }
        return key.sleepImpactExplanation
    }

    // MARK: Baseline panel

    @ViewBuilder
    private var baselinePanel: some View {
        if hasBaseline, let baseline, let mean = baseline.means[key], let tonight, let reaction {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                Text("Tonight vs your baseline")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .tracking(0.6)

                HStack(alignment: .top, spacing: BetterSpacing.medium) {
                    column(title: "Your baseline",
                           value: formattedValue(mean),
                           sub: "±\(formattedValue(baseline.stdDevs[key] ?? 0)) \(tab.unit) · \(sampleCount) night\(sampleCount == 1 ? "" : "s")")
                    Spacer(minLength: 0)
                    column(title: "Tonight",
                           value: formattedValue(tonight),
                           sub: deltaSubLine(reaction: reaction),
                           valueColor: tickColor(for: reaction.direction))
                }

                MiniDeltaBar(tab: tab, reaction: reaction, tonight: tonight, style: .expanded)
            }
            .padding(BetterSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BetterColors.border, lineWidth: 1))
        }
    }

    private func column(title: String, value: String, sub: String, valueColor: Color = BetterColors.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                Text(tab.unit)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
            Text(sub)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deltaSubLine(reaction: SleepBiomarkerReaction) -> String {
        if reaction.direction == .neutral {
            return "in your baseline range"
        }
        // SpO₂ pulse-ox accuracy is ±2% — suppress sub-1% deltas instead of
        // showing values like "↑0.4 % vs baseline" that imply false precision.
        if tab == .spo2, abs(reaction.delta) < 1.0 {
            return "in your baseline range"
        }
        let arrow = reaction.delta > 0 ? "↑" : "↓"
        let diff = formattedValue(abs(reaction.delta))
        return "\(arrow)\(diff) \(tab.unit) vs baseline"
    }

    private func tickColor(for direction: BiomarkerReactionDirection) -> Color {
        switch direction {
        case .improved: return BetterColors.success
        case .worse:    return BetterColors.danger
        case .neutral:  return BetterColors.text
        }
    }

    // MARK: Measurement footer

    private var measurementFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "applewatch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BetterColors.subtext)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Measured during sleep")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                if let provenance {
                    Text("\(provenance.compactSourceLabel) · \(provenance.neutralTrustCopy)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(buildingCopy)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(BetterSpacing.small)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var buildingCopy: String {
        if !hasBaseline {
            return readiness.neutralCopy
        }
        if let baseline {
            return "Compared against your past \(baseline.windowDays) days of nightly readings."
        }
        return ""
    }

    // MARK: Reference range section

    private var referenceRangeSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                    referenceExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Reference ranges")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .tracking(0.6)
                    Spacer()
                    Image(systemName: referenceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BetterColors.subtext)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if referenceExpanded {
                HStack(spacing: 6) {
                    ForEach(legendOrderedZones(), id: \.label) { zone in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(zone.color)
                                    .frame(width: 7, height: 7)
                                    .overlay {
                                        if differentiateWithoutColor {
                                            Circle()
                                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                        }
                                    }
                                Text(zone.label)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(BetterColors.text)
                            }
                            Text(rangeText(for: zone))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(zone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                Text("Population reference — your personal baseline above is the more meaningful comparison.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.subtext.opacity(0.8))
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legendOrderedZones() -> [SleepBiometricZone] {
        var seen = Set<String>()
        var ordered: [SleepBiometricZone] = []
        for zone in tab.zones where seen.insert(zone.label).inserted {
            ordered.append(zone)
        }
        let priority = ["Optimal", "Normal", "Fair", "Needs Attention"]
        ordered.sort { (a, b) in
            (priority.firstIndex(of: a.label) ?? .max) < (priority.firstIndex(of: b.label) ?? .max)
        }
        return ordered
    }

    private func rangeText(for zone: SleepBiometricZone) -> String {
        let lower = String(format: "%.0f", zone.range.lowerBound)
        let upper = String(format: "%.0f", zone.range.upperBound)
        return "\(lower)–\(upper) \(tab.unit)"
    }

    private func formattedValue(_ value: Double) -> String {
        switch tab {
        case .rhr, .hrv: return String(format: "%.0f", value)
        case .spo2:      return String(format: "%.0f", value)   // whole percent — pulse-ox accuracy is ±2%
        case .breath:    return String(format: "%.1f", value)
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
    /// When non-nil, draws a dashed horizontal line at this value labelled
    /// "Your usual" and dims the population zone bands so the user's personal
    /// baseline becomes the visual focus.
    var baselineValue: Double? = nil

    @State private var trimAmount: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, size in
                    drawChart(context: &context, size: size)
                }

                if let baselineValue, let y = baselineYPosition(value: baselineValue, height: size.height) {
                    HStack {
                        Spacer(minLength: 0)
                        Text("Your baseline \(formattedBaseline(baselineValue))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55), in: Capsule())
                    }
                    .position(x: size.width / 2, y: max(10, y - 10))
                    .allowsHitTesting(false)
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

        // Dim the population zones when the user has a personal baseline so it
        // becomes the visual focus instead of the colored backdrop.
        let zoneOpacity: Double = baselineValue == nil ? 0.16 : 0.06
        for zone in zones {
            let clampedLow = max(chartMin, zone.range.lowerBound)
            let clampedHigh = min(chartMax, zone.range.upperBound)
            guard clampedHigh > clampedLow else { continue }
            let top = yPos(clampedHigh)
            let bottom = yPos(clampedLow)
            context.fill(
                Path(CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))),
                with: .color(zone.color.opacity(zoneOpacity))
            )
        }

        // Dashed personal-baseline reference line.
        if let baselineValue, baselineValue >= chartMin, baselineValue <= chartMax {
            let y = yPos(baselineValue)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(color.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 4])
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

    private func baselineYPosition(value: Double, height: CGFloat) -> CGFloat? {
        guard value >= chartMin, value <= chartMax else { return nil }
        let spread = max(0.1, chartMax - chartMin)
        let normalized = (value - chartMin) / spread
        return height - height * CGFloat(normalized)
    }

    private func formattedBaseline(_ value: Double) -> String {
        if value.rounded() == value || abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
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
