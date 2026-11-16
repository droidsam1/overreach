import Domain
import FeatureToday
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
    /// In priority order: when two sources report the same value, the first wins.
    let metricsSources: [any MetricsSource]

    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        checkIns: any CheckInRepository,
        metricsSources: [any MetricsSource]
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.checkIns = checkIns
        self.metricsSources = metricsSources
    }

    /// Production wiring. Phase 1 replaces the in-memory store with the SwiftData store.
    static func live() -> AppContainer {
        let store = InMemoryStore()
        return AppContainer(
            workouts: store,
            exercises: store,
            checkIns: store,
            metricsSources: [GarminMetricsSource(), HealthKitMetricsSource()]
        )
    }

    // MARK: Feature factories

    func makeTodayModel() -> TodayModel {
        TodayModel(sources: metricsSources)
    }
}
