import Domain
import Foundation

/// Where one exercise stands: the settings it is progressed with and whether it is progressing, holding or stalled.
/// The one answer the logger, Plan, the deload advice and the AI context use (ADR-0035).
public struct LiftStatus: Hashable, Sendable {
    public let exerciseID: UUID
    /// Exposures that count for progression, oldest first.
    public let history: [ExerciseExposure]
    public let settings: ProgressionSettings
    public let status: ExerciseStatus

    public var isStalled: Bool { status.isStalled }
    public var lastTrained: Date? { history.last?.date }

    /// The status of `history` judged with `settings` (the logger passes the settings of the session in progress).
    public static func assess(exerciseID: UUID, history: [ExerciseExposure], settings: ProgressionSettings) -> Self {
        Self(
            exerciseID: exerciseID, history: history, settings: settings,
            status: StallDetection.status(history: history, settings: settings)
        )
    }

    /// Every exercise trained in `index`, each judged with the settings of the latest session that trained it: its
    /// routine's prescription and the declared focus, as the logger set its targets.
    public static func assessAll(
        index: ExposureIndex, exercises: [UUID: Exercise], stored: [UUID: ProgressionSettings], routines: [Routine]
    ) -> [Self] {
        let routineByID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return index.progressionExerciseIDs.map { id in
            let session = index.lastProgressionSession(of: id)
            let routine = session?.routineID.flatMap { routineByID[$0] }
            let settings = ProgressionTargets.settings(
                for: exercises[id], stored: stored[id], focus: stored[id]?.focus ?? session?.focus ?? routine?.focus,
                prescription: routine?.prescription(for: id)
            )
            return assess(exerciseID: id, history: index.progressionExposures(of: id), settings: settings)
        }
        .sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
    }
}
