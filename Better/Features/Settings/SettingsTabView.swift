import SwiftUI
import UIKit

struct SettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var sleepModeViewModel: SleepModeViewModel
    @Bindable var redLightFilterService: RedLightFilterService
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: ResearchExportDocument?
    @State private var showExportError = false

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
                        isRunningBiomarkerDiagnostic: viewModel.isLoadingBiomarkerDiagnostic,
                        openSettings: openAppSettings,
                        runBiomarkerDiagnostic: {
                            Task { await viewModel.runBiomarkerDiagnostic() }
                        }
                    )
                    ConnectedDevicesView(sources: viewModel.connectedSources)
                    ProfileSettingsView(profile: $viewModel.profile) {
                        Task { await viewModel.saveProfile() }
                    }
                    SleepModeScheduleView(viewModel: sleepModeViewModel)
                    RedLightFilterSettingsCard(service: redLightFilterService)
                    PrivacyControlsView(
                        service: viewModel.privacyService,
                        healthAuthState: viewModel.healthAuthorizationState,
                        onResync: { Task { await viewModel.privacyService.resyncFromAppleHealth() } }
                    )
                    ResearchExportView(
                        isResearchMode: viewModel.profile.isResearchMode,
                        isExporting: viewModel.isExporting,
                        exportURL: viewModel.exportURL,
                        insightSummary: viewModel.insightSummary
                    ) {
                        Task {
                            await viewModel.exportRecentCSV()
                            if let exportURL = viewModel.exportURL {
                                exportDocument = ResearchExportDocument(url: exportURL)
                            } else if viewModel.errorMessage != nil {
                                showExportError = true
                            }
                        }
                    }
                    about
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sleepModeViewModel.reloadSchedule()
            await viewModel.onAppear()
        }
        .refreshable { await viewModel.loadSettings() }
        .sheet(item: $exportDocument) { document in
            ResearchExportDocumentPicker(url: document.url)
                .ignoresSafeArea()
        }
        .sheet(item: $viewModel.biomarkerDiagnosticReport) { report in
            BiomarkerDiagnosticReportSheet(report: report)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(BetterTypography.subheadline.bold())
                .foregroundStyle(BetterColors.brand)
                .accessibilityLabel("Close Settings")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Settings")
                .font(BetterTypography.boardDisplay)
                .foregroundStyle(BetterColors.text)
            Text("Health sync, profile and data export")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var profileCard: some View {
        HStack(spacing: BetterSpacing.medium) {
            Text(profileInitial)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.boardTextPrimary)
                .frame(width: 56, height: 56)
                .background(BetterColors.boardBrand03)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(profileDisplayName)
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

    private var profileDisplayName: String {
        viewModel.profile.displayName?.trimmedNonEmpty ?? "Better Sleep"
    }

    private var profileInitial: String {
        let fallback = "B"
        return profileDisplayName.first.map { String($0).uppercased() } ?? fallback
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

private struct ResearchExportDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BiomarkerDiagnosticReportSheet: View {
    let report: BiomarkerDiagnosticReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()
                ScrollView {
                    Text(report.plainText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BetterColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(BetterSpacing.screen)
                }
            }
            .navigationTitle("Biomarker Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(BetterTypography.subheadline.bold())
                    .foregroundStyle(BetterColors.brand)
                }
            }
        }
    }
}

private struct ResearchExportDocumentPicker: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Settings") {
    let env = AppEnvironment.preview()
    SettingsTabView(
        viewModel: SettingsViewModel(
            localRepository: env.localRepository,
            healthRepository: env.healthRepository,
            syncCoordinator: env.syncCoordinator,
            privacyService: env.privacyDataService
        ),
        sleepModeViewModel: SleepModeViewModel(
            scheduleService: env.sleepModeScheduleService,
            localRepository: env.localRepository
        ),
        redLightFilterService: env.redLightFilterService
    )
}
#endif
