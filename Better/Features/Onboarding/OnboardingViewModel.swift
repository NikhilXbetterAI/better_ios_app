import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor
@Observable
final class OnboardingViewModel {
    private let localRepository: LocalDataRepositoryProtocol
    let syncCoordinator: SyncCoordinator
    private let notificationCenter: UNUserNotificationCenter

    var profile = UserProfile()
    var answersByQuestionID: [String: SleepAssessmentAnswer] = [:]
    var notificationPermissionRequested = false
    var notificationPermissionGranted = false
    var isLoading = false
    var errorMessage: String?

    init(
        localRepository: LocalDataRepositoryProtocol,
        syncCoordinator: SyncCoordinator,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.localRepository = localRepository
        self.syncCoordinator = syncCoordinator
        self.notificationCenter = notificationCenter
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await localRepository.fetchProfile()
            answersByQuestionID = Dictionary(
                uniqueKeysWithValues: profile.sleepAssessmentAnswers.map { ($0.questionID, $0) }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func connectHealth() async {
        await syncCoordinator.requestHealthAuthorization()
        if case .failed(let message) = syncCoordinator.authorizationState {
            errorMessage = message
            return
        }
        await syncCoordinator.performInitialSync()
    }

    func requestNotifications() async {
        notificationPermissionRequested = true
        do {
            notificationPermissionGranted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding() async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            var updated = profile
            updated.normalizeForStorage()
            updated.hasCompletedOnboarding = true
            updated.sleepAssessmentAnswers = SleepAssessmentQuestion.allQuestions.compactMap { answersByQuestionID[$0.id] }
            updated.updatedAt = Date()
            try await localRepository.saveProfile(updated)
            profile = updated
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
