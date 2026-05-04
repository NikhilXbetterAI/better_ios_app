import SwiftUI
import UIKit

struct SettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    profileCard
                    HealthStatusView(
                        isAvailable: viewModel.healthAvailability,
                        lastSync: viewModel.lastSuccessfulSync,
                        openSettings: openAppSettings
                    )
                    ConnectedDevicesView(sources: viewModel.connectedSources)
                    ProfileSettingsView(profile: $viewModel.profile) {
                        Task { await viewModel.saveProfile() }
                    }
                    ResearchExportView(
                        isResearchMode: viewModel.profile.isResearchMode,
                        isExporting: viewModel.isExporting,
                        exportURL: viewModel.exportURL
                    ) {
                        Task { await viewModel.exportRecentCSV() }
                    }
                    about
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.loadSettings() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Settings")
                .font(BetterTypography.display)
                .foregroundStyle(BetterColors.text)
            Text("Health sync, profile and data export")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var profileCard: some View {
        HStack(spacing: BetterSpacing.medium) {
            Text("A")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(BetterColors.brand)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Better Sleep")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text("\(String(format: "%.1f", viewModel.profile.sleepGoalHours))h goal · \(viewModel.profile.baselineWindowDays)-day baseline")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Text(viewModel.profile.isResearchMode ? "Research" : "Standard")
                .font(BetterTypography.caption)
                .foregroundStyle(viewModel.profile.isResearchMode ? BetterColors.success : BetterColors.subtext)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var about: some View {
        Text("Better Sleep · Local-first derived sleep insights")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.medium)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("Settings") {
    let env = AppEnvironment.preview()
    SettingsTabView(viewModel: SettingsViewModel(
        localRepository: env.localRepository,
        healthRepository: env.healthRepository,
        syncCoordinator: env.syncCoordinator
    ))
}
