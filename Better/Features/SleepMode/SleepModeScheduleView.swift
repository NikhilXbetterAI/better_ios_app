import SwiftUI
import UIKit

struct SleepModeScheduleView: View {
    @Bindable var viewModel: SleepModeViewModel
    var onSaveSuccess: (() -> Void)? = nil

    @State private var draft: SleepModeSchedule
    @State private var settingsDraft: SleepModeSettings
    @State private var isSaving = false

    private let reminderOptions = [0, 10, 20, 30]
    private let weekdays = Calendar.current.shortWeekdaySymbols.enumerated().map { index, symbol in
        WeekdayOption(id: index + 1, title: symbol)
    }

    init(viewModel: SleepModeViewModel, onSaveSuccess: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSaveSuccess = onSaveSuccess
        _draft = State(initialValue: viewModel.schedule)
        _settingsDraft = State(initialValue: viewModel.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            header
            scheduleControls
            notificationStatusCard
            behaviorControls
            focusCard
            saveButton
        }
        .task {
            await viewModel.refreshNotificationStatus()
        }
    }

    private var header: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BetterColors.brandLight)
                .frame(width: 40, height: 40)
                .background(BetterColors.brand.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Sleep Mode Schedule")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                Text(draft.scheduleSummary)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                HStack(spacing: 4) {
                    Circle()
                        .fill(notificationStatusColor)
                        .frame(width: 7, height: 7)
                    Text(shortStatusText)
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            Spacer()

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .tint(BetterColors.brand)
        }
    }

    private var scheduleControls: some View {
        VStack(spacing: BetterSpacing.medium) {
            DatePicker(
                "Bedtime start",
                selection: startBinding,
                displayedComponents: .hourAndMinute
            )
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.text)

            DatePicker(
                "Wake time",
                selection: endBinding,
                displayedComponents: .hourAndMinute
            )
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.text)

            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text("Days")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                HStack(spacing: BetterSpacing.xSmall) {
                    ForEach(weekdays) { weekday in
                        Button {
                            toggleWeekday(weekday.id)
                        } label: {
                            Text(weekday.title.prefix(1))
                                .font(BetterTypography.caption)
                                .foregroundStyle(draft.activeWeekdays.contains(weekday.id) ? BetterColors.text : BetterColors.subtext)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    draft.activeWeekdays.contains(weekday.id)
                                    ? BetterColors.brand.opacity(0.34)
                                    : BetterColors.cardSecondary,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Picker("Reminder", selection: $draft.reminderLeadMinutes) {
                ForEach(reminderOptions, id: \.self) { minutes in
                    Text(reminderTitle(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            .font(BetterTypography.footnote)
            .foregroundStyle(BetterColors.text)

            Toggle("Bedtime reminder", isOn: $draft.remindersEnabled)
                .toggleStyle(.switch)
                .tint(BetterColors.brand)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var notificationStatusCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.small) {
                Image(systemName: notificationStatusIcon)
                    .foregroundStyle(notificationStatusColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminder status")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(notificationStatusText)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if viewModel.notificationStatus == .denied || viewModel.notificationStatus == .notScheduled(.permissionDenied) {
                Button {
                    openAppSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(BetterTypography.caption.bold())
                        .foregroundStyle(BetterColors.brand)
                }
                .buttonStyle(.plain)
            }

            #if DEBUG
            Button {
                Task { await viewModel.sendTestReminder() }
            } label: {
                Label("Send test reminder in 10 seconds", systemImage: "bell.badge")
                    .font(BetterTypography.caption.bold())
                    .foregroundStyle(BetterColors.brandLight)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var behaviorControls: some View {
        VStack(spacing: BetterSpacing.medium) {
            Toggle("Auto-enter if app is open", isOn: $draft.autoEnterWhenForeground)
            Toggle("Blackout after breathing", isOn: $settingsDraft.blackoutAfterBreathing)
            Toggle("Dim blackout screen", isOn: $settingsDraft.dimScreenDuringBlackout)
        }
        .toggleStyle(.switch)
        .tint(BetterColors.brand)
        .font(BetterTypography.footnote)
        .foregroundStyle(BetterColors.text)
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.small) {
                Image(systemName: "moon.circle.fill")
                    .foregroundStyle(BetterColors.brandLight)
                Text("Focus")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
            }
            Text("Use iOS Focus to silence notifications and allow important calls during your scheduled wind down.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveButton: some View {
        VStack(spacing: BetterSpacing.small) {
            Button {
                Task { await saveDraft() }
            } label: {
                HStack(spacing: BetterSpacing.small) {
                    if isSaving {
                        ProgressView()
                            .tint(BetterColors.text)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSaving ? "Saving" : "Save Sleep Mode Schedule")
                }
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BetterSpacing.medium)
                .background(BetterColors.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(BetterTypography.caption)
                    .foregroundStyle(viewModel.statusMessageIsError ? BetterColors.warning : BetterColors.success)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { draft.isEnabled },
            set: { newValue in
                draft.isEnabled = newValue
                if newValue {
                    draft.remindersEnabled = true
                }
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.startDate() },
            set: { draft.startDateComponents = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: draft.endHour, minute: draft.endMinute, second: 0, of: Date()) ?? Date() },
            set: { draft.endDateComponents = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }

    private var shortStatusText: String {
        switch viewModel.notificationStatus {
        case .scheduled(let count, _):
            return "\(count) reminder\(count == 1 ? "" : "s") scheduled"
        case .authorized:
            return "Notifications allowed"
        case .notDetermined:
            return "Permission not requested"
        case .denied:
            return "Notifications off"
        case .notScheduled(let reason):
            switch reason {
            case .scheduleDisabled: return "Schedule disabled"
            case .remindersDisabled: return "Reminders off"
            case .permissionDenied: return "Notifications blocked"
            case .permissionNotDetermined: return "Permission not requested"
            case .noActiveDays: return "No active days"
            case .unavailable: return "Not scheduled"
            }
        }
    }

    private var notificationStatusIcon: String {
        switch viewModel.notificationStatus {
        case .scheduled:
            return "bell.badge.fill"
        case .authorized:
            return "bell.fill"
        case .notDetermined:
            return "bell"
        case .denied:
            return "bell.slash.fill"
        case .notScheduled:
            return "exclamationmark.triangle.fill"
        }
    }

    private var notificationStatusColor: Color {
        switch viewModel.notificationStatus {
        case .scheduled:
            return BetterColors.success
        case .authorized, .notDetermined:
            return BetterColors.brandLight
        case .denied, .notScheduled:
            return BetterColors.warning
        }
    }

    private var notificationStatusText: String {
        switch viewModel.notificationStatus {
        case .notDetermined:
            return "Save with reminders enabled to allow bedtime notifications."
        case .authorized:
            return "Notifications are allowed. Save to schedule bedtime reminders."
        case .denied:
            return "Notifications are off for Better. Turn them on in Settings to receive bedtime reminders."
        case .scheduled(let count, let nextDate):
            if let nextDate {
                return "\(count) reminder\(count == 1 ? "" : "s") scheduled. Next: \(formatted(nextDate))."
            }
            return "\(count) reminder\(count == 1 ? "" : "s") scheduled."
        case .notScheduled(let reason):
            switch reason {
            case .scheduleDisabled:
                return "Turn on the schedule and save to create bedtime reminders."
            case .remindersDisabled:
                return "Bedtime reminders are off."
            case .permissionDenied:
                return "Notifications are blocked. Open Settings to enable reminders."
            case .permissionNotDetermined:
                return "Save with reminders enabled to request notification permission."
            case .noActiveDays:
                return "Choose at least one active day."
            case .unavailable:
                return "No Sleep Mode reminders are currently scheduled."
            }
        }
    }

    private func reminderTitle(_ minutes: Int) -> String {
        minutes == 0 ? "At bedtime" : "\(minutes) min before"
    }

    private func saveDraft() async {
        isSaving = true
        await viewModel.save(schedule: draft, settings: settingsDraft)
        isSaving = false
        if !viewModel.statusMessageIsError {
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                onSaveSuccess?()
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func toggleWeekday(_ weekday: Int) {
        if draft.activeWeekdays.contains(weekday) {
            draft.activeWeekdays.remove(weekday)
        } else {
            draft.activeWeekdays.insert(weekday)
        }
        if draft.activeWeekdays.isEmpty {
            draft.activeWeekdays.insert(weekday)
        }
    }
}

private struct WeekdayOption: Identifiable, Hashable {
    let id: Int
    let title: String
}

#if DEBUG
#Preview {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        ScrollView {
            SleepModeScheduleView(viewModel: SleepModeViewModel())
                .padding()
        }
    }
}
#endif
