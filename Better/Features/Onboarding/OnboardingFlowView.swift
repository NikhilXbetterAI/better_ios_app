import SwiftUI

struct OnboardingFlowView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onCompleted: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var movingForward = true
    @State private var healthConnectAttempted = false
    @State private var notificationAttempted = false
    @State private var finishPulse = false

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            ZStack(alignment: .top) {
                // ── Layer 1: Per-step radial glow background ──────────────────
                stepBackground(screenHeight: screenHeight)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: step)

                // ── Layer 2: Step content with slide transition ────────────────
                currentStep
                    .id(step)
                    .transition(stepTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)

                // ── Layer 3: Chrome overlaid on top ───────────────────────────
                if step != .assessment {
                    VStack(spacing: 0) {
                        topChrome
                        Spacer()
                        bottomChrome
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Background

    private func stepBackground(screenHeight: CGFloat) -> some View {
        ZStack {
            BetterColors.background
            RadialGradient(
                colors: [step.accentColor.opacity(0.12), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: screenHeight * 0.50
            )
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:
            WelcomeStepView()
        case .health:
            HealthPermissionStepView(
                authorizationState: viewModel.syncCoordinatorAuthorizationState,
                isWorking: viewModel.syncCoordinatorIsBusy,
                onConnect: { Task { await viewModel.connectHealth() } }
            )
        case .sleepGoal:
            SleepGoalStepView(sleepGoalHours: $viewModel.profile.sleepGoalHours)
        case .assessment:
            SleepQuestionnaireStepView(
                answersByQuestionID: $viewModel.answersByQuestionID,
                onCompleted: { goForward() }
            )
        case .notifications:
            NotificationPermissionStepView(
                isRequested: viewModel.notificationPermissionRequested,
                isGranted: viewModel.notificationPermissionGranted,
                onRequest: { Task { await viewModel.requestNotifications() } }
            )
        case .research:
            ResearchModeStepView(isResearchMode: $viewModel.profile.isResearchMode)
        case .preferredName:
            PreferredNameStepView(
                displayName: $viewModel.profile.displayName,
                onSubmit: { primaryAction() }
            )
        }
    }

    // MARK: - Top chrome (dots + back button)

    private var topChrome: some View {
        HStack {
            Button {
                movingForward = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    step = step.previous ?? step
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(step.previous == nil
                        ? BetterColors.subtext.opacity(0.3)
                        : BetterColors.text)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(BetterColors.glassStroke, lineWidth: 1))
            }
            .disabled(step.previous == nil)
            .buttonStyle(.plain)

            Spacer()

            PageDotsIndicator(
                count: OnboardingStep.dotSteps.count,
                activeIndex: step.dotIndex,
                activeColor: step.accentColor
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: step)

            Spacer()

            // Invisible mirror for centering
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, BetterSpacing.screen)
        .padding(.top, BetterSpacing.large)
    }

    // MARK: - Bottom chrome (skip + CTA pill)

    private var bottomChrome: some View {
        VStack(spacing: BetterSpacing.medium) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BetterSpacing.screen)
            }

            if step.canSkip {
                Button("Skip for now") { goForward() }
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .buttonStyle(.plain)
            }

            Button(action: primaryAction) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(resolvedPrimaryTitle)
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    primaryDisabled
                        ? AnyShapeStyle(BetterColors.cardTertiary)
                        : AnyShapeStyle(BetterColors.brandGradient),
                    in: Capsule()
                )
            }
            .disabled(primaryDisabled)
            .buttonStyle(.plain)
            .padding(.horizontal, BetterSpacing.screen)
            .scaleEffect(finishPulse ? 1.04 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: finishPulse)
        }
        .padding(.bottom, BetterSpacing.xLarge)
    }

    // MARK: - Primary button title

    private var resolvedPrimaryTitle: String {
        switch step {
        case .health:
            return healthConnectAttempted ? "Continue" : "Connect Apple Health"
        case .notifications:
            return notificationAttempted ? "Continue" : "Enable Notifications"
        case .preferredName:
            return "Finish"
        default:
            return step.primaryTitle
        }
    }

    // MARK: - Primary action

    private func primaryAction() {
        switch step {
        case .health:
            if !healthConnectAttempted {
                healthConnectAttempted = true
                Task { await viewModel.connectHealth() }
            } else {
                goForward()
            }
        case .notifications:
            if !notificationAttempted {
                notificationAttempted = true
                Task { await viewModel.requestNotifications() }
            } else {
                goForward()
            }
        case .research:
            goForward()
        case .preferredName:
            finishPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { finishPulse = false }
            Task {
                let completed = await viewModel.completeOnboarding()
                if completed { onCompleted() }
            }
        default:
            goForward()
        }
    }

    private var primaryDisabled: Bool {
        viewModel.isLoading ||
        (step == .assessment && viewModel.answersByQuestionID.count < SleepAssessmentQuestion.allQuestions.count)
    }

    private func goForward() {
        guard let next = step.next else { return }
        movingForward = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            step = next
        }
    }

    // MARK: - Slide transition

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

// MARK: - OnboardingStep extensions

private extension OnboardingViewModel {
    var syncCoordinatorAuthorizationState: HealthAuthorizationPresentationState {
        syncCoordinator.authorizationState
    }

    var syncCoordinatorIsBusy: Bool {
        switch syncCoordinator.phase {
        case .authorizing, .syncing: true
        case .idle, .observing, .failed: false
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case health
    case sleepGoal
    case assessment
    case notifications
    case research
    case preferredName

    var index: Int { rawValue }

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep?     { OnboardingStep(rawValue: rawValue + 1) }

    var canSkip: Bool {
        switch self {
        case .health, .notifications: true
        default: false
        }
    }

    var primaryTitle: String {
        switch self {
        case .welcome:                          "Get Started"
        case .health, .sleepGoal, .assessment,
             .notifications:                   "Continue"
        case .research:                         "Continue"
        case .preferredName:                    "Finish"
        }
    }

    // Dot indicator — excludes .assessment (it has its own chrome)
    static let dotSteps: [OnboardingStep] = [.welcome, .health, .sleepGoal, .notifications, .research, .preferredName]

    var dotIndex: Int {
        Self.dotSteps.firstIndex(of: self) ?? 0
    }

    var accentColor: Color {
        switch self {
        case .welcome:       BetterColors.brand
        case .health:        BetterColors.heartRate
        case .sleepGoal:     BetterColors.success
        case .assessment:    BetterColors.stageDeep
        case .notifications: BetterColors.stageAwake
        case .research:      BetterColors.hrv
        case .preferredName: BetterColors.brand
        }
    }
}

// MARK: - Reusable shared components (used by step views)

struct OnboardingNoticeView: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(BetterSpacing.medium)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingFlowView(
        viewModel: OnboardingViewModel(
            localRepository: PreviewSleepData.makeMockRepository(),
            syncCoordinator: AppEnvironment.preview().syncCoordinator
        ),
        onCompleted: {}
    )
}
