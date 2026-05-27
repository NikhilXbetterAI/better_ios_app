import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selectedTab: AppTab = .sleep
    @State private var sleepViewModel: SleepDashboardViewModel
    @State private var trendsViewModel: TrendsViewModel
    @State private var alertsViewModel: AlertsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var biologyViewModel: BiologyViewModel
    @State private var activityViewModel: ActivityViewModel
    @State private var onboardingViewModel: OnboardingViewModel
    @State private var sleepModeCoordinator: SleepModeCoordinator
    @State private var sleepModeViewModel: SleepModeViewModel
    @State private var hasLoadedProfile = false
    @State private var hasCompletedOnboarding = false
    @State private var secondarySheet: SecondarySheet?

    init(environment: AppEnvironment) {
        self.environment = environment
        _sleepViewModel = State(initialValue: SleepDashboardViewModel(
            syncCoordinator: environment.syncCoordinator,
            localRepository: environment.localRepository,
            biomarkerBaselineService: environment.biomarkerBaselineService
        ))
        _trendsViewModel = State(initialValue: TrendsViewModel(
            localRepository: environment.localRepository
        ))
        _alertsViewModel = State(initialValue: AlertsViewModel(
            localRepository: environment.localRepository
        ))
        _settingsViewModel = State(initialValue: SettingsViewModel(
            localRepository: environment.localRepository,
            healthRepository: environment.healthRepository,
            syncCoordinator: environment.syncCoordinator,
            privacyService: environment.privacyDataService
        ))
        _biologyViewModel = State(initialValue: BiologyViewModel(
            localRepository: environment.localRepository,
            healthRepository: environment.healthRepository
        ))
        _activityViewModel = State(initialValue: ActivityViewModel(
            localRepository: environment.localRepository,
            healthRepository: environment.healthRepository
        ))
        _onboardingViewModel = State(initialValue: OnboardingViewModel(
            localRepository: environment.localRepository,
            syncCoordinator: environment.syncCoordinator
        ))
        _sleepModeCoordinator = State(initialValue: environment.sleepModeCoordinator)
        _sleepModeViewModel = State(initialValue: SleepModeViewModel(
            scheduleService: environment.sleepModeScheduleService,
            localRepository: environment.localRepository
        ))
    }

    var body: some View {
        Group {
            if hasLoadedProfile && !hasCompletedOnboarding {
                OnboardingFlowView(viewModel: onboardingViewModel) {
                    hasCompletedOnboarding = true
                    Task {
                        await settingsViewModel.loadSettings()
                    }
                }
            } else {
                tabs
            }
        }
        .task {
            await loadOnboardingState()
            await environment.runProtocolFormulaMigrationIfNeeded()
        }
        .onChange(of: settingsViewModel.privacyService.deleteCompleted) { _, completed in
            guard completed else { return }
            hasLoadedProfile = false
            hasCompletedOnboarding = false
            Task { await loadOnboardingState() }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // ── Sleep ────────────────────────────────────────────────────
            NavigationStack {
                SleepTabView(
                    viewModel: sleepViewModel,
                    sleepModeViewModel: sleepModeViewModel,
                    redLightFilterService: environment.redLightFilterService,
                    onOpenProfile: { secondarySheet = .settings }
                )
            }
            .tabItem { Label(AppTab.sleep.title, systemImage: AppTab.sleep.systemImageName) }
            .tag(AppTab.sleep)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // ── Insights / Trends ────────────────────────────────────────
            NavigationStack {
                TrendsTabView(viewModel: trendsViewModel)
            }
            .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.systemImageName) }
            .tag(AppTab.insights)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // ── Protocol ─────────────────────────────────────────────────
            // Protocol Formula Tracking is the only Protocol surface. The legacy
            // `ProtocolTabView` + feature-flag gate has been retired; deletion of
            // the legacy view models and supporting services is a follow-up cleanup.
            ProtocolFormulaTabView(
                localRepository: environment.localRepository,
                historicalRefresh: { await environment.syncCoordinator.performInitialSync() }
            )
                .tabItem { Label(AppTab.protocol.title, systemImage: AppTab.protocol.systemImageName) }
                .tag(AppTab.protocol)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)

            // ── Biology ─────────────────────────────────────────────────
            NavigationStack {
                BiologyTabView(viewModel: biologyViewModel)
            }
            .tabItem { Label(AppTab.biology.title, systemImage: AppTab.biology.systemImageName) }
            .tag(AppTab.biology)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // ── Activity ────────────────────────────────────────────────
            NavigationStack {
                ActivityTabView(
                    viewModel: activityViewModel,
                    onOpenAlerts: { secondarySheet = .alerts }
                )
            }
            .tabItem { Label(AppTab.activity.title, systemImage: AppTab.activity.systemImageName) }
            .tag(AppTab.activity)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        .tint(BetterColors.brand)
        .onChange(of: sleepViewModel.selectedSleepDateKey) { _, newKey in
            if let date = SleepDateKey.date(from: newKey) {
                Task { await activityViewModel.selectDate(date) }
            }
        }
        .sheet(item: $secondarySheet) { sheet in
            NavigationStack {
                switch sheet {
                case .alerts:
                    AlertsTabView(viewModel: alertsViewModel)
                case .settings:
                    SettingsTabView(
                        viewModel: settingsViewModel,
                        sleepModeViewModel: sleepModeViewModel,
                        redLightFilterService: environment.redLightFilterService
                    )
                }
            }
        }
        .fullScreenCover(item: $sleepModeCoordinator.activePresentation) { _ in
            SleepModeView(viewModel: sleepModeViewModel, redLightService: environment.redLightFilterService)
                .task {
                    await sleepModeViewModel.reloadSchedule()
                }
        }
    }

    private func loadOnboardingState() async {
        guard !hasLoadedProfile else { return }

        do {
            let profile = try await environment.localRepository.fetchProfile()
            hasCompletedOnboarding = profile.hasCompletedOnboarding
            
            if hasCompletedOnboarding {
                // Fire off health auth and sync in background without blocking the splash screen dismissal
                Task {
                    await environment.syncCoordinator.requestHealthAuthorization()
                    await environment.syncCoordinator.performLaunchSync()
                }
            }
        } catch {
            hasCompletedOnboarding = false
        }

        withAnimation(.easeInOut) {
            hasLoadedProfile = true
        }
    }
}

private enum SecondarySheet: String, Identifiable {
    case alerts
    case settings

    var id: String { rawValue }
}

#if DEBUG
#Preview("Root Tabs") {
    RootTabView(environment: .preview())
}
#endif
