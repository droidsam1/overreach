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
        healthSource: (any MetricsSource & ActivitySource)? = nil
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
    }

    /// Production wiring: SwiftData on disk (ADR-0004). If the store cannot be opened, the app still runs on an
    /// in-memory store instead of crashing, and nothing is saved.
    static func live() -> AppContainer {
        let healthKit = HealthKitMetricsSource()
        let sources: [any MetricsSource] = [GarminMetricsSource(), healthKit]
        do {
            let store = SwiftDataStore.make(container: try PersistenceContainer.make())
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store,
                metricsSources: sources, healthSource: healthKit
            )
        } catch {
            let store = InMemoryStore(exercises: ExerciseCatalog.builtIn)
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
                routines: store,
                metricsSources: sources, healthSource: healthKit
            )
        }
    }

    private static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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
            routines: routines, checkIns: checkIns, sources: metricsSources, appVersion: Self.appVersion
        )
    }

    func makeTodayModel() -> TodayModel {
        TodayModel(sources: metricsSources)
    }

    func makeWorkoutModel() -> WorkoutModel {
        WorkoutModel(
            workouts: workouts, exercises: exercises, progression: progression, backup: backup, health: health,
            restAlerts: restAlerts, profiles: profiles
        )
    }

    func makeRoutinesModel() -> RoutinesModel {
        RoutinesModel(
            routines: routines, exercises: exercises, backup: backup, profiles: profiles, workouts: workouts
        )
    }

    func makeHistoryModel() -> HistoryModel {
        HistoryModel(
            workouts: workouts, exercises: exercises, routines: routines, backup: backup, health: health,
            profiles: profiles, progression: progression, activity: healthSource, runs: healthSource
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

    func makeBackupModel() -> BackupModel {
        BackupModel(service: backup)
    }

    func makeImportModel() -> ImportModel {
        ImportModel(importer: importer, workouts: workouts, exercises: exercises)
    }
}
