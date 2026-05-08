import SwiftUI
import UIKit

// MARK: - ProtocolTabView

struct ProtocolTabView: View {
    @Bindable var viewModel: ProtocolViewModel
    @Bindable var comparisonViewModel: ProtocolComparisonDashboardViewModel
    @Bindable var contextViewModel: ContextFactorDashboardViewModel

    @State private var showStartDatePicker = false
    @State private var tempStartDate: Date = Date()

    // Inline journal state
    @State private var caffeineLate: JournalTriState = .unknown
    @State private var alcohol: JournalTriState = .unknown
    @State private var workout: JournalTriState = .unknown
    @State private var lateMeal: JournalTriState = .unknown
    @State private var highStress: JournalTriState = .unknown
    @State private var screenTimeLate: JournalTriState = .unknown
    @State private var nap: JournalTriState = .unknown
    @State private var travel: JournalTriState = .unknown
    @State private var perceivedQuality: PerceivedSleepQuality? = nil
    @State private var morningEnergy: MorningEnergy? = nil
    @State private var journalSyncDone = false
    @State private var shareItem: ResearchShareItem?
    @State private var journalStep = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BetterSpacing.section) {
                header
                if viewModel.isProtocolEnabled {
                    enabledContent
                } else {
                    disabledState
                }
            }
            .padding(.horizontal, BetterSpacing.screen)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(BetterColors.background.ignoresSafeArea())
        .navigationTitle("Protocol")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStartDatePicker) {
            startDatePickerSheet
        }
        .sheet(item: $shareItem) { item in
            ResearchShareSheet(url: item.url)
        }
        .onChange(of: viewModel.exportURL) { _, url in
            shareItem = url.map(ResearchShareItem.init)
        }
        .task {
            await viewModel.onAppear()
            await comparisonViewModel.onAppear()
            syncJournalFromEntry()
        }
        .onChange(of: viewModel.todayContextEntry) { _, _ in
            if !journalSyncDone {
                syncJournalFromEntry()
                journalSyncDone = true
            }
        }
        .refreshable {
            await viewModel.onAppear()
            await comparisonViewModel.loadData(preferDefaultWindow: false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Protocol")
                    .font(BetterTypography.display)
                    .foregroundStyle(BetterColors.text)
                Text("Track your sleep routine")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Button {
                Task { await viewModel.exportResearchData() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isExporting {
                        ProgressView()
                            .tint(BetterColors.brand)
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("Export Data")
                }
                .font(BetterTypography.caption.weight(.semibold))
                .foregroundStyle(BetterColors.brand)
                .padding(.horizontal, BetterSpacing.medium)
                .padding(.vertical, BetterSpacing.small)
                .background(BetterColors.brand.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting)
            Toggle("", isOn: Binding(
                get: { viewModel.isProtocolEnabled },
                set: { _ in viewModel.toggleEnabled() }
            ))
            .toggleStyle(ProtocolToggleStyle())
        }
        .padding(.top, BetterSpacing.medium)
    }

    // MARK: - Enabled Content

    @ViewBuilder
    private var enabledContent: some View {
        if viewModel.protocolStartDate != nil {
            protocolHeroCard
            timelineStrip
            ProtocolResearchDashboard(
                comparisonViewModel: comparisonViewModel,
                points: viewModel.chartPoints,
                baselineSummary: viewModel.beforeProtocolSummary
            )
        } else {
            setStartDateCard
        }
        journalCard
    }

    // MARK: - Set Start Date Prompt

    private var setStartDateCard: some View {
        VStack(spacing: BetterSpacing.large) {
            ZStack {
                Circle()
                    .fill(BetterColors.brand.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(BetterColors.brand)
            }

            VStack(spacing: BetterSpacing.small) {
                Text("When did you start?")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                    .multilineTextAlignment(.center)
                Text("Set your protocol start date and all past nights since then will automatically be counted as taken.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: BetterSpacing.small) {
                previewHintPill("Sleep timeline", icon: "chart.line.uptrend.xyaxis")
                previewHintPill("Impact insights", icon: "sparkles")
            }

            Button {
                tempStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                showStartDatePicker = true
            } label: {
                Text("Set Start Date")
                    .font(BetterTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BetterSpacing.medium)
                    .background(BetterColors.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(BetterSpacing.xLarge)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BetterColors.cardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(BetterColors.glassStroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.36), radius: 20, y: 10)
        }
    }

    private func previewHintPill(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.brand)
            .padding(.horizontal, BetterSpacing.medium)
            .padding(.vertical, BetterSpacing.xSmall)
            .background(BetterColors.brand.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Hero Card

    private var protocolHeroCard: some View {
        let isTakenToday = viewModel.items.first.map { viewModel.isTakenToday($0) } ?? false

        return VStack(spacing: 0) {
            // Day counter section
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [BetterColors.brand.opacity(0.16), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 200
                )
                .frame(height: 180)

                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(viewModel.daysOnProtocol)")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(BetterColors.brand)
                        Text("days")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                            .padding(.bottom, 12)
                    }
                    Text("on your sleep protocol")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.subtext)
                    if let startDate = viewModel.protocolStartDate {
                        Text("since \(startDate.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.mutedText)
                    }
                }
                .padding(.vertical, BetterSpacing.xLarge)
            }

            Divider()
                .overlay(BetterColors.border)

            // Tonight's check
            VStack(spacing: BetterSpacing.small) {
                HStack(spacing: BetterSpacing.medium) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tonight")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                        Text(isTakenToday ? "Protocol taken ✓" : "Did you take it tonight?")
                            .font(BetterTypography.headline)
                            .foregroundStyle(BetterColors.text)
                    }
                    Spacer()

                    if let item = viewModel.items.first {
                        Button {
                            Task { await viewModel.markTaken(item) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isTakenToday ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(isTakenToday ? "Taken" : "Mark taken")
                                    .font(BetterTypography.footnote.weight(.semibold))
                            }
                            .foregroundStyle(isTakenToday ? Color.black : BetterColors.success)
                            .padding(.horizontal, BetterSpacing.large)
                            .padding(.vertical, 10)
                            .background(isTakenToday ? BetterColors.success : BetterColors.success.opacity(0.18))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTakenToday)
                    }
                }

                HStack {
                    if viewModel.adherenceStreak > 0 {
                        Label("\(viewModel.adherenceStreak) day streak", systemImage: "flame.fill")
                            .font(BetterTypography.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Start your streak tonight")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.mutedText)
                    }
                    Spacer()
                    if let startDate = viewModel.protocolStartDate {
                        Button {
                            tempStartDate = startDate
                            showStartDatePicker = true
                        } label: {
                            Text("Change start date")
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(BetterSpacing.large)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BetterColors.cardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(BetterColors.glassStroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.36), radius: 20, y: 10)
        }
    }

    // MARK: - Timeline Strip

    private var timelineStrip: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack {
                Text("History")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                legendDot(color: BetterColors.success, label: "Taken")
                legendDot(color: BetterColors.danger.opacity(0.7), label: "Missed")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(timelineDays.enumerated()), id: \.offset) { _, date in
                            TimelineDayDot(
                                date: date,
                                status: dayStatus(for: date),
                                isToday: Calendar.current.isDateInToday(date)
                            )
                            .id(Calendar.current.isDateInToday(date) ? "today" : "")
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onAppear {
                    withAnimation {
                        proxy.scrollTo("today", anchor: .trailing)
                    }
                }
            }
        }
        .padding(BetterSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BetterColors.card)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(BetterTypography.micro)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var timelineDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let protocolStart = viewModel.protocolStartDate.map { calendar.startOfDay(for: $0) }
        let lookback = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let rangeStart = protocolStart.map { max($0, lookback) } ?? lookback

        var days: [Date] = []
        var current = rangeStart
        while current <= today {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return days
    }

    private func dayStatus(for date: Date) -> TimelineDayStatus {
        let calendar = Calendar.current
        guard let startDate = viewModel.protocolStartDate else { return .beforeProtocol }
        let protocolStart = calendar.startOfDay(for: startDate)
        let dayStart = calendar.startOfDay(for: date)

        if dayStart < protocolStart { return .beforeProtocol }

        let key = ProtocolViewModel.dateKey(for: date)
        let hasTaken = viewModel.adherenceHistory.contains { $0.dateKey == key && $0.taken }

        if calendar.isDateInToday(date) {
            return hasTaken ? .taken : .today
        }
        return hasTaken ? .taken : .missed
    }

    // MARK: - Journal Card

    private var journalCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            journalHeader
            journalFlow
        }
        .padding(BetterSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BetterColors.cardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(BetterColors.glassStroke, lineWidth: 1)
                }
        }
    }

    private var journalHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tonight's Journal")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                Text(viewModel.journalSaved ? "Autosaved" : Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(BetterTypography.caption)
                    .foregroundStyle(viewModel.journalSaved ? BetterColors.success : BetterColors.subtext)
            }
            Spacer()
            journalCompletionRing
        }
    }

    private var journalCompletionRing: some View {
        let total = 10 // 8 factors + 2 morning
        let filled = filledFactorCount
        let fraction = Double(filled) / Double(total)

        return ZStack {
            Circle()
                .stroke(BetterColors.cardSecondary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    BetterColors.brand,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: fraction)
            Text("\(filled)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(fraction > 0 ? BetterColors.brand : BetterColors.mutedText)
        }
        .frame(width: 36, height: 36)
    }

    private var filledFactorCount: Int {
        let states: [JournalTriState] = [caffeineLate, alcohol, workout, lateMeal, highStress, screenTimeLate, nap, travel]
        var count = states.filter { $0 != .unknown }.count
        if perceivedQuality != nil { count += 1 }
        if morningEnergy != nil { count += 1 }
        return count
    }

    private var journalFlow: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            journalProgressBar

            if journalStep >= journalStepCount {
                journalCompleteState
            } else if journalStep < 8 {
                journalBooleanPrompt
            } else if journalStep == 8 {
                journalQualityPrompt
            } else {
                journalEnergyPrompt
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: journalStep)
    }

    private var journalStepCount: Int { 10 }

    private var journalProgressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(journalStep >= journalStepCount ? "Complete" : "\(min(journalStep + 1, journalStepCount)) of \(journalStepCount)")
                    .font(BetterTypography.micro.weight(.semibold))
                    .foregroundStyle(BetterColors.subtext)
                Spacer()
                Text("\(filledFactorCount)/\(journalStepCount)")
                    .font(BetterTypography.micro.weight(.semibold))
                    .foregroundStyle(BetterColors.mutedText)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(BetterColors.cardSecondary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(BetterColors.brand)
                            .frame(width: proxy.size.width * min(CGFloat(filledFactorCount) / CGFloat(journalStepCount), 1))
                    }
            }
            .frame(height: 6)
        }
    }

    private var journalBooleanPrompt: some View {
        let prompt = booleanPrompt(for: journalStep)
        let state = booleanState(for: journalStep)

        return VStack(spacing: BetterSpacing.large) {
            VStack(spacing: BetterSpacing.medium) {
                ZStack {
                    Circle()
                        .fill(prompt.color.opacity(0.16))
                        .frame(width: 78, height: 78)
                    Image(systemName: prompt.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(prompt.color)
                }

                VStack(spacing: 6) {
                    Text(prompt.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)
                    Text(prompt.subtitle)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))

            HStack(spacing: BetterSpacing.medium) {
                journalAnswerButton(
                    title: "Yes",
                    systemImage: "checkmark",
                    color: BetterColors.success,
                    selectedForeground: Color.black,
                    isSelected: state == .yes
                ) {
                    setBooleanState(.yes, for: journalStep)
                    completeCurrentJournalStep()
                }

                journalAnswerButton(
                    title: "No",
                    systemImage: "xmark",
                    color: BetterColors.danger,
                    selectedForeground: Color.white,
                    isSelected: state == .no
                ) {
                    setBooleanState(.no, for: journalStep)
                    completeCurrentJournalStep()
                }
            }

            journalNavigationRow
        }
    }

    private var journalQualityPrompt: some View {
        VStack(spacing: BetterSpacing.large) {
            journalPromptHeader(icon: "bed.double.fill", color: BetterColors.brand, title: "How did you sleep?", subtitle: "Pick what matches this morning.")
            HStack(spacing: BetterSpacing.small) {
                ForEach(PerceivedSleepQuality.allCases) { quality in
                    journalChoiceButton(
                        emoji: quality.emoji,
                        label: quality.displayName,
                        isSelected: perceivedQuality == quality
                    ) {
                        perceivedQuality = quality
                        completeCurrentJournalStep()
                    }
                }
            }
            journalNavigationRow
        }
    }

    private var journalEnergyPrompt: some View {
        VStack(spacing: BetterSpacing.large) {
            journalPromptHeader(icon: "sunrise.fill", color: BetterColors.warning, title: "Energy now?", subtitle: "How ready do you feel today?")
            HStack(spacing: BetterSpacing.small) {
                ForEach(MorningEnergy.allCases) { energy in
                    journalChoiceButton(
                        emoji: energy.emoji,
                        label: energy.displayName,
                        isSelected: morningEnergy == energy
                    ) {
                        morningEnergy = energy
                        completeCurrentJournalStep()
                    }
                }
            }
            journalNavigationRow
        }
    }

    private var journalCompleteState: some View {
        VStack(spacing: BetterSpacing.medium) {
            ZStack {
                Circle()
                    .fill(BetterColors.success.opacity(0.16))
                    .frame(width: 82, height: 82)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(BetterColors.success)
            }
            Text("Journal complete")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.text)
            Text("Your answers are saved for tonight.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)

            Button {
                withAnimation { journalStep = 0 }
            } label: {
                Text("Review answers")
                    .font(BetterTypography.footnote.weight(.semibold))
                    .foregroundStyle(BetterColors.brand)
                    .padding(.horizontal, BetterSpacing.large)
                    .padding(.vertical, BetterSpacing.small)
                    .background(BetterColors.brand.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BetterSpacing.large)
    }

    private var journalNavigationRow: some View {
        HStack {
            Button {
                withAnimation {
                    journalStep = max(journalStep - 1, 0)
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(BetterTypography.caption.weight(.semibold))
                    .foregroundStyle(journalStep == 0 ? BetterColors.mutedText : BetterColors.subtext)
            }
            .buttonStyle(.plain)
            .disabled(journalStep == 0)

            Spacer()

            Button {
                completeCurrentJournalStep()
            } label: {
                Text("Skip")
                    .font(BetterTypography.caption.weight(.semibold))
                    .foregroundStyle(BetterColors.subtext)
            }
            .buttonStyle(.plain)
        }
    }

    private func journalPromptHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: BetterSpacing.medium) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 78, height: 78)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func journalAnswerButton(
        title: String,
        systemImage: String,
        color: Color,
        selectedForeground: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isSelected ? selectedForeground : color)
            .frame(maxWidth: .infinity)
            .frame(height: 116)
            .background(isSelected ? color : color.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(color.opacity(isSelected ? 0.0 : 0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func journalChoiceButton(emoji: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 30))
                Text(label)
                    .font(BetterTypography.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.black : BetterColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(isSelected ? BetterColors.brand : BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func completeCurrentJournalStep() {
        saveJournal()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            journalStep = min(journalStep + 1, journalStepCount)
        }
    }

    private func booleanPrompt(for index: Int) -> (icon: String, title: String, subtitle: String, color: Color) {
        switch index {
        case 0: ("cup.and.saucer.fill", "Coffee today?", "", BetterColors.warning)
        case 1: ("wineglass.fill", "Alcohol today?", "", BetterColors.danger)
        case 2: ("figure.run", "Workout today?", "", BetterColors.success)
        case 3: ("fork.knife", "Late meal?", "", BetterColors.warning)
        case 4: ("brain.head.profile", "High stress?", "", BetterColors.danger)
        case 5: ("iphone", "Screens late?", "", BetterColors.brand)
        case 6: ("zzz", "Nap today?", "", BetterColors.hrv)
        default: ("airplane", "Travel today?", "", BetterColors.subtext)
        }
    }

    private func booleanState(for index: Int) -> JournalTriState {
        switch index {
        case 0: caffeineLate
        case 1: alcohol
        case 2: workout
        case 3: lateMeal
        case 4: highStress
        case 5: screenTimeLate
        case 6: nap
        default: travel
        }
    }

    private func setBooleanState(_ state: JournalTriState, for index: Int) {
        switch index {
        case 0: caffeineLate = state
        case 1: alcohol = state
        case 2: workout = state
        case 3: lateMeal = state
        case 4: highStress = state
        case 5: screenTimeLate = state
        case 6: nap = state
        default: travel = state
        }
    }

    private var eveningFactorGrid: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Label("Evening Factors", systemImage: "moon.stars.fill")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)

            let factors: [(String, String, Binding<JournalTriState>)] = [
                ("cup.and.saucer.fill", "Caffeine", $caffeineLate),
                ("wineglass.fill",      "Alcohol",   $alcohol),
                ("figure.run",          "Workout",   $workout),
                ("fork.knife",          "Late Meal", $lateMeal),
                ("brain.head.profile",  "Stress",    $highStress),
                ("iphone",              "Screens",   $screenTimeLate),
                ("zzz",                 "Nap",       $nap),
                ("airplane",            "Travel",    $travel),
            ]

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: BetterSpacing.small) {
                ForEach(Array(factors.enumerated()), id: \.offset) { _, factor in
                    ResearchFactorTile(
                        icon: factor.0,
                        label: factor.1,
                        state: factor.2,
                        onChange: { saveJournal() }
                    )
                }
            }
        }
    }

    private var saveJournalButton: some View {
        Button {
            saveJournal()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.journalSaved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                Text(viewModel.journalSaved ? "Saved ✓" : "Save Journal")
            }
            .font(BetterTypography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.medium)
            .background(viewModel.journalSaved ? BetterColors.success : BetterColors.brand)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.journalSaved)
    }

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Label("Morning Report", systemImage: "sunrise.fill")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)

            VStack(spacing: BetterSpacing.medium) {
                VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                    Text("How rested did you feel?")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.mutedText)
                    HStack(spacing: BetterSpacing.xSmall) {
                        ForEach(PerceivedSleepQuality.allCases) { q in
                            morningPickerButton(
                                emoji: q.emoji,
                                label: q.displayName,
                                isSelected: perceivedQuality == q
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    perceivedQuality = perceivedQuality == q ? nil : q
                                }
                                saveJournal()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                    Text("Energy level")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.mutedText)
                    HStack(spacing: BetterSpacing.xSmall) {
                        ForEach(MorningEnergy.allCases) { e in
                            morningPickerButton(
                                emoji: e.emoji,
                                label: e.displayName,
                                isSelected: morningEnergy == e
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    morningEnergy = morningEnergy == e ? nil : e
                                }
                                saveJournal()
                            }
                        }
                    }
                }
            }
        }
    }

    private func morningPickerButton(
        emoji: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 22))
                Text(label)
                    .font(BetterTypography.micro)
                    .foregroundStyle(isSelected ? .white : BetterColors.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.small)
            .background(isSelected ? BetterColors.brand : BetterColors.cardSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
    }

    // MARK: - Journal helpers

    private func syncJournalFromEntry() {
        guard let entry = viewModel.todayContextEntry else { return }
        caffeineLate   = JournalTriState(entry.caffeineLate)
        alcohol        = JournalTriState(entry.alcohol)
        workout        = JournalTriState(entry.workout)
        lateMeal       = JournalTriState(entry.lateMeal)
        highStress     = JournalTriState(entry.highStress)
        screenTimeLate = JournalTriState(entry.screenTimeLate)
        nap            = JournalTriState(entry.nap)
        travel         = JournalTriState(entry.travel)
        perceivedQuality = entry.perceivedSleepQuality
        morningEnergy    = entry.morningEnergy
        journalStep = firstIncompleteJournalStep()
    }

    private func firstIncompleteJournalStep() -> Int {
        let states: [JournalTriState] = [caffeineLate, alcohol, workout, lateMeal, highStress, screenTimeLate, nap, travel]
        if let index = states.firstIndex(where: { $0 == .unknown }) {
            return index
        }
        if perceivedQuality == nil { return 8 }
        if morningEnergy == nil { return 9 }
        return journalStepCount
    }

    private func saveJournal() {
        let key = ProtocolViewModel.dateKey(for: Date())
        let now = Date()
        let entry = SleepContextEntry(
            id: viewModel.todayContextEntry?.id ?? UUID(),
            sleepDateKey: key,
            caffeineLate:   caffeineLate.boolValue,
            alcohol:        alcohol.boolValue,
            workout:        workout.boolValue,
            lateMeal:       lateMeal.boolValue,
            highStress:     highStress.boolValue,
            screenTimeLate: screenTimeLate.boolValue,
            nap:            nap.boolValue,
            travel:         travel.boolValue,
            perceivedSleepQuality: perceivedQuality,
            morningEnergy:         morningEnergy,
            createdAt: viewModel.todayContextEntry?.createdAt ?? now,
            updatedAt: now
        )
        Task { await viewModel.saveJournalEntry(entry) }
    }

    // MARK: - Disabled State

    private var disabledState: some View {
        VStack(spacing: BetterSpacing.large) {
            ZStack {
                Circle()
                    .fill(BetterColors.cardSecondary)
                    .frame(width: 76, height: 76)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(BetterColors.subtext)
            }

            VStack(spacing: BetterSpacing.small) {
                Text("Protocol tracking is off")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                Text("Toggle on to track your sleep routine and discover how it impacts your rest.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BetterSpacing.xxLarge)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BetterColors.card)
        }
    }

    // MARK: - Start Date Picker Sheet

    private var startDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: BetterSpacing.xxLarge) {
                VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                    Text("When did you start?")
                        .font(BetterTypography.title)
                        .foregroundStyle(BetterColors.text)
                    Text("Pick the date you began. Past nights will automatically be marked as taken.")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BetterSpacing.screen)

                DatePicker(
                    "Protocol Start Date",
                    selection: $tempStartDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(BetterColors.brand)
                .padding(.horizontal, BetterSpacing.screen)

                Spacer()

                Button {
                    showStartDatePicker = false
                    Task { await viewModel.setStartDate(tempStartDate) }
                } label: {
                    Text("Confirm Start Date")
                        .font(BetterTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.medium)
                        .background(BetterColors.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.bottom, BetterSpacing.large)
            }
            .padding(.top, BetterSpacing.large)
            .background(BetterColors.background.ignoresSafeArea())
            .navigationTitle("Protocol Start Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStartDatePicker = false }
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Timeline Day Status

enum TimelineDayStatus {
    case taken, missed, today, beforeProtocol
}

// MARK: - Timeline Day Dot

struct TimelineDayDot: View {
    let date: Date
    let status: TimelineDayStatus
    let isToday: Bool

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var weekday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return String(f.string(from: date).prefix(1))
    }

    private var dotColor: Color {
        switch status {
        case .taken:          BetterColors.success
        case .missed:         BetterColors.danger
        case .today:          BetterColors.brand
        case .beforeProtocol: Color.clear
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(weekday)
                .font(BetterTypography.micro)
                .foregroundStyle(isToday ? BetterColors.brand : BetterColors.mutedText)

            ZStack {
                Circle()
                    .fill(status == .beforeProtocol
                          ? BetterColors.cardSecondary.opacity(0.4)
                          : dotColor.opacity(0.18))
                    .frame(width: 30, height: 30)

                if isToday && status == .today {
                    Circle()
                        .strokeBorder(BetterColors.brand, lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                }

                switch status {
                case .taken:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BetterColors.success)
                case .missed:
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BetterColors.danger.opacity(0.7))
                case .today:
                    Circle()
                        .fill(BetterColors.brand)
                        .frame(width: 7, height: 7)
                case .beforeProtocol:
                    EmptyView()
                }
            }

            Text(dayNumber)
                .font(BetterTypography.micro)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? BetterColors.text : BetterColors.subtext)
        }
        .frame(width: 34)
    }
}

