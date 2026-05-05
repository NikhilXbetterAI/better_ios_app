import SwiftUI

struct ActivityTabView: View {
    @Bindable var viewModel: ActivityViewModel
    var onOpenAlerts: () -> Void = {}
    @State private var isStatusEditorPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    weekSelector
                    statusCard
                    todayActivityCard
                    travelLogCard
                    profileShortcuts
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xxLarge)
                .padding(.bottom, 110)
            }

            FloatingActionButton(systemImageName: "plus") {
                isStatusEditorPresented = true
            }
            .padding(.trailing, BetterSpacing.screen)
            .padding(.bottom, BetterSpacing.xxLarge)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $isStatusEditorPresented) {
            ActivityStatusEditorSheet(
                currentLog: viewModel.selectedStatusLog,
                onSave: { status, note in
                    Task {
                        await viewModel.saveStatus(status, note: note)
                        isStatusEditorPresented = false
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity")
                    .font(BetterTypography.largeTitle)
                    .foregroundStyle(BetterColors.text)
                Text("Manual context for better sleep insights")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Button {
                isStatusEditorPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BetterColors.text)
                    .frame(width: 42, height: 42)
                    .background(BetterColors.cardSecondary, in: Circle())
                    .overlay(Circle().stroke(BetterColors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var weekSelector: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                BetterSectionHeader(title: "This Week", trailing: selectedDateLabel)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(daysInSelectedWeek, id: \.self) { date in
                        dayButton(for: date)
                    }
                }
                if let summary = selectedSummary {
                    HStack {
                        Text("\(duration(summary.totalSleepTime)) asleep")
                        Spacer()
                        Text(summary.score.map { "Score \(Int($0))" } ?? "No score")
                            .foregroundStyle(scoreColor(summary.score))
                    }
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                }
            }
        }
    }

    private func dayButton(for date: Date) -> some View {
        let key = SleepDateKey.calendarDateKey(for: date)
        let isSelected = key == viewModel.selectedDateKey
        let summary = viewModel.weekSummaries.first { $0.sleepDateKey == key }
        let height = max(18, CGFloat((summary?.totalSleepTime ?? 4 * 3_600) / (9 * 3_600)) * 62)

        return Button {
            Task { await viewModel.selectDate(date) }
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? BetterColors.brand : scoreColor(summary?.score).opacity(summary == nil ? 0.22 : 0.85))
                    .frame(height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isSelected ? BetterColors.text.opacity(0.7) : .clear, lineWidth: 1)
                    )
                Text(weekday(date))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? BetterColors.brand : BetterColors.subtext)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92, alignment: .bottom)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(weekday(date))")
    }

    private var statusCard: some View {
        let status = viewModel.selectedStatusLog?.status
        return BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                HStack {
                    Text("Activity Status")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .textCase(.uppercase)
                    Spacer()
                    Text(selectedDateLabel)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.mutedText)
                }

                Button {
                    isStatusEditorPresented = true
                } label: {
                    HStack(spacing: BetterSpacing.medium) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill((status?.accentColor ?? BetterColors.brand).opacity(0.20))
                            Image(systemName: status?.systemImageName ?? "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(status?.accentColor ?? BetterColors.brand)
                        }
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(status?.title ?? "Add status")
                                .font(BetterTypography.headline)
                                .foregroundStyle(BetterColors.text)
                            Text(status?.subtitle ?? "Log active, travel, illness, jet lag, or injury")
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.subtext)
                                .lineLimit(2)
                        }

                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BetterColors.subtext)
                    }
                    .padding(BetterSpacing.medium)
                    .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                insightBanner(status: status)
            }
        }
    }

    private func insightBanner(status: UserActivityStatus?) -> some View {
        Text(status?.insight ?? "No status logged yet. Manual context makes trends easier to interpret when routine changes.")
            .font(BetterTypography.footnote)
            .foregroundStyle(status?.accentColor ?? BetterColors.subtext)
            .fixedSize(horizontal: false, vertical: true)
            .padding(BetterSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((status?.accentColor ?? BetterColors.brand).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke((status?.accentColor ?? BetterColors.brand).opacity(0.18), lineWidth: 1)
            )
    }

    private var todayActivityCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.large) {
                BetterSectionHeader(title: "Today's Activity", subtitle: "Apple Watch when available")
                HStack(spacing: BetterSpacing.medium) {
                    ActivityRingView(title: "Move", value: kcalText, progress: progress(viewModel.activitySummary.activeEnergy, goal: 600), color: BetterColors.heartRate)
                    ActivityRingView(title: "Exercise", value: minutesText, progress: progress(viewModel.activitySummary.exerciseMinutes, goal: 30), color: BetterColors.success)
                    ActivityRingView(title: "Stand", value: standText, progress: progress(viewModel.activitySummary.standHours, goal: 12), color: BetterColors.activity)
                }
                LazyVGrid(columns: twoColumns, spacing: BetterSpacing.medium) {
                    activityTile("Steps", value: number(viewModel.activitySummary.steps), color: BetterColors.warning)
                    activityTile("Distance", value: distanceText, color: BetterColors.cyan)
                    activityTile("Flights", value: number(viewModel.activitySummary.flights), color: BetterColors.violet)
                    activityTile("Status days", value: "\(viewModel.recentStatusLogs.count)", color: BetterColors.brand)
                }
            }
        }
    }

    private var travelLogCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                BetterSectionHeader(title: "Context Trace", subtitle: "Manual entries for this week")
                if viewModel.recentStatusLogs.isEmpty {
                    Text("No status changes logged this week.")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                } else {
                    ForEach(viewModel.recentStatusLogs) { log in
                        HStack(spacing: BetterSpacing.medium) {
                            Image(systemName: log.status.systemImageName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(log.status.accentColor)
                                .frame(width: 28, height: 28)
                                .background(log.status.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.status.title)
                                    .font(BetterTypography.subheadline)
                                    .foregroundStyle(BetterColors.text)
                                Text(log.note ?? log.status.subtitle)
                                    .font(BetterTypography.footnote)
                                    .foregroundStyle(BetterColors.subtext)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(shortDate(log.dateKey))
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.mutedText)
                        }
                    }
                }
            }
        }
    }

    private var profileShortcuts: some View {
        BetterHealthCard {
            VStack(spacing: 0) {
                shortcut("Alerts", icon: "bell.fill", color: BetterColors.warning, action: onOpenAlerts)
                divider
                shortcut("Export Sleep Data", icon: "square.and.arrow.up.fill", color: BetterColors.activity, action: {})
            }
        }
    }

    private func shortcut(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BetterColors.subtext)
            }
            .padding(.vertical, BetterSpacing.small)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Divider().background(BetterColors.border)
    }

    private func activityTile(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(BetterTypography.headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(BetterSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var twoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: BetterSpacing.medium),
            GridItem(.flexible(), spacing: BetterSpacing.medium)
        ]
    }

    private var daysInSelectedWeek: [Date] {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: viewModel.selectedDate)
        let start = interval?.start ?? viewModel.selectedDate.addingTimeInterval(-6 * 86_400)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedSummary: SleepDaySummary? {
        viewModel.weekSummaries.first { $0.sleepDateKey == viewModel.selectedDateKey }
    }

    private var selectedDateLabel: String {
        viewModel.selectedDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var kcalText: String {
        guard let value = viewModel.activitySummary.activeEnergy else { return "--" }
        return "\(Int(value))"
    }

    private var minutesText: String {
        guard let value = viewModel.activitySummary.exerciseMinutes else { return "--" }
        return "\(Int(value))m"
    }

    private var standText: String {
        guard let value = viewModel.activitySummary.standHours else { return "--" }
        return "\(Int(value))h"
    }

    private var distanceText: String {
        guard let meters = viewModel.activitySummary.distanceMeters else { return "--" }
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return "\(Int(meters)) m"
    }

    private func progress(_ value: Double?, goal: Double) -> Double {
        guard let value else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "--" }
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func scoreColor(_ score: Double?) -> Color {
        guard let score else { return BetterColors.cardTertiary }
        if score >= 85 { return BetterColors.success }
        if score >= 72 { return BetterColors.warning }
        return BetterColors.danger
    }

    private func shortDate(_ key: String) -> String {
        guard let date = SleepDateKey.date(from: key) else { return key }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ActivityRingView: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: BetterSpacing.small) {
            ZStack {
                MetricGaugeView(progress: progress, color: color, lineWidth: 7)
                    .frame(width: 58, height: 58)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityStatusEditorSheet: View {
    let currentLog: ActivityStatusLog?
    let onSave: (UserActivityStatus, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: UserActivityStatus
    @State private var note: String

    init(currentLog: ActivityStatusLog?, onSave: @escaping (UserActivityStatus, String?) -> Void) {
        self.currentLog = currentLog
        self.onSave = onSave
        _selectedStatus = State(initialValue: currentLog?.status ?? .active)
        _note = State(initialValue: currentLog?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BetterSpacing.medium) {
                        ForEach(UserActivityStatus.allCases) { status in
                            statusButton(status)
                        }
                        TextField("Optional note", text: $note, axis: .vertical)
                            .font(BetterTypography.body)
                            .foregroundStyle(BetterColors.text)
                            .padding(BetterSpacing.large)
                            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(BetterSpacing.screen)
                }
            }
            .navigationTitle("Activity Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        onSave(selectedStatus, note)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func statusButton(_ status: UserActivityStatus) -> some View {
        Button {
            selectedStatus = status
        } label: {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: status.systemImageName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(status.accentColor)
                    .frame(width: 44, height: 44)
                    .background(status.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(BetterTypography.headline)
                        .foregroundStyle(BetterColors.text)
                    Text(status.subtitle)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                Image(systemName: selectedStatus == status ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedStatus == status ? BetterColors.brand : BetterColors.subtext)
            }
            .padding(BetterSpacing.medium)
            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selectedStatus == status ? BetterColors.brand.opacity(0.7) : BetterColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Activity") {
    ActivityTabView(
        viewModel: ActivityViewModel(
            localRepository: AppEnvironment.preview().localRepository,
            healthRepository: AppEnvironment.preview().healthRepository
        )
    )
}
