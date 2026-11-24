import Domain
import Foundation

/// An unfinished workout. This versioned file is intentionally separate from backup and history formats.
struct WorkoutDraft: Codable {
    static let currentVersion = 1

    var version = currentVersion
    let id: UUID
    let startedAt: Date
    let name: String
    let notes: String
    let focus: TrainingFocus?
    let routine: Routine?
    let effortScale: EffortScale
    let exercises: [DraftExercise]
    let rest: RestTimerDraft?
    var rotationRPECap: Double?
    var startsFromRotationHistory: Bool?
    var rotationCap: RotationAdjustment.Outcome?
}

struct RestTimerDraft: Codable {
    let setID: DraftSet.ID
    let exerciseID: DraftExercise.ID
    var endsAt: Date
    var durationSeconds: Int
}
