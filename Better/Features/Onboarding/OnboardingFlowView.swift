import SwiftUI

struct OnboardingFlowView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onCompleted: () -> Void
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader

                currentStep
                    .padding(.horizontal, BetterSpacing.screen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, BetterSpacing.screen)
                    .padding(.bottom, BetterSpacing.large)
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:
            WelcomeStepView()
        case .health:
            HealthPermissionStepView(
                authorizationState: viewModel.syncCoordinatorAuthorizationState,
                isWorking: viewModel.syncCoordinatorIsBusy,
                onConnect: {
                    Task { await viewModel.connectHealth() }
                }
            )
        case .sleepGoal:
            SleepGoalStepView(sleepGoalHours: $viewModel.profile.sleepGoalHours)
        case .assessment:
            SleepQuestionnaireStepView(answersByQuestionID: $viewModel.answersByQuestionID)
        case .notifications:
            NotificationPermissionStepView(
                isRequested: viewModel.notificationPermissionRequested,
                isGranted: viewModel.notificationPermissionGranted,
                onRequest: {
                    Task { await viewModel.requestNotifications() }
                }
            )
        case .research:
            ResearchModeStepView(isResearchMode: $viewModel.profile.isResearchMode)
        }
    }

    private var progressHeader: some View {
        VStack(spacing: BetterSpacing.small) {
            HStack {
                Button {
                    step = step.previous ?? step
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(step.previous == nil ? BetterColors.subtext.opacity(0.35) : BetterColors.text)
                        .frame(width: 36, height: 36)
                        .background(BetterColors.card, in: Circle())
                }
                .disabled(step.previous == nil)
                .buttonStyle(.plain)

                Spacer()

                Text("Step \(step.index + 1) of \(OnboardingStep.allCases.count)")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            ProgressView(value: Double(step.index + 1), total: Double(OnboardingStep.allCases.count))
                .tint(BetterColors.brand)
        }
        .padding(.horizontal, BetterSpacing.screen)
        .padding(.top, BetterSpacing.large)
        .padding(.bottom, BetterSpacing.medium)
    }

    private var footer: some View {
        VStack(spacing: BetterSpacing.medium) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: BetterSpacing.medium) {
                if step.canSkip {
                    Button("Skip") {
                        goForward()
                    }
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.subtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
                }

                Button(action: primaryAction) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(step.primaryTitle)
                    }
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(primaryDisabled ? BetterColors.cardTertiary : BetterColors.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(primaryDisabled)
                .buttonStyle(.plain)
            }
        }
    }

    private var primaryDisabled: Bool {
        viewModel.isLoading || (step == .assessment && viewModel.answersByQuestionID.count < SleepAssessmentQuestion.allQuestions.count)
    }

    private func primaryAction() {
        if step == .research {
            Task {
                let completed = await viewModel.completeOnboarding()
                if completed {
                    onCompleted()
                }
            }
        } else {
            goForward()
        }
    }

    private func goForward() {
        if let next = step.next {
            step = next
        }
    }
}

private extension OnboardingViewModel {
    var syncCoordinatorAuthorizationState: HealthAuthorizationPresentationState {
        syncCoordinator.authorizationState
    }

    var syncCoordinatorIsBusy: Bool {
        switch syncCoordinator.phase {
        case .authorizing, .syncing:
            true
        case .idle, .observing, .failed:
            false
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

    var index: Int { rawValue }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var canSkip: Bool {
        switch self {
        case .health, .notifications:
            true
        case .welcome, .sleepGoal, .assessment, .research:
            false
        }
    }

    var primaryTitle: String {
        switch self {
        case .welcome:
            "Get Started"
        case .health, .sleepGoal, .assessment, .notifications:
            "Continue"
        case .research:
            "Finish"
        }
    }
}

struct OnboardingStepHeader: View {
    let icon: String
    let title: String
    let description: String

    init(icon: String, title: String, body: String) {
        self.icon = icon
        self.title = title
        self.description = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 52, height: 52)
                .background(BetterColors.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text(title)
                    .font(BetterTypography.display)
                    .foregroundStyle(BetterColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(BetterTypography.body)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, BetterSpacing.large)
    }
}

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

#Preview("Onboarding") {
    OnboardingFlowView(
        viewModel: OnboardingViewModel(
            localRepository: PreviewSleepData.makeMockRepository(),
            syncCoordinator: AppEnvironment.preview().syncCoordinator
        ),
        onCompleted: {}
    )
}
