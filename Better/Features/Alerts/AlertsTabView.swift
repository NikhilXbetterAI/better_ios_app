import SwiftUI

struct AlertsTabView: View {
    @Bindable var viewModel: AlertsViewModel
    @State private var selectedAlert: SleepAlert?

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    analysisBanner
                    NotificationSettingsView(
                        dailyReminderSettings: $viewModel.dailyReminderSettings,
                        smartAlertSettings: $viewModel.smartAlertSettings
                    )
                    AlertThresholdsView()
                    recentAlerts
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.loadAlerts() }
        .sheet(item: $selectedAlert) { alert in
            AlertDetailSheet(alert: alert) {
                Task { await viewModel.markRead(alert) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                Text("Alerts")
                    .font(BetterTypography.display)
                    .foregroundStyle(BetterColors.text)
                Text("Notifications and reminders")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            if viewModel.unreadCount > 0 {
                Button {
                    Task { await viewModel.markAllRead() }
                } label: {
                    Text("\(viewModel.unreadCount) new")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.text)
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, BetterSpacing.xSmall)
                        .background(BetterColors.brand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var analysisBanner: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BetterColors.success)
                .frame(width: 36, height: 36)
                .background(BetterColors.success.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis ready alerts stay in-app")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Notification permission is only requested after an explicit opt-in.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.brand.opacity(0.14))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.brand.opacity(0.3), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentAlerts: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Recent")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            if viewModel.alerts.isEmpty {
                ContentUnavailableView(
                    "No alerts yet",
                    systemImage: "bell.slash",
                    description: Text("Smart alerts will appear after sleep analysis is generated.")
                )
                .foregroundStyle(BetterColors.subtext)
                .padding(.vertical, BetterSpacing.large)
            } else {
                ForEach(viewModel.alerts) { alert in
                    Button {
                        selectedAlert = alert
                    } label: {
                        AlertRowView(alert: alert)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview("Alerts") {
    AlertsTabView(viewModel: AlertsViewModel(localRepository: AppEnvironment.preview().localRepository))
}
