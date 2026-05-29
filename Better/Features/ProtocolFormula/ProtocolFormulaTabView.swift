import SwiftUI

/// Shell view for Protocol Formula Tracking. Routes to onboarding (if no versions exist),
/// then renders Home with navigation to Formula Setup, Edit Log, Timeline, All Metrics,
/// and Version Dive screens.
struct ProtocolFormulaTabView: View {
    let localRepository: LocalDataRepositoryProtocol
    let historicalRefresh: (() async -> Void)?

    @State private var homeViewModel: ProtocolFormulaHomeViewModel
    @State private var setupViewModel: ProtocolFormulaSetupViewModel
    @State private var editLogViewModel: ProtocolEditLogViewModel
    @State private var onboardingViewModel: ProtocolOnboardingViewModel
    @State private var timelineViewModel: ProtocolTimelineViewModel
    @State private var allMetricsViewModel: ProtocolAllMetricsViewModel
    @State private var versionDiveViewModel: ProtocolVersionDiveViewModel

    @State private var route: Route?
    @State private var showOnboarding = false
    @State private var didCheckOnboarding = false
    private let userDefaults: UserDefaults

    enum Route: Hashable {
        case formulaSetup
        case editLog
        case timeline
        case allMetrics
        case versionDive
    }

    init(
        localRepository: LocalDataRepositoryProtocol,
        userDefaults: UserDefaults = .standard,
        historicalRefresh: (() async -> Void)? = nil
    ) {
        self.localRepository = localRepository
        self.historicalRefresh = historicalRefresh
        self.userDefaults = userDefaults
        _homeViewModel = State(initialValue: ProtocolFormulaHomeViewModel(
            localRepository: localRepository,
            historicalRefresh: historicalRefresh
        ))
        _setupViewModel = State(initialValue: ProtocolFormulaSetupViewModel(localRepository: localRepository))
        _editLogViewModel = State(initialValue: ProtocolEditLogViewModel(localRepository: localRepository))
        _onboardingViewModel = State(initialValue: ProtocolOnboardingViewModel(
            localRepository: localRepository,
            historicalRefresh: historicalRefresh
        ))
        _timelineViewModel = State(initialValue: ProtocolTimelineViewModel(repository: localRepository))
        _allMetricsViewModel = State(initialValue: ProtocolAllMetricsViewModel(repository: localRepository))
        _versionDiveViewModel = State(initialValue: ProtocolVersionDiveViewModel(repository: localRepository))
    }

    var body: some View {
        Group {
            if showOnboarding {
                ProtocolOnboardingView(viewModel: onboardingViewModel) {
                    userDefaults.set(true, forKey: ProtocolFormulaHistoryOnboardingStorage.completedKey)
                    showOnboarding = false
                    Task { await homeViewModel.refresh() }
                }
            } else {
                NavigationStack {
                    ProtocolFormulaHomeView(
                        viewModel: homeViewModel,
                        onOpenFormulaSetup: {
                            if homeViewModel.versions.isEmpty {
                                showOnboarding = true
                            } else {
                                route = .formulaSetup
                            }
                        },
                        onOpenEditLog: { route = .editLog },
                        onOpenTimeline: { route = .timeline },
                        onOpenAllMetrics: { route = .allMetrics },
                        onOpenVersionDive: { route = .versionDive }
                    )
                    .navigationTitle("Formula")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Formula versions") { route = .formulaSetup }
                                Button("Edit log") { route = .editLog }
                                Divider()
                                Button("Timeline") { route = .timeline }
                                Button("All metrics") { route = .allMetrics }
                                Button("Version dive") { route = .versionDive }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                    .navigationDestination(item: $route) { dest in
                        switch dest {
                        case .formulaSetup:
                            ProtocolFormulaSetupView(viewModel: setupViewModel)
                                .navigationTitle("Formula versions")
                        case .editLog:
                            ProtocolEditLogView(viewModel: editLogViewModel)
                                .navigationTitle("Edit log")
                        case .timeline:
                            ProtocolTimelineView(viewModel: timelineViewModel)
                                .navigationTitle("Timeline")
                        case .allMetrics:
                            ProtocolAllMetricsView(viewModel: allMetricsViewModel)
                                .navigationTitle("All metrics")
                        case .versionDive:
                            ProtocolVersionDiveView(viewModel: versionDiveViewModel)
                                .navigationTitle("Version dive")
                        }
                    }
                }
            }
        }
        .task {
            guard !didCheckOnboarding else { return }
            didCheckOnboarding = true
            showOnboarding = await ProtocolFormulaOnboardingGate.shouldShowOnboarding(
                userDefaults: userDefaults,
                repository: localRepository
            )
        }
    }
}

@MainActor
enum ProtocolFormulaOnboardingGate {
    static func shouldShowOnboarding(
        userDefaults: UserDefaults,
        repository: LocalDataRepositoryProtocol
    ) async -> Bool {
        let completedKey = ProtocolFormulaHistoryOnboardingStorage.completedKey
        guard userDefaults.bool(forKey: completedKey) == false else {
            return false
        }

        do {
            let inventory = try await repository.fetchDataInventory()
            if inventory.protocolFormulaVersionCount > 0 || inventory.protocolNightLogCount > 0 {
                userDefaults.set(true, forKey: completedKey)
                return false
            }
            return true
        } catch {
            // Inventory read failed. Show onboarding only when we can confirm no versions exist;
            // if the version fetch also fails, default to showing onboarding (new install).
            if let versions = try? await repository.fetchAllFormulaVersions() {
                if versions.isEmpty {
                    return true
                } else {
                    userDefaults.set(true, forKey: completedKey)
                    return false
                }
            }
            return true
        }
    }
}
