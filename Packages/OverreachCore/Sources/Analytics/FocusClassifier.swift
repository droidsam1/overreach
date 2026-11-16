import Domain
import Foundation

/// Infers the focus of sets, exposures and sessions from what was actually lifted.
///
/// A set's focus comes from its reps and, when an estimated 1RM is known, its relative load: ≤ 6 reps at
/// ≥ 78 % e1RM → strength; ≥ 15 reps → endurance; otherwise hypertrophy. Groups of sets take the majority focus;
/// with no clear majority (< 60 %) the group is `mixed`. Thresholds are heuristics (`focus-heuristics`)
/// anchored on the loading evidence (`loading-by-goal`).
public enum FocusClassifier {
    public static let strengthMaxReps = 6
    public static let strengthMinRelativeLoad = 0.78
    public static let enduranceMinReps = 15
    public static let majority = 0.6

    /// Focus of one set. `oneRepMaxKg` is a recent estimate for the exercise, if known.
    public static func focus(of set: WorkoutSet, oneRepMaxKg: Double?) -> TrainingFocus? {
        guard set.isWorking, let reps = set.reps, reps > 0 else { return nil }
        if reps >= enduranceMinReps { return .endurance }
        if reps <= strengthMaxReps {
            guard let oneRepMaxKg, oneRepMaxKg > 0, let weight = set.weightKg, weight > 0 else {
                return reps <= 5 ? .strength : .hypertrophy
            }
            return weight / oneRepMaxKg >= strengthMinRelativeLoad ? .strength : .hypertrophy
        }
        return .hypertrophy
    }

    /// Majority focus of a group of per-set foci; `mixed` when no focus reaches `majority`.
    public static func dominant(_ foci: [TrainingFocus]) -> TrainingFocus? {
        guard !foci.isEmpty else { return nil }
        var counts: [TrainingFocus: Int] = [:]
        for focus in foci { counts[focus, default: 0] += 1 }
        let best = counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value < rhs.value
        }
        guard let best else { return nil }
        return Double(best.value) / Double(foci.count) >= majority ? best.key : .mixed
    }

    /// Focus of one exposure, using the best e1RM seen in `previous` exposures (or this one) as reference.
    public static func focus(of exposure: ExerciseExposure, previous: [ExerciseExposure]) -> TrainingFocus? {
        let reference = (previous.suffix(6) + [exposure]).compactMap(\.bestEstimatedOneRepMax).max()
        return dominant(exposure.sets.compactMap { focus(of: $0, oneRepMaxKg: reference) })
    }

    /// Focus of a whole session (all its working sets), with per-exercise e1RM references from `history`.
    public static func focus(of session: StrengthSession, history: [StrengthSession]) -> TrainingFocus? {
        var foci: [TrainingFocus] = []
        for entry in session.entries {
            let previous = ExerciseExposure.history(of: entry.exerciseID, in: history.filter { $0.startedAt < session.startedAt })
            let current = ExerciseExposure(date: session.startedAt, sets: entry.sets)
            let reference = (previous.suffix(6) + [current]).compactMap(\.bestEstimatedOneRepMax).max()
            foci += current.sets.compactMap { focus(of: $0, oneRepMaxKg: reference) }
        }
        return dominant(foci)
    }
}
