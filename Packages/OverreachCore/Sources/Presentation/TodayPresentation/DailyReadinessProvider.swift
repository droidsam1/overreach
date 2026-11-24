import Analytics
import Domain
import Foundation
import TrainingServices

/// The readiness light Today shows, for screens that only need the light and its reasons. It reads and judges
/// like `TodayModel` does (ADR-0035), so Today and the plan follow-up agree for the same session.
public enum DailyReadinessProvider {
    // swiftlint:disable:next function_parameter_count
    public static func make(
        sources: [any MetricsSource], activity: [any ActivitySource], checkIns: (any CheckInRepository)?,
        workouts: (any WorkoutRepository)?, exercises: (any ExerciseRepository)?,
        recordedStrength: (any RecordedStrengthSource)?, routines: (any RoutineRepository)?,
        progression: (any ProgressionSettingsRepository)?, cycle: (any CycleSource)?,
        settings: ReadinessRules.Settings = .init(), calendar: Calendar = .current
    ) -> @Sendable (Date, AthleteProfile) async -> Readiness? {
        let loader = TrainingRecordLoader(
            sources: sources, activity: activity, checkIns: checkIns, workouts: workouts, exercises: exercises,
            recordedStrength: recordedStrength, routines: routines, progression: progression, cycle: cycle
        )
        return { now, profile in
            await loader.readiness(now: now, profile: profile, settings: settings, calendar: calendar)
        }
    }
}
