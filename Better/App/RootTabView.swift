import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selectedTab: AppTab = .sleep
    @State private var sleepViewModel: SleepDashboardViewModel
    @State private var trendsViewModel: TrendsViewModel
    @State private var protocolViewModel: ProtocolViewModel
    @State private var alertsViewModel: AlertsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var biologyViewModel: BiologyViewModel
    @State private var activityViewModel: ActivityViewModel
    @State private var onboardingViewModel: OnboardingViewModel
    @State private var hasLoadedProfile = false
    @State private var hasCompletedOnboarding = false
    @State private var secondarySheet: SecondarySheet?

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
                SleepTabView(
                    viewModel: sleepViewModel,
                    onOpenProfile: { secondarySheet = .settings }
                )
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

            // ── Biology ─────────────────────────────────────────────────
            NavigationStack {
                BiologyTabView(viewModel: biologyViewModel)
            }
            .tabItem { Label(AppTab.biology.title, systemImage: AppTab.biology.systemImageName) }
            .tag(AppTab.biology)

            // ── Activity ────────────────────────────────────────────────
            NavigationStack {
                ActivityTabView(
                    viewModel: activityViewModel,
                    onOpenAlerts: { secondarySheet = .alerts }
                )
            }
            .tabItem { Label(AppTab.activity.title, systemImage: AppTab.activity.systemImageName) }
            .tag(AppTab.activity)
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
                    SettingsTabView(viewModel: settingsViewModel)
                }
            }
        }
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

private enum SecondarySheet: String, Identifiable {
    case alerts
    case settings

    var id: String { rawValue }
}

#Preview("Root Tabs") {
    RootTabView(environment: .preview())
}