// MARK: - Journal Tri-State

enum JournalTriState: Equatable {
    case yes, no, unknown

    init(_ bool: Bool?) {
        switch bool {
        case true:  self = .yes
        case false: self = .no
        default:    self = .unknown
        }
    }

    var boolValue: Bool? {
        switch self {
        case .yes:     true
        case .no:      false
        case .unknown: nil
        }
    }

    mutating func cycle() {
        self = switch self {
        case .unknown: .yes
        case .yes:     .no
        case .no:      .unknown
        }
    }
}

// MARK: - Research Factor Tile

struct ResearchFactorTile: View {
    let icon: String
    let label: String
    @Binding var state: JournalTriState
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state == .unknown ? BetterColors.subtext : BetterColors.text)
                Text(label)
                    .font(BetterTypography.micro)
                    .foregroundStyle(state == .unknown ? BetterColors.subtext : BetterColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 4) {
                choiceButton(title: "✓ Yes", target: .yes, color: BetterColors.success)
                choiceButton(title: "✗ No", target: .no, color: BetterColors.danger)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BetterColors.cardSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: state)
    }

    private var borderColor: Color {
        switch state {
        case .yes:
            BetterColors.success.opacity(0.35)
        case .no:
            BetterColors.danger.opacity(0.35)
        case .unknown:
            Color.clear
        }
    }

    private func choiceButton(title: String, target: JournalTriState, color: Color) -> some View {
        let selected = state == target
        return Button {
            state = selected ? .unknown : target
            onChange()
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? (target == .yes ? Color.black : Color.white) : color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? color : color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Research Share Sheet

struct ResearchShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ResearchShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Protocol Toggle Style

private struct ProtocolToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? BetterColors.success : BetterColors.cardSecondary)
                    .frame(width: 52, height: 30)
                    .overlay(
                        Capsule()
                            .stroke(
                                configuration.isOn ? BetterColors.success.opacity(0.3) : BetterColors.border,
                                lineWidth: 1
                            )
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: configuration.isOn ? 11 : -11)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Protocol — Active") {
    let env = AppEnvironment.preview()
    NavigationStack {
        ProtocolTabView(
            viewModel: ProtocolViewModel(localRepository: env.localRepository, healthRepository: env.healthRepository),
            comparisonViewModel: ProtocolComparisonDashboardViewModel(localRepository: env.localRepository),
            contextViewModel: ContextFactorDashboardViewModel(localRepository: env.localRepository)
        )
    }
}
#endif
