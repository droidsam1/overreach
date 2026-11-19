import Domain
import Foundation

/// One session's work on one exercise: the straight working sets (no warm-ups, no drop sets), in order.
public struct ExerciseExposure: Hashable, Sendable {
    public let date: Date
    public let sets: [WorkoutSet]

    public init(date: Date, sets: [WorkoutSet]) {
        self.date = date
        self.sets = sets.filter { set in
            (set.kind == .working || set.kind == .failure) && (set.reps ?? 0) > 0
        }
    }

    /// Exposures of `exerciseID` across `sessions`, oldest first, with working sets only: warm-ups would shift
    /// set positions and the working weight. Entries marked as not counting for progression (left unfinished) and
    /// sessions without usable sets are skipped.
    public static func history(of exerciseID: UUID, in sessions: [StrengthSession]) -> [ExerciseExposure] {
        sessions
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { session -> ExerciseExposure? in
                let sets = session.entries
                    .filter { $0.exerciseID == exerciseID && $0.countsForProgression }
                    .flatMap(\.sets)
                    .filter(\.isWorking)
                let exposure = ExerciseExposure(date: session.startedAt, sets: sets)
                return exposure.sets.isEmpty ? nil : exposure
            }
    }

    /// The load used for most sets (ties go to the heavier load). 0 for bodyweight sets without load.
    public var workingWeightKg: Double {
        var counts: [Double: Int] = [:]
        for set in sets {
            counts[set.weightKg ?? 0, default: 0] += 1
        }
        let best = counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }
        return best?.key ?? 0
    }

    /// Sets performed at `workingWeightKg`, in order.
    public var setsAtWorkingWeight: [WorkoutSet] {
        let weight = workingWeightKg
        return sets.filter { abs(($0.weightKg ?? 0) - weight) < 0.001 }
    }

    /// Best RPE-adjusted estimated 1RM among the sets (sets above 12 reps are ignored).
    public var bestEstimatedOneRepMax: Double? {
        sets.compactMap { set -> Double? in
            guard let weight = set.weightKg, let reps = set.reps else { return nil }
            return LoadPrescription.estimatedOneRepMax(weightKg: weight, reps: reps, rpe: set.rpe)
        }.max()
    }
}
