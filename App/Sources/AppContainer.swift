import AssistantPresentation
import Domain
import ExercisesPresentation
import FeatureHistory
import FeaturePlan
import FeatureSettings
import FeatureToday
import FeatureWorkout
import Foundation
import GarminSource
import HealthKitSource
import HistoryPresentation
import LocalAlerts
import Observation
import OnboardingPresentation
import Persistence
import PlanPresentation
import PresentationKit
import SettingsPresentation
import TodayPresentation
import TrendsPresentation
import WorkoutPresentation

/// Composition root: the only place that knows the concrete implementations (ADR-0002).
/// Features receive `Domain` protocols from here and never construct their own dependencies.
@MainActor
@Observable
final class AppContainer {
    let workouts: any WorkoutRepository
    private let workoutDraftStore: (any WorkoutDraftStore)?
    let exercises: any ExerciseRepository
    let checkIns: any CheckInRepository
    let progression: any ProgressionSettingsRepository
    let profiles: any ProfileRepository
    let routines: any RoutineRepository
    let importer: any TrainingHistoryImporter
    let backup: any BackupService
    let restAlerts: any RestAlertScheduler
    let health: any HealthWorkoutWriter
    let onboardingStatus: any OnboardingStatusStore
    /// In priority order: when two sources report the same value, the first wins.
    let metricsSources: [any MetricsSource]
    /// Apple Health: steps for the History calendar.
    let healthSource: (any MetricsSource & ActivitySource)?
    /// Walks for Today (ADR-0010): Garmin's walking activities and Apple Health's walks, each walk once.
    let activitySources: [any ActivitySource]
    /// Apple Health: menstrual flow for phase-aware baselines (ADR-0009).
    let cycleSource: (any CycleSource)?
    /// The person's Garmin account (ADR-0022). Also in `metricsSources`.
    let garmin: (any GarminAccount)?
    private let recordedStrength: (any RecordedStrengthSource)?
    private let historyRecordedStrength: (any RecordedStrengthSource)?

    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        checkIns: any CheckInRepository,
        progression: any ProgressionSettingsRepository,
        profiles: any ProfileRepository,
        routines: any RoutineRepository,
        importer: any TrainingHistoryImporter = StrongHistoryImporter(),
        backupDestination: any BackupDestination = FolderBackupDestination(),
        workoutDraftStore: (any WorkoutDraftStore)? = nil,
        restAlerts: any RestAlertScheduler = LocalRestAlerts(),
        health: any HealthWorkoutWriter = HealthKitWorkoutWriter(),
        onboardingStatus: any OnboardingStatusStore = DefaultsOnboardingStatus(),
        metricsSources: [any MetricsSource],
        healthSource: (any MetricsSource & ActivitySource)? = nil,
        activitySources: [any ActivitySource]? = nil,
        cycleSource: (any CycleSource)? = nil,
        garmin: (any GarminAccount)? = nil,
        recordedStrength: (any RecordedStrengthSource)? = nil,
        historyRecordedStrength: (any RecordedStrengthSource)? = nil
    ) {
        self.workouts = workouts
        self.workoutDraftStore = workoutDraftStore
        self.exercises = exercises
        self.checkIns = checkIns
        self.progression = progression
        self.profiles = profiles
        self.routines = routines
        self.importer = importer
        self.restAlerts = restAlerts
        self.health = health
        self.onboardingStatus = onboardingStatus
        self.backup = RepositoryBackupService(
            workouts: workouts, exercises: exercises, checkIns: checkIns, profiles: profiles, progression: progression,
            routines: routines, destination: backupDestination, appVersion: Self.appVersion
        )
        self.metricsSources = metricsSources
        self.healthSource = healthSource
        self.activitySources = activitySources ?? healthSource.map { [$0 as any ActivitySource] } ?? []
        self.cycleSource = cycleSource
        self.garmin = garmin
        self.recordedStrength = recordedStrength
        self.historyRecordedStrength = historyRecordedStrength ?? recordedStrength
    }

    /// Production wiring: SwiftData on disk (ADR-0004). If the store cannot be opened, the app still runs on an
    /// in-memory store instead of crashing, and nothing is saved.
    static func live() -> AppContainer {
        let healthKit = HealthKitMetricsSource()
        let garmin = GarminConnect.makeService()
        let sources: [any MetricsSource] = [garmin, healthKit]
        // Garmin's strength records plus other apps' strength workouts in Apple Health (e.g. the Apple Watch), each
        // workout once.
        let strengthSources: [any RecordedStrengthSource] = [garmin, HealthKitWorkoutWriter()]
        let recordedStrength = CombinedRecordedStrengthSource(strengthSources)
        let historyRecordedStrength = CombinedRecordedStrengthSource(strengthSources, preserveOriginals: true)
        do {
            let store = SwiftDataStore.make(container: try PersistenceContainer.make())
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store, workoutDraftStore: FileWorkoutDraftStore(),
                metricsSources: sources, healthSource: healthKit, activitySources: [garmin, healthKit],
                cycleSource: healthKit, garmin: garmin,
                recordedStrength: recordedStrength, historyRecordedStrength: historyRecordedStrength
            )
        } catch {
            let store = InMemoryStore(exercises: ExerciseCatalog.builtIn)
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store,
                metricsSources: sources, healthSource: healthKit, activitySources: [garmin, healthKit],
                cycleSource: healthKit, garmin: garmin,
                recordedStrength: recordedStrength, historyRecordedStrength: historyRecordedStrength
            )
        }
    }

    private static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Removes the app's Health copy of recent sessions that a watch app (e.g. Garmin Connect) also wrote there, once
    /// it has synced (ADR-0023). Best effort; runs at launch and when the app comes back to the foreground.
    func reconcileHealthWorkouts() async {
        let end = Date()
        let start = end.addingTimeInterval(-14 * 86_400)
        guard let sessions = try? await workouts.sessions(from: start, to: end) else { return }
        await health.reconcile(sessions)
    }

    // MARK: Feature factories

    func makePlanImportModel() -> PlanImportModel {
        PlanImportModel(
            exercises: exercises, routines: routines, progression: progression, profiles: profiles, backup: backup
        )
    }

    func makeAskAIModel() -> AskAIModel {
        AskAIModel(
            workouts: workouts, exercises: exercises, progression: progression, profiles: profiles,
            routines: routines, checkIns: checkIns, sources: metricsSources,
            recordedStrength: historyRecordedStrength, activity: activitySources, cycle: cycleSource,
            activityMatchChoices: readActivityMatchChoices,
            appVersion: Self.appVersion
        )
    }

    func makeTodayModel() -> TodayModel {
        TodayModel(
            sources: metricsSources, activity: activitySources,
            checkIns: checkIns, backup: backup, garmin: garmin, profiles: profiles, workouts: workouts,
            exercises: exercises, recordedStrength: historyRecordedStrength, routines: routines,
            progression: progression, cycle: cycleSource, activityMatchChoices: readActivityMatchChoices,
            companionAnswers: dogWalkAnswers, dogRunAnswers: dogRunAnswers,
            profileQuestions: profileQuestions,
            dismissedRunOfferDay: UserDefaults.standard.data(forKey: Self.dismissedRunOfferDayKey).flatMap {
                try? JSONDecoder().decode(CalendarDay.self, from: $0)
            },
            saveDismissedRunOfferDay: { day in
                if let data = try? JSONEncoder().encode(day) {
                    UserDefaults.standard.set(data, forKey: Self.dismissedRunOfferDayKey)
                }
            },
            dismissedRotationDay: UserDefaults.standard.data(forKey: Self.dismissedRotationDayKey).flatMap {
                try? JSONDecoder().decode(CalendarDay.self, from: $0)
            },
            saveDismissedRotationDay: { day in
                if let data = try? JSONEncoder().encode(day) {
                    UserDefaults.standard.set(data, forKey: Self.dismissedRotationDayKey)
                }
            }
        )
    }

    /// Last day the run offer got "Not today" (#264). Per device, not in backups, reports or the profile.
    private static let dismissedRunOfferDayKey = "today.runOffer.dismissedDay"

    private static let dismissedRotationDayKey = "today.rotation.dismissedDay"

    private static let profileQuestionsKey = "today.profileQuestions"

    /// Which profile questions Today already asked or put off (ADR-0041). Per device, not in backups.
    private let profileQuestions: ProfileQuestionLog = {
        let state = UserDefaults.standard.data(forKey: AppContainer.profileQuestionsKey).flatMap {
            try? JSONDecoder().decode(ProfileQuestionLog.State.self, from: $0)
        } ?? ProfileQuestionLog.State()
        return ProfileQuestionLog(state) { state in
            if let data = try? JSONEncoder().encode(state) {
                UserDefaults.standard.set(data, forKey: AppContainer.profileQuestionsKey)
            }
        }
    }()

    private static let dogWalkAnswersKey = "today.dogWalkAnswers"

    private let dogWalkAnswers: DogWalkAnswers = {
        let answers = UserDefaults.standard.data(forKey: AppContainer.dogWalkAnswersKey).flatMap {
            try? JSONDecoder().decode([WalkCompanionAnswer].self, from: $0)
        } ?? []
        return DogWalkAnswers(answers) { answers in
            if let data = try? JSONEncoder().encode(answers) {
                UserDefaults.standard.set(data, forKey: AppContainer.dogWalkAnswersKey)
            }
        }
    }()

    private static let dogRunAnswersKey = "history.dogRunAnswers"

    private let dogRunAnswers: DogRunAnswers = {
        let answers = UserDefaults.standard.data(forKey: AppContainer.dogRunAnswersKey).flatMap {
            try? JSONDecoder().decode([DogRunAnswers.Key: Bool].self, from: $0)
        } ?? [:]
        return DogRunAnswers(answers) { answers in
            if let data = try? JSONEncoder().encode(answers) {
                UserDefaults.standard.set(data, forKey: AppContainer.dogRunAnswersKey)
            }
        }
    }()

    func makeRecoveryProgressModel() -> RecoveryProgressModel {
        RecoveryProgressModel(
            sources: metricsSources, activity: activitySources, checkIns: checkIns, garmin: garmin,
            profiles: profiles, workouts: workouts, exercises: exercises, recordedStrength: recordedStrength,
            routines: routines, progression: progression, cycle: cycleSource
        )
    }

    func makeWorkoutModel() -> WorkoutModel {
        WorkoutModel(
            workouts: workouts, exercises: exercises, progression: progression, backup: backup, health: health,
            restAlerts: restAlerts, profiles: profiles, draftStore: workoutDraftStore
        )
    }

    func makeRoutinesModel() -> RoutinesModel {
        // The plan follow-up reads the same recovery assessment as Today (ADR-0035).
        let readiness = DailyReadinessProvider.make(
            sources: metricsSources, activity: activitySources, checkIns: checkIns, workouts: workouts,
            exercises: exercises, recordedStrength: historyRecordedStrength, routines: routines,
            progression: progression, cycle: cycleSource
        )
        return RoutinesModel(
            routines: routines, exercises: exercises, backup: backup, profiles: profiles, workouts: workouts,
            checkIns: checkIns, readiness: readiness
        )
    }

    private static let runChoicesKey = "history.runMatchChoices"
    private static let strengthChoicesKey = "history.strengthMatchChoices"

    private func readActivityMatchChoices() -> ActivityMatchChoices {
        let defaults = UserDefaults.standard
        let choices = defaults.data(forKey: Self.runChoicesKey).flatMap {
            try? JSONDecoder().decode([RunMatchPair: RunMatchChoice].self, from: $0)
        } ?? [:]
        let strengthChoices = defaults.data(forKey: Self.strengthChoicesKey).flatMap {
            try? JSONDecoder().decode([StrengthMatchPair: StrengthMatchChoice].self, from: $0)
        } ?? [:]
        return ActivityMatchChoices(runs: choices, strength: strengthChoices)
    }

    func makeHistoryModel() -> HistoryModel {
        let choices = readActivityMatchChoices()
        let defaults = UserDefaults.standard
        return HistoryModel(
            workouts: workouts, exercises: exercises, routines: routines, backup: backup, health: health,
            profiles: profiles, progression: progression, activity: healthSource, runSources: metricsSources,
            recordedStrength: historyRecordedStrength, walkSources: activitySources, companionAnswers: dogWalkAnswers,
            dogRunAnswers: dogRunAnswers,
            runChoices: choices.runs,
            saveRunChoices: { choices in
                if let data = try? JSONEncoder().encode(choices) {
                    defaults.set(data, forKey: Self.runChoicesKey)
                }
            },
            strengthChoices: choices.strength,
            saveStrengthChoices: { choices in
                if let data = try? JSONEncoder().encode(choices) {
                    defaults.set(data, forKey: Self.strengthChoicesKey)
                }
            }
        )
    }

    func makePlanModel() -> PlanModel {
        PlanModel(
            profiles: profiles, workouts: workouts, exercises: exercises, progression: progression,
            routines: routines, runSources: metricsSources, recordedStrength: recordedStrength
        )
    }

    func makeExercisesModel() -> ExercisesModel {
        ExercisesModel(
            workouts: workouts, exercises: exercises, progression: progression, routines: routines, backup: backup,
            profiles: profiles
        )
    }

    func makeWhatsNewModel() -> WhatsNewModel {
        WhatsNewModel(status: onboardingStatus, workouts: workouts, currentVersion: Self.appVersion)
    }

    func makeOnboardingModel() -> OnboardingModel {
        OnboardingModel(profiles: profiles, workouts: workouts, status: onboardingStatus)
    }

    func makeTrainingProfileModel() -> TrainingProfileModel {
        TrainingProfileModel(profiles: profiles)
    }

    func makeTrainingSettingsModel() -> TrainingSettingsModel {
        TrainingSettingsModel(profiles: profiles)
    }

    func makeGarminSetupModel() -> GarminSetupModel {
        GarminSetupModel(account: garmin ?? NoGarminAccount(), reminders: LocalReminders())
    }

    func makeBackupModel() -> BackupModel {
        BackupModel(service: backup)
    }

    func makeImportModel() -> ImportModel {
        ImportModel(importer: importer, workouts: workouts, exercises: exercises, profiles: profiles)
    }
}

/// Stands in when the app runs without Garmin (previews, tests): nothing is connected.
private struct NoGarminAccount: GarminAccount {
    func connection() async -> GarminConnectionInfo? { nil }
    func connect(key: String, lifetime: GarminKeyLifetime) async throws(GarminAccountError) {
        throw .garminUnavailable
    }
    func sync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) async throws(GarminAccountError) -> GarminSyncSummary {
        throw .notConnected
    }
    func disconnect() async {}
}
