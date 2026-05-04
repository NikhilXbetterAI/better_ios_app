import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selectedTab: AppTab = .sleep
    @State private var sleepViewModel: SleepDashboardViewModel
    @State private var trendsViewModel: TrendsViewModel
    @State private var protocolViewModel: ProtocolViewModel
    @State private var alertsViewModel: AlertsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var onboardingViewModel: OnboardingViewModel
    @State private var hasLoadedProfile = false
    @State private var hasCompletedOnboarding = false

    init(environment: AppEnvironment) {
        self.environment = environment
        _sleepViewModel = State(initialValue: SleepDashboardViewModel(
            syncCoordinator: environment.syncCoordinator,
            localRepository: environment.localRepository
        ))
        _trendsViewModel = State(initialValue: TrendsViewModel(
            localRepository: environment.localRepository
        ))
        _protocolViewModel = State(initialValue: ProtocolViewModel(
            localRepository: environment.localRepository
        ))
        _alertsViewModel = State(initialValue: AlertsViewModel(
            localRepository: environment.localRepository
        ))
        _settingsViewModel = State(initialValue: SettingsViewModel(
            localRepository: environment.localRepository,
            healthRepository: environment.healthRepository,
            syncCoordinator: environment.syncCoordinator
        ))
        _onboardingViewModel = State(initialValue: OnboardingViewModel(
            localRepository: environment.localRepository,
            syncCoordinator: environment.syncCoordinator
        ))
    }

    var body: some View {
        Group {
            if !hasLoadedProfile {
                loadingView
            } else if hasCompletedOnboarding {
                tabs
            } else {
                OnboardingFlowView(viewModel: onboardingViewModel) {
                    hasCompletedOnboarding = true
                    Task {
                        await settingsViewModel.loadSettings()
                        await protocolViewModel.onAppear()
                    }
                }
            }
        }
        .task {
            await loadOnboardingState()
        }
    }

    private var loadingView: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()
            ProgressView()
                .tint(BetterColors.brand)
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // ── Sleep ────────────────────────────────────────────────────
            NavigationStack {
                SleepTabView(viewModel: sleepViewModel)
            }
            .tabItem { Label(AppTab.sleep.title, systemImage: AppTab.sleep.systemImageName) }
            .tag(AppTab.sleep)

            // ── Insights / Trends ────────────────────────────────────────
            NavigationStack {
                TrendsTabView(
                    viewModel: trendsViewModel,
                    protocolImpactSummary: protocolViewModel.impactSummary
                )
            }
            .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.systemImageName) }
            .tag(AppTab.insights)

            // ── Protocol ─────────────────────────────────────────────────
            NavigationStack {
                ProtocolTabView(viewModel: protocolViewModel)
            }
            .tabItem { Label(AppTab.protocol.title, systemImage: AppTab.protocol.systemImageName) }
            .tag(AppTab.protocol)

            // ── Alerts ───────────────────────────────────────────────────
            NavigationStack {
                AlertsTabView(viewModel: alertsViewModel)
            }
            .tabItem { Label(AppTab.alerts.title, systemImage: AppTab.alerts.systemImageName) }
            .tag(AppTab.alerts)

            // ── Settings ─────────────────────────────────────────────────
            NavigationStack {
                SettingsTabView(viewModel: settingsViewModel)
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImageName) }
            .tag(AppTab.settings)
        }
        .tint(BetterColors.brand)
        .task {
            await protocolViewModel.onAppear()
        }
    }

    private func loadOnboardingState() async {
        guard !hasLoadedProfile else { return }

        do {
            let profile = try await environment.localRepository.fetchProfile()
            hasCompletedOnboarding = profile.hasCompletedOnboarding
        } catch {
            hasCompletedOnboarding = false
        }
        hasLoadedProfile = true
    }
}

#Preview("Root Tabs") {
    RootTabView(environment: .preview())
}
