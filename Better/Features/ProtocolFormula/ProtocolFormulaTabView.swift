import SwiftUI

/// Shell view for Protocol Formula Tracking. Routes to onboarding (if no versions exist),
/// then renders Home with navigation to Formula Setup, Edit Log, Timeline, All Metrics,
/// and Version Dive screens.
struct ProtocolFormulaTabView: View {
    let localRepository: LocalDataRepositoryProtocol

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

    init(localRepository: LocalDataRepositoryProtocol, userDefaults: UserDefaults = .standard) {
        self.localRepository = localRepository
        self.userDefaults = userDefaults
        _homeViewModel = State(initialValue: ProtocolFormulaHomeViewModel(localRepository: localRepository))
        _setupViewModel = State(initialValue: ProtocolFormulaSetupViewModel(localRepository: localRepository))
        _editLogViewModel = State(initialValue: ProtocolEditLogViewModel(localRepository: localRepository))
        _onboardingViewModel = State(initialValue: ProtocolOnboardingViewModel(localRepository: localRepository))
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
                        onOpenFormulaSetup: { route = .formulaSetup },
                        onOpenEditLog: { route = .editLog },
                        onOpenTimeline: { route = .timeline },
                        onOpenAllMetrics: { route = .allMetrics },
                        onOpenVersionDive: { route = .versionDive }
                    )
                    .navigationTitle("Protocol")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Protocol versions") { route = .formulaSetup }
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
                                .navigationTitle("Protocol versions")
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
            showOnboarding = !userDefaults.bool(forKey: ProtocolFormulaHistoryOnboardingStorage.completedKey)
        }
    }
}
