import Foundation
import Observation

extension SleepModeSchedule {
    static let fallback = SleepModeSchedule()

    var startDateComponents: DateComponents {
        get { DateComponents(hour: startHour, minute: startMinute) }
        set {
            startHour = newValue.hour ?? startHour
            startMinute = newValue.minute ?? startMinute
        }
    }

    var endDateComponents: DateComponents {
        get { DateComponents(hour: endHour, minute: endMinute) }
        set {
            endHour = newValue.hour ?? endHour
            endMinute = newValue.minute ?? endMinute
        }
    }

    func startDate(on baseDate: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: startHour,
            minute: startMinute,
            second: 0,
            of: baseDate
        ) ?? baseDate
    }

    var scheduleSummary: String {
        guard isEnabled else { return "Wind down now" }
        return "Tonight at \(startTimeLabel)"
    }
}

enum SleepModeStage: String, Hashable {
    case intro
    case breathing
    case blackout
}

@MainActor
@Observable
final class SleepModeViewModel {
    private static let scheduleStorageKey = "better.sleepMode.schedule.v1"
    private static let settingsStorageKey = "better.sleepMode.settings.v1"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    @ObservationIgnored
    private let scheduleService: SleepModeScheduleService?
    @ObservationIgnored
    private let localRepository: LocalDataRepositoryProtocol?

    private(set) var schedule: SleepModeSchedule
    private(set) var settings: SleepModeSettings
    private(set) var stage: SleepModeStage = .intro
    private(set) var isActive = false
    private(set) var notificationStatus: SleepModeNotificationStatus = .notScheduled(.unavailable)
    private(set) var statusMessage: String?
    private(set) var statusMessageIsError = false
    private var activeSession: SleepModeSession?

    init(
        schedule: SleepModeSchedule? = nil,
        settings: SleepModeSettings? = nil,
        scheduleService: SleepModeScheduleService? = nil,
        localRepository: LocalDataRepositoryProtocol? = nil
    ) {
        self.scheduleService = scheduleService
        self.localRepository = localRepository
        self.schedule = schedule ?? Self.loadStoredSchedule()
        self.settings = settings ?? Self.loadStoredSettings()
    }

    var entrySubtitle: String {
        if isActive {
            return "Active - hold to exit"
        }
        return schedule.scheduleSummary
    }

    func start() {
        isActive = true
        stage = .intro
        activeSession = nil
    }

    func startBreathing() {
        isActive = true
        stage = .breathing
        activeSession = SleepModeSession(startedAt: Date())
    }

    func enterBlackout() {
        if activeSession == nil {
            activeSession = SleepModeSession(startedAt: Date())
        }
        stage = .blackout
        if var session = activeSession, session.blackoutStartedAt == nil {
            session.blackoutStartedAt = Date()
            session.updatedAt = Date()
            activeSession = session
        }
    }

    func end() {
        if var session = activeSession {
            let endedAt = Date()
            session.endedAt = endedAt
            if session.blackoutStartedAt != nil, session.blackoutEndedAt == nil {
                session.blackoutEndedAt = endedAt
            }
            session.breathingRoundsCompleted = settings.breathingRounds
            session.updatedAt = endedAt
            Task { [localRepository] in
                try? await localRepository?.saveSleepModeSession(session)
            }
        }
        activeSession = nil
        isActive = false
        stage = .intro
    }

    func save(schedule updatedSchedule: SleepModeSchedule, settings updatedSettings: SleepModeSettings) async {
        var scheduleToStore = updatedSchedule
        var settingsToStore = updatedSettings
        scheduleToStore.updatedAt = Date()
        settingsToStore.updatedAt = Date()
        if let scheduleService {
            do {
                try await scheduleService.saveSchedule(scheduleToStore)
                schedule = scheduleService.schedule
            } catch {
                await refreshNotificationStatus()
                statusMessageIsError = true
                statusMessage = "Could not save Sleep Mode schedule. Check reminder permissions and try again."
                return
            }
        } else if let data = try? Self.encoder.encode(scheduleToStore) {
            UserDefaults.standard.set(data, forKey: Self.scheduleStorageKey)
            schedule = scheduleToStore
        }
        if let localRepository {
            do {
                try await localRepository.saveSleepModeSettings(settingsToStore)
            } catch {
                statusMessageIsError = true
                statusMessage = "Schedule saved, but Sleep Mode settings could not be saved."
                await refreshNotificationStatus()
                return
            }
        }
        if let data = try? Self.encoder.encode(scheduleToStore) {
            UserDefaults.standard.set(data, forKey: Self.scheduleStorageKey)
        }
        if let data = try? Self.encoder.encode(settingsToStore) {
            UserDefaults.standard.set(data, forKey: Self.settingsStorageKey)
        }
        settings = settingsToStore
        scheduleService?.evaluateForegroundActivation()
        await refreshNotificationStatus()
        statusMessageIsError = false
        statusMessage = "Sleep Mode schedule saved."
    }

    func reloadSchedule() async {
        if let scheduleService {
            await scheduleService.loadSchedule()
            schedule = scheduleService.schedule
        } else {
            schedule = Self.loadStoredSchedule()
        }

        if let storedSettings = try? await localRepository?.fetchSleepModeSettings() {
            settings = storedSettings
        } else {
            settings = Self.loadStoredSettings()
        }
        await refreshNotificationStatus()
    }

    func refreshNotificationStatus() async {
        guard let scheduleService else {
            notificationStatus = .notScheduled(.unavailable)
            return
        }
        notificationStatus = await scheduleService.notificationStatus()
    }

    #if DEBUG
    func sendTestReminder() async {
        guard let scheduleService else {
            notificationStatus = .notScheduled(.unavailable)
            return
        }
        notificationStatus = await scheduleService.scheduleTestReminder()
        statusMessageIsError = false
        statusMessage = "Test reminder scheduled for 10 seconds from now."
    }
    #endif

    private static func loadStoredSchedule() -> SleepModeSchedule {
        guard
            let data = UserDefaults.standard.data(forKey: scheduleStorageKey),
            let decoded = try? decoder.decode(SleepModeSchedule.self, from: data)
        else {
            return .fallback
        }
        return decoded
    }

    private static func loadStoredSettings() -> SleepModeSettings {
        guard
            let data = UserDefaults.standard.data(forKey: settingsStorageKey),
            let decoded = try? decoder.decode(SleepModeSettings.self, from: data)
        else {
            return SleepModeSettings()
        }
        return decoded
    }
}
