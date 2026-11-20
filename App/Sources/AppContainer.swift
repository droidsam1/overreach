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
import SettingsPresentation
import TodayPresentation
import WorkoutPresentation

/// Composition root: the only place that knows the concrete implementations (ADR-0002).
/// Features receive `Domain` protocols from here and never construct their own dependencies.
@MainActor
@Observable
final class AppContainer {
    let workouts: any WorkoutRepository
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
    /// Apple Health: steps for the History calendar, and runs (Garmin Connect writes its runs there too).
    let healthSource: (any MetricsSource & ActivitySource)?
    /// The person's Garmin account (ADR-0022). Also in `metricsSources`.
    let garmin: (any GarminAccount)?
    /// Strength workouts recorded by watches (Garmin, other apps through Apple Health), shown next to sessions.
    let strengthRecordings: [any StrengthRecordingSource]

    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        checkIns: any CheckInRepository,
        progression: any ProgressionSettingsRepository,
        profiles: any ProfileRepository,
        routines: any RoutineRepository,
        importer: any TrainingHistoryImporter = StrongHistoryImporter(),
        backupDestination: any BackupDestination = FolderBackupDestination(),
        restAlerts: any RestAlertScheduler = LocalRestAlerts(),
        health: any HealthWorkoutWriter = HealthKitWorkoutWriter(),
        onboardingStatus: any OnboardingStatusStore = DefaultsOnboardingStatus(),
        metricsSources: [any MetricsSource],
        healthSource: (any MetricsSource & ActivitySource)? = nil,
        garmin: (any GarminAccount)? = nil,
        strengthRecordings: [any StrengthRecordingSource] = []
    ) {
        self.workouts = workouts
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
        self.garmin = garmin
        self.strengthRecordings = strengthRecordings
    }

    /// Production wiring: SwiftData on disk (ADR-0004). If the store cannot be opened, the app still runs on an
    /// in-memory store instead of crashing, and nothing is saved.
    static func live() -> AppContainer {
        let healthKit = HealthKitMetricsSource()
        let garmin = GarminConnect.makeService()
        let healthWriter = HealthKitWorkoutWriter()
        let sources: [any MetricsSource] = [garmin, healthKit]
        do {
            let store = SwiftDataStore.make(container: try PersistenceContainer.make())
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store,
                health: healthWriter, metricsSources: sources, healthSource: healthKit, garmin: garmin,
                strengthRecordings: [garmin, healthWriter]
            )
        } catch {
            let store = InMemoryStore(exercises: ExerciseCatalog.builtIn)
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store,
                health: healthWriter, metricsSources: sources, healthSource: healthKit, garmin: garmin,
                strengthRecordings: [garmin, healthWriter]
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
            routines: routines, checkIns: checkIns, sources: metricsSources, recordings: strengthRecordings,
            appVersion: Self.appVersion
        )
    }

    func makeTodayModel() -> TodayModel {
        TodayModel(
            sources: metricsSources, checkIns: checkIns, backup: backup, garmin: garmin, profiles: profiles
        )
    }

    func makeWorkoutModel() -> WorkoutModel {
        WorkoutModel(
            workouts: workouts, exercises: exercises, progression: progression, backup: backup, health: health,
            restAlerts: restAlerts, profiles: profiles
        )
    }

    func makeRoutinesModel() -> RoutinesModel {
        RoutinesModel(
            routines: routines, exercises: exercises, backup: backup, profiles: profiles, workouts: workouts,
            checkIns: checkIns
        )
    }

    func makeHistoryModel() -> HistoryModel {
        HistoryModel(
            workouts: workouts, exercises: exercises, routines: routines, backup: backup, health: health,
            profiles: profiles, progression: progression, activity: healthSource, runs: healthSource,
            recordings: strengthRecordings
        )
    }

    func makePlanModel() -> PlanModel {
        PlanModel(profiles: profiles, workouts: workouts, exercises: exercises, progression: progression)
    }

    func makeExercisesModel() -> ExercisesModel {
        ExercisesModel(
            workouts: workouts, exercises: exercises, progression: progression, routines: routines, backup: backup
        )
    }

    func makeWhatsNewModel() -> WhatsNewModel {
        WhatsNewModel(status: onboardingStatus, workouts: workouts, currentVersion: Self.appVersion)
    }

    func makeOnboardingModel() -> OnboardingModel {
        OnboardingModel(profiles: profiles, workouts: workouts, status: onboardingStatus)
    }

    func makeGarminSetupModel() -> GarminSetupModel {
        GarminSetupModel(account: garmin ?? NoGarminAccount(), reminders: LocalReminders())
    }

    func makeBackupModel() -> BackupModel {
        BackupModel(service: backup)
    }

    func makeImportModel() -> ImportModel {
        ImportModel(importer: importer, workouts: workouts, exercises: exercises)
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
