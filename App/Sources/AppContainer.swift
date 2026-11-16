import Domain
import FeatureHistory
import FeatureToday
import FeatureWorkout
import Foundation
import GarminSource
import HealthKitSource
import Observation
import Persistence

/// Composition root: the only place that knows the concrete implementations (ADR-0002).
/// Features receive `Domain` protocols from here and never construct their own dependencies.
@MainActor
@Observable
final class AppContainer {
    let workouts: any WorkoutRepository
    let exercises: any ExerciseRepository
    let checkIns: any CheckInRepository
    let progression: any ProgressionSettingsRepository
    /// In priority order: when two sources report the same value, the first wins.
    let metricsSources: [any MetricsSource]

    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        checkIns: any CheckInRepository,
        progression: any ProgressionSettingsRepository,
        metricsSources: [any MetricsSource]
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.checkIns = checkIns
        self.progression = progression
        self.metricsSources = metricsSources
    }

    /// Production wiring: SwiftData on disk (ADR-0004). If the store cannot be opened, the app still runs on an
    /// in-memory store instead of crashing, and nothing is saved.
    static func live() -> AppContainer {
        let sources: [any MetricsSource] = [GarminMetricsSource(), HealthKitMetricsSource()]
        do {
            let store = SwiftDataStore.make(container: try PersistenceContainer.make())
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, metricsSources: sources
            )
        } catch {
            let store = InMemoryStore(exercises: ExerciseCatalog.builtIn)
            return AppContainer(
                workouts: store, exercises: store, checkIns: store, progression: store, metricsSources: sources
            )
        }
    }

    // MARK: Feature factories

    func makeTodayModel() -> TodayModel {
        TodayModel(sources: metricsSources)
    }

    func makeWorkoutModel() -> WorkoutModel {
        WorkoutModel(workouts: workouts, exercises: exercises, progression: progression)
    }

    func makeHistoryModel() -> HistoryModel {
        HistoryModel(workouts: workouts, exercises: exercises)
    }
}
