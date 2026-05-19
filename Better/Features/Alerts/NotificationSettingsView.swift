import SwiftUI

struct NotificationSettingsView: View {
    @Binding var dailyReminderSettings: DailyReminderSettings
    @Binding var smartAlertSettings: SmartAlertSettings

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            sectionTitle("Daily Reminders")
            toggleRow(
                title: "Bedtime Reminder",
                subtitle: reminderTime,
                systemImage: "bell.fill",
                color: BetterColors.brand,
                isOn: $dailyReminderSettings.isEnabled
            )
            sectionTitle("Smart Alerts")
            toggleRow(
                title: "Analysis Ready",
                subtitle: "Get notified when a night has been processed.",
                systemImage: "checkmark.circle.fill",
                color: BetterColors.brand,
                isOn: $smartAlertSettings.analysisReadyEnabled
            )
            Divider().overlay(BetterColors.border)
            toggleRow(title: "Low Sleep Score", subtitle: "Below 70", systemImage: "chart.line.downtrend.xyaxis", color: BetterColors.danger, isOn: $smartAlertSettings.lowScoreEnabled)
            toggleRow(title: "Low Deep Sleep", subtitle: "Below personal baseline", systemImage: "moon.fill", color: BetterColors.stageDeep, isOn: $smartAlertSettings.lowDeepSleepEnabled)
            toggleRow(title: "Low REM", subtitle: "Below personal baseline", systemImage: "brain.head.profile", color: BetterColors.stageREM, isOn: $smartAlertSettings.lowRemSleepEnabled)
            toggleRow(title: "Missed Protocol", subtitle: "Notify me when protocol logging is missed.", systemImage: "pills.fill", color: BetterColors.warning, isOn: $smartAlertSettings.missedProtocolEnabled)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reminderTime: String {
        String(format: "%02d:%02d", dailyReminderSettings.hour, dailyReminderSettings.minute)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
                Text(subtitle).font(BetterTypography.caption).foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(BetterColors.brand)
        }
    }
}
